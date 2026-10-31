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

**Configured (preferred).** The `extensions:` array in `database.yml` loads extensions on connect. Requires the `sqlite3` gem >= 2.4.0 (which added passing extensions to the `Database.new` constructor). Each entry is a filesystem path, ERB that returns a path, or a constant/module that responds to `.to_path`:

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

**Low-level (manual).** In an initializer against the raw connection, for conditional loading:

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

It does brute-force KNN by default (no mature ANN/HNSW index), so it suits a small-to-moderate corpus.

## Full-Text Search: FTS5

FTS5 is a virtual-table module compiled into most SQLite builds, with built-in BM25 ranking and external-content mode. Prefer it over an external search engine for single-server apps.

**FTS5 rowids are integers.** `content_rowid` must name an `INTEGER PRIMARY KEY`; pointing it at a UUID string key fails with `datatype mismatch`. Nor can you fall back to the implicit rowid of a UUID-keyed table, which `VACUUM` may renumber. With UUID primary keys, index a separate integer-keyed search table rather than the source table:

```ruby
create_table :search_records do |t|   # integer key on purpose: it becomes the FTS5 rowid
  t.string :searchable_type, null: false
  t.string :searchable_id, null: false
  t.string :title
  t.text :content
  t.index [:searchable_type, :searchable_id], unique: true
end
```

**Rails has native migration support** (`create_virtual_table` / `drop_virtual_table`) and dumps the virtual table to `schema.rb`, including `content=` and `content_rowid=`, while excluding its shadow tables. Create virtual tables with `create_virtual_table`, not a multi-line `execute`: the dumper's parser doesn't match SQL that spans lines and raises.

```ruby
create_virtual_table "search_records_fts", "fts5",
  ["title", "content", "content='search_records'", "content_rowid='id'", "tokenize='porter'"]
```

**Keep the index in sync with DB triggers** on the search table (external-content mode; transactional, unlike AR callbacks). On SQLite, `execute` runs only the first statement of a multi-statement string and silently drops the rest, so create each trigger with its own `execute`:

```ruby
execute <<~SQL
  CREATE TRIGGER search_records_ai AFTER INSERT ON search_records BEGIN
    INSERT INTO search_records_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
  END
SQL
execute <<~SQL
  CREATE TRIGGER search_records_ad AFTER DELETE ON search_records BEGIN
    INSERT INTO search_records_fts(search_records_fts, rowid, title, content) VALUES ('delete', old.id, old.title, old.content);
  END
SQL
execute <<~SQL
  CREATE TRIGGER search_records_au AFTER UPDATE ON search_records BEGIN
    INSERT INTO search_records_fts(search_records_fts, rowid, title, content) VALUES ('delete', old.id, old.title, old.content);
    INSERT INTO search_records_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
  END
SQL
```

The model writes its row from `after_save_commit` with `upsert(..., unique_by: [:searchable_type, :searchable_id])` and deletes it from `after_destroy_commit`. Writing from the model also reaches ActionText bodies, which live in `action_text_rich_texts`, out of sight of triggers on the source table.

**Query from ActiveRecord:**

```ruby
SearchRecord.joins("JOIN search_records_fts ON search_records_fts.rowid = search_records.id")
            .where("search_records_fts MATCH ?", query)
            .where(account_id: Current.account.id, board_id: Current.user.board_ids)
            .order(Arel.sql("bm25(search_records_fts)"))
```

`MATCH` parses FTS5 query syntax, so quote user input as a phrase; a stray `"`
raises `ActiveRecord::StatementInvalid`. Each search row carries `account_id`
and the access-scope key so a search authorizes without a join, and the account
clears its rows in `before_destroy`.

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
| **Column length limits** | ignored | **Dumped but not enforced.** SQLite stores any length in a `t.string :x, limit: 255` column. Enforce with `validates :x, length: { maximum: 255 }` or `t.check_constraint "length(x) <= 255"`. |

## The sqlite3-ruby Gem

Maintained by sparklemotion; the 2.x line vendors and compiles the latest libsqlite3 and ships precompiled native gems. Two versions matter for the features above:

- **2.0** — the non-GVL-blocking `busy_handler_timeout=` that Rails' busy handler uses.
- **2.4.0** — extensions can be passed to the `Database.new` constructor, which the `extensions:` config depends on.

## References

- [Extensions config PR #53827](https://github.com/rails/rails/pull/53827) · [Virtual tables / FTS5 schema PR #52354](https://github.com/rails/rails/pull/52354)
- [sqlite-vec](https://github.com/asg017/sqlite-vec) · [sqlean](https://github.com/nalgeon/sqlean) · [sqlpkg-ruby](https://github.com/fractaledmind/sqlpkg-ruby)
- [litestack / litesearch](https://github.com/oldmoe/litestack)
- [sqlite3-ruby releases](https://github.com/sparklemotion/sqlite3-ruby/releases)
