# Zero Trust Tunnel, ACME Passthrough, and Rulesets

Terraform for connecting an origin server through a Cloudflare Zero Trust tunnel,
passing Let's Encrypt HTTP-01 challenges through to the origin, and zone rulesets.
All Terraform targets the `cloudflare/cloudflare` provider v5.

## Contents

- [Zero Trust Tunnel](#zero-trust-tunnel)
- [ACME/Let's Encrypt Passthrough](#acmelets-encrypt-passthrough)
- [Rulesets](#rulesets)

## Zero Trust Tunnel

Establishes a secure outbound connection from an origin server to Cloudflare's edge. No
public IP or open inbound ports needed on the origin.

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

The cloudflared accessory container must use `network: host` so it can connect to
services on the origin's localhost.

## ACME/Let's Encrypt Passthrough

When using a Zero Trust tunnel + strict SSL + a Worker, Let's Encrypt HTTP-01 challenges
require **three coordinated layers** to reach the origin:

**Layer 1: Tunnel ingress** (above) — Routes ACME paths to `http://localhost:80`.

**Layer 2: SSL ruleset** — Downgrades SSL to `flexible` for ACME paths so Cloudflare
connects to origin via HTTP:

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

**Layer 3: Worker bypass** — A more specific Worker route with no script takes
precedence, letting the request pass through to the tunnel:

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

## Rulesets

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
