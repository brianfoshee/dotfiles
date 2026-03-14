---
name: cloudflare-domain-setup
description: Sets up a new domain on Cloudflare with Terraform-managed infrastructure including a static landing page served by a Worker, email routing with auto-reply via a separate email Worker, D1 database for email metadata, and R2 for raw email storage. Use when setting up a new domain, creating a landing page on Cloudflare Workers, or adding email handling to a Cloudflare zone.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Cloudflare Domain Setup

Sets up a new domain on Cloudflare with a static landing page Worker, email routing with auto-reply, and Terraform infrastructure.

## Architecture Overview

Two Workers per domain, all infrastructure managed by Terraform:

1. **Site Worker** — Serves static HTML/CSS from a `dist/` directory via Terraform's assets binding
2. **Email Worker** — Handles inbound email via Cloudflare Email Routing, stores in R2 + D1, sends auto-reply

Supporting infrastructure:
- **D1 Database** — Email metadata (sender, recipient, subject, dates)
- **R2 Bucket** — Raw email storage
- **Email Routing** — MX/DNS records, routing rules to the email worker
- **Zone Settings** — HTTPS enforcement, TLS 1.2 minimum, HSTS

## Project Structure

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
├── terraform/
│   ├── provider.tf            # Cloudflare provider
│   ├── variables.tf           # Account/zone IDs, API token
│   ├── site.tf                # Site worker, custom domain, zone settings
│   └── email.tf               # Email worker, D1, R2, routing rules
└── CLAUDE.md
```

## Terraform Configuration

### Provider (`provider.tf`)

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.11"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
```

### Variables (`variables.tf`)

Three required variables:
- `cloudflare_api_token` (sensitive) — API token with zone/worker/D1/R2 permissions
- `cloudflare_account_id` — Cloudflare account ID
- `cloudflare_zone_id` — Zone ID for the domain

### Site Resources (`site.tf`)

Key resources:
- `cloudflare_workers_script` — Site worker with assets binding pointing to `../dist/`
  - Configure `assets { directory = "../dist/", binding = "ASSETS" }` with `html_handling = "auto-trailing-slash"` and `not_found_handling = "404-page"`
- `cloudflare_workers_custom_domain` — Routes apex domain to the site worker
- `cloudflare_zone_setting` — Always HTTPS, min TLS 1.2, HSTS (1 year, include subdomains, preload)
- Enable observability with `observability { enabled = true, logs { enabled = true, invocation_logs = true } }`

### Email Resources (`email.tf`)

Key resources:
- `cloudflare_d1_database` — For email metadata
- `cloudflare_r2_bucket` — For raw email storage
- `cloudflare_email_routing_settings` — Enables email routing on the zone
- `cloudflare_email_routing_dns` — Creates required MX and verification DNS records
- `cloudflare_workers_script` — Email worker with D1 and R2 bindings, `nodejs_compat` flag
- `cloudflare_email_routing_rule` — Routes specific addresses to the email worker

## Worker Code

### Site Worker (`site-worker.js`)

Minimal — assets are served automatically by the assets binding. The worker only handles fallback:

```javascript
// Fallback handler for routes not matched by static assets
export default {
  async fetch(request) {
    return new Response("Not Found", { status: 404 });
  },
};
```

### Email Worker (`email-worker.js`)

Handles inbound email with these responsibilities:

1. **Auto-reply detection** (RFC 3834) — Check `Auto-Submitted`, `Precedence`, and `X-Auto-Response-Suppress` headers to prevent mail loops
2. **Raw storage** — Buffer the raw email stream and store in R2 with a timestamped UUID key
3. **Metadata storage** — Insert sender, recipient, subject, message ID, and date into D1
4. **Auto-reply** — Send a MIME-formatted reply with `Auto-Submitted: auto-replied` and `In-Reply-To` headers

Dependencies: `mimetext` for MIME message construction.

### D1 Schema (`schema.sql`)

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

## Build Setup

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
- `wrangler` (dev) — D1 migrations
- `serve` (dev) — Local dev server

## Build & Deploy

```bash
# Build
cd cloudflare && npm install && npm run build

# Deploy (Terraform manages everything)
cd terraform && terraform apply

# D1 migrations (separate from Terraform)
cd cloudflare && npm run db:migrate
```

## Setup Checklist for a New Domain

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

## Key Design Decisions

- **Terraform over Wrangler for deployment** — Wrangler is only used for D1 migrations. All worker deployment and infrastructure is Terraform-managed for reproducibility.
- **Separate workers** — Site and email workers are independent, deployed separately with different bindings.
- **esbuild for email worker** — The email worker needs `mimetext` bundled. The site worker has no dependencies and doesn't need bundling.
- **RFC 3834 compliance** — Auto-reply detection prevents mail loops by checking standard headers before responding.
- **Dual storage** — R2 for raw email (cheap, durable), D1 for queryable metadata.
