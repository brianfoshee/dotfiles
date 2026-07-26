---
name: cloudflare-domain-setup
description: Sets up a new domain on Cloudflare with Terraform-managed infrastructure. Covers static landing pages, email routing, Zero Trust tunnels to origin servers, app proxy Workers, ACME/Let's Encrypt passthrough, R2 storage, D1 databases, DNS patterns, rulesets, and zone security settings. Use when setting up a new domain, creating Workers, configuring tunnels, or managing any Cloudflare infrastructure with Terraform.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Cloudflare Domain Setup

Domains on Cloudflare with infrastructure managed by the `cloudflare/cloudflare`
Terraform provider v5.

## Deployment models

**Static site + email** — two Workers and no origin server. A site Worker serves
static HTML/CSS from `dist/` through Terraform's assets binding; an email Worker
handles inbound mail via Email Routing, storing raw messages in R2 (cheap and
durable) alongside queryable metadata in D1, and sending auto-replies. Backed by
a D1 database, an R2 bucket, email routing, and zone settings.

**App behind a Zero Trust tunnel** — traffic flows Client → Cloudflare edge →
Worker (optional) → tunnel → origin server, so the origin needs no public IP. An
app proxy Worker sits in front of the tunnel doing pass-through, auth, or
filtering, and a landing Worker can serve the root domain. Backed by DNS records,
ACME passthrough config, rulesets, and zone settings.

The two coexist on one domain — static landing at the root, app via tunnel on a
subdomain, email routing on the zone.

## Layout

Worker source, site assets, and the D1 schema live under `cloudflare/`; build
output goes to a gitignored `dist/`; everything else is Terraform under
`terraform/`, split one file per concern (`site.tf`, `email.tf`,
`worker-app-proxy.tf`, `worker-landing.tf`, `cloudflare.tf` for zone settings,
DNS, tunnel, and rulesets). `backend.tf` puts Terraform state on R2 when wanted.

## Terraform

Pin the provider to `~> 5.0` and check the registry for the current 5.x release.
It authenticates from `var.cloudflare_api_token` or `CLOUDFLARE_API_TOKEN`. The
core variables are `cloudflare_api_token` (sensitive, defaulting to null),
`cloudflare_account_id` (sensitive), `cloudflare_zone_id`, and `domain`.

### Zone settings

Set via `cloudflare_zone_setting` resources, plus `cloudflare_zone_dnssec`:

| `setting_id` | Value | Notes |
|---|---|---|
| `always_use_https` | `on` | |
| `min_tls_version` | `1.2` | |
| `ssl` | `strict` | Requires a valid cert on the origin |
| `security_header` | HSTS object | `max_age` 31536000, include_subdomains, preload, nosniff |
| `automatic_https_rewrites` | `off` | Let the app handle its own asset URLs |
| `websockets` | `on` | For ActionCable and friends |

`cloudflare_zone_setting`'s destroy is a no-op for every `setting_id` — it drops
the resource from state without calling Cloudflare, so the setting stays on.
Turn one off from the dashboard, or by setting its value explicitly rather than
removing the resource.

### DNS

Point an app subdomain at a tunnel with a proxied CNAME to
`${tunnel.id}.cfargotunnel.com`.

Every proxied hostname needs a DNS record, Workers included — a
`cloudflare_workers_route` alone won't route traffic. What lets a
Worker-only domain skip writing one is `cloudflare_workers_custom_domain`,
which provisions the record itself.

A `www` → naked redirect ruleset does need a proxied record for `www`, so
Cloudflare has something to intercept. Point it at the RFC 5737 documentation IP;
the traffic never reaches it:

```hcl
resource "cloudflare_dns_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = "192.0.2.1"
  type    = "A"
  proxied = true
  ttl     = 1
}
```

## Reference docs

- **`docs/workers-terraform.md`** — deploying any Worker (the worker + version + deployment trio), the assets binding, custom domains, binding types, compatibility flags, and worker JS for app proxy, site fallback, landing pages, security headers, and caching
- **`docs/tunnel-and-acme.md`** — Zero Trust tunnels and the token data source, three-layer ACME/Let's Encrypt passthrough, SSL-bypass and www-redirect rulesets, ruleset phases, ACME troubleshooting
- **`docs/email-routing.md`** — the email Worker with D1 + R2 bindings, routing settings/DNS/rules, auto-reply and dual storage, D1 schema
- **`docs/r2-storage.md`** — R2 buckets, Terraform state on R2, Litestream backups, Rails ActiveStorage via the S3 adapter

## API token permissions

| Scope   | Permission          | Access | Used for                           |
|---------|---------------------|--------|------------------------------------|
| Zone    | Zone Settings       | Edit   | SSL mode, HTTPS, TLS version, HSTS |
| Zone    | DNS                 | Edit   | Tunnel CNAME, redirect records     |
| Zone    | Config Rules        | Edit   | ACME challenge SSL override        |
| Zone    | Single Redirects    | Edit   | WWW → naked domain redirect        |
| Zone    | Workers Routes      | Edit   | Worker route bindings              |
| Zone    | Email Routing Rules | Edit   | Email routing configuration        |
| Account | Workers Scripts     | Edit   | Worker deployment                  |
| Account | Cloudflare Tunnel   | Edit   | Tunnel and ingress configuration   |
| Account | D1                  | Edit   | D1 database management             |
| Account | R2 Storage          | Edit   | R2 bucket management               |

## Build and deploy

`npm run build` compiles the site (`@tailwindcss/cli`) and bundles the email
worker, then `terraform apply` deploys everything. D1 migrations run separately
through Wrangler afterward:

```bash
npx @tailwindcss/cli -i site/styles.css -o ../dist/styles.css
npx esbuild email-worker.js --bundle --outfile=email-worker.bundle.js \
  --format=esm --target=es2022 --platform=browser --external:cloudflare:email
npx wrangler d1 execute EMAIL_DB_NAME --remote --file=./schema.sql
```

For the tunnel model, `terraform apply` comes first, then install `cloudflared`
on the origin with the tunnel token and verify connectivity and cert issuance.

## Design decisions

- **Terraform over Wrangler.** Wrangler runs D1 migrations only; all worker and infrastructure deployment is Terraform-managed for reproducibility.
- **Separate workers per concern.** Site, email, and app proxy have different bindings and deploy independently.
- **esbuild for the email worker only.** It's the one with a dependency (`mimetext`); the static workers have none.
- **RFC 3834 auto-reply detection.** Check the `Auto-Submitted` header plus common anti-loop heuristics before replying.
- **Workers.dev disabled.** Nothing should be reachable at a workers.dev URL. `cloudflare_worker` takes `subdomain.enabled` and `subdomain.previews_enabled` directly; `cloudflare_workers_script` has no such attribute and needs a separate `cloudflare_workers_script_subdomain` resource.
- **Three-layer ACME passthrough.** Tunnel ingress, SSL ruleset, and Worker bypass are all required together when combining strict SSL, tunnels, and Workers.
- **`network: host` for the tunnel accessory.** cloudflared must use host networking to reach services on localhost.
