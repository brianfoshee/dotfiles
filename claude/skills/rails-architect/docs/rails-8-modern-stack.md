# Rails 8.2 Modern Stack

Production-proven patterns for building Rails 8.2 applications with zero-build, zero-Redis architecture, based on real-world Rails 8.2 implementation.

## Contents

- [Overview](#overview)
- [The Modern Stack](#the-modern-stack)
- [Puma Plugins: Replacing Foreman](#puma-plugins-replacing-foreman)
  - [The Old Way (Rails 7 and earlier)](#the-old-way-rails-7-and-earlier)
  - [The New Way (Rails 8.2)](#the-new-way-rails-82)
  - [Puma Plugin Details](#puma-plugin-details)
- [Local CI Runner: bin/ci](#local-ci-runner-binci)
  - [The Game Changer](#the-game-changer)
  - [Why This Matters](#why-this-matters)
  - [Comprehensive CI Steps](#comprehensive-ci-steps)
  - [Usage Examples](#usage-examples)
- [Rails 8.2 Defaults](#rails-82-defaults)
  - [Jobs After Transaction Commit](#jobs-after-transaction-commit)
  - [Active Storage Immediate Analysis](#active-storage-immediate-analysis)
  - [CSRF Protection via Sec-Fetch-Site](#csrf-protection-via-sec-fetch-site)
  - [SSL Configuration](#ssl-configuration)
- [Combined Credentials](#combined-credentials)
- [Deployment Revision Tracking](#deployment-revision-tracking)
- [SQLite Multi-Database Architecture](#sqlite-multi-database-architecture)
  - [Database Configuration](#database-configuration)
  - [Why Multiple SQLite Databases?](#why-multiple-sqlite-databases)
  - [Environment Configuration](#environment-configuration)
- [Rails 8 SQLite Performance Optimizations](#rails-8-sqlite-performance-optimizations)
  - [Automatic Optimizations (No Configuration Needed)](#automatic-optimizations-no-configuration-needed)
  - [SQLite Production Checklist](#sqlite-production-checklist)
  - [When SQLite Is Production-Ready](#when-sqlite-is-production-ready)
- [Zero Redis Architecture](#zero-redis-architecture)
  - [What Redis Used to Provide](#what-redis-used-to-provide)
  - [Infrastructure Simplification](#infrastructure-simplification)
  - [Benefits of Zero Redis](#benefits-of-zero-redis)
  - [Solid Queue/Cache/Cable Configuration](#solid-queuecachecable-configuration)
- [Development Workflow](#development-workflow)
  - [Starting the Application](#starting-the-application)
  - [Running Tests](#running-tests)
  - [Database Management](#database-management)
- [Benefits Summary](#benefits-summary)
  - [For Developers](#for-developers)
  - [For Operations](#for-operations)
  - [For Applications](#for-applications)
- [When to Use This Stack](#when-to-use-this-stack)
  - [Perfect For:](#perfect-for)
  - [Consider Alternatives For:](#consider-alternatives-for)
- [Required Gems](#required-gems)
- [File Structure](#file-structure)
- [Common Questions](#common-questions)
  - ["Is SQLite really production-ready?"](#is-sqlite-really-production-ready)
  - ["What about scaling?"](#what-about-scaling)
  - ["What if I need Redis?"](#what-if-i-need-redis)
- [References](#references)

## Overview

Rails 8.2 introduces a paradigm shift toward simplicity: single-process development, database-backed infrastructure, and production-ready SQLite. This guide shows how to build modern Rails applications without webpack, Redis, or complex process management.

## The Modern Stack

**Core Technologies:**
- **Rails edge/main** - Patterns here target the forthcoming Rails 8.2 (edge/main), not yet released as stable
- **SQLite** - Primary database + Queue/Cache/Cable
- **Puma Plugins** - Integrated CSS watching and background jobs
- **Solid Queue/Cache/Cable** - Database-backed (no Redis)
- **Import Maps** - Zero-build JavaScript
- **Tailwind CSS v4** - Compiled via Puma plugin
- **Hotwire** - Turbo + Stimulus for interactivity

**What You Don't Need:**
- ❌ Redis (replaced by SQLite)
- ❌ Foreman (replaced by Puma plugins)
- ❌ Webpack/esbuild (replaced by Import Maps)
- ❌ Sidekiq (replaced by Solid Queue)
- ❌ Memcached (replaced by Solid Cache)
- ❌ Complex deployment setup

## Puma Plugins: Replacing Foreman

### The Old Way (Rails 7 and earlier)

```ruby
# Procfile.dev
web: bin/rails server
css: bin/rails tailwindcss:watch
worker: bundle exec sidekiq
```

```bash
# bin/dev
foreman start -f Procfile.dev
```

**Problems:**
- Multiple separate processes
- Requires Foreman gem
- Complex log aggregation
- Hard to debug (which process has the error?)
- Process lifecycle management complexity

### The New Way (Rails 8.2)

```ruby
# config/puma.rb
plugin :tmp_restart
plugin :tailwindcss if ENV.fetch("RAILS_ENV", "development") == "development"
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] || ENV.fetch("RAILS_ENV", "development") == "development"
```

```ruby
# bin/dev
#!/usr/bin/env ruby
exec "./bin/rails", "server", *ARGV
```

**Benefits:**
- ✅ Single process - simpler debugging
- ✅ Unified logging - all output in one stream
- ✅ No Foreman dependency
- ✅ Automatic lifecycle management
- ✅ Conditional plugin loading per environment
- ✅ Pass-through arguments (`bin/dev -p 4000`)

### Puma Plugin Details

#### Tailwind CSS Plugin

```ruby
plugin :tailwindcss if ENV.fetch("RAILS_ENV", "development") == "development"
```

**What it does:**
- Watches for CSS file changes
- Recompiles Tailwind CSS automatically
- Runs inside Puma worker
- Only enabled in development

**Replaces:**
```bash
# Old approach
bin/rails tailwindcss:watch
```

#### Solid Queue Plugin

```ruby
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] || ENV.fetch("RAILS_ENV", "development") == "development"
```

**What it does:**
- Starts Solid Queue supervisor
- Processes background jobs in same process
- Only enabled when explicitly requested or in development

**Replaces:**
```bash
# Old approach
bundle exec sidekiq
# or
bin/jobs  # Solid Queue worker
```

**Environment control:**
```bash
# Production: control via environment variable
SOLID_QUEUE_IN_PUMA=true bin/rails server

# Development: automatic
bin/dev  # Queue worker included automatically
```

## Local CI Runner: bin/ci

### The Game Changer

Rails ships a local CI runner (`bin/ci`, introduced in Rails 8.1) that runs your **exact** CI pipeline on your development machine.

```ruby
# config/ci.rb
CI.run do
  step "Setup", "bin/setup --skip-server"

  group "Checks", parallel: 2 do
    step "Style: Ruby", "bin/rubocop"
    step "Security: Gem audit", "bin/bundler-audit"
    step "Security: Importmap audit", "bin/importmap audit"
    step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  end

  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
```

Steps inside a `group` with `parallel:` run concurrently, reducing CI time.

### Why This Matters

**Before Rails 8.2:**
- Push to GitHub → Wait for CI → Fails → Fix → Repeat
- Feedback loop: 5-10 minutes per iteration
- CI costs for every failed attempt
- Can't easily test CI changes locally

**With Rails 8.2:**
```bash
bin/ci  # Runs entire CI suite in ~2 minutes
```

**Benefits:**
- ✅ Catch failures **before** pushing
- ✅ Match GitHub Actions exactly
- ✅ Faster feedback loop
- ✅ No CI runner costs for failed runs
- ✅ Test CI configuration changes locally
- ✅ Named steps show exactly what's running

### Comprehensive CI Steps

**Setup validation:**
```ruby
step "Setup", "bin/setup --skip-server"
```
Ensures dependencies are installed correctly.

**Style checking:**
```ruby
step "Style: Ruby", "bin/rubocop"
```
Enforces code style consistency.

**Security scanning:**
```ruby
step "Security: Gem audit", "bin/bundler-audit"
step "Security: Importmap audit", "bin/importmap audit"
step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
```
- Bundler audit: checks for vulnerable gems
- Importmap audit: checks for vulnerable JavaScript packages
- Brakeman: static security analysis for Rails code

**Testing:**
```ruby
step "Tests: Rails", "bin/rails test"
step "Tests: System", "bin/rails test:system"
```
Runs unit, integration, controller, and system tests.

**Seed validation:**
```ruby
step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
```
Ensures `db/seeds.rb` can run without errors (often forgotten until production!).

### Usage Examples

```bash
# Run full CI locally
bin/ci

# CI output shows named steps
✓ Setup
✓ Style: Ruby
✓ Security: Gem audit
✓ Security: Importmap audit
✓ Security: Brakeman
✓ Tests: Rails (760 tests, 0 failures)
✓ Tests: System (3 tests, 0 failures)
✓ Tests: Seeds

All checks passed!
```

## Rails 8.2 Defaults

### Jobs After Transaction Commit

```ruby
# config/application.rb
config.active_job.enqueue_after_transaction_commit = true
```

Jobs enqueued inside a transaction now wait for the transaction to commit before being dispatched. Prevents workers from picking up a job before the data it depends on is visible.

### Active Storage Immediate Analysis

```ruby
# config/application.rb (default in 8.2)
config.active_storage.analyze = :immediately
```

Blobs are analyzed (dimensions, metadata) before validation callbacks run, so `has_one_attached :avatar, content_type: "image/*"` validations work on first save.

### CSRF Protection via Sec-Fetch-Site

Rails 8.2 introduces a new CSRF protection strategy based on the `Sec-Fetch-Site` browser header:

```ruby
# config/application.rb (default for new 8.2 apps)
config.action_controller.forgery_protection_verification_strategy = :header_only
```

`:header_only` relies on the browser's `Sec-Fetch-Site` header, eliminating the need for `authenticity_token` form params. Use `:header_or_legacy_token` for a gradual migration that falls back to traditional token verification.

### SSL Configuration

New Rails 8.2 apps no longer generate `config.assume_ssl` or `config.force_ssl` in `production.rb`, so Kamal deployments work out of the box without SSL. When deploying behind an SSL-terminating proxy, explicitly enable:

```ruby
# config/environments/production.rb
config.assume_ssl = true
config.force_ssl = true
```

## Combined Credentials

Rails 8.2 introduces `Rails.app.creds`, a combined lookup that checks ENV first, then falls back to encrypted credentials:

```ruby
Rails.app.creds.require(:stripe_api_key)                    # raises if missing from both
Rails.app.creds.option(:redis_url, default: "redis://localhost:6379")  # optional with default
Rails.app.creds.require(:aws, :bucket)                      # nested: checks AWS__BUCKET env var first
```

`Rails.application.credentials` still works for direct encrypted-file access. `Rails.app.creds` is the recommended unified API.

## Deployment Revision Tracking

```ruby
Rails.app.revision  # => "abc1234" (checks ENV["REVISION"], then REVISION file, then git SHA)
```

Useful for cache keys, error reporting, and deployment verification:

```ruby
config.cache_store = :solid_cache_store, { namespace: Rails.app.revision }
Sentry.set_context("app", { revision: Rails.app.revision })
```

## SQLite Multi-Database Architecture

### Database Configuration

```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000  # Any timeout installs Rails 8's non-GVL-blocking busy handler; 5000 is the generator default (see "Rails 8 SQLite Performance Optimizations" below)

development:
  primary:
    <<: *default
    database: storage/db/development.sqlite3
  queue:
    <<: *default
    database: storage/db/development_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default
    database: storage/db/development_cable.sqlite3
    migrations_paths: db/cable_migrate

production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  cache:
    <<: *default
    database: storage/production_cache.sqlite3
    migrations_paths: db/cache_migrate
  queue:
    <<: *default
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
  cable:
    <<: *default
    database: storage/production_cable.sqlite3
    migrations_paths: db/cable_migrate
```

### Why Multiple SQLite Databases?

**Separation of concerns:**
- **Primary** - Application data (jobs, users, etc.)
- **Queue** - Background job data (Solid Queue)
- **Cache** - Cached data (Solid Cache)
- **Cable** - WebSocket state (Solid Cable)

**Benefits:**
- ✅ **Independent backup strategies** - Primary: 30 days, Queue: 7 days, Cache: 24 hours
- ✅ **Independent migration paths** - db/queue_migrate/, db/cache_migrate/, etc.
- ✅ **Reduced contention** - Cache writes don't block primary database
- ✅ **Easier management** - Can reset cache without affecting primary data
- ✅ **Clear boundaries** - Each database has single responsibility

### Environment Configuration

Wire the Solid adapters per environment; development mirrors production for consistency:

```ruby
# config/environments/production.rb and development.rb
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

Cache, Cable, rate limiting, and the full options (queue.yml, cable.yml, features, usage) are covered in [Solid Queue/Cache/Cable Configuration](#solid-queuecachecable-configuration) below.

## Rails 8 SQLite Performance Optimizations

### Automatic Optimizations (No Configuration Needed)

Rails 8 automatically configures SQLite for production use:

**1. Write-Ahead Logging (WAL)**
```sql
PRAGMA journal_mode = WAL;
```
- Allows concurrent reads during writes
- Better performance for web applications
- Standard for production SQLite

**2. Synchronous Mode**
```sql
PRAGMA synchronous = NORMAL;
```
- Balances durability with performance
- Safe with WAL mode
- Much faster than FULL synchronous

**3. Memory-Mapped I/O**
```sql
PRAGMA mmap_size = 128MB;
```
- Uses OS page cache for reads
- Reduces system calls
- Significant performance improvement

The exact `DEFAULT_PRAGMAS` Rails applies on connect (these values date to Rails 7.1; the named constant and the `pragmas:` override key arrived in 7.2, PR #50460):
```sql
PRAGMA foreign_keys = ON;              -- Enforce foreign keys
PRAGMA journal_mode = WAL;             -- Write-Ahead Logging
PRAGMA synchronous = NORMAL;           -- Balanced durability
PRAGMA mmap_size = 134217728;          -- 128MB memory-mapped I/O
PRAGMA journal_size_limit = 67108864;  -- 64MB journal limit
PRAGMA cache_size = 2000;              -- 2000 pages (~8MB at 4KB page size)
```
**You don't configure these - Rails does it for you.** Note `cache_size` is `2000` *pages* (~8MB), not a byte count. `temp_store` and `busy_timeout` are **not** in the defaults (contrary to some older guides); concurrency is handled by the busy handler below, driven by the `timeout:` connection setting.

**4. Non-GVL-Blocking Busy Handler (Rails 8.0)**

Setting any `timeout:` (ms) in `database.yml` installs a fair-retry busy handler via `busy_handler_timeout=` instead of the old blocking `busy_timeout()`. Without a `timeout:`, there is no wait at all. The generated `database.yml` ships `timeout: 5000`.

**This is half the concurrency story:**
- Ruby's Global VM Lock (GVL) normally blocks during SQLite busy waits
- Rails 8 releases the GVL while the busy handler waits
- Other Ruby threads keep running while one waits for the database lock
- Requires the `sqlite3` gem >= 2.0; translates `SQLite3::BusyException` to `ActiveRecord::StatementTimeout`

**Reference:** [Rails PR #51958](https://github.com/rails/rails/pull/51958)

**5. IMMEDIATE Transactions (Rails 8.0) — the root-cause fix**

This is the single most important concurrency change, and it pairs with the busy handler above.

SQLite's native default is **DEFERRED** transactions: the write lock isn't acquired until the *first write inside* the transaction. If another connection holds the lock at that mid-transaction moment, SQLite **cannot retry** — you get an immediate `SQLite3::BusyException: database is locked`, even with a busy_timeout set. In a Rails app where nearly every explicit `transaction do` block writes, this is the real source of spurious lock errors.

Rails 8.0 sets `default_transaction_mode: :immediate`, acquiring the write lock at `BEGIN`. Contention now happens *before* the transaction does work, so the busy handler can fairly queue and retry it.

```ruby
# DEFERRED (SQLite default): lock grabbed mid-transaction, can't retry → BusyException
# IMMEDIATE (Rails 8 default): lock grabbed at BEGIN, handler retries fairly
```

Fixtures and joinable transactions stay DEFERRED internally; there is no public config flag to change the default. Together with WAL + the busy handler, IMMEDIATE transactions are what actually eliminate the error storm: benchmarks show untuned SQLite erroring on ~half of responses at just 4 concurrent writers, versus near-zero errors and roughly an order-of-magnitude better P99 once all three are in place.

**Reference:** [Rails PR #50371](https://github.com/rails/rails/pull/50371)

> **Note on `activerecord-enhancedsqlite3-adapter`:** Stephen Margheim's gem originally backported these features, but WAL/NORMAL default pragmas (7.1), generated columns (7.2), and the IMMEDIATE-transaction default + GVL-releasing busy handler (8.0) are all in core now. On Rails 8 the gem is largely redundant — only reach for it for its deferred/custom foreign-key sugar or the experimental reader/writer connection-pool split.

### Customizing Pragmas (Rails 7.2)

Override any default PRAGMA (or add your own) under a `pragmas:` key in `database.yml`. Values merge over `DEFAULT_PRAGMAS`; unknown pragmas warn.

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
    pragmas:
      temp_store: memory       # keep temp tables/indexes in RAM
      cache_size: -64000       # negative = KB, so this is 64MB (default is 2000 pages)
```

**Reference:** [Rails PR #50460](https://github.com/rails/rails/pull/50460)

### Loading SQLite Extensions (Rails 8.1)

Load extensions (sqlite-vec, sqlean, etc.) via an `extensions:` array in `database.yml`. Requires the `sqlite3` gem >= 2.4.0. Each entry is a filesystem path, ERB returning a path, or a module that responds to `.to_path`.

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
    extensions:
      - SQLean::UUID                     # gem module responding to .to_path
      - <%= SqliteVec.loadable_path %>   # ERB returning a path
      - .sqlpkg/nalgeon/crypto/crypto.so # filesystem path
```

See `docs/sqlite-extensions-and-features.md` for the extension ecosystem and modern schema features. **Reference:** [Rails PR #53827](https://github.com/rails/rails/pull/53827)

### SQLite Production Checklist

```ruby
# ✅ Set a timeout to install the non-GVL-blocking busy handler
timeout: 5000  # Any value works; 5000 is the generator default

# ✅ Use WAL mode (automatic in Rails 8)
# No configuration needed

# ✅ Use proper database paths
database: storage/production.sqlite3  # Persistent storage

# ✅ Configure connection pool
pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

# ✅ Use Litestream for backups (highly recommended)
# See: Litestream documentation
```

### When SQLite Is Production-Ready

**Good fit for:**
- ✅ Single-server deployments
- ✅ Read-heavy workloads with moderate writes
- ✅ Applications with < 100k users
- ✅ Internal tools and B2B applications
- ✅ Applications deployed with Kamal

**Not recommended for:**
- ❌ Multi-server deployments requiring shared database
- ❌ Extremely write-heavy workloads (millions of writes/day)
- ❌ Applications requiring complex replication
- ❌ Systems needing distributed transactions

**With Rails 8 optimizations, SQLite handles:**
- Thousands of requests per second
- Hundreds of concurrent connections
- Multi-gigabyte databases
- Production workloads for most applications

## Zero Redis Architecture

### What Redis Used to Provide

1. **Cache storage** → Replaced by Solid Cache (SQLite)
2. **Background job queue** → Replaced by Solid Queue (SQLite)
3. **ActionCable pub/sub** → Replaced by Solid Cable (SQLite)
4. **Session storage** → Rails session store (cookie or database)
5. **Rate limiting** → Solid Cache (SQLite)

### Infrastructure Simplification

**Old stack (Rails 7):**
```
┌─────────────┐
│ Rails App   │
└─────┬───────┘
      │
      ├──────> Database (primary data)
      ├──────> Redis (cache)
      ├──────> Redis (Sidekiq)
      ├──────> Redis (ActionCable)
      └──────> Memcached (optional)

Multiple technologies to manage
```

**New stack (Rails 8.2):**
```
┌─────────────┐
│ Rails App   │
└─────┬───────┘
      │
      ├──────> SQLite (primary data)
      ├──────> SQLite (cache)
      ├──────> SQLite (queue)
      └──────> SQLite (cable)

1 database technology
```

### Benefits of Zero Redis

**Operational:**
- ✅ **Simpler deployment** - One database technology to manage
- ✅ **Lower costs** - No Redis hosting/memory costs
- ✅ **Easier monitoring** - Unified database monitoring
- ✅ **Unified backups** - Single backup strategy (e.g., Litestream)
- ✅ **Fewer dependencies** - No Redis client gems, no connection management

**Development:**
- ✅ **Simpler setup** - `bin/setup` just works, no Redis to install
- ✅ **No Docker needed** - Pure Ruby stack
- ✅ **Faster CI** - No Redis service to start
- ✅ **Better local development** - Everything in one process

**Performance:**
- ✅ **No network latency** - Database is local file
- ✅ **Better memory usage** - OS manages cache, not Redis
- ✅ **Disk-based persistence** - Cache survives restarts

### Solid Queue/Cache/Cable Configuration

#### Solid Queue (Background Jobs)

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

**Features:**
- Database-backed job queue
- Web UI for monitoring (mount at `/solid_queue`)
- Supports priorities, delays, recurring jobs
- ACID guarantees (no lost jobs)
- Works with SQLite in production

**Queues configuration:**
```ruby
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 2
      polling_interval: 0.1
```

#### Solid Cache (Caching)

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store
config.action_controller.rate_limiting_cache_store = :solid_cache_store
```

**Features:**
- Database-backed cache
- Survives application restarts
- No memory limits (disk-based)
- Automatic expiration
- Works with SQLite

**Usage (same as any Rails cache):**
```ruby
Rails.cache.fetch("user_#{user.id}", expires_in: 1.hour) do
  expensive_operation
end
```

#### Solid Cable (ActionCable)

```ruby
# config/cable.yml
production:
  adapter: solid_cable
  connects_to: cable
```

**Features:**
- Database-backed pub/sub for WebSockets
- No Redis dependency
- Persistent message storage
- Works with SQLite

**Usage (same as any ActionCable):**
```ruby
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "notifications_#{current_user.id}"
  end
end
```

## Development Workflow

### Starting the Application

```bash
# Single command starts everything
bin/dev

# Equivalent to:
bin/rails server

# Which loads:
# - Rails application
# - Tailwind CSS watcher (via plugin)
# - Solid Queue worker (via plugin)
# - All in one process
```

### Running Tests

```bash
# All tests except system tests
bin/rails test

# All tests including system tests
bin/rails test:all

# Full CI suite (recommended before commits)
bin/ci
```

### Database Management

```bash
# Primary database
bin/rails db:migrate
bin/rails db:seed

# Queue database
bin/rails db:migrate:queue

# Cable database
bin/rails db:migrate:cable

# Cache database
bin/rails db:migrate:cache
```

## Benefits Summary

### For Developers

- ✅ **Simpler mental model** - One process, one database technology
- ✅ **Faster setup** - No Redis to install or configure
- ✅ **Easier debugging** - All logs in one place
- ✅ **Better local development** - Everything "just works"
- ✅ **Faster CI feedback** - Run full CI locally in minutes

### For Operations

- ✅ **Lower costs** - No Redis hosting fees
- ✅ **Simpler infrastructure** - Fewer moving parts
- ✅ **Easier backups** - Unified backup strategy (Litestream)
- ✅ **Better reliability** - Fewer dependencies to fail
- ✅ **Easier scaling** - Vertical scaling with SQLite performs excellently

### For Applications

- ✅ **Production-ready** - Rails 8 makes SQLite production-worthy
- ✅ **Better performance** - IMMEDIATE transactions + GVL-releasing busy handler eliminate spurious lock errors under concurrency
- ✅ **Zero-build** - Import maps eliminate build complexity
- ✅ **Modern stack** - Latest Rails conventions
- ✅ **Future-proof** - Foundation for Rails 9+

## When to Use This Stack

### Perfect For:

- ✅ **Single-server applications** - Most apps fit this category
- ✅ **Startups and MVPs** - Simplicity accelerates development
- ✅ **Internal tools** - B2B applications, admin dashboards
- ✅ **Content-heavy sites** - Blogs, documentation, marketing sites
- ✅ **Moderate traffic** - Up to 100k+ users
- ✅ **Budget-conscious** - Lower infrastructure costs

### Consider Alternatives For:

- ⚠️ **Multi-region deployments** - Requires distributed database
- ⚠️ **Extreme scale** - Millions of users, high write volume
- ⚠️ **Multi-server horizontal scaling** - Shared database required

**Important:** Most applications never reach the scale where they outgrow this stack. Start simple, scale when needed.

## Required Gems

```ruby
# Gemfile
gem "rails", "~> 8.2.0"
gem "sqlite3", ">= 2.1"
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
gem "thruster"  # X-Sendfile, HTTP/2, asset caching
```

## File Structure

```
app/
config/
  ci.rb                           # Local CI configuration
  database.yml                    # Multi-database setup
  puma.rb                         # Puma plugins
  queue.yml                       # Solid Queue configuration
  environments/
    production.rb                 # Solid adapters
    development.rb                # Solid adapters
db/
  migrate/                        # Primary database migrations
  queue_migrate/                  # Queue database migrations
  cache_migrate/                  # Cache database migrations
  cable_migrate/                  # Cable database migrations
storage/
  db/
    development.sqlite3           # Primary DB
    development_queue.sqlite3     # Queue DB
    development_cable.sqlite3     # Cable DB
  production.sqlite3              # Production primary
  production_queue.sqlite3        # Production queue
  production_cache.sqlite3        # Production cache
  production_cable.sqlite3        # Production cable
```

## Common Questions

### "Is SQLite really production-ready?"

**Yes, with Rails 8.**

- Rails 8's optimizations make SQLite production-worthy
- Used by: Basecamp, GitHub (for some systems), Fly.io, many others
- Handles thousands of requests/second
- Simpler infrastructure for single-server apps

### "What about scaling?"

**Vertical scaling works excellently:**
- SQLite scales to multi-GB databases
- Modern servers have 32+ cores, 128+ GB RAM
- Most applications never need horizontal database scaling
- Vertical scaling is sufficient for most applications

**When you truly need horizontal scaling:**
- Use read replicas (Litestream can help)
- Consider application-level sharding
- Don't prematurely optimize

### "What if I need Redis?"

You probably don't, but if you do:

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
config.active_job.queue_adapter = :sidekiq
```

The beauty of this stack: Easy to adopt Redis later if needed. Start simple.

## References

- [Rails 8 Release Notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [Solid Queue](https://github.com/basecamp/solid_queue)
- [Solid Cache](https://github.com/basecamp/solid_cache)
- [Solid Cable](https://github.com/basecamp/solid_cable)
- [Busy handler PR #51958](https://github.com/rails/rails/pull/51958) · [IMMEDIATE transactions #50371](https://github.com/rails/rails/pull/50371) · [pragmas: config #50460](https://github.com/rails/rails/pull/50460) · [extensions: config #53827](https://github.com/rails/rails/pull/53827)
- [Puma Plugins](https://github.com/puma/puma/blob/master/docs/plugins.md)
