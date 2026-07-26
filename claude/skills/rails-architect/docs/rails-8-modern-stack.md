# Rails 8.2 Modern Stack

Zero-build, zero-Redis Rails: SQLite for everything, Puma plugins instead of
Foreman, import maps instead of a bundler. Version labels name the release that
introduced a feature, so you can tell what your app already has.

## Contents

- [Puma plugins](#puma-plugins)
- [Local CI runner](#local-ci-runner)
- [Framework defaults](#framework-defaults)
- [Combined credentials](#combined-credentials)
- [Deployment revision tracking](#deployment-revision-tracking)
- [SQLite multi-database setup](#sqlite-multi-database-setup)
- [SQLite concurrency](#sqlite-concurrency)
- [Customizing pragmas](#customizing-pragmas)
- [Loading SQLite extensions](#loading-sqlite-extensions)
- [When SQLite fits](#when-sqlite-fits)
- [Solid Queue / Cache / Cable](#solid-queue--cache--cable)
- [Gems and layout](#gems-and-layout)
- [References](#references)

## Puma plugins

Puma plugins fold the CSS watcher and the job worker into the web process, so
`bin/dev` is just `rails server` and there's no Procfile or Foreman:

```ruby
# config/puma.rb — as generated on main (8.2)
plugin :tmp_restart
plugin :solid_queue if ![ "", "false", "0" ].include?(ENV["SOLID_QUEUE_IN_PUMA"].to_s.downcase)

# from the tailwindcss-rails gem, not the Rails app template
plugin :tailwindcss if ENV.fetch("RAILS_ENV", "development") == "development"
```

```ruby
# bin/dev
#!/usr/bin/env ruby
exec "./bin/rails", "server", *ARGV
```

Mind the polarity, which flipped between releases. On 8.1 the generated line is
`plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` — opt-in, so jobs run in the
web process only when you ask. On 8.2 it is opt-*out*: unset loads the plugin.
To run `bin/jobs` as its own process on 8.2, set `SOLID_QUEUE_IN_PUMA=false`
explicitly, or you get a supervisor in both places.

## Local CI runner

`bin/ci` runs the CI pipeline locally from a Ruby config, so the same definition
drives local runs and GitHub Actions. The runner and `step` are 8.1; the
`group … parallel:` DSL below is 8.2 (#56774) and was not backported, so on 8.1
write flat `step` calls instead:

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

Steps in a `group` with `parallel:` run concurrently. The seeds step is worth
copying — a broken `db/seeds.rb` usually isn't discovered until it's needed.

## Framework defaults

`load_defaults "8.2"` already sets all of these — they're listed to explain the
behavior, not as lines to write:

```ruby
config.active_job.enqueue_after_transaction_commit = true
config.active_storage.analyze = :immediately
config.action_controller.forgery_protection_verification_strategy = :header_only
```

`enqueue_after_transaction_commit` holds jobs enqueued inside a transaction
until it commits, so a worker can't pick up a job before the data it depends on
is visible. `analyze: :immediately` analyzes blobs before validation callbacks
run, so `has_one_attached :avatar, content_type: "image/*"` validates on first
save.

### CSRF via Sec-Fetch-Site (8.2)

`:header_only` is the 8.2 default: forgery protection verifies the browser's
`Sec-Fetch-Site` header and needs no `authenticity_token` form param. Migrating
an existing app is where you'd override it, falling back to token verification:

```ruby
config.action_controller.forgery_protection_verification_strategy = :header_or_legacy_token
```

A companion `config.action_controller.forgery_protection_trusted_origins` takes
an allowlist array. The same change deprecates `InvalidAuthenticityToken` in
favor of `InvalidCrossOriginRequest`, so rescue clauses naming the old constant
need updating. (#56350)

### SSL

Since 8.1 (#56010), the generator *comments out* `config.assume_ssl` and
`config.force_ssl` in `production.rb` when the app is generated with Kamal, so
Kamal deploys work out of the box. They're still emitted, just inert — and with
`--skip-kamal` they're generated active. Behind an SSL-terminating proxy,
uncomment both:

```ruby
# config/environments/production.rb
config.assume_ssl = true
config.force_ssl = true
```

## Combined credentials

`Rails.app.creds` (8.2) checks ENV first, then falls back to encrypted
credentials — with a dotenv layer in between when running in development.
`Rails.app.envs` reads the ENV layer alone.

```ruby
Rails.app.creds.require(:stripe_api_key)                   # raises if missing from both
Rails.app.creds.option(:redis_url, default: "redis://...") # optional with default
Rails.app.creds.require(:aws, :bucket)                     # nested: checks AWS__BUCKET first
```

`Rails.application.credentials` still reads the encrypted file directly.

## Deployment revision tracking

```ruby
Rails.app.revision  # checks ENV["REVISION"], then a REVISION file, then the git SHA
```

Useful for cache namespacing and error reporting:

```ruby
config.cache_store = :solid_cache_store, { namespace: Rails.app.revision }
Sentry.set_context("app", { revision: Rails.app.revision })
```

## SQLite multi-database setup

Separate databases per concern give each one its own migration path, backup
policy, and write contention profile — cache churn never blocks primary writes,
and the cache can be dropped and rebuilt without touching application data.

```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000  # installs the busy handler; see SQLite concurrency below

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

Migrate each with `bin/rails db:migrate:queue`, `db:migrate:cache`,
`db:migrate:cable`. Mirror the production Solid wiring in development so the two
behave alike.

## SQLite concurrency

Rails applies six pragmas on connect, without configuration:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;             -- concurrent reads during writes
PRAGMA synchronous = NORMAL;           -- safe with WAL, much faster than FULL
PRAGMA mmap_size = 134217728;          -- 128MB
PRAGMA journal_size_limit = 67108864;  -- 64MB
PRAGMA cache_size = 2000;              -- 2000 *pages* (~8MB), not a byte count
```

`temp_store` and `busy_timeout` are not among them, contrary to some guides.

**Busy handler.** Setting any `timeout:` (ms) in `database.yml` installs a
fair-retry handler via `busy_handler_timeout=`; with no `timeout:` there is no
wait at all. Rails releases the GVL while it waits, so other threads keep
running, and translates `SQLite3::BusyException` into
`ActiveRecord::StatementTimeout`. Needs the `sqlite3` gem >= 2.0. (#51958)

**IMMEDIATE transactions** are the root-cause fix for spurious `database is
locked` errors. SQLite's native DEFERRED mode acquires the write lock at the
first write *inside* the transaction; if another connection holds it at that
moment SQLite cannot retry, and raises immediately even with a timeout set. In a
Rails app where nearly every `transaction do` block writes, that is where the
lock errors come from. Rails sets `default_transaction_mode: :immediate`,
acquiring the lock at `BEGIN` so contention happens before any work and the busy
handler can queue and retry fairly. Fixtures and joinable transactions stay
DEFERRED internally; there's no public flag to change the default. (#50371)

WAL, the busy handler, and IMMEDIATE together are what eliminate the error
storm: untuned SQLite errors on roughly half of responses at four concurrent
writers, versus near-zero with about an order of magnitude better P99.

`activerecord-enhancedsqlite3-adapter` backported most of this before it landed
in core and is now largely redundant — reach for it only for deferred/custom
foreign-key sugar or its experimental reader/writer pool split.

## Customizing pragmas

A `pragmas:` key (7.2) merges over the defaults; unknown pragmas warn. (#50460)

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
    pragmas:
      temp_store: memory  # temp tables and indexes in RAM
      cache_size: -64000  # negative = KB, so 64MB
```

## Loading SQLite extensions

An `extensions:` array (8.1) loads sqlite-vec, sqlean, and friends. Each entry
is a filesystem path, ERB returning a path, or a module responding to
`.to_path`. Needs the `sqlite3` gem >= 2.4.0. (#53827)

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
    extensions:
      - SQLean::UUID
      - <%= SqliteVec.loadable_path %>
      - .sqlpkg/nalgeon/crypto/crypto.so
```

`docs/sqlite-extensions-and-features.md` covers the ecosystem and modern schema
features.

## When SQLite fits

Single-server deployments, read-heavy workloads with moderate writes, internal
and B2B tools, anything deployed with Kamal. Vertical scaling carries these a
long way — multi-GB databases and thousands of requests per second.

Reach for a client/server database when you need multiple app servers sharing
one database, multi-region deployment, sustained very high write volume, or
distributed transactions. Litestream's live read replicas cover some read
scaling without that move; see `docs/production-infrastructure.md`.

## Solid Queue / Cache / Cable

Solid Queue replaces Sidekiq, Solid Cache replaces Redis/Memcached, and Solid
Cable replaces the Redis pub/sub backend for ActionCable. All three are ordinary
Rails APIs at the call site — `Rails.cache.fetch`, `perform_later`,
`stream_from` — so only the wiring differs.

```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
config.cache_store = :solid_cache_store
```

`ActionController::RateLimiting` reads
`config.action_controller.cache_store`, falling back to `config.cache_store`,
so Solid Cache backs rate limiting without extra configuration.

```yaml
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

```yaml
# config/cable.yml
production:
  adapter: solid_cable
  connects_to: cable
```

Solid Queue gets ACID guarantees from the database, supports priorities, delays,
and recurring jobs via `config/recurring.yml`, and mounts a monitoring UI. Solid
Cache is disk-backed, so it survives restarts and isn't bounded by memory.

## Gems and layout

8.2 is unreleased, so there is no version to pin — track main directly:

```ruby
gem "rails", github: "rails/rails", branch: "main"
gem "sqlite3", ">= 2.1"
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
gem "thruster"  # X-Sendfile, HTTP/2, asset caching
```

```
config/
  ci.rb          database.yml   puma.rb        queue.yml
db/
  migrate/       queue_migrate/ cache_migrate/ cable_migrate/
storage/
  db/development.sqlite3  production.sqlite3  production_{cache,queue,cable}.sqlite3
```

## References

- [Rails 8 release notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [Solid Queue](https://github.com/basecamp/solid_queue) · [Solid Cache](https://github.com/basecamp/solid_cache) · [Solid Cable](https://github.com/basecamp/solid_cable)
- [Puma plugins](https://github.com/puma/puma/blob/master/docs/plugins.md)
- Rails PRs: [#51958 busy handler](https://github.com/rails/rails/pull/51958) · [#50371 IMMEDIATE](https://github.com/rails/rails/pull/50371) · [#50460 pragmas](https://github.com/rails/rails/pull/50460) · [#53827 extensions](https://github.com/rails/rails/pull/53827) · [#56350 CSRF](https://github.com/rails/rails/pull/56350)
