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
tests. Production 37signals apps run about five for an entire product.

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

Set the account for every test, and give integration tests the URL prefix that
the tenancy middleware expects:

```ruby
# test/test_helper.rb
module ActiveSupport
  class TestCase
    setup { Current.account = accounts(:primary) }
    teardown { Current.clear_all }
  end
end

class ActionDispatch::IntegrationTest
  setup do
    integration_session.default_url_options[:script_name] = "/#{accounts(:primary).slug}"
  end
end
```

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
  parallelize workers: :number_of_processors,
              work_stealing: ENV["WORK_STEALING"] != "false"
end
```

System tests often need `PARALLEL_WORKERS=1` — browser instances contend.

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

Group helpers by domain rather than piling them into `test_helper.rb`:

```ruby
# test/test_helpers/session_test_helper.rb
module SessionTestHelper
  def sign_in_as(user_fixture_name)
    user = users(user_fixture_name)
    session = user.identity.sessions.create!
    cookies.signed[:session_token] = session.signed_id
  end
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
