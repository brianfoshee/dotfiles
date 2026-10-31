---
name: rails-architect
description: Expert Ruby on Rails architect for reviewing existing Rails applications, suggesting architectural improvements, and designing new features following modern Rails best practices. Use when working with Rails apps, designing Rails features, or reviewing Rails architecture. Based on 37signals/Basecamp production patterns.
allowed-tools: Read, Glob, Grep, Agent
---

# Ruby on Rails Architecture Expert

Review Rails applications, design features, and advise on architecture using
production patterns from 37signals/Basecamp. Prefer vanilla Rails over external
abstractions, put business logic in rich domain models with controllers only
coordinating, and follow convention unless there's a compelling reason not to.

## Target stack

Apps run rails/rails main with `config.load_defaults 8.2`, on Ruby 3.3.5 or
newer. The Gemfile follows the branch, and `Gemfile.lock` holds the revision:

```ruby
gem "rails", github: "rails/rails", branch: "main"
```

Hotwire (Turbo + Stimulus) for reactive UI, import maps for zero-build
JavaScript, Propshaft with tailwindcss-rails for CSS, Solid Queue/Cache/Cable
instead of Redis, UUIDv7 primary keys, and fixtures rather than factories.

## Architecture patterns

**Multi-tenancy by URL path.** Middleware extracts the account from `/:account_id/...`,
moves the prefix into `SCRIPT_NAME`, and wraps the request in
`Current.with_account`, so routes carry no account scope and helpers prefix
automatically. Every tenant-owned table carries `account_id`, including Active
Storage and Action Text tables (inject `belongs_to :account, default:` in
`to_prepare`); identity, session, token and credential tables stay global.

Mailers, broadcasts and `ApplicationController.renderer` run outside a request:
merge `script_name: Current.account.slug` into the mailer's
`default_url_options` and pass it to `renderer.new`. `script_name: nil` leaves
the tenant. Jobs capture the account at enqueue and resolve it in
`around_perform`, so a deleted account hits `discard_on`. Prepend that module
onto `ActionMailer::MailDeliveryJob` and Turbo's broadcast jobs too — they don't
inherit `ApplicationJob`.

**Concern-based model organization.** Model-specific concerns go in
`app/models/card/` (`Card::Closeable`), cross-model ones in `app/models/concerns/`
(`Eventable`). Extract by trait even when only Card uses it, so the model reads
as a table of contents. A model concern can `include ::Eventable` and override
its template hooks.

**Strict REST.** Map every action onto a resource instead of adding custom
controller actions — `post :close` becomes a nested `resource :closure` served by
`Cards::ClosuresController#create` and `#destroy`.

**State as a record.** Model a toggleable state as a `has_one` row (`Closure`),
not a boolean. It records when (and who, given a `user_id`), scopes are
`joins(:closure)` / `where.missing(:closure)`, and it maps onto `resource :closure`.

**Current attributes** carry request context: session, identity, user, account,
request_id, user agent, IP. Not application state or configuration. The account
comes first, from the URL; setting `Current.session` cascades to its identity,
then to that identity's user in `Current.account`. Time zone goes through
`around_action { Time.use_zone(...) }` (or `user.in_time_zone {}` in jobs), not
Current. Outside a request, use `Current.set(user:, account:)`.

**Event records.** `track_event` writes an `Event` row per domain action, inside
the verb's transaction or from a lifecycle callback. Not event sourcing — state
lives in its own tables. Events drive the timeline, notifications and webhooks. Per-user state such as a star isn't activity and tracks no event.

**Notifications** fan out in a job per source, dedupe on a unique
`[recipient_id, source_type, source_id]` index with `create_or_find_by!`, and
record read state as a `read_at` timestamp. Create them in one recipient order
everywhere (`sort_by(&:id)`) so concurrent runs can't deadlock.

**Smart defaults with lambdas** keep associations implicit:
`belongs_to :account, default: -> { board.account }` and
`belongs_to :creator, default: -> { Current.user }`.

**Intention-revealing domain methods.** `card.close(user:)` over
`card.update(status: :closed)` — it encapsulates the business rules, wraps them
in a transaction, and tracks the event.

**Service-shaped classes** earn their place for multi-model operations, external
API integrations and form objects. They live in `app/models`, under the model's
namespace when they serve one model (`Card::Importer#import`), named with a
domain verb rather than `#call`. When a model owns the collaborator, the model
exposes the entry point (`card.import_later`), not the controller.

**Background jobs delegate to models.** Jobs stay thin wrappers: `deliver_later`
enqueues a job whose `perform` calls `deliver`, and the `_later` method is
usually private and fired from `after_*_commit`.

**Sequential user-facing IDs.** UUID primary keys with a separate sequential
number for display; override `to_param` so URLs use the number. Assign it in
`before_create` with `account.with_lock { account.increment!(:cards_count).cards_count }`,
backed by a unique `[account_id, number]` index — without the lock, `increment!`
returns a stale count. On SQLite `with_lock` emits no `FOR UPDATE`; IMMEDIATE
transactions serialize the writers.

**SQLite FTS5 for search** rather than an external search engine. Index an
integer-keyed `search_records` table — a UUID key can't be `content_rowid` —
that models upsert from `after_save_commit`, which also reaches Action Text
bodies; triggers on `search_records` keep the FTS index in sync. Every search
row carries `account_id`, and every query filters on it.

## Review checklist

**Models**: business logic rather than CRUD, concerns for shared behavior, smart
defaults, domain methods, multi-tenancy enforced.
**Controllers**: thin — one model call, any extra length only from
`respond_to` branches; standard REST verbs only; one controller answers HTML,
Turbo Stream and JSON (jbuilder + `wrap_parameters`), no `Api::` namespace;
`fresh_when` on GETs.
**Database**: UUIDs, indexes, `account_id` on every tenant-owned table, no N+1s.
**Frontend**: Hotwire used well, import maps, forms that work without JS, Turbo
Frames/Streams for partial updates, templates that pass `bin/rails herb:check`.
**Jobs**: thin wrappers, account context preserved, Solid Queue.
`discard_on ActiveJob::DeserializationError` when the record may be gone;
`ActiveJob::Continuable` for long sweeps (the model takes `start:`, the job owns
the cursor); `limits_concurrency` to serialize per record; `perform_all_later`
for fan-out. Recurring work as `command: "Model.cleanup"` over a `stale` scope
in `config/recurring.yml`; `class:` only when the job needs job features.
**Testing**: fixtures not factories, parallelized, one test per behavior, side
effects checked.
**Organization**: concerns in the right directories, methods ordered by
invocation, expanded `if/else` over guard clauses (an early return only as the
first line of a non-trivial method), `!` only when a non-bang twin exists.

Review alone doesn't verify a design. Once it lands as code, run the test suite
(`bin/ci`) and judge from the output.

## Gotchas

- No advisory tool flags Rails on main: the gems report `8.2.0.alpha`, which
  satisfies every patched range. Dependabot's daily bump of the locked revision
  is the security mechanism, and it only bumps `branch:`, never a `ref:` pin.
- Herb compiles `.html.erb`. An element opened in one ERB branch and closed in
  another fails at compile time; `<%= %>` in a tag's attribute list fails
  `bin/rails herb:check`. Use `tag.attributes` or `<% if %>` control flow.
- `:header_only` CSRF rejects an HTTPS request with no `Sec-Fetch-Site` header
  even when its authenticity token is valid. Non-browser JSON clients send none;
  override `verified_via_header_only?` with
  `super || (sec_fetch_site_value.nil? && request.format.json?)` — safe only with
  a `SameSite=Lax` session cookie, `allow_browser versions: :modern`, and bearer
  auth restricted to JSON.
- Puma's `solid_queue` plugin loads only when `SOLID_QUEUE_IN_PUMA` is set to
  something other than empty, `false` or `0`.
- IMMEDIATE transactions (`default_transaction_mode: :immediate`) are the
  root-cause fix for spurious `database is locked` — DEFERRED acquires the write
  lock mid-transaction, where the busy handler can't retry.
- On SQLite, `execute` runs only the first statement of a multi-statement
  string and silently drops the rest — one `execute` per `CREATE TRIGGER`.
- database.yml: `extensions:` needs sqlite3 gem 2.4+. `strict: true` means
  strict *quoting*, not SQLite STRICT tables.
- Rate limiting raises `ActionController::TooManyRequests`, a bare class
  with no `retry_after`; pass `with:` a method name and set `Retry-After` there.
  The store comes from `config.action_controller.cache_store` or per-call
  `store:`. Budgets are keyed by `controller_path` unless `scope:` names a
  shared one, and `by:` may return a record. The test env's `:null_store` never
  trips a limit — swap in a `MemoryStore` rather than stubbing `increment`.
- `script_name`, `host` and `only_path` are `url_for` generation options, so
  `params.permit!` passed to `url_for` lets `?script_name=` retarget the link.
  Forward named keys.
- Renaming a job class fails jobs already queued under the old name. Leave a
  one-line subclass shim until the queue drains.
- The ActionText editor is one global setting (`config.action_text.editor`);
  `has_rich_text` takes no `editor:` kwarg.
- Litestream v0.5 config takes a singular `replica:` map per database, not a
  `replicas:` list; v0.3-format backups are not restore-compatible.

## Reference docs

- **`docs/authorization-and-roles.md`** — roles, permissions, access control, opt-out macros and `*Scoped` concerns, bearer tokens, Active Storage authorization, revocation, Identity vs User separation, multi-tenant user management
- **`docs/view-patterns.md`** — semantic tag builders, display-variant partials, Herb-safe templates and hand-built attribute strings, Turbo refresh morphs, fragment-cache keys, JSON with jbuilder
- **`docs/passkey-authentication.md`** — passkey-only auth: Current.user binding, signed challenges, magic-link provisioning, webauthn-ruby encoding traps, virtual authenticator testing
- **`docs/uuidv7-sqlite.md`** — UUID generation, the binary-UUID alternative, Active Storage config, fixture IDs, foreign keys, migrations
- **`docs/sqlite-extensions-and-features.md`** — `extensions:` config, sqlite-vec vector search, FTS5, sqlean, generated columns, RETURNING, JSON, column length limits, the STRICT-table caveat
- **`docs/testing-pyramid.md`** — fixture UUIDs, multi-tenancy and sign-in test setup, parallel and shuffled-order runs, CSRF and content-type pins, bin/ci groups
- **`docs/lexxy-rich-text-editor.md`** — rich text and ActionText customization, pluggable editor registry, @mentions, slash commands, SGID attachables, tables, Tailwind styling
- **`docs/rails-8-modern-stack.md`** — running main, Puma plugins and tuning, bin/ci, 8.2 framework defaults, Sec-Fetch-Site CSRF, Active Storage analysis, Herb, Active Record, SQLite multi-database, Solid adapters, job continuations, framework patches, unified credentials, revision tracking
- **`docs/production-infrastructure.md`** — Kamal accessories, Litestream v0.5 config, ACME through a tunnel, CI/CD hardening, Dependabot for rails main, generated-Dockerfile deviations
