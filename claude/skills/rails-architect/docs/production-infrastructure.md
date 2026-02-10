# Production Infrastructure for Rails 8.1

Production-proven deployment patterns for Rails 8.1 applications using Kamal, SQLite with Litestream replication, and modern cloud infrastructure.

## Overview

This guide covers the complete production infrastructure stack for deploying Rails 8.1 applications:
- **Kamal** - Container deployment without Kubernetes
- **Litestream** - Continuous SQLite replication to cloud storage
- **Cloud-init** - VM provisioning automation
- **Zero Trust networking** - Secure tunnel-based access
- **CI/CD** - Automated testing and deployment pipelines

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CI/CD PIPELINE                                  │
│  PR → CI checks │ main push → build image → deploy via VPN/tunnel   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  CDN / EDGE (Cloudflare, Fastly, etc.)                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────────┐ │
│  │ DNS (CNAME) │→ │ Zero Trust   │→ │ SSL termination + ACME      │ │
│  │             │  │ Tunnel       │  │ passthrough rules           │ │
│  └─────────────┘  └──────┬───────┘  └─────────────────────────────┘ │
└──────────────────────────┼──────────────────────────────────────────┘
                           │ (tunnel daemon on VM)
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  CLOUD VM (No public IP)                                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  KAMAL CONTAINERS                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐ │  │
│  │  │ app-web     │  │ app-job     │  │ app-litestream       │ │  │
│  │  │ Puma+Thruster│ SolidQueue   │  │ Continuous backup    │ │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────────┬───────────┘ │  │
│  │         │                │                    │             │  │
│  │         ▼                ▼                    ▼             │  │
│  │  ┌────────────────────────────────────────────────────────┐ │  │
│  │  │  Docker Volume: /rails/storage                         │ │  │
│  │  │  - production.sqlite3                                  │ │  │
│  │  │  - production_queue/cache/cable.sqlite3               │ │  │
│  │  └────────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌─────────────────┐  ┌──────────────────────────────────────────┐ │
│  │ Tunnel daemon   │  │ VPN (Tailscale/WireGuard for SSH access) │ │
│  │ (cloudflared)   │  │ Firewall: only VPN ports allowed         │ │
│  └─────────────────┘  └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  CLOUD STORAGE                                                      │
│  ┌────────────────────────┐  ┌─────────────────────────────────────┐│
│  │ Database Backups       │  │ User Attachments                    ││
│  │ (Litestream target)    │  │ (ActiveStorage service)             ││
│  └────────────────────────┘  └─────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

## Kamal Deployment

### What is Kamal?

Kamal is a deployment tool from 37signals that deploys containerized applications to bare VMs without Kubernetes. It handles:
- Docker image building and pushing
- Rolling deployments with zero downtime
- SSL certificate management (Let's Encrypt)
- Accessory containers (like Litestream)
- Health checks and rollbacks

### Configuration Structure

```yaml
# config/deploy.yml
service: myapp
image: ghcr.io/myorg/myapp

servers:
  web:
    - app-server              # Hostname (resolved via VPN/DNS)
  job:
    hosts:
      - app-server
    cmd: bin/jobs             # Solid Queue worker

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
    JOB_CONCURRENCY: 4        # Solid Queue processes
    WEB_CONCURRENCY: 2        # Puma workers
    RAILS_MAX_THREADS: 5      # Threads per Puma worker
  secret:
    - RAILS_MASTER_KEY

volumes:
  - "app_storage:/rails/storage"

accessories:
  litestream:
    image: litestream/litestream:0.5
    host: app-server
    cmd: replicate
    files:
      - config/litestream.yml:/etc/litestream.yml
    volumes:
      - "app_storage:/rails/storage"
    env:
      secret:
        - STORAGE_ACCOUNT_NAME
        - STORAGE_ACCOUNT_KEY

ssh:
  user: deploy
```

### Key Concepts

**Services vs Accessories:**
- **Services** (web, job): Core application containers, managed by kamal-proxy
- **Accessories** (litestream): Supporting containers that run alongside services

**Volumes:**
```yaml
volumes:
  - "app_storage:/rails/storage"
```
Named Docker volumes persist SQLite databases across deployments.

**Proxy (kamal-proxy):**
- Reverse proxy handling SSL termination
- Automatic Let's Encrypt certificate management
- Zero-downtime deployments via health checks

### Kamal Commands

```bash
# Initial setup (first deployment)
bin/kamal setup

# Deploy new version
bin/kamal deploy

# Deploy without rebuilding image (image already pushed)
bin/kamal deploy --skip-push

# View logs
bin/kamal logs -f
bin/kamal logs -f -r job    # Job server logs

# Access Rails console
bin/kamal console

# SSH to server
bin/kamal ssh

# Restart accessories
bin/kamal accessory reboot litestream
```

### Secrets Management

```bash
# .kamal/secrets (not committed to git)
KAMAL_REGISTRY_PASSWORD=$GITHUB_TOKEN
RAILS_MASTER_KEY=$RAILS_MASTER_KEY
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
STORAGE_ACCOUNT_KEY=$STORAGE_ACCOUNT_KEY
```

Kamal reads environment variables and injects them into containers.

## Litestream: SQLite Replication

### What is Litestream?

Litestream continuously replicates SQLite databases to cloud storage (S3, Azure Blob, GCS, etc.). It provides:
- **Continuous backup** - Changes replicated within seconds
- **Point-in-time recovery** - Restore to any moment
- **Zero downtime** - No application changes needed
- **Low cost** - Uses cheap object storage

### Configuration

```yaml
# config/litestream.yml
access-key-id: ${STORAGE_ACCOUNT_NAME}
secret-access-key: ${STORAGE_ACCOUNT_KEY}

dbs:
  # Primary database - most important, longest retention
  - path: /rails/storage/production.sqlite3
    replicas:
      - type: abs                        # Azure Blob Storage (or s3, gcs)
        bucket: db-backups-production
        endpoint: https://mystorageaccount.blob.core.windows.net
        sync-interval: 1s                # Near real-time replication
        retention: 720h                  # 30 days of history

  # Queue database - important but shorter retention
  - path: /rails/storage/production_queue.sqlite3
    replicas:
      - type: abs
        bucket: db-backups-production
        path: queue
        sync-interval: 1s
        retention: 168h                  # 7 days

  # Cache database - least critical
  - path: /rails/storage/production_cache.sqlite3
    replicas:
      - type: abs
        bucket: db-backups-production
        path: cache
        sync-interval: 60s               # Less frequent
        retention: 24h                   # 1 day only

  # Cable database - WebSocket state
  - path: /rails/storage/production_cable.sqlite3
    replicas:
      - type: abs
        bucket: db-backups-production
        path: cable
        sync-interval: 60s
        retention: 24h
```

### Retention Strategy

| Database | Sync Interval | Retention | Rationale |
|----------|--------------|-----------|-----------|
| Primary | 1 second | 30 days | Business data, needs full history |
| Queue | 1 second | 7 days | Jobs can be re-enqueued if lost |
| Cache | 60 seconds | 24 hours | Ephemeral, easily regenerated |
| Cable | 60 seconds | 24 hours | WebSocket state, transient |

### Recovery Commands

```bash
# Restore to latest state
litestream restore -o /rails/storage/production.sqlite3 \
  abs://db-backups-production/production.sqlite3

# Restore to specific point in time
litestream restore -o /rails/storage/production.sqlite3 \
  -timestamp "2024-01-15T10:30:00Z" \
  abs://db-backups-production/production.sqlite3

# List available snapshots
litestream snapshots abs://db-backups-production/production.sqlite3
```

### Kamal Integration

Litestream runs as a Kamal accessory, sharing the storage volume with the Rails app:

```yaml
# config/deploy.yml
accessories:
  litestream:
    image: litestream/litestream:0.5
    host: app-server
    cmd: replicate
    files:
      - config/litestream.yml:/etc/litestream.yml
    volumes:
      - "app_storage:/rails/storage"    # Same volume as Rails app
    env:
      secret:
        - STORAGE_ACCOUNT_NAME
        - STORAGE_ACCOUNT_KEY
```

## Cloud-Init: VM Provisioning

### What is Cloud-Init?

Cloud-init is the industry standard for VM initialization. It runs once when a VM is first created and handles:
- Package installation
- User creation
- Service configuration
- Firewall setup

### Example Cloud-Init Script

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - curl
  - wget
  - git
  - jq
  - htop
  - ufw

users:
  - name: deploy
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

write_files:
  # Tunnel daemon service
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
  # Install tunnel daemon (Cloudflare example)
  - curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
  - echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
  - apt-get update && apt-get install -y cloudflared
  - useradd -r -s /usr/sbin/nologin cloudflared
  - systemctl enable cloudflared
  - systemctl start cloudflared

  # Install VPN for SSH access (Tailscale example)
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${tailscale_auth_key} --ssh

  # Configure firewall - deny all except VPN
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 41641/udp    # VPN control traffic
  - ufw allow 3478/udp     # STUN (NAT traversal)
  - ufw --force enable

  # Completion logging
  - echo "Cloud-init complete at $(date)" >> /var/log/cloud-init-complete.log
```

### Key Components

**1. Docker Installation:**
```yaml
packages:
  - docker.io
  - docker-compose
```
Kamal requires Docker on the target server.

**2. Deploy User:**
```yaml
users:
  - name: deploy
    groups: [sudo, docker]
    ssh_authorized_keys:
      - ${ssh_public_key}
```
Non-root user for Kamal deployments with Docker access.

**3. Zero Trust Tunnel:**
The tunnel daemon (cloudflared, Tailscale, etc.) creates an outbound connection to the edge network, allowing HTTP traffic without exposing ports.

**4. VPN for SSH:**
Tailscale or WireGuard provides secure SSH access for deployments without opening SSH to the public internet.

**5. Firewall:**
```yaml
- ufw default deny incoming
- ufw allow 41641/udp    # VPN only
```
Only VPN traffic allowed inbound. HTTP traffic arrives through the tunnel.

## Zero Trust Networking

### The Problem with Traditional Deployment

```
Traditional:
┌──────────────┐     ┌───────────────┐
│   Internet   │────▶│ VM (public IP) │
│              │     │ Port 22 (SSH)  │
│              │     │ Port 80 (HTTP) │
│              │     │ Port 443 (HTTPS)│
└──────────────┘     └───────────────┘

Vulnerabilities:
- SSH brute force attacks
- DDoS on public IP
- SSL certificate management complexity
```

### Zero Trust Architecture

```
Zero Trust:
┌──────────────┐     ┌───────────────┐     ┌───────────────┐
│   Internet   │────▶│ Edge (CDN)    │────▶│ VM (no public │
│              │     │ SSL termination│     │ IP, outbound  │
│              │     │ DDoS protection│     │ tunnel only)  │
└──────────────┘     └───────────────┘     └───────────────┘
                                                   │
                                                   ▼
                     ┌───────────────┐     ┌───────────────┐
                     │ CI/CD Runner  │────▶│ VM via VPN    │
                     │ (deployment)  │     │ (SSH access)  │
                     └───────────────┘     └───────────────┘

Benefits:
- No public IP = no direct attacks
- Edge handles SSL, DDoS, caching
- SSH only via authenticated VPN
- Audit trail for all access
```

### Tunnel Configuration (Cloudflare Example)

```hcl
# Terraform: Cloudflare Zero Trust Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "app" {
  account_id = var.cloudflare_account_id
  name       = "app-tunnel"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "app" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id

  config {
    # ACME challenges - HTTP for Let's Encrypt validation
    ingress_rule {
      hostname = "app.example.com"
      path     = "/.well-known/acme-challenge/*"
      service  = "http://localhost:80"
    }

    # Regular traffic - HTTPS to app
    ingress_rule {
      hostname = "app.example.com"
      service  = "https://localhost:443"
      origin_request {
        origin_server_name = "app.example.com"
      }
    }

    # Catch-all
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS record pointing to tunnel
resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.app.id}.cfargotunnel.com"
  proxied = true
}
```

### ACME/Let's Encrypt Passthrough

For automatic SSL certificates, Let's Encrypt validates domain ownership via HTTP-01 challenges. With a Zero Trust tunnel and strict SSL mode, this requires **three coordinated configurations**:

#### The Problem

Let's Encrypt sends an HTTP request to `/.well-known/acme-challenge/<token>` expecting a specific response. With Cloudflare in front:
1. **Strict SSL** rejects HTTP-to-origin connections
2. **Tunnel** might route to HTTPS instead of HTTP
3. **Workers** might intercept and break the flow

All three layers must allow the ACME challenge through.

#### Layer 1: Tunnel Ingress (Route to HTTP)

The tunnel must route ACME paths to HTTP port 80, not HTTPS port 443:

```hcl
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "app" {
  config {
    ingress = [
      # ACME challenges - MUST route to HTTP (port 80)
      {
        hostname = "app.example.com"
        path     = "/.well-known/acme-challenge/*"
        service  = "http://localhost:80"    # HTTP, not HTTPS
      },
      # Regular traffic - HTTPS to kamal-proxy
      {
        hostname = "app.example.com"
        service  = "https://localhost:443"
        origin_request = {
          origin_server_name = "app.example.com"
        }
      },
      # Catch-all
      {
        service = "http_status:404"
      }
    ]
  }
}
```

**Why:** Let's Encrypt validation happens over HTTP. Kamal-proxy listens on port 80 for ACME challenges and port 443 for HTTPS traffic.

#### Layer 2: Configuration Rule (Downgrade SSL)

With zone-wide `ssl = "strict"`, Cloudflare requires valid SSL on the origin. Create a ruleset to downgrade SSL for ACME paths only:

```hcl
resource "cloudflare_ruleset" "acme_ssl_bypass" {
  zone_id     = var.cloudflare_zone_id
  name        = "ACME Challenge SSL Configuration"
  description = "Set SSL mode to flexible for Let's Encrypt ACME challenges"
  kind        = "zone"
  phase       = "http_config_settings"

  rules = [{
    action = "set_config"
    action_parameters = {
      ssl = "flexible"    # Allows HTTP to origin
    }
    expression  = "(http.host eq \"app.example.com\" and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\"))"
    description = "Downgrade SSL for ACME challenges"
    enabled     = true
  }]
}
```

**Why:** `ssl = "flexible"` allows Cloudflare to connect to the origin via HTTP. This is only applied to ACME paths; all other traffic uses strict SSL.

#### Layer 3: Worker Bypass (If Using Workers)

If you have a Cloudflare Worker intercepting traffic (e.g., for authentication, caching, or routing), you must bypass it for ACME challenges:

```hcl
# Main worker route - catches all app traffic
resource "cloudflare_workers_route" "app_proxy" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.example.com/*"
  script  = cloudflare_worker.app_proxy.name
}

# ACME bypass - more specific pattern, no script = bypass worker
resource "cloudflare_workers_route" "acme_bypass" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.example.com/.well-known/acme-challenge/*"
  # No script specified = route disabled, falls through to origin
}
```

**Why:** Worker routes are matched by specificity. The more specific ACME route (with no script) takes precedence, allowing the request to pass directly through the tunnel to the origin.

#### Complete Configuration Summary

| Layer | Resource | Setting | Purpose |
|-------|----------|---------|---------|
| **Tunnel** | `cloudflare_zero_trust_tunnel_cloudflared_config` | `service = "http://localhost:80"` for ACME path | Route to HTTP port |
| **Ruleset** | `cloudflare_ruleset` (phase: `http_config_settings`) | `ssl = "flexible"` for ACME path | Allow HTTP-to-origin |
| **Worker** | `cloudflare_workers_route` | No script for ACME path | Bypass worker |

#### Troubleshooting ACME Failures

If Let's Encrypt validation fails:

1. **Check tunnel logs**: `cloudflared tunnel log` - Is the request reaching the tunnel?
2. **Check kamal-proxy logs**: `bin/kamal proxy logs` - Is the request reaching port 80?
3. **Test manually**:
   ```bash
   # From outside, this should return the challenge token
   curl -v http://app.example.com/.well-known/acme-challenge/test
   ```
4. **Verify ruleset**: In Cloudflare dashboard, check Rules → Configuration Rules
5. **Verify worker routes**: In Cloudflare dashboard, check Workers → Routes (ACME route should have no script)

## CI/CD Pipeline

### GitHub Actions Workflow

```yaml
# .github/workflows/deploy.yml
name: CI/CD

on:
  pull_request:
    paths:
      - 'app/**'
      - '.github/workflows/deploy.yml'
  push:
    branches: [main]
    paths:
      - 'app/**'

jobs:
  # Security scans
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bin/brakeman --no-pager --exit-on-warn
      - run: bin/bundler-audit
      - run: bin/importmap audit

  # Linting
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bin/rubocop -f github

  # Tests
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bin/rails db:test:prepare test
      - run: bin/rails test:system
        if: always()
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: screenshots
          path: tmp/screenshots

  # Build and push Docker image
  build:
    needs: [scan, lint, test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bin/kamal registry login
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
      - run: bin/kamal build push
        env:
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}

  # Deploy via VPN
  deploy:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      # Connect to VPN for SSH access
      - uses: tailscale/github-action@v2
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_CLIENT_SECRET }}
          tags: tag:ci

      # Deploy
      - run: |
          if bin/kamal proxy status 2>/dev/null; then
            bin/kamal deploy --skip-push
          else
            bin/kamal setup
          fi
        env:
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
          STORAGE_ACCOUNT_NAME: ${{ secrets.STORAGE_ACCOUNT_NAME }}
          STORAGE_ACCOUNT_KEY: ${{ secrets.STORAGE_ACCOUNT_KEY }}

      # Verify deployment
      - run: |
          sleep 10
          bin/kamal proxy status
```

### Required Secrets

| Secret | Purpose | Source |
|--------|---------|--------|
| `RAILS_MASTER_KEY` | Rails credentials encryption | `config/credentials.key` |
| `GITHUB_TOKEN` | Container registry auth | Auto-provided by GitHub |
| `TAILSCALE_OAUTH_CLIENT_ID` | VPN authentication | Tailscale admin console |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | VPN authentication | Tailscale admin console |
| `STORAGE_ACCOUNT_NAME` | Litestream backup destination | Cloud provider |
| `STORAGE_ACCOUNT_KEY` | Litestream backup auth | Cloud provider |

### Deployment Flow

1. **PR opened**: Run security scans, linting, tests
2. **PR merged to main**: All checks pass → build image → push to registry
3. **Deploy**: Connect VPN → SSH to server → run `kamal deploy`
4. **Verify**: Check containers are running via `kamal proxy status`

## ActiveStorage with Cloud Storage

### Configuration

```yaml
# config/storage.yml
local:
  service: Disk
  root: <%= Rails.root.join("storage/files") %>

production:
  service: AzureStorage           # Or S3, GCS
  storage_account_name: <%= ENV['STORAGE_ACCOUNT_NAME'] %>
  storage_access_key: <%= ENV['STORAGE_ACCESS_KEY'] %>
  container: attachments-<%= Rails.env %>

# For S3-compatible storage:
# production:
#   service: S3
#   access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
#   secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
#   region: us-east-1
#   bucket: myapp-attachments-<%= Rails.env %>
```

### Environment Configuration

```ruby
# config/environments/production.rb
config.active_storage.service = :production
```

### CORS Configuration

For direct uploads, configure CORS on your storage bucket:

```json
{
  "corsRules": [
    {
      "allowedOrigins": ["https://app.example.com"],
      "allowedMethods": ["GET", "HEAD", "PUT", "POST", "OPTIONS"],
      "allowedHeaders": ["*"],
      "exposedHeaders": ["ETag"],
      "maxAgeInSeconds": 3600
    }
  ]
}
```

## Dockerfile Best Practices

### Multi-Stage Build

```dockerfile
# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.4.1

# Base image
FROM ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle

# Build stage
FROM base AS build

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential git pkg-config libssl-dev libyaml-dev

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

# Copy application code
COPY . .

# Precompile bootsnap and assets
RUN bundle exec bootsnap precompile app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage
FROM base

# Install runtime dependencies only
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl libjemalloc2 libvips sqlite3 poppler-utils && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Create non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp

USER 1000:1000

# Enable jemalloc for better memory performance
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

### Docker Entrypoint

```bash
#!/bin/bash
set -e

# Enable jemalloc
export LD_PRELOAD=$(find /usr/lib -name 'libjemalloc.so.2' 2>/dev/null | head -1)

# Auto-migrate when starting Rails server
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "$@"
```

### Key Optimizations

1. **Multi-stage build**: Separates build dependencies from runtime
2. **jemalloc**: Better memory allocation, reduces fragmentation
3. **Non-root user**: Security best practice
4. **Bootsnap precompile**: Faster boot times
5. **Asset precompilation**: Done at build time, not runtime

## Thruster: HTTP Layer

### What is Thruster?

Thruster is a lightweight HTTP layer that sits in front of Puma:
- **X-Sendfile**: Efficient file serving
- **Asset caching**: Long cache headers for fingerprinted assets
- **Compression**: gzip/brotli compression
- **HTTP/2**: Multiplexed connections

### Configuration

```ruby
# Gemfile
gem "thruster", require: false
```

```dockerfile
# Dockerfile
CMD ["./bin/thrust", "./bin/rails", "server"]
```

Thruster automatically:
- Serves static assets with long cache headers
- Compresses responses
- Handles keep-alive connections efficiently

## Security Considerations

### Network Security

1. **No public IP**: VM only accessible via tunnel and VPN
2. **Firewall**: UFW denies all except VPN traffic
3. **Edge protection**: DDoS mitigation, WAF at CDN layer
4. **SSH**: Only via authenticated VPN

### Application Security

1. **SSL everywhere**: Strict SSL mode with HSTS
2. **Secrets management**: Environment variables, never in code
3. **Security scanning**: Brakeman, bundler-audit, importmap audit in CI
4. **Regular updates**: Dependabot for dependency updates

### Database Security

1. **Encryption at rest**: Cloud storage encryption
2. **Continuous backup**: Litestream replication
3. **Point-in-time recovery**: Restore to any moment
4. **No external access**: Database is local file, not network accessible

## Cost Optimization

### Infrastructure Costs

| Component | Traditional | SQLite Stack |
|-----------|------------|--------------|
| Database | $50-200/mo (managed PostgreSQL) | $0 (SQLite on VM) |
| Redis | $15-50/mo (managed Redis) | $0 (Solid Cache/Queue/Cable) |
| Backup storage | Included | $5-10/mo (object storage) |
| VM | $20-100/mo | $20-100/mo |
| **Total** | **$85-350/mo** | **$25-110/mo** |

### Why SQLite is Cheaper

1. No managed database service fees
2. No Redis hosting costs
3. Object storage is cheap ($0.02/GB/month)
4. Single VM handles everything

## Monitoring and Observability

### Health Checks

```ruby
# config/routes.rb
get '/up', to: 'health#show'

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    render json: {
      status: 'ok',
      database: database_connected?,
      queue: queue_healthy?,
      cache: cache_healthy?
    }
  end

  private

  def database_connected?
    ApplicationRecord.connection.active?
  rescue
    false
  end

  def queue_healthy?
    SolidQueue::Process.where('last_heartbeat_at > ?', 5.minutes.ago).exists?
  rescue
    false
  end

  def cache_healthy?
    Rails.cache.write('health_check', Time.current)
    Rails.cache.read('health_check').present?
  rescue
    false
  end
end
```

### Logging

```ruby
# config/environments/production.rb
config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info').to_sym
config.rails_semantic_logger.format = :json  # If using semantic_logger
config.log_tags = [:request_id]              # Trace requests across logs
```

### Kamal Log Access

```bash
# View all logs
bin/kamal logs -f

# View specific service
bin/kamal logs -f -r job

# View accessory logs
bin/kamal accessory logs litestream
```

## References

- [Kamal Documentation](https://kamal-deploy.org/)
- [Litestream Documentation](https://litestream.io/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Rails 8 Solid Queue](https://github.com/rails/solid_queue)
- [Thruster](https://github.com/basecamp/thruster)
