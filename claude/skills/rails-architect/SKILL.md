---
name: rails-architect
description: Expert Ruby on Rails architect for reviewing existing Rails applications, suggesting architectural improvements, and designing new features following modern Rails best practices. Use when working with Rails apps, designing Rails features, or reviewing Rails architecture. Based on 37signals/Basecamp production patterns.
allowed-tools: Read, Glob, Grep, Task
---

# Ruby on Rails Architecture Expert

Review Rails applications, design features, and advise on architecture using
production patterns from 37signals/Basecamp. Prefer vanilla Rails over external
abstractions, put business logic in rich domain models with controllers only
coordinating, and follow convention unless there's a compelling reason not to.

## Target stack

These patterns target Rails edge/main, so references to 8.2 are deliberate
rather than mistakes for the current stable release.

Hotwire (Turbo + Stimulus) for reactive UI, import maps and Propshaft for a
zero-build asset pipeline, Solid Queue/Cache/Cable instead of Redis, UUIDv7
primary keys, and fixtures rather than factories.

## Architecture patterns

**Multi-tenancy by URL path.** Middleware extracts the account from `/:account_id/...`
and wraps the request in `Current.with_account`. Every table carries `account_id`,
and background jobs serialize and restore the account context.

**Concern-based model organization.** Single-purpose concerns under
`app/models/card/` for behavior shared across models or worth extracting on its
own; keep it in the model when it's specific to that model or a simple accessor.

```ruby
class Card < ApplicationRecord
  include Closeable, Assignable, Taggable, Searchable, Eventable
end
```

**Strict REST.** Map every action onto a resource instead of adding custom
controller actions — `post :close` becomes a nested `resource :closure` served by
`Cards::ClosuresController#create` and `#destroy`.

**Current attributes** carry request context: user, account, request_id,
timezone, locale. Not application state or configuration. Setting `Current.user`
should cascade to `Current.account`.

**Event sourcing.** An `Eventable#track_event` writing `Event` records drives
activity timelines, notifications, webhooks, analytics, and audit logs.

**Smart defaults with lambdas** keep associations implicit:

```ruby
belongs_to :account, default: -> { board.account }
belongs_to :creator, default: -> { Current.user }
```

**Intention-revealing domain methods.** `card.close(user:)` over
`card.update(status: :closed)` — it encapsulates the business rules, wraps them
in a transaction, and tracks the event.

**Background jobs delegate to models.** Jobs stay thin wrappers; `_later` methods
enqueue and `_now` methods execute:

```ruby
class Event::RelayJob < ApplicationJob
  def perform(event) = event.relay_now
end
```

**Sequential user-facing IDs.** UUID primary keys with a separate sequential
number for display; override `to_param` so URLs use the number.

**SQLite FTS5 for search** via `create_virtual_table` plus sync triggers, rather
than an external search engine. At scale, shard search tables and route by
account hash.

## Review checklist

**Models**: business logic rather than CRUD, concerns for shared behavior, smart
defaults, domain methods, multi-tenancy enforced.
**Controllers**: thin (under ~10 lines per action), standard REST verbs only,
Turbo Stream responses.
**Database**: UUIDs, indexes, `account_id` everywhere, no N+1s.
**Frontend**: Hotwire used well, import maps, forms that work without JS, Turbo
Frames/Streams for partial updates.
**Jobs**: thin wrappers, account context preserved, recurring work in
`config/recurring.yml`, Solid Queue.
**Testing**: fixtures not factories, parallelized, one test per behavior, side
effects checked.
**Organization**: concerns in the right directories, methods ordered by
invocation, guard clauses at the top.

Review alone doesn't verify a design. Once it lands as code, run the test suite
(`bin/ci`, or `bin/rails test` before 8.1) and judge from the output.

## Gotchas

Version boundaries that bite because this skill targets edge/main while apps
usually run stable:

- `bin/ci` and `step` are 8.1; the `group ... parallel:` DSL is 8.2-only and was
  not backported.
- Puma's `solid_queue` plugin flipped polarity: 8.1 loads it only when
  `SOLID_QUEUE_IN_PUMA` is set, 8.2 loads it unless disabled.
- IMMEDIATE transactions (`default_transaction_mode: :immediate`, 8.0) are the
  root-cause fix for spurious `database is locked` — DEFERRED acquires the write
  lock mid-transaction, where the busy handler can't retry.
- database.yml: `pragmas:` needs 7.2+, `extensions:` needs 8.1+ and sqlite3 gem
  2.4+. `strict: true` means strict *quoting*, not SQLite STRICT tables.
- Rate limiting raises `ActionController::TooManyRequests` (8.1), a bare class
  with no `retry_after`. The store comes from
  `config.action_controller.cache_store` or per-call `store:`.
- The ActionText editor is one global setting (`config.action_text.editor`);
  `has_rich_text` takes no `editor:` kwarg.
- `SecureRandom.uuid_v7` needs Ruby 3.3+.
- Litestream v0.5 config takes a singular `replica:` map per database, not a
  `replicas:` list; v0.3-format backups are not restore-compatible.

## Reference docs

- **`docs/anti-patterns.md`** — service objects, fat controllers, god objects, custom actions, over-engineering, missing transactions, mocked tests
- **`docs/feature-design-patterns.md`** — starring, comments, search, notifications, each as a complete migration + model + controller + routes
- **`docs/authorization-and-roles.md`** — roles, permissions, access control, Identity vs User separation, multi-tenant user management
- **`docs/view-patterns.md`** — instance variables vs locals, helpers vs ERB, partial extraction, display variants, Turbo integration, caching
- **`docs/passkey-authentication.md`** — WebAuthn/passkeys, session-based challenges, admin-controlled provisioning, clone detection, virtual authenticator testing
- **`docs/uuidv7-sqlite.md`** — UUID generation, Active Storage config, fixture IDs, foreign keys, migrations
- **`docs/sqlite-extensions-and-features.md`** — `extensions:` config, sqlite-vec vector search, FTS5, sqlean, generated columns, RETURNING, JSON, the STRICT-table caveat
- **`docs/testing-pyramid.md`** — test levels and distribution, avoiding slow system tests, JSON fields, multi-tenancy testing
- **`docs/lexxy-rich-text-editor.md`** — rich text and ActionText customization, pluggable editor registry, @mentions, slash commands, SGID attachables, tables
- **`docs/rails-8-modern-stack.md`** — Puma plugins, bin/ci, SQLite multi-database, Solid adapters, unified credentials, revision tracking
- **`docs/production-infrastructure.md`** — Kamal, Cloudflare Tunnel, ACME passthrough, R2, Litestream, cloud-init, CI/CD, Dockerfiles
