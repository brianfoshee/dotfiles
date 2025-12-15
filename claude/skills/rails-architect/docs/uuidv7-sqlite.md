# UUIDv7 Primary Keys with SQLite

Complete guide to implementing UUIDv7 as primary keys in Rails applications using SQLite, based on production Rails 8.1 implementation.

## Overview

UUIDv7 provides time-ordered, globally unique identifiers that are superior to both auto-incrementing integers and UUIDv4 for distributed systems.

## Why UUIDv7?

**Advantages over integer IDs:**
- ✅ **Globally unique** - No coordination needed between services or databases
- ✅ **Time-ordered** - Natural sort by creation time (better index performance than UUIDv4)
- ✅ **URL-safe** - Can be used in routes without exposing sequential IDs
- ✅ **Future-proof** - Supports service extraction and data migration
- ✅ **Native Ruby 3.4+ support** - Built-in via `SecureRandom.uuid_v7`

**Advantages over UUIDv4:**
- ✅ **Sequential nature** - Less index fragmentation in database
- ✅ **Sortable** - Timestamp embedded in first 48 bits
- ✅ **Better performance** - SQLite string comparison works correctly with time ordering

**Trade-offs:**
- ⚠️ Larger index size (36 bytes vs 4-8 bytes for integers)
- ⚠️ Slightly slower joins (negligible in practice)
- ⚠️ More storage required

## Rails Configuration

### Step 1: Configure Generators

In `config/application.rb`:

```ruby
module YourApp
  class Application < Rails::Application
    # ...

    config.generators do |g|
      g.orm :active_record, primary_key_type: :string
    end
  end
end
```

This ensures all future migrations create tables with string IDs suitable for UUIDs.

### Step 2: ApplicationRecord Setup

In `app/models/application_record.rb`:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # UUID v7 validation regex
  UUID_V7_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  # Generate UUIDv7 for all models
  before_create :generate_uuid_v7

  # Validate UUID format on all string IDs and foreign keys
  validate :validate_uuid_formats

  # Cache foreign key string columns at class level for performance
  def self.foreign_key_string_columns
    @foreign_key_string_columns ||= columns.select do |c|
      c.name.end_with?("_id") && c.name != "id" && c.type == :string
    end
  end

  private

  def generate_uuid_v7
    return if self.class.column_for_attribute(:id).type != :string

    # Use 12 extra timestamp bits for ~244ns precision and deterministic ordering
    # This prevents ordering issues when UUIDs are created in rapid succession
    # See: https://docs.ruby-lang.org/en/master/Random.html#method-i-uuid_v7
    self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
  end

  def validate_uuid_formats
    # Validate primary key if it's a string
    if self.class.column_for_attribute(:id).type == :string && id.present?
      errors.add(:id, "must be a valid UUIDv7") unless id.match?(UUID_V7_REGEX)
    end

    # Validate all foreign keys (string columns ending in _id)
    self.class.foreign_key_string_columns.each do |column|
      value = send(column.name)
      if value.present? && !value.match?(UUID_V7_REGEX)
        errors.add(column.name.to_sym, "must be a valid UUIDv7")
      end
    end
  end
end
```

**Why 12 extra timestamp bits?**
- Provides ~244 nanosecond precision
- Ensures deterministic ordering even when creating records in rapid succession
- Critical for maintaining correct sort order in tests and bulk operations

### Step 3: Active Storage Configuration

Active Storage models don't inherit from ApplicationRecord, so they need explicit configuration.

Create `config/initializers/active_storage.rb`:

```ruby
# Configure Active Storage models to use UUIDv7 primary keys
# Use 12 extra timestamp bits for ~244ns precision and deterministic ordering
# This prevents ordering issues when UUIDs are created in rapid succession
# See: https://docs.ruby-lang.org/en/master/Random.html#method-i-uuid_v7

# Use to_prepare to ensure callbacks are set up every time classes are reloaded
# This fixes race conditions where after_initialize might run too late
Rails.application.config.to_prepare do
  ActiveStorage::Blob.before_validation do
    self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
  end

  ActiveStorage::Attachment.before_validation do
    self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
  end

  ActiveStorage::VariantRecord.before_validation do
    self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
  end
end
```

**Why `to_prepare` instead of `after_initialize`:**
- ✅ Runs on every code reload in development
- ✅ Fixes race conditions where callbacks might not be set up in time
- ✅ More reliable for initializers that modify framework classes

**Why `before_validation` instead of `before_create`:**
- ✅ ID is set earlier in the lifecycle
- ✅ Allows validations to run on the ID if needed
- ✅ More consistent with ApplicationRecord's `before_create` pattern

### Step 4: Action Text Configuration (If Using Action Text)

If your application uses Action Text for rich text content, configure it similarly.

Add to `config/initializers/active_storage.rb` (or create a separate `action_text.rb` initializer):

```ruby
# Configure Action Text models to use UUIDv7 primary keys
Rails.application.config.to_prepare do
  ActionText::Record.before_create do
    self.id ||= SecureRandom.uuid_v7(extra_timestamp_bits: 12)
  end
end
```

**What is ActionText::Record:**
- Base class for Action Text's RichText model
- Stores rich text content in separate table
- Like Active Storage, doesn't inherit from ApplicationRecord
- Requires explicit UUID configuration

**When you need this:**
- ✅ Using `has_rich_text :content` in your models
- ✅ Action Text migrations have been run
- ✅ You want UUIDs for rich text records

**When you don't need this:**
- ❌ Not using Action Text in your application
- ❌ Using Trix editor without Action Text backend

## Database Migrations

### Creating New Tables

```ruby
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :string do |t|
      t.string :name
      t.string :email
      t.timestamps
    end
  end
end
```

### Foreign Keys

Always specify `type: :string` for foreign key references:

```ruby
class CreatePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :posts, id: :string do |t|
      t.string :title
      t.references :user, type: :string, foreign_key: true, null: false
      t.timestamps
    end
  end
end

# Alternative explicit syntax
class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments, id: :string do |t|
      t.text :body
      t.string :post_id, null: false
      t.string :user_id, null: false
      t.timestamps
    end

    add_foreign_key :comments, :posts
    add_foreign_key :comments, :users
    add_index :comments, :post_id
    add_index :comments, :user_id
  end
end
```

### Join Tables (Many-to-Many)

For join tables, use `id: false` since the composite foreign keys serve as the natural primary key:

```ruby
class CreateCompaniesJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :companies_jobs, id: false do |t|
      t.string :company_id, null: false
      t.string :job_id, null: false
      t.timestamps
    end

    # Composite unique index (serves as primary key)
    add_index :companies_jobs, [:company_id, :job_id], unique: true

    # Individual indexes for reverse lookups
    add_index :companies_jobs, :company_id
    add_index :companies_jobs, :job_id

    # Foreign key constraints
    add_foreign_key :companies_jobs, :companies
    add_foreign_key :companies_jobs, :jobs
  end
end
```

**Why `id: false` for join tables:**
- ✅ Join tables don't need their own UUID primary key
- ✅ Composite index on foreign keys serves as natural key
- ✅ Saves storage space (no extra 36-byte UUID column)
- ✅ Clearer intent - this is purely a relationship table
- ✅ Faster lookups - composite index is all you need

**When to use `id: false`:**
- Pure join tables with only foreign keys and timestamps
- Tables that exist solely to represent many-to-many relationships
- No additional business logic or attributes on the relationship

**When to keep `id: :string`:**
- Join tables with additional attributes (e.g., `role`, `permissions`, `joined_at` with meaning)
- Tables that might evolve to have business logic
- Tables you want to reference from other tables

### Active Storage Migration

The Active Storage migration automatically detects the configured primary key type:

```ruby
class CreateActiveStorageTables < ActiveRecord::Migration[8.0]
  def change
    # Use Active Record's configured type for primary and foreign keys
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_table :active_storage_blobs, id: primary_key_type do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum

      t.datetime :created_at, null: false

      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments, id: primary_key_type do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false, type: foreign_key_type
      t.references :blob,     null: false, type: foreign_key_type

      t.datetime :created_at, null: false

      t.index [ :record_type, :record_id, :name, :blob_id ], name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records, id: primary_key_type do |t|
      t.belongs_to :blob, null: false, index: false, type: foreign_key_type
      t.string :variation_digest, null: false

      t.index [ :blob_id, :variation_digest ], name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end

  private
    def primary_and_foreign_key_types
      config = Rails.configuration.generators
      setting = config.options[config.orm][:primary_key_type]
      primary_key_type = setting || :primary_key
      foreign_key_type = setting || :bigint
      [primary_key_type, foreign_key_type]
    end
end
```

## Test Configuration

### Fixture ID Generation

Test fixtures need deterministic UUIDv7s. In `test/test_helper.rb`:

```ruby
require "digest"
require "time"

# Configure ActiveRecord to use UUIDs for fixture primary keys
ActiveRecord::FixtureSet.reset_cache

# Override fixture ID generation to use UUIDs instead of integers
class ActiveRecord::FixtureSet
  class << self
    alias_method :original_identify, :identify if !method_defined?(:original_identify)

    def identify(label, column_type = nil)
      # Generate a deterministic UUIDv7 that maintains time-ordering
      # UUIDv7 format: timestamp (48 bits) + version (4 bits) + random (12 bits) +
      #                variant (2 bits) + random (62 bits)

      # Use a hash of the label to get a deterministic but unique value
      hash = Digest::SHA256.hexdigest(label.to_s)

      # Create a base timestamp (using a fixed point in time for fixtures)
      # Using 2024-01-01 00:00:00 UTC as base, then add deterministic offset
      base_timestamp = Time.parse("2024-01-01 00:00:00 UTC").to_i * 1000

      # Add a deterministic offset based on the first 4 bytes of the hash
      # (ensures unique timestamps)
      offset = hash[0..7].to_i(16) % 1_000_000  # Up to ~1 second of offset
      timestamp_ms = base_timestamp + offset

      # Convert timestamp to hex (48 bits = 12 hex chars)
      timestamp_hex = timestamp_ms.to_s(16).rjust(12, "0")

      # Build UUIDv7:
      # - First 8 chars: first 32 bits of timestamp
      # - Next 4 chars: last 16 bits of timestamp
      # - Next 4 chars: version (7) + random bits from hash
      # - Next 4 chars: variant (10) + random bits from hash
      # - Last 12 chars: random bits from hash

      uuid = [
        timestamp_hex[0..7],                    # timestamp high 32 bits
        timestamp_hex[8..11],                    # timestamp low 16 bits
        "7#{hash[12..14]}",                      # version 7 + random
        "#{(0x8 | hash[15].to_i(16) & 0x3).to_s(16)}#{hash[16..18]}", # variant 10 + random
        hash[19..30]                             # random
      ].join("-")

      uuid
    end
  end
end
```

**Why this approach:**
- ✅ Generates valid UUIDv7s for all fixtures
- ✅ IDs are deterministic (same label always generates same UUID)
- ✅ Fixtures sort before newly created records (base timestamp in past)
- ✅ Time-ordering is preserved
- ✅ No ID collisions between fixtures and test-created records

### Test Assertions

When testing redirects after creating records, use the actual created record:

```ruby
# ✅ GOOD - uses the actual created record
test "should create user" do
  assert_difference("User.count") do
    post users_url, params: { user: { name: "Test" } }
  end
  assert_redirected_to user_url(User.last)
end

# ❌ BAD - assumes fixture ID
test "should create user" do
  assert_difference("User.count") do
    post users_url, params: { user: { name: "Test" } }
  end
  assert_redirected_to user_url(users(:some_fixture))
end
```

## Migration from Integer IDs

### Fresh Start (Recommended)

If starting a new project or can afford to recreate the database:

```bash
# 1. Backup the schema
cp db/schema.rb db/schema_integer_backup.rb

# 2. Drop and recreate
bin/rails db:drop db:create

# 3. Archive old migrations (optional)
mkdir db/migrate_integer_backup
mv db/migrate/*.rb db/migrate_integer_backup/

# 4. Generate new migrations with UUID support
bin/rails generate model User name:string email:string

# 5. Run migrations
bin/rails db:migrate db:seed

# 6. Update tests
bin/rails db:test:prepare
bin/rails test:all
```

### In-Place Migration (Complex)

For existing databases with data:

```ruby
# This is complex and risky - backup first!
class MigrateToUuids < ActiveRecord::Migration[8.0]
  def up
    # 1. Add new UUID columns
    add_column :users, :uuid, :string

    # 2. Generate UUIDs for existing records
    User.find_each do |user|
      user.update_column(:uuid, SecureRandom.uuid_v7(extra_timestamp_bits: 12))
    end

    # 3. Update foreign keys (complex - requires temp columns and data migration)
    # ... this gets very complicated for many tables

    # 4. Swap columns
    # ... even more complex

    # Recommendation: Consider this a full data migration project
  end
end
```

**Recommendation:** For existing applications, migrating to UUIDs is a major undertaking. Consider it only if you're planning a significant refactor or have a strong business need.

## Database-Specific Notes

### SQLite (Recommended for Single-Server Apps)

- Stores UUIDs as TEXT (36 characters)
- String comparison for ordering works correctly with UUIDv7
- No native UUID type, but this doesn't affect functionality
- Excellent for Rails 8+ apps using Solid Queue/Cache/Cable
- Production-ready with Rails 8 optimizations

## Performance Considerations

### Index Size
- UUID indexes are larger (36 bytes vs 4-8 bytes)
- For most applications, the difference is negligible
- UUIDv7's sequential nature minimizes fragmentation

### Join Performance
- Slightly slower than integer joins
- In practice, difference is not noticeable
- Benefits of UUIDs outweigh costs for distributed systems

### Storage
- ~30 extra bytes per record vs integers
- For most tables, this is acceptable overhead
- Consider if you have tables with hundreds of millions of rows

## Best Practices

### 1. Always Use UUIDv7, Not UUIDv4

```ruby
# ✅ GOOD - time-ordered
SecureRandom.uuid_v7(extra_timestamp_bits: 12)

# ❌ BAD - random, causes index fragmentation
SecureRandom.uuid
```

### 2. Use Lowercase Format

```ruby
# Rails generates lowercase by default
# Validation enforces lowercase
# Database stores lowercase
# Always use lowercase for consistency and performance
```

### 3. Set IDs Explicitly When Needed

```ruby
# Seeds or data imports
user = User.new(
  id: SecureRandom.uuid_v7(extra_timestamp_bits: 12),
  name: "Admin",
  email: "admin@example.com"
)
user.save!
```

### 4. Index Foreign Keys

```ruby
create_table :posts, id: :string do |t|
  t.references :user, type: :string, foreign_key: true, index: true
end
```

### 5. Consider Composite Indexes

```ruby
# If querying by UUID + another field frequently
add_index :posts, [:user_id, :created_at]
```

## Validation

UUIDv7 format is validated automatically via ApplicationRecord:

```ruby
class ApplicationRecord < ActiveRecord::Base
  UUID_V7_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  validate :validate_uuid_formats

  private

  def validate_uuid_formats
    # Validates primary key if string
    # Validates all foreign keys (columns ending in _id)
    # Only validates when values are present (allows nil for optional associations)
  end
end
```

The validation ensures:
- ✅ Primary keys follow UUIDv7 format (lowercase only)
- ✅ Foreign keys follow UUIDv7 format or are NULL
- ✅ Invalid UUIDs caught before database insertion
- ✅ Clear error messages provided
- ✅ Automatic for all models

## Troubleshooting

### Fixture IDs Not Working

```ruby
# Ensure test_helper.rb has the fixture override
ActiveRecord::FixtureSet.reset_cache

# After changes, reset cache
bin/rails db:test:prepare
```

### Foreign Key Constraints Failing

```ruby
# Check that foreign key columns are type: :string
t.references :user, type: :string, foreign_key: true

# Ensure both tables use string IDs
```

### Ordering Issues

```ruby
# ✅ UUIDv7s naturally sort by creation time
Post.order(:id)  # Chronological order

# For other ordering, be explicit
Post.order(:created_at)
```

### Active Storage Not Using UUIDs

```ruby
# Ensure initializer is present and loaded
# Check that Active Storage tables have string IDs in schema.rb
# Re-run migrations if needed
```

## UUIDv7 Format Reference

```
UUIDv7: xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx

Where:
- x = timestamp or random bits
- 7 = version (always 7 for UUIDv7)
- y = variant (8, 9, a, or b)

Structure:
- Bytes 0-5:   48-bit timestamp (milliseconds since Unix epoch)
- Bytes 6-7:   4-bit version (0111) + 12-bit random or extra timestamp bits
- Bytes 8-9:   2-bit variant (10) + 14-bit random bits
- Bytes 10-15: 48-bit random bits

With extra_timestamp_bits: 12:
- Total timestamp precision: 60 bits (~244 nanosecond precision)
- Remaining random bits: 62 bits (sufficient for uniqueness)
```

## Benefits Summary

- ✅ No ID conflicts in distributed systems
- ✅ Time-ordered for efficient indexing
- ✅ Globally unique without coordination
- ✅ URL-safe when used in routes
- ✅ Future-proof for scaling and service extraction
- ✅ Native Ruby 3.4+ support
- ✅ Works excellently with SQLite in Rails 8+

## References

- [Ruby SecureRandom.uuid_v7 Documentation](https://docs.ruby-lang.org/en/master/Random.html#method-i-uuid_v7)
- [RFC 9562 - UUIDv7 Specification](https://www.rfc-editor.org/rfc/rfc9562.html)
- [Rails Generators Configuration](https://guides.rubyonrails.org/configuring.html#configuring-generators)
