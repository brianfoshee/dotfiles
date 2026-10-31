# Production Infrastructure

Deploying a SQLite-backed Rails app: Kamal onto a VM with no public IP, traffic
arriving through a Cloudflare Zero Trust tunnel, Litestream replicating to R2,
SSH only over Tailscale. The Cloudflare side is Terraform; the
`cloudflare-domain-setup` skill covers the zone, tunnel and DNS resources.

## Contents

- [Kamal](#kamal)
- [Litestream](#litestream)
- [VM provisioning](#vm-provisioning)
- [ACME through a tunnel](#acme-through-a-tunnel)
- [CI/CD](#cicd)
- [Active Storage on R2](#active-storage-on-r2)
- [Dockerfile](#dockerfile)
- [SSL behind a proxy](#ssl-behind-a-proxy)
- [Health checks and logging](#health-checks-and-logging)
- [References](#references)

## Kamal

Beyond the generated `config/deploy.yml`:

```yaml
servers:
  web:
    - app-server                # hostname resolved over the VPN
  job:
    hosts: [app-server]
    cmd: bin/jobs               # Solid Queue worker

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
      secret: [TUNNEL_TOKEN]

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
```

Accessories are **not** touched by `kamal deploy`: `kamal accessory boot
litestream` the first time, `reboot` after a config change. Web concurrency is
set in `config/puma.rb` (Puma tuning in `docs/rails-8-modern-stack.md`), so
measure before adding `WEB_CONCURRENCY` or `RAILS_MAX_THREADS` to `env:`.

## Litestream

Continuous replication of SQLite to object storage with point-in-time restore.
The primary can also serve live read-only replicas, which pull pages from object
storage on demand (a read-only VFS that requires CGO). Litestream is pre-1.0,
so treat the config as stable in practice but not SemVer-guaranteed.

Each database takes a single `replica:` map, and retention is global under
`snapshot.retention`, so differing windows per database means separate
Litestream processes. R2 uses the `s3` type; Litestream interpolates `$VAR`
after the YAML parses, so anchors and env vars compose:

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

Azure is the same shape with `type: abs`, `bucket` as the container name and
`endpoint: https://<account>.blob.core.windows.net`.

**What to replicate.** Always the primary. The queue database holds enqueued
jobs that haven't run, so replicate it if losing pending work in a crash
matters. Skip cache and cable; both regenerate on demand.

Restores take the replica URL with the same env vars set; `-timestamp` picks a
point in time, `litestream ltx <url>` lists the available LTX files (the
pre-0.5 `wal` subcommand is gone, and 0.3-format backups don't restore).

## VM provisioning

Cloud-init at first boot: install Docker for Kamal, create a non-root `deploy`
user in the `docker` group, install and enable `cloudflared` as a systemd
service running `tunnel --no-autoupdate run --token ...` under its own system
user, `tailscale up --authkey=... --ssh`, then `ufw default deny incoming` with
only `41641/udp` (Tailscale) and `3478/udp` (STUN) open. HTTP never needs an
open port because it arrives through the tunnel.

## ACME through a tunnel

Combining strict SSL, a tunnel and Workers means kamal-proxy's HTTP-01
challenges need three layers configured together — any one alone fails:

| Layer   | Where                                        | Setting                                                  |
|---------|----------------------------------------------|----------------------------------------------------------|
| Tunnel  | tunnel config ingress                        | `/.well-known/acme-challenge/*` → `http://localhost:80`, before the `https://localhost:443` catch-all |
| Ruleset | `cloudflare_ruleset`, `http_config_settings` | `set_config` with `ssl = "flexible"` for the ACME path   |
| Worker  | `cloudflare_workers_route`                   | a route with no script, so the path bypasses the Worker  |

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

The HTTPS ingress needs `origin_request = { origin_server_name = "app.example.com" }`
so cloudflared sends that SNI to kamal-proxy and validates its certificate
against it rather than against `localhost`.

## CI/CD

Scan (`brakeman`, `bundler-audit`, `importmap audit`), lint and test on every
PR; build and deploy only from `main`. Rules the generated workflow doesn't
follow:

- Pin every action to a commit SHA with the version in a comment. A tag can be
  moved to malicious code, a SHA can't, and Dependabot still bumps both. Audit
  with [zizmor](https://docs.zizmor.sh) (`zizmor .github/`).
- `persist-credentials: false` on every checkout, and top-level
  `permissions: { contents: read }`. Job-level `permissions:` replace the
  top-level block rather than extending it, so the build job restates
  `contents: read` beside `packages: write` for ghcr.io.
- `bin/rails herb:check` goes in the test job because it boots the app. Run
  `test:system` with `if: always()` and upload `tmp/screenshots` on failure.
- The deploy job joins the VPN with `tailscale/github-action` (OAuth client,
  `tags: tag:ci`), then runs `kamal deploy --skip-push` if `kamal proxy status`
  succeeds and `kamal setup` otherwise. `RAILS_MASTER_KEY` is needed at deploy
  and runtime, not to build the image.

The scan job's `bundler-audit` covers every gem except Rails, whose advisories
it can't see while the app runs main (see `docs/rails-8-modern-stack.md`).
Dependabot's daily revision bumps deliver Rails security fixes:

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

A `cooldown:` (holding new releases for some days) blunts supply-chain attacks
but delays security fixes the same way, so list `rails` and other
security-critical gems under `cooldown.exclude`.

## Active Storage on R2

R2 is S3-compatible: `service: S3` with the `aws-sdk-s3` gem,
`endpoint: https://<account_id>.r2.cloudflarestorage.com`, `region: auto` and
`force_path_style: true`. Direct uploads need CORS on the bucket — allow the app
origin for `GET/HEAD/PUT/POST/OPTIONS` and expose `ETag`.

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
- A non-root `USER 1000:1000` set before `COPY --chown=rails:rails`.
- `ARG RUBY_VERSION` matching `.ruby-version`; bump both together.
- The entrypoint runs `db:prepare` only when the command is `rails server`, so
  `kamal console` and one-off commands don't migrate.

Deviations worth making: add `poppler-utils` (PDF previews) or other runtime
libraries to the base stage's package list, and set `builder: arch:` in
`config/deploy.yml` to the server's architecture. `bin/thrust` wraps Puma with
Thruster (`gem "thruster", require: false`) for X-Sendfile, asset caching,
compression and HTTP/2.

## SSL behind a proxy

With Cloudflare and kamal-proxy both in front of the app, set **both**
`config.assume_ssl = true` and `config.force_ssl = true`. `assume_ssl` marks
the request as HTTPS before `force_ssl` inspects it; with only `force_ssl`, the
proxy's plain-HTTP hop triggers a redirect that the proxy re-issues, producing
a loop.

## Health checks and logging

The generated `get "up" => "rails/health#show"` is what kamal-proxy probes
before switching traffic. It skips `ApplicationController`, so authentication
filters never block it. Don't fold the database, cache or queue into the probe:
a probe that fails when a dependency hiccups gets healthy containers pulled out
of rotation. Monitor those separately.

`config.log_tags = [:request_id]` traces a request across log lines, and
`Sentry.set_context("app", { revision: Rails.app.revision })` maps a stack trace
to a commit.

## References

- [Kamal](https://kamal-deploy.org/) · [Thruster](https://github.com/basecamp/thruster)
- [Litestream](https://litestream.io/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/) · [Tailscale](https://tailscale.com/kb/)
