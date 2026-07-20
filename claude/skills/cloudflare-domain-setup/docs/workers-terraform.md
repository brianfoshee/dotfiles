# Workers: Terraform and JavaScript

Terraform deployment patterns and worker JavaScript for the Cloudflare Workers used in
this skill. All Terraform targets the `cloudflare/cloudflare` provider v5.

## Contents

- [Modern Worker Deployment Pattern](#modern-worker-deployment-pattern) — worker + version + deployment trio
- [Binding Types](#binding-types)
- [Compatibility Flags](#compatibility-flags)
- [Site Worker (Assets Binding)](#site-worker-assets-binding)
- [Worker Code](#worker-code) — app proxy, site fallback, landing page
- [Security Headers and Caching](#security-headers-and-caching)

## Modern Worker Deployment Pattern

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

## Binding Types

- `plain_text` — Static content (HTML, config strings)
- `d1` — D1 database
- `r2_bucket` — R2 storage
- `assets` — Static file directory (see the site worker below)

## Compatibility Flags

- `nodejs_compat` — Required for Workers using Node.js APIs (e.g., email Worker with `mimetext`)

## Site Worker (Assets Binding)

For static sites, use the assets binding to serve files from a build directory. In
provider v5 `assets` is a single nested attribute (`assets = { ... }`), the `ASSETS`
binding is declared in the `bindings` list with `type = "assets"`, and `observability`
is a nested attribute. A module-syntax worker is indicated by setting `main_module`.

```hcl
resource "cloudflare_workers_script" "site" {
  account_id  = var.cloudflare_account_id
  script_name = "mysite"
  content     = file("../cloudflare/site-worker.js")
  main_module = "site-worker.js"

  assets = {
    directory = "../dist/"
    config = {
      html_handling      = "auto-trailing-slash"
      not_found_handling = "404-page"
    }
  }

  bindings = [
    {
      name = "ASSETS"
      type = "assets"
    }
  ]

  observability = {
    enabled = true
    logs = {
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

## Security Headers and Caching

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
