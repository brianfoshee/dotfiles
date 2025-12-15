# Rails 8.1 Modern Stack

Production-proven patterns for building Rails 8.1 applications with zero-build, zero-Redis architecture, based on real-world Rails 8.1 implementation.

## Overview

Rails 8.1 introduces a paradigm shift toward simplicity: single-process development, database-backed infrastructure, and production-ready SQLite. This guide shows how to build modern Rails applications without webpack, Redis, or complex process management.

## The Modern Stack

**Core Technologies:**
- **Rails 8.1** - Latest stable release
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

### The New Way (Rails 8.1)

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

Rails 8.1 includes a local CI runner that runs your **exact** CI pipeline on your development machine.

```ruby
# config/ci.rb
CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap audit", "bin/importmap audit"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
```

### Why This Matters

**Before Rails 8.1:**
- Push to GitHub → Wait for CI → Fails → Fix → Repeat
- Feedback loop: 5-10 minutes per iteration
- CI costs for every failed attempt
- Can't easily test CI changes locally

**With Rails 8.1:**
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

## SQLite Multi-Database Architecture

### Database Configuration

```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000  # Triggers Rails 8's modern busy handler (releases GVL, 25x faster)
  # Rails 8 automatically configures optimal SQLite settings:
  # - journal_mode: WAL, synchronous: NORMAL, mmap_size: 128MB
  # - Non-GVL-blocking busy handler with fair retry intervals

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

```ruby
# config/environments/production.rb
Rails.application.configure do
  # Solid Cache instead of Redis/Memcached
  config.cache_store = :solid_cache_store

  # Solid Queue instead of Sidekiq/Resque
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Solid Cable instead of Redis (for ActionCable)
  config.action_cable.adapter = :solid_cable

  # Use Solid Cache for rate limiting
  config.action_controller.rate_limiting_cache_store = :solid_cache_store
end

# config/environments/development.rb
Rails.application.configure do
  # Same configuration - consistency across environments
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
end
```

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

**4. Non-GVL-Blocking Busy Handler**
```ruby
timeout: 5000  # Must be >= 5000ms to enable
```

**This is the breakthrough:**
- Ruby's Global VM Lock (GVL) normally blocks during SQLite busy waits
- Rails 8 releases GVL during busy handler
- Other Ruby threads can run while waiting for database lock
- **25x faster** in concurrent scenarios
- Critical for production SQLite

**How it works:**
```ruby
# Old approach (pre-Rails 8): Blocks GVL
# Thread 1: Writing to DB, holds lock, blocks GVL
# Thread 2: Tries to write, waits with GVL blocked
# Result: Other threads can't run AT ALL

# Rails 8 approach: Releases GVL
# Thread 1: Writing to DB, holds lock
# Thread 2: Tries to write, releases GVL, waits with fair retry
# Thread 3-N: Continue processing other requests
# Result: Application remains responsive under load
```

**Reference:**
- [Rails PR #51958](https://github.com/rails/rails/pull/51958)
- Implements fair retry intervals and GVL release

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

**New stack (Rails 8.1):**
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

## Rails 8 SQLite Performance Details

### Critical Configuration: timeout >= 5000

```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  timeout: 5000  # CRITICAL: Triggers Rails 8's modern busy handler
```

**Why this matters:**
- Setting `timeout: 5000` (or higher) enables Rails 8's non-GVL-blocking busy handler
- Without this, you get the old blocking behavior
- **25x performance improvement** in concurrent scenarios

### What Rails 8 Does Automatically

When you connect to SQLite, Rails 8 automatically runs:

```sql
PRAGMA journal_mode = WAL;        -- Write-Ahead Logging
PRAGMA synchronous = NORMAL;      -- Balanced durability
PRAGMA mmap_size = 134217728;     -- 128MB memory-mapped I/O
PRAGMA journal_size_limit = 67108864;  -- 64MB journal limit
PRAGMA cache_size = -64000;       -- 64MB cache
```

**You don't configure these - Rails does it for you.**

### The Busy Handler Breakthrough

**The problem:**
- SQLite uses database-level locking
- When a write transaction is in progress, other writes must wait
- Ruby's GVL (Global VM Lock) was blocked during waits
- Result: Entire application freezes waiting for database

**Rails 8 solution:**
```ruby
# Non-GVL-blocking busy handler with fair retry intervals
# Releases GVL while waiting for lock
# Other threads can continue processing
```

**Real-world impact:**
```
Old behavior (Rails 7):
  - Write in progress
  - 10 concurrent requests arrive
  - All 10 block on GVL waiting for SQLite lock
  - Application appears frozen
  - Response times: 5000ms+

New behavior (Rails 8):
  - Write in progress
  - 10 concurrent requests arrive
  - Requests release GVL, wait with fair retry
  - Other threads continue processing
  - Response times: 50-200ms
```

**Performance numbers:**
- 25x faster in concurrent write scenarios
- 10x more throughput under load
- Production-ready for moderate-traffic applications

### SQLite Production Checklist

```ruby
# ✅ Ensure timeout is set correctly
timeout: 5000  # Minimum for Rails 8 optimizations

# ✅ Use WAL mode (automatic in Rails 8)
# No configuration needed

# ✅ Use proper database paths
database: storage/production.sqlite3  # Persistent storage

# ✅ Configure connection pool
pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

# ✅ Use Litestream for backups (highly recommended)
# See: Litestream documentation
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
- ✅ **Better performance** - 25x improvement with new busy handler
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
gem "rails", "~> 8.1.0"
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
- [SQLite Optimizations PR](https://github.com/rails/rails/pull/51958)
- [Puma Plugins](https://github.com/puma/puma/blob/master/docs/plugins.md)
