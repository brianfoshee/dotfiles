# Testing

Rails-specific testing setup that isn't obvious from the guides: fixture UUIDs,
tenancy in tests, parallel runs on main, and pins for the 8.2 defaults.

Push each test as far down the pyramid as it will go. System tests are slow and
flaky, so they earn their place only when the behavior can't be observed
without a real browser — drag-and-drop, a JS-dependent flow, one critical
end-to-end journey. Mature apps stay near 1% system tests. Before adding one,
check whether a controller test reaches the behavior and whether an existing
system test already walks that workflow.

## Contents

- [Deterministic fixture UUIDs](#deterministic-fixture-uuids)
- [Multi-tenancy setup](#multi-tenancy-setup)
- [Signing in](#signing-in)
- [Parallel execution](#parallel-execution)
- [Shuffled unordered selects](#shuffled-unordered-selects)
- [Forgery protection](#forgery-protection)
- [Content-type allow-lists](#content-type-allow-lists)
- [Running the suite in bin/ci](#running-the-suite-in-binci)

## Deterministic fixture UUIDs

With UUIDv7 primary keys, fixtures need IDs that are stable across runs and
older than anything created during a test, so `.first` and `.last` behave:

```ruby
# test/test_helper.rb
module FixturesTestHelper
  extend ActiveSupport::Concern

  class_methods do
    def identify(label, column_type = :integer)
      return super(label, column_type) unless column_type.in?([:uuid, :string])
      generate_fixture_uuid(label)
    end

    private
      def generate_fixture_uuid(label)
        fixture_int = Zlib.crc32("fixtures/#{label}") % (2**30 - 1)
        base_time = Time.utc(2024, 1, 1, 0, 0, 0)
        uuid_v7_with_timestamp(base_time + (fixture_int / 1000.0), label)
      end
  end
end

ActiveSupport.on_load(:active_record_fixture_set) do
  prepend(FixturesTestHelper)
end
```

## Multi-tenancy setup

Set the account for every test, and give integration and system tests the URL
prefix the tenancy middleware expects. Rails main freezes
`default_url_options`, so merge and reassign rather than writing a key in
place, which raises `FrozenError`:

```ruby
# test/test_helper.rb
module ActiveSupport
  class TestCase
    setup { Current.account = accounts(:primary) }
    teardown { Current.clear_all }

    # Jobs must restore their own account, not borrow the test's
    def perform_enqueued_jobs(...)
      saved_account, Current.account = Current.account, nil
      super
    ensure
      Current.account = saved_account
    end
  end
end

class ActionDispatch::IntegrationTest
  setup do
    integration_session.default_url_options =
      integration_session.default_url_options.merge(script_name: "/#{accounts(:primary).slug}")
  end
end

class ActionDispatch::SystemTestCase
  setup do
    self.default_url_options = default_url_options.merge(script_name: "/#{accounts(:primary).slug}")
  end
end
```

Without the `perform_enqueued_jobs` override, the per-test `Current.account`
leaks into every job the test performs and hides a job that fails to serialize
and restore its account.

## Signing in

An integration test's `cookies` is a Rack::Test jar with no `.signed`, so sign
the value in a request cookie jar and copy it across, as Rails' authentication
generator does:

```ruby
# test/test_helpers/session_test_helper.rb
module SessionTestHelper
  def sign_in_as(user_fixture_name)
    session = users(user_fixture_name).identity.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_token] = session.signed_id
      cookies["session_token"] = cookie_jar[:session_token]
    end
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
```

## Parallel execution

Tests are assigned to workers round-robin, so the same `--seed` and worker count
run the same sequence on each worker — an order-dependent failure reproduces by
rerunning with that seed. One worker can draw most of the slow tests, though.
`work_stealing: true` lets idle workers take tests from busy ones, in
deterministic order, which smooths runtime at the cost of reproducibility. An
environment switch keeps both:

```ruby
parallelize workers: :number_of_processors, work_stealing: ENV["WORK_STEALING"] != "false"
```

Rerun a failure with `WORK_STEALING=false` and its seed to reproduce it.
System tests often need `PARALLEL_WORKERS=1` — browser instances contend.

## Shuffled unordered selects

```ruby
# config/environments/test.rb
config.active_record.shuffle_unordered_selects = true
```

Active Record shuffles the rows of every SELECT it generates without an
`ORDER BY`, surfacing code that depends on whatever order the database happens
to return. Treat a failure as an application bug, not a test bug: the order is
undefined in production too. It's best effort — raw SQL strings, `find`,
`find_by` and association loads aren't shuffled, and a `LIMIT 1` query is
unaffected.

## Forgery protection

The test environment sets `allow_forgery_protection = false`, so a test of the
CSRF strategy switches it on, and uses `https!` because a request with no
`Sec-Fetch-Site` header passes `:header_only` over plain HTTP. Assert only what
the app chose — here, that a `:header_or_legacy_token` override still accepts
a token from a client that sends no header — not Rails' own header handling:

```ruby
class ForgeryProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @allow_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    https!
    sign_in_as :member
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @allow_forgery_protection
  end

  test "accepts an authenticity token when Sec-Fetch-Site is missing" do
    get root_path
    token = css_select("meta[name=csrf-token]").first["content"]

    post cards_path, params: { card: { title: "Logo" } },
                     headers: { "X-CSRF-Token" => token }

    assert_response :redirect
  end
end
```

## Content-type allow-lists

Marcel 2 identifies new blobs with canonical types (`image/bmp`, not
`image/x-bmp`), so an allow-list that string-compares `content_type` can stop
matching without any error. Pin it with a test that identifies a sample of each
allowed extension the way an upload is identified:

```ruby
test "every allowed upload type is identified as allowed" do
  Dir[File.join(file_fixture_path, "uploads", "*")].each do |path|
    File.open(path) do |io|
      blob = ActiveStorage::Blob.build_after_unfurling(io: io, filename: File.basename(path))

      assert_includes Attachment::ALLOWED_CONTENT_TYPES, blob.content_type, path
    end
  end
end
```

## Running the suite in bin/ci

`config/ci.rb` (shown in `docs/rails-8-modern-stack.md`) runs the checks in a
`group "Checks", parallel: 2` with the tests as a sub-group. A sub-group takes
one slot and runs its steps sequentially, and unit and system tests must stay
sequential when they share the test SQLite file. `bin/rails herb:check` goes in
the checks, so a template Herb rejects fails CI rather than a page.

Don't expect the parallel group to save time on a developer laptop. Measured on
a 10-core machine, it made no net difference: the parallelized unit tests
already saturate the cores, and Brakeman competes with them. It pays off where
the checks dominate the run.
