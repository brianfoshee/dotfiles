# Testing Pyramid for Rails Applications

How to distribute tests across levels, and the Rails-specific testing patterns
that aren't obvious from the guides.

## Contents

- [Distribution](#distribution)
- [Choosing a level](#choosing-a-level)
- [Fixtures over factories](#fixtures-over-factories)
- [Deterministic fixture UUIDs](#deterministic-fixture-uuids)
- [Multi-tenancy setup](#multi-tenancy-setup)
- [JSON and store columns](#json-and-store-columns)
- [Turbo Stream responses](#turbo-stream-responses)
- [State transitions and side effects](#state-transitions-and-side-effects)
- [Background jobs](#background-jobs)
- [Parallel execution](#parallel-execution)
- [Shuffled unordered selects](#shuffled-unordered-selects)
- [Forgery protection](#forgery-protection)
- [Content-type allow-lists](#content-type-allow-lists)
- [Running the suite in bin/ci](#running-the-suite-in-binci)
- [External HTTP with VCR](#external-http-with-vcr)
- [Test helper modules](#test-helper-modules)
- [Anti-patterns](#anti-patterns)

## Distribution

A healthy suite is bottom-heavy:

| Level             | Share  | Covers                              |
|-------------------|--------|-------------------------------------|
| Model / service   | 60–70% | Business logic, validations, scopes |
| Controller        | 25–35% | HTTP, routing, authorization, CRUD  |
| Integration       | 5–10%  | Multi-request workflows             |
| Unit              | 2–5%   | Isolated calculations, helpers      |
| System            | <1%    | Critical journeys needing a browser |

For scale: a 760-test application under this distribution has three system
tests. Mature production apps stay near 1%, each system test pinning a
regression only a browser can reproduce.

## Choosing a level

Push each test as far down the pyramid as it will go. System tests are slow,
flaky, and hard to debug, so they earn their place only when the behavior can't
be observed without a real browser — drag-and-drop, a JS-dependent flow, a
genuinely critical end-to-end journey. CRUD, field visibility, calculations, API
endpoints, and validations all belong lower down.

Before adding a system test, check whether a controller or integration test
reaches the same behavior, and whether an existing system test already walks
through that workflow. Expand an existing test file rather than starting a new
one for the same subject.

## Fixtures over factories

Fixtures load once per suite rather than building objects per test, which is
most of the speed difference between a fast Rails suite and a slow one.

```yaml
# test/fixtures/users.yml
admin:
  name: Admin User
  email: admin@example.com
  company: acme
```

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
prefix that the tenancy middleware expects. Rails main freezes
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

## JSON and store columns

Mutating a JSON hash in place doesn't mark the attribute dirty, so the write is
silently dropped. Replace the value instead:

```ruby
# Lost on save — no change detected
result.results["water_pressure"] = 50
result.save!

# Persisted
updated = result.results.deep_dup
updated["water_pressure"] = 50
result.update!(results: updated)
```

## Turbo Stream responses

Controller actions generally answer both Turbo Stream and JSON; test both:

```ruby
test "create as turbo_stream" do
  card = cards(:logo)

  assert_changes -> { card.reload.closed? }, from: false, to: true do
    post card_closure_path(card), as: :turbo_stream
    assert_turbo_stream action: "replace", target: dom_id(card, :container)
  end
end

test "create as JSON" do
  post card_closure_path(cards(:logo)), as: :json
  assert_response :no_content
end
```

## State transitions and side effects

`assert_changes` states the transition being tested, which reads better than a
before-assert / after-assert pair:

```ruby
assert_changes -> { card.reload.closed? }, from: false, to: true do
  card.close
end
```

Domain methods usually have side effects worth asserting on separately — the
event, the notification, the counter:

```ruby
test "closing card creates event" do
  card = cards(:open)

  assert_difference("Event.count") do
    card.close(user: users(:one))
  end

  assert_equal "closed", card.events.last.action
end
```

## Background jobs

Assert on enqueuing; reach for `perform_enqueued_jobs` only when the job's own
logic is what's under test.

```ruby
assert_enqueued_with job: NotificationJob, args: [card] do
  card.close
end
```

## Parallel execution

```ruby
class ActiveSupport::TestCase
  parallelize workers: :number_of_processors
end
```

Tests are assigned to workers round-robin, so the same `--seed` and worker count
run the same sequence on each worker — an order-dependent failure reproduces by
rerunning with that seed. One worker can draw most of the slow tests, though.
`work_stealing: true` lets idle workers take tests from busy ones, in
deterministic order, which smooths runtime at the cost of reproducibility; turn
it on when runtime matters more than chasing a flaky test. An environment
switch keeps both:

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
`ORDER BY`, surfacing code and tests that depend on whatever order the database
happens to return. Treat a failure as an application bug, not a test bug: the
order is undefined in production too; in one app it found a report section
whose order had never been specified. It's best effort — raw SQL strings, `find`,
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

## External HTTP with VCR

```ruby
VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data("<API_KEY>") { ENV["API_KEY"] }

  # Timestamps in request bodies otherwise break cassette matching
  config.before_record do |i|
    i.request.body&.gsub!(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/, "<TIME>")
  end
end
```

## Test helper modules

Group helpers by domain rather than piling them into `test_helper.rb`, and
mirror the code's layout in the tests: `Card::Closeable` is tested in
`test/models/card/closeable_test.rb`.

An integration test's `cookies` is a Rack::Test jar with no `.signed`, so sign
the value in a request cookie jar and copy it across, as Rails' authentication
generator does. Signing in through the real endpoints instead also exercises
the sign-in flow, at the cost of a few requests per test:

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

## Anti-patterns

**Testing the mock.** A test that only asserts a mock received a message
verifies nothing about the system:

```ruby
# Asserts on the mock, not the behavior
card = mock
card.expects(:update).with(closed: true)
card.close

# Asserts on the result
card = cards(:open)
card.close
assert card.reload.closed?
assert card.events.closed.exists?
```

**System-testing CRUD.** A form submission that a controller test covers in
milliseconds doesn't need a browser.

## References

- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)
- [Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html)
