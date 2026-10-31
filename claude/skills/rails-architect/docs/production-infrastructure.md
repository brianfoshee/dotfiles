# Production Infrastructure

Deploying a SQLite-backed Rails app: Kamal onto a VM with no public IP, traffic
arriving through a Zero Trust tunnel, Litestream replicating to object storage,
SSH only over a VPN.

## Contents

- [Kamal](#kamal)
- [Litestream](#litestream)
- [VM provisioning](#vm-provisioning)
- [Tunnel and ACME](#tunnel-and-acme)
- [CI/CD](#cicd)
- [Active Storage](#active-storage)
- [Dockerfile](#dockerfile)
- [SSL behind a proxy](#ssl-behind-a-proxy)
- [Health checks and logging](#health-checks-and-logging)
- [References](#references)

## Kamal

```yaml
# config/deploy.yml
service: myapp
image: myorg/myapp              # registry server is prepended automatically

servers:
  web:
    - app-server                # hostname resolved over the VPN
  job:
    hosts:
      - app-server
    cmd: bin/jobs               # Solid Queue worker

proxy:
  ssl: true
  host: app.example.com
  app_port: 80

registry:
  server: ghcr.io
  username: myorg
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
    JOB_CONCURRENCY: 4
  secret:
    - RAILS_MASTER_KEY

volumes:
  - "app_storage:/rails/storage"   # named volume keeps SQLite across deploys

asset_path: /rails/public/assets   # old and new assets both served mid-deploy

accessories:
  tunnel:
    image: cloudflare/cloudflared:latest
    host: app-server
    network: host               # top-level key; replaces the default kamal network
    cmd: tunnel run
    env:
      secret:
        - TUNNEL_TOKEN

  litestream:
    image: litestream/litestream:0.5
    host: app-server
    cmd: replicate
    files:
      - config/litestream.yml:/etc/litestream.yml
    volumes:
      - "app_storage:/rails/storage"   # same volume as the app
    env:
      secret:
        - LITESTREAM_ACCESS_KEY_ID
        - LITESTREAM_SECRET_ACCESS_KEY
        - LITESTREAM_REPLICA_BUCKET
        - LITESTREAM_REPLICA_ENDPOINT

ssh:
  user: deploy
```

Services (web, job) sit behind kamal-proxy, which terminates SSL, manages
Let's Encrypt certificates, and health-checks new containers for zero-downtime
rollouts. Accessories run alongside and are **not** touched by `kamal deploy` —
boot them yourself:

```bash
kamal accessory boot litestream      # first time
kamal accessory reboot litestream    # after a config change
kamal accessory logs litestream -f
```

The generated `production.rb` logs to STDOUT and serves `public/` with no env
vars set. Web concurrency is set in `config/puma.rb` — see Puma tuning in
`docs/rails-8-modern-stack.md` — so measure before adding `WEB_CONCURRENCY` or
`RAILS_MAX_THREADS` here.

Everyday commands: `bin/kamal setup` (first deploy), `deploy`,
`deploy --skip-push` (image already pushed by CI), `logs -f [-r job]`,
`console`, `ssh`.

Secrets come from the environment via `.kamal/secrets`, which is not committed:

```bash
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
RAILS_MASTER_KEY=$(cat config/master.key)
TUNNEL_TOKEN=$TUNNEL_TOKEN
```

## Litestream

Continuous replication of SQLite to object storage, with point-in-time restore
and no application changes. The primary can also serve live read-only replicas,
which pull pages from object storage on demand — a read-only VFS that requires
CGO.

Each database takes a single `replica:` map, and retention is global under
`snapshot.retention`. Litestream is pre-1.0, so treat the config as stable in
practice but not SemVer-guaranteed.

**What to replicate.** Always the primary. The queue database is a judgment
call — it holds enqueued jobs that haven't run, so replicate it if losing
pending work in a crash matters. Skip cache and cable; both are transient and
regenerate on demand, and replicating them just costs storage and noise.

R2 is S3-compatible, so it uses the `s3` replica type. A YAML anchor avoids
repeating the shared fields, and Litestream interpolates `$VAR` after the YAML
parses, so anchors and env vars compose:

```yaml
# config/litestream.yml
snapshot:
  retention: 720h                # 30 days, applies to every database below

dbs:
  - path: /rails/storage/production.sqlite3
    replica: &r2_replica
      type: s3
      bucket: $LITESTREAM_REPLICA_BUCKET
      endpoint: $LITESTREAM_REPLICA_ENDPOINT   # https://<account>.r2.cloudflarestorage.com
      region: auto
      access-key-id: $LITESTREAM_ACCESS_KEY_ID
      secret-access-key: $LITESTREAM_SECRET_ACCESS_KEY
      path: production.sqlite3
      sync-interval: 1s

  - path: /rails/storage/production_queue.sqlite3
    replica:
      <<: *r2_replica
      path: production_queue.sqlite3

  # cache and cable intentionally omitted
```

Azure is the same shape with `type: abs`, `bucket` as the container name,
`endpoint: https://<account>.blob.core.windows.net`, and top-level
`access-key-id` / `secret-access-key` set from the storage account name and key.

Retention is global, so differing windows per database means running separate
Litestream configs and processes.

Restores take the replica URL, with the same env vars set:

```bash
litestream restore -o /rails/storage/production.sqlite3 \
  s3://myapp-backups/production.sqlite3

litestream restore -o /rails/storage/production.sqlite3 \
  -timestamp "2024-01-15T10:30:00Z" s3://myapp-backups/production.sqlite3

litestream ltx s3://myapp-backups/production.sqlite3   # list available LTX files
litestream info s3://myapp-backups/production.sqlite3
```

```hcl
resource "cloudflare_r2_bucket" "backups" {
  account_id    = var.cloudflare_account_id
  name          = "myapp-backups"
  location      = "enam"
  storage_class = "Standard"
}
```

## VM provisioning

Cloud-init runs once at first boot: install Docker for Kamal, create a non-root
`deploy` user in the docker group, start the tunnel daemon, join the VPN, and
close the firewall to everything except VPN traffic. HTTP never needs an open
port because it arrives through the tunnel.

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages: [docker.io, docker-compose, curl, git, jq, ufw]

users:
  - name: deploy
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

write_files:
  - path: /etc/systemd/system/cloudflared.service
    content: |
      [Unit]
      Description=Cloudflare Tunnel
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      User=cloudflared
      ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token ${tunnel_token}
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

runcmd:
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
  - echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
  - apt-get update && apt-get install -y cloudflared
  - useradd -r -s /usr/sbin/nologin cloudflared
  - systemctl enable --now cloudflared

  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${tailscale_auth_key} --ssh

  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 41641/udp    # VPN control traffic
  - ufw allow 3478/udp     # STUN, NAT traversal
  - ufw --force enable
```

## Tunnel and ACME

```hcl
resource "cloudflare_zero_trust_tunnel_cloudflared" "app" {
  account_id = var.cloudflare_account_id
  name       = "app-tunnel"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "app" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id
  config = {
    ingress = [
      {
        hostname = "app.example.com"
        path     = "/.well-known/acme-challenge/*"
        service  = "http://localhost:80"
      },
      {
        hostname = "app.example.com"
        service  = "https://localhost:443"
        origin_request = { origin_server_name = "app.example.com" }
      },
      { service = "http_status:404" },
    ]
  }
}

resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app.example.com"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.app.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "app" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id
}
```

Combining strict SSL, a tunnel, and Workers means HTTP-01 challenges need three
layers configured together — any one alone fails:

| Layer   | Where                                            | Setting                              |
|---------|--------------------------------------------------|--------------------------------------|
| Tunnel  | tunnel config ingress                            | `service = "http://localhost:80"` for the ACME path |
| Ruleset | `cloudflare_ruleset`, `http_config_settings`     | `ssl = "flexible"` for the ACME path |
| Worker  | `cloudflare_workers_route`                       | route with no script, so it bypasses |

```hcl
resource "cloudflare_ruleset" "acme_ssl_bypass" {
  zone_id = var.cloudflare_zone_id
  name    = "ACME Challenge SSL Configuration"
  kind    = "zone"
  phase   = "http_config_settings"
  rules = [{
    action            = "set_config"
    action_parameters = { ssl = "flexible" }
    expression        = "(http.host eq \"app.example.com\" and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\"))"
    enabled           = true
  }]
}

# No script = route disabled = falls through to the origin
resource "cloudflare_workers_route" "acme_bypass" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.example.com/.well-known/acme-challenge/*"
}
```

## CI/CD

Scan, lint, and test on every PR; build and deploy only from main. The deploy
job joins the VPN before it can reach the server at all.

```yaml
# .github/workflows/deploy.yml
name: CI/CD

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - uses: ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a # v1.329.0
        with: { bundler-cache: true }
      - run: bin/brakeman --no-pager --exit-on-warn
      - run: bin/bundler-audit
      - run: bin/importmap audit

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - uses: ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a # v1.329.0
        with: { bundler-cache: true }
      - run: bin/rubocop -f github

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - uses: ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a # v1.329.0
        with: { bundler-cache: true }
      - run: bin/rails herb:check
      - run: bin/rails db:test:prepare test
      - run: bin/rails test:system
        if: always()
      - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        if: failure()
        with: { name: screenshots, path: tmp/screenshots }

  build:
    needs: [scan, lint, test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read     # job permissions replace the top-level ones, so restate this
      packages: write    # ghcr.io push
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - uses: ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a # v1.329.0
        with: { bundler-cache: true }
      - run: bin/kamal build push
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}

  deploy:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { persist-credentials: false }
      - uses: ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a # v1.329.0
        with: { bundler-cache: true }
      - uses: tailscale/github-action@d1b6cd204f8dceda5b3eaad7f1f767be390056cd # v4.2.0
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_CLIENT_SECRET }}
          tags: tag:ci
      - run: |
          if bin/kamal proxy status 2>/dev/null; then
            bin/kamal deploy --skip-push
          else
            bin/kamal setup
          fi
        env:
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
```

Pin every action to a commit SHA with the version in a comment: a tag can be
moved to malicious code, a SHA can't, and Dependabot still bumps both.
`persist-credentials: false` keeps the token out of `.git/config`, and the
top-level `permissions:` makes every job read-only unless it asks for more.
Audit the workflow files with [zizmor](https://docs.zizmor.sh) (`zizmor
.github/`), which flags unpinned actions, persisted credentials and template
injection.

`RAILS_MASTER_KEY` is needed at deploy and runtime, not to build the image.
`GITHUB_TOKEN` is provided automatically but needs `packages: write`. The
Tailscale OAuth pair and the Litestream storage credentials come from their
respective consoles.

`herb:check` sits in the test job because it boots the app. The scan job's
`bin/bundler-audit` covers every gem except Rails, whose advisories it can't see
while the app runs main (see `docs/rails-8-modern-stack.md`). Dependabot's
revision bumps are what deliver Rails security fixes:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: bundler
    directory: "/"
    schedule:
      interval: daily
    groups:
      bundler:
        patterns: ["*"]
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    groups:
      github-actions:
        patterns: ["*"]
```

With `gem "rails", github: "rails/rails", branch: "main"`, the daily grouped PR
moves the locked revision forward; a `ref:` pin would never be bumped. A
`cooldown:` (holding new releases for some days) blunts supply-chain attacks,
but it delays security fixes the same way, so list `rails` and other
security-critical gems under `cooldown.exclude`.

## Active Storage

```yaml
# config/storage.yml
r2:
  service: S3                      # R2 is S3-compatible; needs the aws-sdk-s3 gem
  access_key_id: <%= Rails.application.credentials.dig(:r2, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:r2, :secret_access_key) %>
  endpoint: https://<account_id>.r2.cloudflarestorage.com
  region: auto
  bucket: myapp-uploads
  force_path_style: true
```

Direct uploads need CORS on the bucket — allow the app origin for
`GET/HEAD/PUT/POST/OPTIONS` and expose `ETag`.

## Dockerfile

Start from the Dockerfile and `bin/docker-entrypoint` that `rails new`
generates, and keep them close to the generator so upgrades diff cleanly. The
generated file already does what hand-written ones tend to get wrong:

- `# check=error=true` fails the build on Dockerfile lint warnings.
- jemalloc is linked through an arch-neutral path
  (`/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2` → `/usr/local/lib`) and
  set once in `ENV LD_PRELOAD`, so arm64 and amd64 images both work. Don't
  hard-code `x86_64` or set `LD_PRELOAD` in the entrypoint.
- `BUNDLE_WITHOUT="development"`, `bootsnap precompile --gemfile`, and `git` in
  the build stage, which Bundler needs to clone rails/rails; the checkouts'
  `.git` directories are deleted in the same layer.
- A non-root `USER 1000:1000` set before `COPY --chown=rails:rails`, so the app
  owns only its runtime files.
- `ARG RUBY_VERSION` matching `.ruby-version`; bump both together.
- The entrypoint runs `db:prepare` only when the command is `rails server`, so
  `kamal console` and one-off commands don't migrate.

Deviations worth making: add `poppler-utils` (PDF previews) or other runtime
libraries to the base stage's package list, and set `builder: arch:` in
`config/deploy.yml` to the server's architecture.

`bin/thrust` wraps Puma with Thruster (`gem "thruster", require: false`), which
adds X-Sendfile, asset caching, compression, and HTTP/2.

## SSL behind a proxy

With Cloudflare and kamal-proxy both in front of the app, set **both**:

```ruby
config.assume_ssl = true
config.force_ssl = true
```

`assume_ssl` marks the request as HTTPS before `force_ssl` inspects it. With
only `force_ssl`, the proxy's plain-HTTP hop to the app triggers a redirect that
the proxy re-issues, producing a loop.

## Health checks and logging

Use the built-in endpoint the generator routes, which kamal-proxy probes before
switching traffic:

```ruby
# config/routes.rb
get "up" => "rails/health#show", as: :rails_health_check
```

It returns 200 once the app has booted and 500 if it raises. It skips
`ApplicationController`, so authentication filters never block it. Don't fold
the database, cache or queue into the probe: a probe that fails when a
dependency hiccups gets healthy containers pulled out of rotation. Monitor those
separately.

```ruby
config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym
config.log_tags = [:request_id]   # trace a request across log lines
```

Tag error reports with the deployed revision so a stack trace maps to a commit:

```ruby
Sentry.set_context("app", { revision: Rails.app.revision })
```

## References

- [Kamal](https://kamal-deploy.org/) · [Thruster](https://github.com/basecamp/thruster)
- [Litestream](https://litestream.io/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) · [Tailscale](https://tailscale.com/kb/)
