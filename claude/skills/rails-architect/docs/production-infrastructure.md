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
    RAILS_LOG_TO_STDOUT: true
    RAILS_SERVE_STATIC_FILES: true
    JOB_CONCURRENCY: 4
    WEB_CONCURRENCY: 2
    RAILS_MAX_THREADS: 5
  secret:
    - RAILS_MASTER_KEY

volumes:
  - "app_storage:/rails/storage"   # named volume keeps SQLite across deploys

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
and no application changes. Since v0.5 the primary can also stream to live
read-only replicas — the capability that used to require LiteFS.

**v0.5 broke the config format.** Each database now takes a single `replica:`
map, not a `replicas:` list. Retention moved to a global `snapshot.retention`.
`litestream wal` became `litestream ltx`, and v0.3 replicas are not
restore-compatible with v0.5. Litestream is still pre-1.0, so the config is
stable in practice but not SemVer-guaranteed.

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
  retention: 720h                # 30 days, global — per-replica retention is gone

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

Because retention is now global, differing windows per database means running
separate Litestream configs and processes.

Restores take the replica URL, with the same env vars set:

```bash
litestream restore -o /rails/storage/production.sqlite3 \
  s3://myapp-backups/production.sqlite3

litestream restore -o /rails/storage/production.sqlite3 \
  -timestamp "2024-01-15T10:30:00Z" s3://myapp-backups/production.sqlite3

litestream ltx s3://myapp-backups/production.sqlite3   # list available LTX files
litestream info s3://myapp-backups/production.sqlite3
```

The v0.3 `litestream snapshots` command no longer exists — the LTX rewrite
replaced it.

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

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/brakeman --no-pager --exit-on-warn
      - run: bin/bundler-audit
      - run: bin/importmap audit

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/rubocop -f github

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/rails db:test:prepare test
      - run: bin/rails test:system
        if: always()
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: screenshots, path: tmp/screenshots }

  build:
    needs: [scan, lint, test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read     # explicit permissions drop the defaults, so checkout needs this
      packages: write    # ghcr.io push
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bin/kamal build push
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}

  deploy:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - uses: tailscale/github-action@v2
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

`RAILS_MASTER_KEY` is needed at deploy and runtime, not to build the image.
`GITHUB_TOKEN` is provided automatically but needs `packages: write`. The
Tailscale OAuth pair and the Litestream storage credentials come from their
respective consoles.

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

```dockerfile
# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.4.1

FROM ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential git pkg-config libssl-dev libyaml-dev

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

COPY . .
RUN bundle exec bootsnap precompile app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl libjemalloc2 libvips sqlite3 poppler-utils && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

`bin/thrust` wraps Puma with Thruster (`gem "thruster", require: false`), which
adds X-Sendfile, asset caching, compression, and HTTP/2.

The entrypoint migrates only when actually booting the server, so `kamal
console` and one-off commands don't run migrations:

```bash
#!/bin/bash
set -e

export LD_PRELOAD=$(find /usr/lib -name 'libjemalloc.so.2' 2>/dev/null | head -1)

if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "$@"
```

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

```ruby
class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    render json: { status: "ok", database: database_connected?,
                   queue: queue_healthy?, cache: cache_healthy? }
  end

  private
    def database_connected?
      ApplicationRecord.connection.active?
    rescue
      false
    end

    def queue_healthy?
      SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).exists?
    rescue
      false
    end

    def cache_healthy?
      Rails.cache.write("health_check", Time.current)
      Rails.cache.read("health_check").present?
    rescue
      false
    end
end
```

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
