# Email Routing

Inbound email handling with Cloudflare Email Routing: a Worker that stores raw email in
R2 and metadata in D1, plus the routing settings, DNS, and rules. All Terraform targets
the `cloudflare/cloudflare` provider v5.

## Contents

- [Email Infrastructure (Terraform)](#email-infrastructure-terraform)
- [Email Worker](#email-worker)
- [D1 Schema](#d1-schema)

## Email Infrastructure (Terraform)

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

# Email routing settings. Email Routing enablement is managed by Cloudflare;
# the `enabled` attribute is read-only in provider v5, so it is not set here.
resource "cloudflare_email_routing_settings" "zone" {
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_email_routing_dns" "zone" {
  zone_id = var.cloudflare_zone_id
}

# Email worker with D1 and R2 bindings. In provider v5 all bindings live in a single
# `bindings` list (no per-type blocks), and a module-syntax worker sets `main_module`.
resource "cloudflare_workers_script" "email" {
  account_id  = var.cloudflare_account_id
  script_name = "myapp-email"
  content     = file("../cloudflare/email-worker.bundle.js")
  main_module = "email-worker.bundle.js"

  compatibility_flags = ["nodejs_compat"]

  bindings = [
    {
      name = "EMAIL_DB"
      type = "d1"
      id   = cloudflare_d1_database.email.id
    },
    {
      name        = "EMAIL_RAW"
      type        = "r2_bucket"
      bucket_name = cloudflare_r2_bucket.email.name
    }
  ]
}

# Route specific addresses to the email worker. Matchers and actions are attribute
# lists in provider v5.
resource "cloudflare_email_routing_rule" "info" {
  zone_id = var.cloudflare_zone_id
  name    = "info@${var.domain}"

  matchers = [
    {
      type  = "literal"
      field = "to"
      value = "info@${var.domain}"
    }
  ]

  actions = [
    {
      type  = "worker"
      value = [cloudflare_workers_script.email.script_name]
    }
  ]
}
```

## Email Worker

Handles inbound email with these responsibilities:

1. **Auto-reply detection** — Check the `Auto-Submitted` header (RFC 3834) to prevent
   mail loops, plus `Precedence` and `X-Auto-Response-Suppress` (a Microsoft header) as
   common anti-loop heuristics
2. **Raw storage** — Buffer the raw email stream and store in R2 with a timestamped UUID key
3. **Metadata storage** — Insert sender, recipient, subject, message ID, and date into D1
4. **Auto-reply** — Send a MIME-formatted reply with `Auto-Submitted: auto-replied`
   (RFC 3834) and `In-Reply-To` headers

Dependencies: `mimetext` for MIME message construction. The email worker is bundled with
esbuild because of this dependency (see the build scripts in SKILL.md).

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
