# SQLite Extensions and Modern Schema Features

Loading SQLite extensions from Rails and using modern SQLite schema features (vector search, full-text search, generated columns, RETURNING, JSON, STRICT tables) through the ActiveRecord DSL.

## Contents

- [Loading Extensions](#loading-extensions)
- [Vector Search: sqlite-vec](#vector-search-sqlite-vec)
- [Full-Text Search: FTS5](#full-text-search-fts5)
- [The sqlean Bundle](#the-sqlean-bundle)
- [Modern Schema Features](#modern-schema-features)
- [The sqlite3-ruby Gem](#the-sqlite3-ruby-gem)
- [References](#references)

## Loading Extensions

Two paths, low-level and configured.

**Configured (Rails 8.1, preferred).** The `extensions:` array in `database.yml` loads extensions on connect. Requires the `sqlite3` gem >= 2.4.0 (which added passing extensions to the `Database.new` constructor). Each entry is a filesystem path, ERB that returns a path, or a constant/module that responds to `.to_path`:

```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
    extensions:
      - SQLean::UUID                     # module responding to .to_path (most ergonomic)
      - <%= SqliteVec.loadable_path %>   # ERB returning a path
      - .sqlpkg/nalgeon/crypto/crypto.so # filesystem path
```

**Low-level (manual).** In an initializer against the raw connection — needed on Rails < 8.1 or for conditional loading:

```ruby
db = ActiveRecord::Base.connection.raw_connection
db.enable_load_extension(true)
db.load_extension(SqliteVec.loadable_path)
db.enable_load_extension(false)
```

**Distributing binaries.** Extension `.so`/`.dylib` files are platform-specific. Options, best to worst fit:
- **Ruby gems that vendor a specific extension** (`sqlite-vec`, `sqlite-ulid`, the `sqlean` gems) — expose a `.to_path`, drop straight into `extensions:`.
- **sqlpkg-ruby** (fractaledmind) — vendors sqlpkg-managed extensions into a Rails app.
- **sqlpkg** (nalgeon) — SQLite package manager/registry (~100 extensions). Flag: marked no-longer-maintained upstream, though the CLI/registry still function.

**Windows caveat:** since `sqlite3` gem v2.6.0, extension loading is unavailable on Windows with precompiled/vendored-source gems (SQLite 3.48+ changed the amalgamation). Workaround: compile against a system libsqlite3.

## Vector Search: sqlite-vec

Vector search extension by Alex Garcia (successor to the deprecated `sqlite-vss`). Pure C, zero dependencies. **Pre-1.0 (alpha)** — the SQL API and on-disk storage format may break before v1.0, so caveat any production use.

The `sqlite-vec` Ruby gem ships precompiled binaries and exposes a loadable path, so it drops into `extensions:` (or `SqliteVec.load(db)` for the manual path). Define `vec0` virtual tables and query with `MATCH` + `ORDER BY distance`:

```sql
CREATE VIRTUAL TABLE vec_items USING vec0(embedding float[384]);
INSERT INTO vec_items(rowid, embedding) VALUES (1, '[0.1, 0.2, ...]');

SELECT rowid, distance FROM vec_items
WHERE embedding MATCH '[...]' ORDER BY distance LIMIT 10;
```

`vec0` tables aren't standard AR-modeled tables, so query them via `execute` / `find_by_sql`.

**vs pgvector.** sqlite-vec wins on zero-infra/embedded/edge deployment (single file, no server) — a natural fit when the app is already SQLite-on-Rails and the corpus is small-to-moderate. It does brute-force KNN by default (no mature ANN/HNSW index), so pgvector remains the safer choice for large-scale, high-concurrency RAG.

## Full-Text Search: FTS5

FTS5 is a virtual-table module compiled into most SQLite builds, with built-in BM25 ranking and external-content mode. Prefer it over an external search engine for single-server apps.

**Rails 8.0 added native migration support** (`create_virtual_table` / `drop_virtual_table`, PR #52354) and fixed `schema.rb` dumping so the virtual table is dumped while its shadow tables are excluded:

```ruby
create_virtual_table "documents_fts", "fts5",
  ["title", "body", "content='documents'", "content_rowid='id'", "tokenize='porter'"]
```

**Keep the index in sync with DB triggers** (external-content mode; transactional, unlike AR callbacks):

```ruby
execute <<~SQL
  CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO documents_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
  END;
  CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
    INSERT INTO documents_fts(documents_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
  END;
  CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
    INSERT INTO documents_fts(documents_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
    INSERT INTO documents_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
  END;
SQL
```

**Query from ActiveRecord:**

```ruby
Document.joins("JOIN documents_fts ON documents_fts.rowid = documents.id")
        .where("documents_fts MATCH ?", query)
        .order(Arel.sql("bm25(documents_fts)"))
```

**litesearch** (part of oldmoe's litestack) offers a model DSL over FTS5 (tokenizers, field weights, associated-table targets) if you want to avoid hand-writing triggers. Note it doesn't support ActionText fields.

## The sqlean Bundle

`sqlean` (nalgeon) is a "standard library" set of extensions, each usable individually or as one bundle: `crypto` (hashing/encoding for tokens), `uuid`, `fuzzy` (approximate matching), `math`, `stats`, `regexp`, `text`, `time`, `fileio`, `define`, `ipaddr`. No external dependencies; Linux/macOS/Windows builds. Ruby-friendly via `SQLean::*` modules that respond to `.to_path` for the `extensions:` config.

For UUID/ULID primary-key defaults, `sqlean.uuid`, `sqlite-ulid`, or gems like `sqlite_crypto` provide SQL functions usable as column defaults (e.g. `t.primary_key :id, :string, default: -> { "uuid7()" }`). See `docs/uuidv7-sqlite.md` for the Ruby-side UUIDv7 approach Rails uses by default.

## Modern Schema Features

What the ActiveRecord schema DSL supports natively for SQLite:

| Feature | SQLite | Rails support |
|---|---|---|
| **STRICT tables** | 3.37+ | **Not directly.** Rails' `strict: true` in `database.yml` is strict *quoting* (a connection flag disallowing double-quoted string literals), **not** STRICT-typed tables. There's no `strict:` option on `create_table` for STRICT typing — append it via raw SQL (`options: "STRICT"`). Common confusion worth calling out. |
| **Generated / virtual columns** | 3.31+ | **Yes.** `t.virtual :full_name, type: :string, as: "first \|\| ' ' \|\| last", stored: true` (stored persists; otherwise recomputed). Dumped to `schema.rb`. |
| **RETURNING** | 3.35+ | **Yes.** `insert_all`/`upsert_all` accept `returning:` (PK by default, or a column list, or `false`). |
| **JSON** | JSON1 built-in | **Yes** via the `json` column type (stored as TEXT, queryable with `json_extract`). |
| **JSONB** | 3.45+ | **No first-class helper** — no `t.jsonb` for SQLite yet; use `json`. |
| **Partial indexes** | yes | **Yes.** `add_index :table, :col, where: "condition"`. |
| **Expression indexes** | yes | **Yes.** `add_index :table, "lower(name)"`. |

## The sqlite3-ruby Gem

Maintained by sparklemotion; the 2.x line vendors and compiles the latest libsqlite3 and ships precompiled native gems. Two versions matter for the features above:

- **2.0** — the non-GVL-blocking `busy_handler_timeout=` that Rails 8.0's busy handler uses.
- **2.4.0** — extensions can be passed to the `Database.new` constructor, which Rails 8.1's `extensions:` config depends on.

## References

- [Extensions config PR #53827](https://github.com/rails/rails/pull/53827) · [Virtual tables / FTS5 schema PR #52354](https://github.com/rails/rails/pull/52354)
- [sqlite-vec](https://github.com/asg017/sqlite-vec) · [sqlean](https://github.com/nalgeon/sqlean) · [sqlpkg-ruby](https://github.com/fractaledmind/sqlpkg-ruby)
- [litestack / litesearch](https://github.com/oldmoe/litestack)
- [sqlite3-ruby releases](https://github.com/sparklemotion/sqlite3-ruby/releases)
