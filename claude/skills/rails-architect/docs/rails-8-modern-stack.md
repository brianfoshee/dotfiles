# Rails 8.2 Modern Stack

No JS bundler, no Redis: SQLite for everything, Puma plugins instead of
Foreman, import maps for JavaScript and tailwindcss-rails for CSS. Runs rails/rails main with
`config.load_defaults 8.2`.

## Contents

- [Running main](#running-main)
- [Puma plugins](#puma-plugins)
- [Puma tuning](#puma-tuning)
- [Local CI runner](#local-ci-runner)
- [Framework defaults](#framework-defaults)
- [Herb templates](#herb-templates)
- [Active Record](#active-record)
- [Other APIs](#other-apis)
- [Job continuations](#job-continuations)
- [Combined credentials](#combined-credentials)
- [Deployment revision tracking](#deployment-revision-tracking)
- [SQLite multi-database setup](#sqlite-multi-database-setup)
- [SQLite concurrency](#sqlite-concurrency)
- [Customizing pragmas](#customizing-pragmas)
- [Loading SQLite extensions](#loading-sqlite-extensions)
- [Framework patches](#framework-patches)
- [References](#references)

## Running main

```ruby
# Gemfile
gem "rails", github: "rails/rails", branch: "main"
```

`Gemfile.lock` holds the exact revision. Dependabot bumps the locked revision of
a git gem that follows a branch (a daily `bundler` group does it), but leaves a
`ref: "<sha>"` pin alone, so follow `branch:`, not `ref:`. The Dependabot config
is in `docs/production-infrastructure.md`.

**Advisory blind spot.** bundler-audit and Dependabot alerts match on version,
and the main gems report `8.2.0.alpha`, which satisfies every patched range such
as `>= 8.1.2.1`. No advisory tool will ever flag Rails while the app is on main;
the daily revision bump is what delivers security fixes, so don't let those PRs
sit.

Rails 8.2 requires Ruby 3.3.5 or newer. Bundler's git checkouts need `git` in
the Docker build stage.

## Puma plugins

Puma plugins fold the CSS watcher and the job worker into the web process, so
`bin/dev` is just `rails server` and there's no Procfile or Foreman:

```ruby
# config/puma.rb
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

The job plugin is opt-*in*: it loads only when `SOLID_QUEUE_IN_PUMA` is set to
something other than empty, `false` or `0`. The generated `config/deploy.yml`
sets `SOLID_QUEUE_IN_PUMA: true` for single-server deployments; set it in
development too if `bin/dev` should run jobs. Leave it unset wherever `bin/jobs`
runs as its own process, or you get a supervisor in both places.

## Puma tuning

The generated `threads 3` assumes a database across the network. With SQLite on
local disk there's little I/O wait for extra threads to fill, so start at one
worker per physical core with one thread each, then measure:

```ruby
# config/puma.rb
unless Rails.env.local?
  workers Integer(ENV.fetch("WEB_CONCURRENCY") { Concurrent.physical_processor_count })
  threads 1, 1

  # Tidy the heap once before forking, for copy-on-write
  before_fork { Process.warmup }

  # Defer major GC out of the request path
  before_worker_boot { GC.config(rgengc_allow_full_mark: false) }
  out_of_band { GC.start if GC.latest_gc_info(:need_major_by) }
end
```

Slow outbound calls — webhooks, third-party APIs — are what argue for more
threads. `GC.config(rgengc_allow_full_mark:)` needs Ruby 3.4. The edge guide
"Tuning Performance for Deployment" covers the trade-offs.

## Local CI runner

`bin/ci` runs the CI pipeline locally from a Ruby config, so the same definition
drives local runs and GitHub Actions:

```ruby
# config/ci.rb
CI.run do
  step "Setup", "bin/setup --skip-server"

  group "Checks", parallel: 2 do
    step "Style: Ruby", "bin/rubocop"
    step "Security: Gem audit", "bin/bundler-audit"
    step "Security: Importmap audit", "bin/importmap audit"
    step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "Templates: Herb", "bin/rails herb:check"

    group "Tests" do
      step "Tests: Rails", "bin/rails test"
      step "Tests: System", "bin/rails test:system"
      step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
    end
  end
end
```

Steps in a `group` with `parallel:` run concurrently, each step's output
captured so it doesn't interleave. A sub-group occupies one parallel slot and
runs its own steps sequentially, which is how the tests stay in order while the
checks run beside them. The seeds step is worth copying — a broken
`db/seeds.rb` usually isn't discovered until it's needed. `herb:check` boots
the app, so it belongs in the GitHub workflow's test job as well (see
`docs/production-infrastructure.md`). Whether the parallel group pays off
depends on the machine; `docs/testing-pyramid.md` has the measurement.

## Framework defaults

`load_defaults "8.2"` already sets all of these — they're listed to explain the
behavior, not as lines to write:

```ruby
config.action_view.erb_implementation = :herb
config.action_controller.forgery_protection_verification_strategy = :header_only
config.action_controller.default_protect_from_forgery_with = :exception
config.action_controller.rescue_from_event_backtrace = :array
config.action_dispatch.strict_accept_header = true
config.action_dispatch.default_headers = { ... }  # no X-XSS-Protection
config.active_record.postgresql_adapter_decode_bytea = true
config.active_record.postgresql_adapter_decode_money = true
config.active_storage.analyze = :immediately
config.active_storage.s3_public_uploads_via_acl = false
config.active_job.enqueue_after_transaction_commit = true
ActiveSupport.raise_on_invalid_time_zone_parse = true
```

`strict_accept_header` honors a specific format in `Accept` even alongside
`*/*`, so `Accept: application/json, */*` gets JSON rather than HTML.
`raise_on_invalid_time_zone_parse` makes `Time.zone.parse("foobar")` raise
`ArgumentError` instead of returning nil. The Herb default has its own section
below.

### Jobs after commit

`enqueue_after_transaction_commit` holds jobs enqueued inside a transaction —
including from `after_create` and other callbacks — until it commits. That
closes the race where a worker polling a separate queue database picks the job
up before the row it depends on exists, or runs against a record that was
rolled back. It's an ordinary boolean, so an app can turn it off globally.

The built-in Sidekiq adapter is gone, and the `queue_classic`, `resque`,
`delayed_job`, `backburner` and `sneakers` adapters are deprecated in favor of
the adapters those gems ship themselves.

### Active Storage analysis

`analyze: :immediately` analyzes a file attached on the server — an
`UploadedFile`, `StringIO` or `File` — in process, in a `before_validation`
callback, so metadata is available to validations on the first save:

```ruby
has_one_attached :avatar
validate :avatar_large_enough, if: -> { avatar.attached? }

def avatar_large_enough
  if avatar.metadata[:width] < 200 || avatar.metadata[:height] < 200
    errors.add(:avatar, "must be at least 200x200")
  end
end
```

The IO must still be open when validation runs. A blob attached by signed id
from a direct upload has no local bytes, so it falls back to `AnalyzeJob` and
its metadata isn't there to validate; validate those on the client. The
built-in analyzers rescue and log vips, ImageMagick and ffprobe failures, so an
unreadable file doesn't fail the save. Override per attachment with
`has_one_attached :document, analyze: :later` or `analyze: :lazily`.

Named variants take `process: :immediately` (generated with the attachment),
`:later` (background job) or `:lazily` (on request, the default);
`preprocessed: true` is deprecated in favor of `process: :later`.
`config.active_storage.variant_processor` accepts a transformer class as well
as `:vips` / `:mini_magick`; the built-in image analyzers then need a custom
analyzer alongside it.

**Untrusted uploads.** libvips parses whatever it's handed. Block the loaders
that aren't fuzzed, after Active Storage has set its own defaults, and cap
libvips' threads and cache:

```ruby
# config/initializers/vips.rb
ActiveStorage::Transformers::Vips   # load first, so the blocks below stick
Vips.block_untrusted(true)
Vips.concurrency_set 4
Vips.cache_set_max_mem 10.megabytes
```

`Vips.block("VipsForeignLoadTiff", true)` blocks a single loader the app never
needs.

Content types come from Marcel 2, which returns canonical types for newly
identified blobs (`image/x-bmp` becomes `image/bmp`, `text/x-yaml` becomes
`application/yaml`). An allow-list that string-compares `content_type` needs the
pin test in `docs/testing-pyramid.md`.

### CSRF via Sec-Fetch-Site

Forgery protection verifies the browser's `Sec-Fetch-Site` header. GET, HEAD and
QUERY requests are never checked. Two strategies, set globally or per
controller:

```ruby
protect_from_forgery using: :header_only, with: :exception
protect_from_forgery using: :header_or_legacy_token, with: :exception
```

`:header_only` (the default) accepts `same-origin` and `same-site` and rejects
`cross-site`. It never looks at the authenticity token: over HTTPS a request
with no header is rejected even when its token is valid (a missing header passes
only over plain HTTP with `force_ssl` off), and `none` is always rejected.
`:header_or_legacy_token` runs the same header check first and falls back to the
token only when the header is missing or `none`.

Before switching to `:header_only`, find out who would break. Every time the
token path is used, Rails instruments `csrf_token_fallback.action_controller`
(payload: `request`, `controller`, `action`, `sec_fetch_site`) and logs
`Falling back to CSRF token verification for Controller#action` at warn level,
so querying the logs while running `:header_or_legacy_token` counts the clients
that send no header.

`trusted_origins:` (or `config.action_controller.forgery_protection_trusted_origins`)
admits cross-site requests from an allowlist, such as an SSO callback.
`default_protect_from_forgery_with = :exception` makes a bare
`protect_from_forgery` raise on failure rather than null the session; passing
`with:` explicitly keeps the intent readable. `InvalidAuthenticityToken` is a
deprecated alias for
`InvalidCrossOriginRequest`, so rescue the latter. `ActionController::API`
controllers have no forgery protection at all, so webhook endpoints built on it
are unaffected. Testing the strategy is covered in `docs/testing-pyramid.md`.

### SSL

The generator emits `config.assume_ssl` and `config.force_ssl` in
`production.rb` commented out when the app is generated with Kamal, so Kamal
deploys work out of the box; `--skip-kamal` emits them active. Behind an
SSL-terminating proxy, uncomment both:

```ruby
# config/environments/production.rb
config.assume_ssl = true
config.force_ssl = true
```

## Herb templates

Herb (marcoroth/herb) is the ERB compiler. It parses HTML and ERB as one tree —
a C lexer and parser for the HTML, Prism for the Ruby — where Erubi treated the
HTML as opaque text. Only `.html.erb` goes through it; every other format stays
on Erubi. The Rails handler (`ActionView::Template::Handlers::ERB::Herb`) emits
the same `@output_buffer` code Erubi does and leaves escaping to
`ActionView::OutputBuffer`, so a valid template renders identically with no
runtime cost.

**Compile-time failures.** Herb raises when a template compiles, with file and
line, on unclosed or misnested tags, an element opened in one ERB branch and
closed in another, a stray `%>`, and `case`/`when` inside a single ERB tag.

**Security validator.** `bin/rails herb:check` compiles every HTML+ERB template
with Herb's security validator added, lists each failure, and exits non-zero. The
validator rejects `<%= %>` output in a tag's attribute list ("ERB output tags
(<%= %>) are not allowed in attribute position") or inside an attribute name
("ERB output in attribute names is not allowed for security reasons"). The one
allowed form is an unconditional `<%= tag.attributes(...) %>`; a conditional one
is rejected too, so write `<% if x %><%= tag.attributes(...) %><% end %>`. The
validator runs only in `herb:check`, not at render, so the check belongs in
`config/ci.rb` and the GitHub workflow — see [Local CI runner](#local-ci-runner).
The template patterns that replace the rejected ones are in
`docs/view-patterns.md`.

The escape hatch is global only: `config.action_view.erb_implementation =
:erubi`. Herb also ships a linter (`npx @herb-tools/linter`), an experimental
formatter (`npx @herb-tools/formatter`) and a language server for VS Code, Zed
and Neovim.

## Active Record

**`schema_ignored_tables`** replaces `ActiveRecord::SchemaDumper.ignore_tables`
and `schema_cache_ignored_tables`, both deprecated. It applies to the schema
dump and the schema cache, and matches real table names, including
`table_name_prefix` and `table_name_suffix`:

```ruby
config.active_record.schema_ignored_tables = [/^_/]
```

**Scoped `update`.** `Relation#update` and `#update!` with an id look the record
up through the relation, so `post.comments.update!(id, ...)` raises
`RecordNotFound` for a comment outside it instead of updating any comment.

**Negative enum scopes** (`not_published`) include rows where the column is
NULL.

**`implicit_persistence_transaction(connection, &block)`** is the hook wrapping
`save`, `destroy` and `touch` in a transaction; override it privately in a model
to set an isolation level or skip the transaction when one is already open.

**SQLite table rebuilds** — `remove_column` and the other alterations SQLite
can't do in place — disable foreign keys around the rebuild transaction, so
`ON DELETE CASCADE` on child tables doesn't fire.

**Shuffled unordered selects.** `config.active_record.shuffle_unordered_selects
= true` in the test environment randomizes the row order of SELECTs that have
no `ORDER BY`; `docs/testing-pyramid.md` covers what it catches.

**JSON schema cache.** A `schema_cache_path` ending in `.json` dumps and loads
the schema cache as JSON, noticeably faster than YAML or Marshal.

**`has_json` / `has_delegated_json`** give a JSON attribute a schema: each key
declares a default or a type, values are cast on write, and
`has_delegated_json` exposes the keys as accessors on the model itself:

```ruby
has_json :settings, restrict_creation_to_admins: true, max_invites: 10
has_delegated_json :flags, beta: false, staff: :boolean
```

## Other APIs

- `Rails.app` is an alias for `Rails.application`.
- `has_secure_password algorithm: :argon2` (with `gem "argon2"`) removes
  BCrypt's 72-byte limit; `ActiveModel::SecurePassword.register_algorithm`
  registers others by symbol.
- `SecureRandom.base32` generates case-insensitive keys that are unambiguous to
  humans.
- `render layout: "cards/frame", collection: @cards, as: :card do ... end`
  renders the partial once per card, and each one's `yield` runs the block.
- Routes with dynamic `:controller` or `:action` segments raise when drawn. With
  eager loading on, a route to a missing controller logs
  `GET /photos(.:format) references a missing controller` at boot.
- Action Text's Trix-specific API is deprecated (`to_trix_html`,
  `ActionText::TrixAttachment`, `Attachments::TrixConversion`,
  `to_trix_content_attachment_partial_path`); the editor is pluggable, and
  `docs/lexxy-rich-text-editor.md` covers Lexxy.

## Job continuations

`ActiveJob::Continuable` lets a long sweep stop at a deploy and resume from a
cursor instead of starting over. The model's query takes the cursor; the job
owns it:

```ruby
class Webhook::DispatchJob < ApplicationJob
  include ActiveJob::Continuable

  def perform(event)
    step :dispatch do |step|
      Webhook.active.subscribed_to(event).find_each(start: step.cursor) do |webhook|
        webhook.deliver(event)
        step.advance! from: webhook.id
      end
    end
  end
end
```

Code outside a `step` runs on every resume; completed steps are skipped.
`step.set!(cursor)` records an arbitrary cursor and `step.checkpoint!` is a
bare interruption point. An error raised after the cursor has advanced resumes
the job rather than failing it, and `max_resumptions` is unlimited by default,
so a deterministic failure retries forever: set `self.max_resumptions` or
`self.resume_errors_after_advancing = false`. In `config/recurring.yml`, a
continuable job needs `class:`; plain sweeps can be `command: "Model.cleanup"`.

## Combined credentials

`Rails.app.creds` checks ENV first, then falls back to encrypted
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

Use it for error reporting and deploy verification, not cache namespacing:

```ruby
Sentry.set_context("app", { revision: Rails.app.revision })
```

Template digests and `cache_key_with_version` already invalidate stale
fragments, so a revision namespace only cold-starts the cache on every deploy.
Namespace by environment instead (`namespace: Rails.env` in
`config/cache.yml`).

## SQLite multi-database setup

The generator's `database.yml` gives primary, cache, queue and cable their own
files, so each has its own migration path (`db:migrate:queue` and friends),
backup policy and write contention profile. Two things to change in it:
`max_connections:` replaces the deprecated `pool:` key, and `timeout: 5000`
installs the busy handler (below). Mirror the production Solid wiring in
development so the two behave alike.

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
`ActiveRecord::StatementTimeout`. Needs the `sqlite3` gem >= 2.0.

**IMMEDIATE transactions** are the root-cause fix for spurious `database is
locked` errors. SQLite's native DEFERRED mode acquires the write lock at the
first write *inside* the transaction; if another connection holds it at that
moment SQLite cannot retry, and raises immediately even with a timeout set. In a
Rails app where nearly every `transaction do` block writes, that is where the
lock errors come from. Rails sets `default_transaction_mode: :immediate`,
acquiring the lock at `BEGIN` so contention happens before any work and the busy
handler can queue and retry fairly. Fixtures and joinable transactions stay
DEFERRED internally; there's no public flag to change the default.

WAL, the busy handler, and IMMEDIATE together are what eliminate the error
storm: untuned SQLite errors on roughly half of responses at four concurrent
writers, versus near-zero with about an order of magnitude better P99.

`activerecord-enhancedsqlite3-adapter` duplicates most of this and is largely
redundant — reach for it only for deferred/custom foreign-key sugar or its
experimental reader/writer pool split.

## Customizing pragmas

A `pragmas:` key merges over the defaults; unknown pragmas warn.

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

An `extensions:` array loads sqlite-vec, sqlean, and friends. Each entry is a
filesystem path, ERB returning a path, or a module responding to `.to_path`.
Needs the `sqlite3` gem >= 2.4.0.

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

## Framework patches

One file per patch, named `lib/rails_ext/<framework>_<behavior>.rb`, preferably
a module prepended onto the framework class. Keep the directory out of the
autoloader and require it from one initializer:

```ruby
# config/application.rb
config.autoload_lib(ignore: %w[ assets tasks rails_ext ])

# config/initializers/extensions.rb
Dir[Rails.root.join("lib", "rails_ext", "*.rb")].each { |path| require path }
```

Open each file with why the patch exists and, on main, the upstream PR that
will let you delete it.

## References

- [Rails 8.2 release notes](https://edgeguides.rubyonrails.org/8_2_release_notes.html) · [Rails 8 release notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [Herb](https://herb-tools.dev) · [marcoroth/herb](https://github.com/marcoroth/herb)
- [Solid Queue](https://github.com/basecamp/solid_queue) · [Solid Cache](https://github.com/basecamp/solid_cache) · [Solid Cable](https://github.com/basecamp/solid_cable)
- [Puma plugins](https://github.com/puma/puma/blob/master/docs/plugins.md)
- Rails PRs: [#51958 busy handler](https://github.com/rails/rails/pull/51958) · [#50371 IMMEDIATE](https://github.com/rails/rails/pull/50371) · [#50460 pragmas](https://github.com/rails/rails/pull/50460) · [#53827 extensions](https://github.com/rails/rails/pull/53827) · [#56350 CSRF](https://github.com/rails/rails/pull/56350)
