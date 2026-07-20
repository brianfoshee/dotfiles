---
name: cloudflare-domain-setup
description: Sets up a new domain on Cloudflare with Terraform-managed infrastructure. Covers static landing pages, email routing, Zero Trust tunnels to origin servers, app proxy Workers, ACME/Let's Encrypt passthrough, R2 storage, D1 databases, DNS patterns, rulesets, and zone security settings. Use when setting up a new domain, creating Workers, configuring tunnels, or managing any Cloudflare infrastructure with Terraform.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Cloudflare Domain Setup

Guide for setting up domains on Cloudflare with Terraform-managed infrastructure
(`cloudflare/cloudflare` provider v5). Covers two deployment models and all common
Cloudflare features. Detailed Terraform, worker code, and storage patterns live in
`docs/` — see [Reference Documentation](#reference-documentation).

## Architecture Overview

### Deployment Model 1: Static Site + Email

Two Workers, no origin server needed:

1. **Site Worker** — Serves static HTML/CSS from a `dist/` directory via Terraform's assets binding
2. **Email Worker** — Handles inbound email via Cloudflare Email Routing, stores in R2 + D1, sends auto-reply

Supporting infrastructure: D1 database, R2 bucket, email routing, zone settings.

### Deployment Model 2: App with Zero Trust Tunnel

Traffic flows through Cloudflare to an origin server via a Zero Trust tunnel:

```
Client → Cloudflare Edge → Worker (optional) → Zero Trust Tunnel → Origin Server
```

1. **App Proxy Worker** — Sits in front of the tunnel (pass-through, auth, filtering)
2. **Landing Worker** — Serves static landing page at root domain
3. **Zero Trust Tunnel** — Secure connection from origin VM to Cloudflare (no public IP needed)

Supporting infrastructure: DNS records, ACME passthrough config, rulesets, zone settings.

### Combined Model

Both models can coexist on the same domain — e.g., static landing at root, app via tunnel on subdomain, email routing on the zone.

## Project Structure

### Static Site + Email

```
project/
├── cloudflare/
│   ├── site/
│   │   ├── index.html        # Landing page
│   │   └── styles.css         # Tailwind CSS v4 entrypoint
│   ├── site-worker.js         # Static asset fallback handler
│   ├── email-worker.js        # Email handler with auto-reply
│   ├── schema.sql             # D1 database schema
│   ├── wrangler.jsonc         # Wrangler config (D1 migrations only)
│   └── package.json           # Build scripts and dependencies
├── dist/                      # Build output (gitignored)
└── terraform/
    ├── provider.tf
    ├── variables.tf
    ├── site.tf                # Site worker, custom domain, zone settings
    └── email.tf               # Email worker, D1, R2, routing rules
```

### App with Tunnel

```
project/
├── cloudflare/
│   └── workers/
│       ├── app-proxy/
│       │   └── index.js       # App proxy worker (pass-through or auth)
│       └── landing/
│           ├── index.js       # Landing page worker
│           └── index.html     # Landing page content
└── terraform/
    ├── backend.tf             # R2-backed Terraform state (optional)
    ├── main.tf                # Provider configuration
    ├── variables.tf
    ├── cloudflare.tf          # Zone settings, DNS, tunnel, rulesets
    ├── worker-app-proxy.tf    # App proxy worker deployment
    └── worker-landing.tf      # Landing page worker deployment
```

## Terraform Configuration

### Provider

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
      # Check https://registry.terraform.io/providers/cloudflare/cloudflare/latest for the latest 5.x release
    }
  }
}

# Authenticates via var.cloudflare_api_token or CLOUDFLARE_API_TOKEN env var
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
```

### Variables

Core variables for any Cloudflare setup:

```hcl
variable "cloudflare_api_token" {
  description = "Cloudflare API token (optional if CLOUDFLARE_API_TOKEN env var is set)"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "example.com"
}
```

### Zone Settings

```hcl
# Redirect HTTP to HTTPS
resource "cloudflare_zone_setting" "always_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

# HSTS with preload
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 31536000
      include_subdomains = true
      preload            = true
      nosniff            = true
    }
  }
}

# Minimum TLS 1.2
resource "cloudflare_zone_setting" "min_tls" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

# SSL Full (Strict) — requires valid certificate on origin
resource "cloudflare_zone_setting" "ssl_strict" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

# Disable automatic HTTPS rewrites (let the app handle asset URLs)
resource "cloudflare_zone_setting" "https_rewrites" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "automatic_https_rewrites"
  value      = "off"
}

# Enable WebSockets (for ActionCable, Phoenix Channels, etc.)
# WARNING: Cannot be destroyed via Terraform once created. Must disable via dashboard.
resource "cloudflare_zone_setting" "websockets" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "websockets"
  value      = "on"
}

# DNSSEC
resource "cloudflare_zone_dnssec" "dnssec" {
  zone_id = var.cloudflare_zone_id
  status  = "active"
}
```

### DNS Patterns

**App subdomain via tunnel** — CNAME pointing to the tunnel:

```hcl
resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.app.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}
```

**Workers handle DNS for Worker-served domains** — When a Worker route is bound to a domain pattern, Cloudflare handles the DNS routing automatically. No placeholder A records are needed for domains served entirely by Workers.

**WWW redirect** — If using a ruleset to redirect `www` to the naked domain, a proxied DNS record is needed for the www subdomain so Cloudflare can intercept and redirect the request:

```hcl
resource "cloudflare_dns_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = "192.0.2.1" # RFC 5737 documentation IP (traffic handled by redirect rule)
  type    = "A"
  proxied = true
  ttl     = 1
}
```

## Reference Documentation

Detailed Terraform, worker JavaScript, and storage patterns live in `docs/`. Read the
relevant file when its topic comes up.

### Workers (Terraform + JS)
**`docs/workers-terraform.md`** — Three-resource worker deployment (worker + version + deployment), site worker with the assets binding, worker custom domains, binding types, compatibility flags, and worker JavaScript (app proxy pass-through, site fallback, landing page, security headers, caching).
**When to read**: Deploying any Worker, serving static sites/assets, worker bindings, worker routes, or writing worker JS.

### Zero Trust Tunnel & Routing
**`docs/tunnel-and-acme.md`** — Zero Trust tunnel + token data source, three-layer ACME/Let's Encrypt passthrough, SSL-bypass ruleset, www→naked redirect ruleset, ruleset phases, and ACME troubleshooting.
**When to read**: Tunnels to an origin server, ACME/Let's Encrypt cert issuance behind Cloudflare, redirects, or rulesets.

### Email Routing
**`docs/email-routing.md`** — Email worker with D1 + R2 bindings, email routing settings/DNS/rules, the email worker's responsibilities (auto-reply, dual storage), and the D1 schema.
**When to read**: Inbound email handling, email routing rules, D1 databases, or auto-reply logic.

### R2 Storage
**`docs/r2-storage.md`** — R2 buckets, Terraform state backend on R2, Litestream backups, and Rails ActiveStorage via the S3 adapter.
**When to read**: R2 buckets, S3-compatible storage, Terraform remote state, SQLite backups, or ActiveStorage.

## Cloudflare API Token Permissions

| Scope   | Permission          | Access | Used for                          |
|---------|---------------------|--------|-----------------------------------|
| Zone    | Zone Settings       | Edit   | SSL mode, HTTPS, TLS version, HSTS |
| Zone    | DNS                 | Edit   | Tunnel CNAME, redirect records    |
| Zone    | Config Rules        | Edit   | ACME challenge SSL override       |
| Zone    | Single Redirects    | Edit   | WWW → naked domain redirect       |
| Zone    | Workers Routes      | Edit   | Worker route bindings             |
| Account | Workers Scripts     | Edit   | Worker deployment                 |
| Account | Cloudflare Tunnel   | Edit   | Tunnel and ingress configuration  |
| Account | D1                  | Edit   | D1 database management            |
| Account | R2 Storage          | Edit   | R2 bucket management              |
| Zone    | Email Routing Rules | Edit   | Email routing configuration       |

## Build & Deploy

### package.json Scripts

```json
{
  "scripts": {
    "build:site": "mkdir -p ../dist && cp site/index.html ../dist/ && npx @tailwindcss/cli -i site/styles.css -o ../dist/styles.css",
    "build:email": "npx esbuild email-worker.js --bundle --outfile=email-worker.bundle.js --format=esm --target=es2022 --platform=browser --external:cloudflare:email",
    "build": "npm run build:site && npm run build:email",
    "dev": "npx @tailwindcss/cli -i site/styles.css -o ../dist/styles.css --watch & npx serve ../dist -l 3014",
    "db:migrate": "npx wrangler d1 execute EMAIL_DB_NAME --remote --file=./schema.sql"
  }
}
```

### Dependencies

- `@tailwindcss/cli` — CSS compilation
- `mimetext` — MIME message construction for email replies
- `esbuild` (dev) — Bundles email worker with its dependencies
- `wrangler` (dev) — D1 migrations only
- `serve` (dev) — Local dev server

### Deployment

```bash
# Build (for static site + email model)
cd cloudflare && npm install && npm run build

# Deploy all infrastructure
cd terraform && terraform apply

# D1 migrations (separate from Terraform)
cd cloudflare && npm run db:migrate
```

## Setup Checklist

### Static Site + Email

1. Register domain and add to Cloudflare (get zone ID)
2. Create Terraform variables for account ID, zone ID, API token
3. Create site worker with assets binding
4. Create landing page HTML + Tailwind CSS in `cloudflare/site/`
5. Create email worker with auto-reply logic
6. Create D1 database and R2 bucket via Terraform
7. Configure email routing settings, DNS, and rules via Terraform
8. Set zone security settings (HTTPS, TLS, HSTS)
9. Build and deploy: `npm run build` then `terraform apply`
10. Run D1 migrations: `npm run db:migrate`
11. Verify email routing works by sending a test email

### App with Tunnel

1. Register domain and add to Cloudflare (get zone ID)
2. Create Terraform variables for account ID, zone ID, API token
3. Create Zero Trust tunnel resource and ingress config
4. Create DNS CNAME record pointing app subdomain to tunnel
5. Create app proxy Worker (pass-through or with auth logic)
6. Create ACME passthrough: SSL ruleset + Worker route bypass
7. Create landing Worker for root domain (optional)
8. Create WWW redirect ruleset (optional)
9. Set zone security settings (HTTPS, TLS, HSTS, WebSockets, DNSSEC)
10. Run `terraform apply`
11. Install cloudflared on origin and connect using the tunnel token
12. Verify tunnel connectivity and SSL certificate issuance

## Key Design Decisions

- **Terraform over Wrangler for deployment** — Wrangler is only used for D1 migrations. All worker deployment and infrastructure is Terraform-managed for reproducibility.
- **Separate workers per concern** — Site, email, and app proxy workers are independent with different bindings and deploy separately.
- **esbuild for email worker only** — Only the email worker needs bundling (has `mimetext` dependency). Static workers have no dependencies.
- **RFC 3834 auto-reply detection** — Auto-reply prevention checks the RFC 3834 `Auto-Submitted` header plus common anti-loop heuristics before responding.
- **Dual storage for email** — R2 for raw email (cheap, durable), D1 for queryable metadata.
- **Workers.dev disabled** — All workers have `subdomain.enabled = false` and `subdomain.previews_enabled = false` to prevent public access via workers.dev URLs.
- **Three-layer ACME passthrough** — Tunnel ingress + SSL ruleset + Worker bypass are all needed when combining strict SSL, tunnels, and Workers.
- **`network: host` for tunnel accessory** — The cloudflared container must use host networking to connect to services on localhost.
