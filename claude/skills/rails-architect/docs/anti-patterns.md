# Common Anti-Patterns in Rails Applications

Reference guide for identifying and fixing common Rails anti-patterns during architecture reviews.

## 1. Service Objects Everywhere

**Problem**: Unnecessary abstraction layer between controllers and models.

```ruby
# BAD
class CardClosureService
  def call(card, user)
    card.update(closed: true)
  end
end

# GOOD
class Card
  def close(user: Current.user)
    # Business logic here
  end
end
```

**When services ARE appropriate**: Complex multi-model operations, external API integrations, form objects.

## 2. Skinny Models, Fat Controllers

**Problem**: Business logic in controllers instead of models.

```ruby
# BAD (controller)
def close
  @card.update(closed: true, closed_at: Time.now)
  @card.events.create(action: :closed)
  NotificationJob.perform_later(@card)
end

# GOOD (controller)
def create
  @card.close
end

# GOOD (model)
def close
  transaction do
    create_closure!
    track_event :closed
  end
end
```

## 3. God Objects

**Problem**: Models with hundreds of methods.

```ruby
# BAD
class Card < ApplicationRecord
  # 50+ methods in one file
end

# GOOD
class Card < ApplicationRecord
  include Closeable, Assignable, Taggable, Searchable
  # Each concern handles one aspect
end
```

## 4. Custom Controller Actions

**Problem**: Non-REST actions instead of new resources.

```ruby
# BAD
post '/cards/:id/archive'

# GOOD
resource :archive  # Cards::ArchivesController
```

## 5. Over-Engineering

**Problem**: Adding complexity for hypothetical future needs.
- Feature flags for simple changes
- Abstractions for single use case
- Complex inheritance hierarchies
- Unnecessary gems/dependencies

## 6. Missing Transaction Wrapping

**Problem**: Multi-step operations without atomicity.

```ruby
# BAD
def close
  create_closure!
  track_event :closed  # Could fail leaving orphaned closure
end

# GOOD
def close
  transaction do
    create_closure!
    track_event :closed
  end
end
```

## 7. Testing Mocked Behavior

**Problem**: Tests that only verify mock interactions.

```ruby
# BAD
test "closes card" do
  card = mock
  card.expects(:update).with(closed: true)
  card.close
end

# GOOD
test "closes card" do
  card = cards(:open)
  card.close
  assert card.reload.closed?
  assert card.events.closed.exists?
end
```
