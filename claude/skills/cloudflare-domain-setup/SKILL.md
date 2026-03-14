---
name: cloudflare-domain-setup
description: Sets up a new domain on Cloudflare with Terraform-managed infrastructure. Covers static landing pages, email routing, Zero Trust tunnels to origin servers, app proxy Workers, ACME/Let's Encrypt passthrough, R2 storage, D1 databases, DNS patterns, rulesets, and zone security settings. Use when setting up a new domain, creating Workers, configuring tunnels, or managing any Cloudflare infrastructure with Terraform.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Cloudflare Domain Setup

Comprehensive guide for setting up domains on Cloudflare with Terraform-managed infrastructure. Covers two deployment models and all common Cloudflare features.

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
      # Check https://registry.terraform.io/providers/cloudflare/cloudflare/latest for the latest version
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

### Zero Trust Tunnel

Establishes a secure outbound connection from an origin server to Cloudflare's edge. No public IP or open inbound ports needed on the origin.

```hcl
resource "cloudflare_zero_trust_tunnel_cloudflared" "app" {
  account_id = var.cloudflare_account_id
  name       = "myapp"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "app" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id

  config = {
    ingress = [
      # ACME challenges — route to HTTP port 80 for Let's Encrypt validation
      {
        hostname = "app.${var.domain}"
        path     = "/.well-known/acme-challenge/*"
        service  = "http://localhost:80"
      },
      # Regular traffic — HTTPS to the app's reverse proxy
      {
        hostname = "app.${var.domain}"
        service  = "https://localhost:443"
        origin_request = {
          origin_server_name = "app.${var.domain}"
        }
      },
      # Catch-all
      {
        service = "http_status:404"
      }
    ]
  }
}

# Retrieve the tunnel token for the cloudflared daemon
data "cloudflare_zero_trust_tunnel_cloudflared_token" "app" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.app.id
}

output "tunnel_token" {
  description = "Token for connecting the cloudflared daemon"
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.app.token
  sensitive   = true
}
```

### ACME/Let's Encrypt Passthrough

When using a Zero Trust tunnel + strict SSL + a Worker, Let's Encrypt HTTP-01 challenges require **three coordinated layers** to reach the origin:

**Layer 1: Tunnel ingress** (above) — Routes ACME paths to `http://localhost:80`.

**Layer 2: SSL ruleset** — Downgrades SSL to `flexible` for ACME paths so Cloudflare connects to origin via HTTP:

```hcl
resource "cloudflare_ruleset" "acme_ssl_bypass" {
  zone_id = var.cloudflare_zone_id
  name    = "ACME Challenge SSL Configuration"
  kind    = "zone"
  phase   = "http_config_settings"

  rules = [
    {
      action = "set_config"
      action_parameters = {
        ssl = "flexible"
      }
      expression  = "(http.host eq \"app.${var.domain}\" and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\"))"
      description = "Downgrade SSL for ACME challenges"
      enabled     = true
    }
  ]
}
```

**Layer 3: Worker bypass** — A more specific Worker route with no script takes precedence, letting the request pass through to the tunnel:

```hcl
# Main worker route
resource "cloudflare_workers_route" "app_proxy" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.${var.domain}/*"
  script  = cloudflare_worker.app_proxy.name
}

# ACME bypass — more specific pattern, no script = bypass Worker
resource "cloudflare_workers_route" "acme_bypass" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.${var.domain}/.well-known/acme-challenge/*"
  # No script = route disabled, falls through to origin
}
```

**ACME troubleshooting:**
1. Check tunnel logs — is the request reaching the tunnel?
2. Check reverse proxy logs — is the request reaching port 80?
3. Test manually: `curl -v http://app.example.com/.well-known/acme-challenge/test`
4. Verify ruleset in dashboard: Rules → Configuration Rules
5. Verify Worker routes in dashboard: Workers → Routes (ACME route should have no script)

### Rulesets

**WWW → naked domain redirect:**

```hcl
resource "cloudflare_ruleset" "www_redirect" {
  zone_id = var.cloudflare_zone_id
  name    = "Redirect www to naked domain"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      action      = "redirect"
      expression  = "(http.host eq \"www.${var.domain}\")"
      description = "Redirect www to naked domain"

      action_parameters = {
        from_value = {
          status_code           = 301
          preserve_query_string = true
          target_url = {
            expression = "concat(\"https://${var.domain}\", http.request.uri.path)"
          }
        }
      }
    }
  ]
}
```

**Common ruleset phases:**
- `http_config_settings` — SSL mode, cache settings (applied before routing)
- `http_request_dynamic_redirect` — Redirects (applied before Workers/cache)

### R2 Buckets

```hcl
resource "cloudflare_r2_bucket" "storage" {
  account_id = var.cloudflare_account_id
  name       = "myapp-storage"
}
```

### Workers

#### Modern Worker Deployment Pattern (Provider v5+)

Three-step deployment: resource → version → deployment, plus route binding.

```hcl
# 1. Worker resource (metadata and settings)
resource "cloudflare_worker" "app_proxy" {
  account_id = var.cloudflare_account_id
  name       = "myapp-proxy"

  observability = {
    enabled            = true
    head_sampling_rate = 1.0
    logs = {
      enabled            = true
      invocation_logs    = true
      head_sampling_rate = 1.0
    }
  }

  # Disable public access via workers.dev
  subdomain = {
    enabled          = false
    previews_enabled = false
  }
}

# 2. Worker version (script content and bindings)
resource "cloudflare_worker_version" "app_proxy" {
  account_id = var.cloudflare_account_id
  worker_id  = cloudflare_worker.app_proxy.id

  modules = [{
    name         = "index.js"
    content_file = "../cloudflare/workers/app-proxy/index.js"
    content_type = "application/javascript+module"
  }]

  main_module        = "index.js"
  compatibility_date = "2024-01-01"

  # Optional bindings
  bindings = [
    {
      name = "html"
      type = "plain_text"
      text = file("../cloudflare/workers/landing/index.html")
    }
  ]
}

# 3. Worker deployment
resource "cloudflare_workers_deployment" "app_proxy" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.app_proxy.name

  strategy = "percentage"
  versions = [{
    version_id = cloudflare_worker_version.app_proxy.id
    percentage = 100
  }]
}

# 4. Route binding
resource "cloudflare_workers_route" "app_proxy" {
  zone_id = var.cloudflare_zone_id
  pattern = "app.${var.domain}/*"
  script  = cloudflare_worker.app_proxy.name
}
```

**Binding types:**
- `plain_text` — Static content (HTML, config strings)
- `d1_database` — D1 database
- `r2_bucket` — R2 storage
- `assets` — Static file directory (with `html_handling` and `not_found_handling`)

**Compatibility flags:**
- `nodejs_compat` — Required for Workers using Node.js APIs (e.g., email Worker with `mimetext`)

#### Site Worker (Assets Binding)

For static sites, use the assets binding to serve files from a build directory:

```hcl
resource "cloudflare_workers_script" "site" {
  account_id = var.cloudflare_account_id
  script_name = "mysite"
  content     = file("../cloudflare/site-worker.js")
  module      = true

  assets {
    directory = "../dist/"
    binding   = "ASSETS"
    config = {
      html_handling    = "auto-trailing-slash"
      not_found_handling = "404-page"
    }
  }

  observability {
    enabled = true
    logs {
      enabled         = true
      invocation_logs = true
    }
  }
}

resource "cloudflare_workers_custom_domain" "site" {
  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  hostname   = var.domain
  service    = cloudflare_workers_script.site.script_name
}
```

#### Email Worker

```hcl
# D1 database for email metadata
resource "cloudflare_d1_database" "email" {
  account_id = var.cloudflare_account_id
  name       = "myapp-email"
}

# R2 bucket for raw email storage
resource "cloudflare_r2_bucket" "email" {
  account_id = var.cloudflare_account_id
  name       = "myapp-email-raw"
}

# Email routing
resource "cloudflare_email_routing_settings" "zone" {
  zone_id = var.cloudflare_zone_id
  enabled = true
}

resource "cloudflare_email_routing_dns" "zone" {
  zone_id = var.cloudflare_zone_id
}

# Email worker with D1 and R2 bindings
resource "cloudflare_workers_script" "email" {
  account_id  = var.cloudflare_account_id
  script_name = "myapp-email"
  content     = file("../cloudflare/email-worker.bundle.js")
  module      = true

  compatibility_flags = ["nodejs_compat"]

  d1_database_binding {
    name        = "EMAIL_DB"
    database_id = cloudflare_d1_database.email.id
  }

  r2_bucket_binding {
    name        = "EMAIL_RAW"
    bucket_name = cloudflare_r2_bucket.email.name
  }
}

# Route specific addresses to the email worker
resource "cloudflare_email_routing_rule" "info" {
  zone_id = var.cloudflare_zone_id
  name    = "info@${var.domain}"

  matcher {
    type  = "literal"
    field = "to"
    value = "info@${var.domain}"
  }

  action {
    type  = "worker"
    value = [cloudflare_workers_script.email.script_name]
  }
}
```

## Worker Code

### App Proxy Worker (Pass-Through)

```javascript
// Passes requests through to origin (tunnel handles routing)
export default {
  async fetch(request) {
    return await fetch(request);
  },
};
```

### Site Worker (Assets Fallback)

```javascript
// Fallback handler for routes not matched by static assets
export default {
  async fetch(request) {
    return new Response("Not Found", { status: 404 });
  },
};
```

### Landing Page Worker (Inline Content)

```javascript
// Serves landing page from plain_text binding
export default {
  async fetch(request, env) {
    return new Response(env.html, {
      headers: {
        "content-type": "text/html;charset=UTF-8",
        "cache-control": "public, max-age=3600",
        "x-frame-options": "DENY",
        "x-content-type-options": "nosniff",
        "referrer-policy": "strict-origin-when-cross-origin",
      },
    });
  },
};
```

### Email Worker

Handles inbound email with these responsibilities:

1. **Auto-reply detection** (RFC 3834) — Check `Auto-Submitted`, `Precedence`, and `X-Auto-Response-Suppress` headers to prevent mail loops
2. **Raw storage** — Buffer the raw email stream and store in R2 with a timestamped UUID key
3. **Metadata storage** — Insert sender, recipient, subject, message ID, and date into D1
4. **Auto-reply** — Send a MIME-formatted reply with `Auto-Submitted: auto-replied` and `In-Reply-To` headers

Dependencies: `mimetext` for MIME message construction.

### Security Headers

Apply to all Worker responses serving content to browsers:

```javascript
const SECURITY_HEADERS = {
  "x-frame-options": "DENY",              // Prevent clickjacking
  "x-content-type-options": "nosniff",     // Prevent MIME sniffing
  "referrer-policy": "strict-origin-when-cross-origin",
};
```

**Caching strategy:**
- HTML pages: `cache-control: public, max-age=3600` (1 hour)
- Static assets (images, fonts): `cache-control: public, max-age=86400` (24 hours)
- API responses: `cache-control: no-store`

## D1 Schema

```sql
CREATE TABLE IF NOT EXISTS emails (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id  TEXT    NOT NULL,
  sender      TEXT    NOT NULL,
  recipient   TEXT    NOT NULL,
  subject     TEXT    NOT NULL DEFAULT '',
  received_at TEXT    NOT NULL,
  r2_key      TEXT    NOT NULL,
  created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_emails_sender ON emails(sender);
CREATE INDEX IF NOT EXISTS idx_emails_received_at ON emails(received_at);
```

## R2 Usage Patterns

### Terraform State Backend

Use R2 as an S3-compatible backend for Terraform state. The R2 bucket must be created manually first (not managed by the same Terraform config that uses it as backend).

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "myapp.tfstate"

    endpoints = {
      s3 = "https://<account-id>.r2.cloudflarestorage.com"
    }
    region = "us-east-1"

    # Required for R2 compatibility
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
```

Authenticate via `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` env vars (R2 API tokens).

### Litestream Backup Target

R2 is S3-compatible, so Litestream uses the `s3` replica type:

```yaml
# config/litestream.yml
dbs:
  - path: /rails/storage/production.sqlite3
    replicas:
      - type: s3
        bucket: myapp-backups
        endpoint: https://<account-id>.r2.cloudflarestorage.com
        region: auto
        access-key-id: $LITESTREAM_ACCESS_KEY_ID
        secret-access-key: $LITESTREAM_SECRET_ACCESS_KEY
        path: production.sqlite3
        sync-interval: 60s
```

### ActiveStorage Service

R2 works with Rails ActiveStorage via the S3 adapter:

```yaml
# config/storage.yml
r2:
  service: S3
  access_key_id: <%= Rails.application.credentials.dig(:r2, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:r2, :secret_access_key) %>
  endpoint: https://<account-id>.r2.cloudflarestorage.com
  region: auto
  bucket: myapp-uploads
  force_path_style: true
```

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
- **RFC 3834 compliance** — Auto-reply detection prevents mail loops by checking standard headers before responding.
- **Dual storage for email** — R2 for raw email (cheap, durable), D1 for queryable metadata.
- **Workers.dev disabled** — All workers have `subdomain.enabled = false` and `subdomain.previews_enabled = false` to prevent public access via workers.dev URLs.
- **Three-layer ACME passthrough** — Tunnel ingress + SSL ruleset + Worker bypass are all needed when combining strict SSL, tunnels, and Workers.
- **`network: host` for tunnel accessory** — The cloudflared container must use host networking to connect to services on localhost.
