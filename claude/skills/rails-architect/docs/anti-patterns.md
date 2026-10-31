# Common Anti-Patterns in Rails Applications

Reference guide for identifying and fixing common Rails anti-patterns during architecture reviews.

## Contents

- [1. Service Objects Everywhere](#1-service-objects-everywhere)
- [2. Skinny Models, Fat Controllers](#2-skinny-models-fat-controllers)
- [3. God Objects](#3-god-objects)
- [4. Custom Controller Actions](#4-custom-controller-actions)
- [5. Over-Engineering](#5-over-engineering)
- [6. Missing Transaction Wrapping](#6-missing-transaction-wrapping)
- [7. Testing Mocked Behavior](#7-testing-mocked-behavior)
- [8. Hand-Built Attribute Strings](#8-hand-built-attribute-strings)
- [9. ERB Output in Attribute Position](#9-erb-output-in-attribute-position)

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
Put them in `app/models`, under the model's namespace when they serve one model
(`Card::Importer#import`), named with a domain verb (`Signup#complete`) rather
than `#call`. When a model owns the collaborator, the model exposes the entry
point (`card.import_later`), not the controller.

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

## 8. Hand-Built Attribute Strings

**Problem**: `<%= %>` HTML-escapes its output, so an attribute assembled as a
Ruby string renders with its quotes escaped. The browser reads
`id=&quot;email&quot;` as an `id` whose value contains literal quote
characters, and every `<label for>` pointing at it silently stops matching.

```erb
<%# BAD — renders id=&quot;email&quot; %>
<input type="email" <%= "id=\"#{id}\"" if id %>>

<%# GOOD — nil values are omitted %>
<input type="email" <%= tag.attributes(id: id) %>>
```

The same goes for element markup. Interpolating into a string and calling
`html_safe` leaves escaping to the author, and one missed `h` is an XSS hole.
Build each piece with a tag helper and join with `safe_join` or the view
helper `to_sentence`. `Array#to_sentence` returns a plain String, so its
markup renders escaped.

```erb
<%# BAD %>
<%= names.map { "<strong>#{h it}</strong>" }.join(", ").html_safe %>

<%# GOOD %>
<%= to_sentence(names.map { tag.strong(it) }) %>
```

## 9. ERB Output in Attribute Position

**Problem**: `<%= %>` inside a tag's attribute list or an attribute name lets
Ruby emit arbitrary markup into the tag. Herb's security validator rejects it,
so `bin/rails herb:check` fails the build.

```erb
<%# BAD %>
<button <%= "disabled" if locked %>>Save</button>

<%# GOOD %>
<button <% if locked %>disabled<% end %>>Save</button>
```

The one form allowed in attribute position is an unconditional
`<%= tag.attributes(...) %>`. See `docs/view-patterns.md` for the full set of
Herb-safe patterns.
