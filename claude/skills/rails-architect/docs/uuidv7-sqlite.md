# UUIDv7 Primary Keys with SQLite

UUIDv7 embeds a millisecond timestamp in its first 48 bits, so ids stay globally
unique without coordination while still sorting by creation time — avoiding the
index fragmentation that makes UUIDv4 a poor primary key. Ruby 3.4 ships
`SecureRandom.uuid_v7`. SQLite stores them as 36-character TEXT, and string
comparison gives correct chronological ordering.

The cost is ~30 bytes per row versus an integer, on both the table and every
index. Only worth weighing on tables with hundreds of millions of rows.

## Contents

- [Configuration](#configuration)
- [Active Storage and Action Text](#active-storage-and-action-text)
- [Migrations](#migrations)
- [Fixtures](#fixtures)
- [Adopting UUIDs in an existing app](#adopting-uuids-in-an-existing-app)
- [Format reference](#format-reference)
- [References](#references)

## Configuration

```ruby
# config/application.rb
config.generators do |g|
  g.orm :active_record, primary_key_type: :string
end
```

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  UUID_V7_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  before_create :generate_uuid_v7
  validate :validate_uuid_formats

  def self.foreign_key_string_columns
    @foreign_key_string_columns ||= columns.select do |c|
      c.name.end_with?("_id") && c.name != "id" && c.type == :string
    end
  end

  private
    def generate_uuid_v7
      return if self.class.column_for_attribute(:id).type != :string

      self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
    end

    def validate_uuid_formats
      if self.class.column_for_attribute(:id).type == :string && id.present?
        errors.add(:id, "must be a valid UUIDv7") unless id.match?(UUID_V7_REGEX)
      end

      self.class.foreign_key_string_columns.each do |column|
        value = send(column.name)
        if value.present? && !value.match?(UUID_V7_REGEX)
          errors.add(column.name.to_sym, "must be a valid UUIDv7")
        end
      end
    end
end
```

`extra_timestamp_bits: 12` spends 12 of the random bits on finer time
resolution, taking precision from a millisecond to roughly 244ns. Without it,
records created inside the same millisecond — bulk inserts, seeds, a fast test —
order randomly among themselves. 62 random bits remain, which is ample.

The foreign-key column list is memoized per class because it's derived from
`columns`, and recomputing it on every validation is measurable in bulk writes.

## Active Storage and Action Text

Neither inherits from `ApplicationRecord`, so both need ids wired up
separately. Use `to_prepare` rather than an `after_initialize` hook or a bare
initializer body: it re-runs on every code reload, so the callbacks survive
development reloading instead of being silently dropped.

```ruby
# config/initializers/active_storage.rb
Rails.application.config.to_prepare do
  [ActiveStorage::Blob, ActiveStorage::Attachment, ActiveStorage::VariantRecord].each do |model|
    model.before_validation { self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12) }
  end

  # Only needed with has_rich_text
  ActionText::Record.before_create { self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12) }
end
```

`before_validation` sets the id early enough that validations can inspect it.

## Migrations

```ruby
create_table :posts, id: :string do |t|
  t.string :title
  t.references :user, type: :string, foreign_key: true, null: false
  t.timestamps
end
```

`type: :string` on every reference is the easy thing to forget; without it Rails
creates a bigint column and the foreign key silently never matches.

Pure join tables take `id: false` — the composite index is the natural key, and
a UUID column would be 36 bytes of nothing:

```ruby
create_table :companies_jobs, id: false do |t|
  t.string :company_id, null: false
  t.string :job_id, null: false
  t.timestamps
end

add_index :companies_jobs, [:company_id, :job_id], unique: true
add_index :companies_jobs, :job_id     # reverse lookups
add_foreign_key :companies_jobs, :companies
add_foreign_key :companies_jobs, :jobs
```

Keep `id: :string` when the join table carries its own attributes, might grow
business logic, or needs to be referenced from elsewhere.

The generated Active Storage migration picks the type up from the generator
config, so it needs no editing:

```ruby
def primary_and_foreign_key_types
  config = Rails.configuration.generators
  setting = config.options[config.orm][:primary_key_type]
  [setting || :primary_key, setting || :bigint]
end
```

## Fixtures

Fixtures need deterministic UUIDv7s that sort before anything a test creates.
`docs/testing-pyramid.md` has the implementation — it prepends onto
`ActiveRecord::FixtureSet` via the `active_record_fixture_set` load hook and
derives the id from a hash of the fixture label with a fixed base timestamp.

One consequence worth knowing: with random-looking ids, a test can't assume
which record it just made. Assert against the record, not a fixture:

```ruby
assert_redirected_to user_url(User.last)
```

## Adopting UUIDs in an existing app

On a new project, or one whose database can be recreated, switch the generator
config and rebuild: `bin/rails db:drop db:create db:migrate db:seed`, then
`db:test:prepare`.

Converting a populated database is a data-migration project, not a migration
file. Every table needs a parallel UUID column, every foreign key has to be
rewritten to match, and the swap has to happen atomically across all of them.
Worth doing only alongside a refactor that already justifies the risk.

## Format reference

```
xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx
                ^    ^
                |    variant (8, 9, a, or b)
                version, always 7

bytes 0-5    48-bit millisecond timestamp
bytes 6-7    4-bit version + 12 bits random (or extra timestamp precision)
bytes 8-9    2-bit variant + 14 bits random
bytes 10-15  48 bits random
```

## References

- [SecureRandom.uuid_v7](https://docs.ruby-lang.org/en/master/Random.html#method-i-uuid_v7)
- [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html)
- [Configuring generators](https://guides.rubyonrails.org/configuring.html#configuring-generators)
