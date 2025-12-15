# Testing Pyramid for Rails Applications

Production-proven testing strategy that prioritizes fast, reliable tests at appropriate levels, based on real Rails 8.1 application with 760+ tests.

## The Testing Pyramid

```
         /\
        / 3 \    System Tests (browser automation) - RARELY ADD
       /-----\
      /  49  \   Integration Tests (HTTP requests) - PREFER FOR WORKFLOWS
     /--------\
    /   19    \  Unit Tests (direct objects) - PREFER FOR LOGIC
   /-----------\
  /    231     \ Controller Tests (HTTP + routing)
 /--------------\
/      460      \ Model/Service Tests (business logic)
```

**CRITICAL PRINCIPLE:** Always prefer writing unit or integration tests over system tests. System tests are expensive (slow, brittle, resource-intensive) and MUST only test critical user workflows.

## When to Write Each Test Type

### Model/Service Tests (test/models/, test/services/)
**460 tests - The foundation of your test suite**

**Use for:**
- Business logic in models
- Validations and callbacks
- Association behavior
- Service object logic
- Calculations and data transformations
- Scopes and class methods

**Inherit from:** `ActiveSupport::TestCase`

**Example:**
```ruby
# test/models/user_test.rb
class UserTest < ActiveSupport::TestCase
  test "user can have multiple roles" do
    user = users(:one)
    user.grant_role("technician")
    user.grant_role("reviewer")

    assert user.technician?
    assert user.reviewer?
    assert_equal 2, user.roles.count
  end

  test "admin role implies other permissions" do
    user = users(:one)
    user.grant_role("admin")

    assert user.admin?
    assert user.reviewer?
    assert user.technician?
  end

  test "validates uuid format on foreign keys" do
    user = User.new(
      name: "Test",
      email: "test@example.com",
      company_id: "not-a-uuid"
    )

    assert_not user.valid?
    assert_includes user.errors[:company_id], "must be a valid UUIDv7"
  end
end
```

**Why this level:**
- ✅ Fast execution (milliseconds per test)
- ✅ No HTTP overhead
- ✅ No browser overhead
- ✅ Easy to debug
- ✅ Test business logic in isolation

### Controller Tests (test/controllers/)
**231 tests - Testing HTTP interactions**

**Use for:**
- CRUD operations (index, new, create, show, edit, update, destroy)
- Parameter handling and validation
- Authentication/authorization checks
- Proper redirects and flash messages
- Response codes and formats

**Inherit from:** `ActionDispatch::IntegrationTest`

**Example:**
```ruby
# test/controllers/jobs_controller_test.rb
class JobsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get jobs_url
    assert_response :success
  end

  test "should create job" do
    assert_difference("Job.count") do
      post jobs_url, params: {
        job: {
          job_number: "S2024",
          company_id: companies(:one).id
        }
      }
    end

    assert_redirected_to job_url(Job.last)
  end

  test "should require authentication" do
    delete logout_url  # Ensure logged out
    get jobs_url
    assert_redirected_to login_url
  end

  test "technician can create jobs" do
    user = users(:technician)
    user.grant_role("technician")
    login_as(user)

    get new_job_url
    assert_response :success
  end

  test "viewer cannot create jobs" do
    user = users(:viewer)
    user.grant_role("viewer")
    login_as(user)

    get new_job_url
    assert_redirected_to root_path
    assert_equal "You don't have permission to do that.", flash[:alert]
  end
end
```

**Why this level:**
- ✅ Fast execution (tens of milliseconds per test)
- ✅ Tests routing and parameter handling
- ✅ Tests authentication and authorization
- ✅ No browser overhead
- ✅ Comprehensive coverage of controller actions

### Unit Tests (test/unit/)
**19 tests - Testing business logic in isolation**

**Use for:**
- Complex calculations
- Data structure manipulation
- Helper methods
- Service object logic
- Algorithms
- Field visibility and conditional logic

**Inherit from:** `ActiveSupport::TestCase`

**Example:**
```ruby
# test/unit/result_calculator_test.rb
class ResultCalculatorTest < ActiveSupport::TestCase
  test "calculates specimen flow from total flow minus extraneous flow" do
    result = results(:one)
    result.update!(results: {
      "total_flow" => 100,
      "extraneous_flow" => 10
    })

    ResultCalculator.new(result).calculate
    result.reload

    assert_equal 90, result.results["specimen_flow"]
  end

  test "converts units correctly" do
    calculator = UnitConverter.new
    assert_equal 25.4, calculator.inches_to_mm(1)
    assert_equal 1.0, calculator.mm_to_inches(25.4)
  end

  test "determines field visibility based on standard" do
    standard = standards(:aama_501)
    assert FieldVisibility.visible?(:water_pressure, standard: standard)
    assert_not FieldVisibility.visible?(:air_pressure, standard: standard)
  end
end
```

**Why this level:**
- ✅ Fastest execution (microseconds to milliseconds)
- ✅ Tests logic in complete isolation
- ✅ No dependencies on database or HTTP
- ✅ Perfect for TDD
- ✅ Easy to debug

### Integration Tests (test/integration/)
**49 tests - Testing multi-step workflows**

**Use for:**
- Multi-step form submissions
- Complex workflows spanning multiple requests
- Search functionality
- Data import workflows
- Session management across requests
- Standards-specific field visibility (via HTTP)

**Inherit from:** `ActionDispatch::IntegrationTest`

**Example:**
```ruby
# test/integration/standards_assignment_test.rb
class StandardsAssignmentTest < ActionDispatch::IntegrationTest
  test "can assign standard to specimen and see appropriate fields" do
    extension = extensions(:one)
    specimen = specimens(:one)
    standard = standards(:aama_501)

    # Step 1: Assign standard
    post extension_specimen_standards_path(extension, specimen), params: {
      standard_id: standard.id
    }

    assert_response :redirect
    assert_includes specimen.reload.standards, standard

    # Step 2: Visit result form and verify fields are visible
    get new_extension_specimen_result_path(extension, specimen)
    assert_response :success
    assert_select "input[name='result[water_pressure]']"
  end
end

# test/integration/webauthn_flow_test.rb
class WebauthnFlowTest < ActionDispatch::IntegrationTest
  test "complete passkey registration flow" do
    user = users(:one)

    # Step 1: Get magic link token
    token = user.generate_magic_link_token

    # Step 2: Visit magic link (auto-login)
    get magic_link_path(token)
    assert_redirected_to new_credential_path
    follow_redirect!

    # Step 3: Begin registration
    post webauthn_registration_begin_path,
         params: { user_id: user.id },
         as: :json

    assert_response :success
    assert session[:webauthn_challenge].present?

    # Step 4: Complete registration (would normally happen via JavaScript)
    # ... mock WebAuthn credential ...
  end
end
```

**Why this level:**
- ✅ Medium speed (hundreds of milliseconds per test)
- ✅ Tests multi-request workflows
- ✅ Tests state management across requests
- ✅ No browser overhead
- ✅ Can test complex user journeys

### System Tests (test/system/)
**3 tests - Testing complete user journeys with browser**

**⚠️ CRITICAL: System tests are expensive and MUST be RARELY added.**

**When to write system tests:**
- ✅ Testing a complete critical user journey end-to-end
- ✅ Testing JavaScript interactions that can't be tested at lower levels
- ✅ Testing cross-browser compatibility for critical workflows
- ✅ Testing complex multi-page workflows with browser state

**When NOT to write system tests:**
- ❌ Testing CRUD operations (use controller tests)
- ❌ Testing individual features (use integration/unit tests)
- ❌ Testing form field visibility (use integration tests)
- ❌ Testing calculations (use unit tests)
- ❌ Testing API endpoints (use integration tests)
- ❌ Testing model validations (use model tests)
- ❌ Testing helper methods (use unit tests)

**Current system tests** (DO NOT ADD MORE unless absolutely necessary):
1. `authentication_test.rb` - Login/logout workflow
2. `core_workflow_test.rb` - Complete user journey: Job creation → Extension management
3. `passkey_authentication_test.rb` - Passkey registration with virtual authenticator

**Example:**
```ruby
# test/system/core_workflow_test.rb
class CoreWorkflowTest < ApplicationSystemTestCase
  test "complete job creation and extension workflow" do
    visit login_path

    # Login
    fill_in "Email", with: users(:one).email
    click_button "Sign in with passkey"
    # ... passkey authentication via virtual authenticator ...

    # Create job
    click_link "New Job"
    fill_in "Job number", with: "S2024"
    select companies(:one).name, from: "Company"
    click_button "Create Job"

    assert_text "Job was successfully created"

    # Navigate to extension
    click_link "Extension 1"
    assert_text "Extension 1 of S2024"

    # Add specimen
    click_link "Add Specimen"
    fill_in "Specimen identifier", with: "Window-1"
    click_button "Create Specimen"

    assert_text "Specimen was successfully created"
  end
end
```

**Before adding a system test, ask:**
1. Can this be tested with a controller test?
2. Can this be tested with an integration test?
3. Can this be tested with a unit test?
4. Does an existing system test already cover this workflow?

**Only proceed if:**
- It tests a NEW critical user workflow not covered
- The workflow requires actual browser automation
- You have approval to add an expensive test

**Why system tests are expensive:**
- ❌ Slow (seconds per test)
- ❌ Brittle (can break due to timing issues)
- ❌ Resource-intensive (requires full browser stack)
- ❌ Hard to debug
- ❌ Flaky (timing-dependent)

## Test Maintenance Guidelines

### 1. Check Before Adding Tests

Before adding ANY test, check if it already exists:

```bash
# Search controller tests
grep -r "test.*your_feature" test/controllers/

# Search model tests
grep -r "test.*your_feature" test/models/

# Check integration tests
ls test/integration/
```

### 2. Prefer Expanding Existing Test Files

Don't create `job_creation_test.rb` if `jobs_controller_test.rb` already exists.

### 3. Keep System Tests Minimal

Current count: 2 files with 3 tests covering core workflows.

**Rule:** For every new system test proposal, you must justify why it can't be tested at a lower level.

### 4. Run Tests at Appropriate Level

```bash
# Fast - Unit tests
bin/rails test test/unit/my_test.rb

# Medium - Integration tests
bin/rails test test/integration/my_test.rb

# Slow - System tests
bin/rails test test/system/my_test.rb

# All tests except system
bin/rails test

# All tests including system
bin/rails test:all
```

### 5. All Tests Must Pass Before Committing

```bash
bin/rails test:all
```

Or use Rails 8.1+ local CI:

```bash
bin/ci
```

## Testing JSON Fields (ActiveRecord Store)

When testing models with JSON fields (like `Result#setup` and `Result#results`):

**IMPORTANT:** Direct hash modification doesn't trigger ActiveRecord change detection.

```ruby
# ❌ WRONG - Changes won't persist
result.results["field"] = "value"
result.save!

# ✅ CORRECT - Use update! with deep_dup
updated_results = result.results.deep_dup
updated_results["field"] = "value"
result.update!(results: updated_results)
```

**Example:**
```ruby
test "updates JSON field correctly" do
  result = results(:one)

  # Get a deep copy
  updated_results = result.results.deep_dup
  updated_results["water_pressure"] = 50

  # Update via update! method
  result.update!(results: updated_results)
  result.reload

  assert_equal 50, result.results["water_pressure"]
end
```

## Advanced Testing Patterns from Production Rails Apps

### Multi-Tenancy Test Setup

When testing multi-tenant applications, set the current account in test setup:

```ruby
# test/test_helper.rb
module ActiveSupport
  class TestCase
    setup do
      Current.account = accounts("primary")
    end

    teardown do
      Current.clear_all
    end
  end
end

# For integration tests with URL-based tenancy
class ActionDispatch::IntegrationTest
  setup do
    integration_session.default_url_options[:script_name] = "/#{accounts(:primary).slug}"
  end
end
```

This ensures all tests run in proper account context.

### Custom Fixture UUID Generation

When using UUIDv7 primary keys, generate deterministic fixture UUIDs that sort correctly:

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
        # Generate deterministic UUIDv7 that sorts by fixture ID
        fixture_int = Zlib.crc32("fixtures/#{label}") % (2**30 - 1)

        # Translate to times in the past so test records are always newer
        base_time = Time.utc(2024, 1, 1, 0, 0, 0)
        timestamp = base_time + (fixture_int / 1000.0)

        uuid_v7_with_timestamp(timestamp, label)
      end
  end
end

ActiveSupport.on_load(:active_record_fixture_set) do
  prepend(FixturesTestHelper)
end
```

**Benefits:**
- `.first`/`.last` work correctly in tests
- Fixtures always older than runtime records
- Deterministic IDs across test runs

### VCR for External HTTP Requests

Record and replay external HTTP interactions:

```ruby
# test/test_helper.rb
require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data("<API_KEY>") { ENV["API_KEY"] }

  # Ignore timestamps in request bodies
  config.before_record do |i|
    if i.request&.body
      i.request.body.gsub!(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/, "<TIME>")
    end
  end
end

# In tests
test "fetches data from external API" do
  VCR.use_cassette("external_api") do
    result = ExternalService.fetch_data
    assert_equal "expected", result
  end
end
```

**Benefits:**
- Fast tests (no real HTTP calls)
- Consistent test results
- Works offline
- Catches API changes

### Test Helper Modules

Organize test helpers by domain:

```ruby
# test/test_helpers/card_test_helper.rb
module CardTestHelper
  def assert_card_container_rerendered(card)
    assert_turbo_stream action: "replace",
                        target: dom_id(card, :container)
  end
end

# test/test_helpers/session_test_helper.rb
module SessionTestHelper
  def sign_in_as(user_fixture_name)
    user = users(user_fixture_name)
    session = user.identity.sessions.create!
    cookies.signed[:session_token] = session.signed_id
  end
end

# Load in test_helper.rb
include CardTestHelper, SessionTestHelper
```

### Testing Turbo Stream Responses

Test both Turbo Stream and JSON responses:

```ruby
# test/controllers/cards/closures_controller_test.rb
test "create as turbo_stream" do
  card = cards(:logo)

  assert_changes -> { card.reload.closed? }, from: false, to: true do
    post card_closure_path(card), as: :turbo_stream
    assert_turbo_stream action: "replace", target: dom_id(card, :container)
  end
end

test "create as JSON" do
  card = cards(:logo)

  post card_closure_path(card), as: :json

  assert_response :no_content
  assert card.reload.closed?
end
```

**Pattern:** Controller actions should support both Turbo Stream (for web) and JSON (for API/mobile).

### Parallel Test Execution

Enable parallel testing for faster CI:

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  parallelize workers: :number_of_processors,
              work_stealing: ENV["WORK_STEALING"] != "false"
end
```

**Note:** System tests often need `PARALLEL_WORKERS=1` due to browser contention.

### Using assert_changes for State Transitions

Prefer `assert_changes` over separate assertions:

```ruby
# ✅ GOOD - Clear state transition testing
test "close changes state" do
  card = cards(:open)

  assert_changes -> { card.reload.closed? }, from: false, to: true do
    card.close
  end
end

# ❌ Less clear
test "close changes state" do
  card = cards(:open)
  assert_not card.closed?
  card.close
  assert card.reload.closed?
end
```

### Testing Background Job Enqueuing

Test that jobs are enqueued, not performed:

```ruby
test "closing card enqueues notification job" do
  card = cards(:open)

  assert_enqueued_with job: NotificationJob, args: [card] do
    card.close
  end
end
```

**Don't:** Use `perform_enqueued_jobs` unless testing the actual job logic.

### Minimal System Tests

Production Rails apps have very few system tests. Example from Fizzy (5 system tests total):

```ruby
# test/system/smoke_test.rb
class SmokeTest < ApplicationSystemTestCase
  # Test 1: Critical user signup flow
  test "joining an account" do
    visit join_url(code: account.join_code.code)
    fill_in "Email address", with: "new@example.com"
    click_on "Continue"
    # ... complete flow
  end

  # Test 2: Core workflow
  test "create a card" do
    sign_in_as(users(:david))
    visit board_url(boards(:primary))
    click_on "Add a card"
    fill_in "Title", with: "Hello, world!"
    click_on "Create card"
    assert_selector "h3", text: "Hello, world!"
  end

  # Test 3-5: Only for JS-dependent features
  test "dragging card to new column" do
    # Tests drag-and-drop JavaScript
  end
end
```

**Key insight:** Only 5 system tests for entire application. Everything else tested at lower levels.

## Testing Best Practices

### Use Fixtures, Not Factories

Rails encourages fixtures over factories for better performance:

```yaml
# test/fixtures/users.yml
admin:
  name: Admin User
  email: admin@example.com
  company: acme

technician:
  name: Technician User
  email: tech@example.com
  company: acme
```

```ruby
# In tests
test "admin can manage users" do
  admin = users(:admin)
  admin.grant_role("admin")
  assert admin.admin?
end
```

### Test One Behavior Per Test

```ruby
# ✅ GOOD - One assertion per test
test "validates name presence" do
  user = User.new(email: "test@example.com")
  assert_not user.valid?
  assert_includes user.errors[:name], "can't be blank"
end

test "validates email presence" do
  user = User.new(name: "Test")
  assert_not user.valid?
  assert_includes user.errors[:email], "can't be blank"
end

# ❌ BAD - Testing multiple behaviors
test "validates user" do
  user = User.new
  assert_not user.valid?
  assert_includes user.errors[:name], "can't be blank"
  assert_includes user.errors[:email], "can't be blank"
  assert_includes user.errors[:company], "can't be blank"
end
```

### Test Side Effects

```ruby
test "closing card creates event" do
  card = cards(:open)

  assert_difference("Event.count") do
    card.close(user: users(:one))
  end

  event = card.events.last
  assert_equal "closed", event.action
  assert_equal users(:one), event.creator
end
```

### Use Descriptive Test Names

```ruby
# ✅ GOOD - Clear what is being tested
test "user with no roles cannot view jobs"
test "admin role implies reviewer permissions"
test "validates UUIDv7 format on foreign keys"

# ❌ BAD - Unclear what is being tested
test "user test"
test "roles work"
test "uuid validation"
```

## Test Coverage by Level

Based on real Rails 8.1 application (760+ tests):

| Level | Count | % | Speed | Use Case |
|-------|-------|---|-------|----------|
| Model/Service | 460 | 61% | Fast | Business logic, validations |
| Controller | 231 | 30% | Fast | HTTP, routing, CRUD |
| Integration | 49 | 6% | Medium | Multi-step workflows |
| Unit | 19 | 2% | Fastest | Isolated calculations |
| System | 3 | <1% | Slow | Critical user journeys |

**Ideal distribution:**
- 60-70% model/service tests
- 25-35% controller tests
- 5-10% integration tests
- 2-5% unit tests
- <1% system tests

## Running Tests

### Local Development

```bash
# All tests except system tests
bin/rails test

# All tests including system tests
bin/rails test:all

# Specific test file
bin/rails test test/models/user_test.rb

# Specific test by line number
bin/rails test test/models/user_test.rb:27

# All model tests
bin/rails test test/models

# All controller tests
bin/rails test test/controllers

# System tests only
bin/rails test:system
```

### Rails 8.1+ Local CI

```bash
# Run full CI suite locally
bin/ci
```

This runs:
1. Setup and dependency check
2. RuboCop style checking
3. Bundler audit (gem vulnerability scanning)
4. Importmap audit (JavaScript dependency scanning)
5. Brakeman security analysis
6. Unit and integration tests
7. System tests
8. Database seed verification

## Common Anti-Patterns

### 1. Testing Mocked Behavior

```ruby
# ❌ BAD - Only verifies mock interactions
test "closes card" do
  card = mock
  card.expects(:update).with(closed: true)
  card.close
end

# ✅ GOOD - Tests actual behavior
test "closes card" do
  card = cards(:open)
  card.close
  assert card.reload.closed?
  assert card.events.closed.exists?
end
```

### 2. Over-Using System Tests

```ruby
# ❌ BAD - System test for simple CRUD
test "creates job via form" do
  visit new_job_path
  fill_in "Job number", with: "S2024"
  click_button "Create Job"
  assert_text "Job was successfully created"
end

# ✅ GOOD - Controller test
test "creates job" do
  assert_difference("Job.count") do
    post jobs_url, params: { job: { job_number: "S2024" } }
  end
  assert_redirected_to job_url(Job.last)
end
```

### 3. Not Testing Edge Cases

```ruby
# ✅ Test happy path AND edge cases
test "validates job number presence" do
  job = Job.new(job_number: nil)
  assert_not job.valid?
end

test "validates job number uniqueness" do
  existing = jobs(:one)
  job = Job.new(job_number: existing.job_number)
  assert_not job.valid?
end

test "validates job number format" do
  job = Job.new(job_number: "invalid format")
  assert_not job.valid?
end
```

## Benefits of This Approach

- ✅ **Fast test suite** - Mostly unit/controller tests that run in milliseconds
- ✅ **Reliable tests** - Fewer flaky system tests
- ✅ **Easy debugging** - Test at appropriate level of abstraction
- ✅ **Good coverage** - Comprehensive without being slow
- ✅ **TDD-friendly** - Fast feedback loop
- ✅ **Maintainable** - Tests organized by type and purpose

## References

- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)
- [Minitest Documentation](https://github.com/minitest/minitest)
- [Testing Pyramid Concept](https://martinfowler.com/bliki/TestPyramid.html)
