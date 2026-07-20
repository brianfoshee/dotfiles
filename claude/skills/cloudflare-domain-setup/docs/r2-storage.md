# R2 Storage

Cloudflare R2 buckets and the S3-compatible integrations that consume them: Terraform
remote state, Litestream backups, and Rails ActiveStorage. R2 speaks the S3 API, so
these all use S3-flavored configuration pointed at the R2 endpoint.

## Contents

- [R2 Buckets](#r2-buckets)
- [Terraform State Backend](#terraform-state-backend)
- [Litestream Backup Target](#litestream-backup-target)
- [ActiveStorage Service](#activestorage-service)

## R2 Buckets

```hcl
resource "cloudflare_r2_bucket" "storage" {
  account_id = var.cloudflare_account_id
  name       = "myapp-storage"
}
```

## Terraform State Backend

Use R2 as an S3-compatible backend for Terraform state. The R2 bucket must be created
manually first (not managed by the same Terraform config that uses it as backend).

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

## Litestream Backup Target

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

## ActiveStorage Service

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
