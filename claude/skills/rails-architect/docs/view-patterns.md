# View Patterns in Rails Applications

Production-proven patterns for organizing and writing Rails views (HTML.erb), based on real-world implementations from 37signals/Basecamp. This focuses on architectural patterns, not HTML/CSS specifics.

## Core Philosophy

**Views should be declarative, not imperative.**

- **Helpers for complex HTML generation** - Keep ERB simple and readable
- **Partials for reusability** - Extract common patterns, not DRY for its own sake
- **Locals over instance variables** - Partials should be explicit about their dependencies
- **Composition over inheritance** - Use `yield` and `content_for` instead of complex layouts
- **Display variants over conditionals** - Separate partials for different contexts

## Variable Usage in Views

### Instance Variables from Controllers

**Primary pattern:** Controllers set instance variables for main resources and page metadata.

```ruby
# app/controllers/cards_controller.rb
class CardsController < ApplicationController
  def show
    # Main resource
    @card = Current.user.accessible_cards.find_by!(number: params[:id])

    # Page metadata
    @page_title = @card.title
    @header_class = "card-header"
  end
end
```

**Common instance variables:**
- `@resource` - Main resource being displayed
- `@page_title` - Browser title and header
- `@header_class`, `@hide_footer` - Layout customization
- `@filter`, `@sort` - Filtering/sorting state (from controller concerns)

### Locals for Partials

**Preferred pattern:** Pass data explicitly via locals, not instance variables.

```erb
<!-- Good - explicit dependencies -->
<%= render "cards/container", card: @card, draggable: true %>

<!-- Less good - implicit dependency on @card -->
<%= render "cards/container" %>
```

**Benefits:**
- Clear partial dependencies
- Reusable across contexts
- Easier to test
- No magic

### Optional Locals with Defaults

```erb
<%# app/views/cards/_card.html.erb %>
<% draggable = local_assigns.fetch(:draggable, false) %>
<% preview_mode = local_assigns.fetch(:preview, false) %>
<% show_board = local_assigns.fetch(:show_board, true) %>

<article class="card <%= 'draggable' if draggable %>">
  <%= card.title %>
  <%= render "cards/board_link", card: card if show_board %>
</article>
```

**Pattern:** Use `local_assigns.fetch(key, default)` for optional parameters.

### Checking for Local Presence

```erb
<% if local_assigns.key?(:preview) %>
  <!-- Preview mode specific rendering -->
<% end %>
```

**When to use:** When you need to distinguish between `nil` and "not passed".

## Helper Methods

### When to Use Helpers

**Helpers are for:**

1. **Complex HTML generation**
   ```ruby
   # app/helpers/cards_helper.rb
   def card_article_tag(card, id: dom_id(card, :article), **options, &block)
     classes = [
       options.delete(:class),
       ("golden-effect" if card.golden?),
       ("card--postponed" if card.postponed?)
     ].compact.join(" ")

     data = {
       controller: "beacon lightbox",
       beacon_url_value: card_reading_path(card)
     }

     tag.article id: id, class: classes, data: data, **options, &block
   end
   ```

2. **Reusable UI components**
   ```ruby
   def avatar_tag(user, size: :medium)
     color = user.avatar_color
     initials = user.initials

     tag.div class: "avatar avatar--#{size}", style: "background-color: #{color}" do
       tag.span initials, class: "avatar__text"
     end
   end
   ```

3. **Conditional logic with presentation**
   ```ruby
   def role_display_name(role)
     case role.to_sym
     when :owner then "Owner"
     when :admin then "Administrator"
     when :member then "Member"
     when :system then "System User"
     end
   end
   ```

4. **Business logic formatting**
   ```ruby
   def sorted_by_label(sort_param)
     case sort_param
     when "newest" then "Newest first"
     when "oldest" then "Oldest first"
     when "latest" then "Recently updated"
     else "Default order"
     end
   end
   ```

5. **URL/path generation with context**
   ```ruby
   def link_back_to_board(board)
     link_to "Back to #{board.name}",
             board_path(board),
             class: "back-link",
             data: { turbo_frame: "_top" }
   end
   ```

### When to Use Inline ERB

**Inline ERB acceptable for:**
- Simple conditionals (`if card.golden?`)
- Direct attribute access (`card.title`, `user.name`)
- Iteration over collections (`cards.each do |card|`)
- Layout structure and organization
- Choosing which partial to render

```erb
<!-- Good - Simple, readable inline logic -->
<% if card.published? %>
  <%= render "cards/container/footer/published", card: card %>
<% elsif card.drafted? %>
  <%= render "cards/container/footer/draft", card: card %>
<% end %>
```

### Helper Organization

**Directory structure:**
```
app/helpers/
├── application_helper.rb      # Global utilities
├── cards_helper.rb             # Card-specific helpers
├── boards_helper.rb            # Board-specific helpers
├── users_helper.rb             # User-specific helpers
├── avatars_helper.rb           # Avatar rendering
├── forms_helper.rb             # Form utilities
├── pagination_helper.rb        # Pagination UI
└── notifications_helper.rb     # Notification formatting
```

**Naming convention:**
- Domain-focused (cards, boards, users)
- Technical-focused (avatars, forms, pagination)
- All helpers automatically available in all views

### Semantic Tag Builders Pattern

**Encapsulate common element patterns:**

```ruby
# app/helpers/boards_helper.rb
def column_tag(column, **options, &block)
  tag.div id: dom_id(column),
          class: ["column", options.delete(:class)].compact.join(" "),
          data: {
            controller: "drag-drop",
            column_id: column.id
          },
          **options,
          &block
end

def column_frame_tag(id, src:, **options)
  turbo_frame_tag id,
                  src: src,
                  loading: :lazy,
                  data: { turbo_action: "advance" },
                  **options
end
```

**Benefits:**
- Consistent data attributes across the app
- One place to change markup structure
- Semantic names (`column_tag` vs generic `div`)
- Encapsulates Stimulus controller attachment

## View Organization & Partials

### Directory Structure Pattern

```
app/views/cards/
├── index.html.erb                  # Main action views
├── show.html.erb
├── _container.html.erb              # Major sections
├── _messages.html.erb
├── comments/                        # Nested resource views
│   ├── _comment.html.erb
│   ├── _new.html.erb
│   └── create.turbo_stream.erb
├── display/                         # Display variants
│   ├── common/                      # Shared components
│   │   ├── _meta.html.erb
│   │   ├── _assignees.html.erb
│   │   └── _background.html.erb
│   ├── preview/                     # List view variant
│   │   ├── _meta.html.erb
│   │   ├── _steps.html.erb
│   │   └── _assignees.html.erb
│   ├── perma/                       # Detail view variant
│   │   ├── _meta.html.erb
│   │   └── _assignees.html.erb
│   └── mini/                        # Compact variant
│       └── _meta.html.erb
└── container/                       # Card detail sections
    ├── _content.html.erb
    └── footer/
        ├── _published.html.erb
        └── _draft.html.erb
```

### Naming Conventions

- **Underscore prefix for partials:** `_comment.html.erb`
- **Directory namespacing for variants:** `display/preview/`, `display/perma/`
- **Turbo Stream responses:** `create.turbo_stream.erb`, `update.turbo_stream.erb`
- **Nested resources in subdirectories:** `comments/`, `assignees/`

### When to Extract Partials

**Extract when:**

1. **Display variants** - Different representations of same model
   ```
   cards/display/preview/  # List item
   cards/display/perma/    # Detail view
   cards/display/mini/     # Compact
   ```

2. **Reusability** - Used in multiple places
   ```erb
   <%= render "shared/avatar", user: card.creator %>
   <%= render "shared/avatar", user: comment.author %>
   ```

3. **Logical sections** - Breaking up complex views
   ```erb
   <%= render "cards/container/header", card: @card %>
   <%= render "cards/container/content", card: @card %>
   <%= render "cards/container/footer", card: @card %>
   ```

4. **Collection rendering** - Optimized with caching
   ```erb
   <%= render partial: "cards/card", collection: @cards, cached: true %>
   ```

**Don't extract when:**
- Only used once and not complex
- Creates indirection without benefit
- Makes code harder to follow

### Partial Rendering Patterns

**Simple render with locals:**
```erb
<%= render "cards/container/content", card: card %>
```

**Collection rendering with caching:**
```erb
<%= render partial: "cards/display/preview",
           collection: cards,
           as: :card,
           cached: true %>
```

**Collection with custom cache key:**
```erb
<%= render partial: "boards/show/column",
           collection: board.columns.sorted,
           cached: ->(column) { [column, column.leftmost?, column.rightmost?] } %>
```

**Composition via yield:**
```erb
<!-- Parent partial provides structure -->
<%# app/views/cards/display/common/_meta.html.erb %>
<div class="card-meta">
  <div class="card-meta__primary">
    <%= card.number %>
    <%= card.status %>
  </div>
  <div class="card-meta__secondary">
    <%= yield if block_given? %>
  </div>
</div>

<!-- Caller provides content -->
<%= render "cards/display/common/meta", card: card do %>
  <%= render "cards/display/perma/assignees", card: card %>
<% end %>
```

## Logic in ERB - Scope Guidelines

### Acceptable in Views

**Simple state checks:**
```erb
<% if card.golden? %>
  <span class="golden-badge">★</span>
<% end %>

<% unless card.description.blank? %>
  <%= card.description %>
<% end %>
```

**Collection iteration:**
```erb
<% card.assignees.each do |assignee| %>
  <%= render "shared/avatar", user: assignee %>
<% end %>
```

**Local variable assignment:**
```erb
<% draggable = local_assigns.fetch(:draggable, false) && card.published? %>
<% meta_id = dom_id(card, :meta) %>
```

**Choosing partials based on state:**
```erb
<% if card.published? %>
  <%= render "cards/container/footer/published", card: card %>
<% elsif card.drafted? %>
  <%= render "cards/container/footer/draft", card: card %>
<% end %>
```

### Belongs in Helpers/Models

**Complex calculations:**
```ruby
# Bad - in view
<% color = "#" + Digest::MD5.hexdigest(user.email)[0..5] %>

# Good - in helper
<%= avatar_tag(user) %>

# Helper implementation
def avatar_tag(user)
  color = user.avatar_color  # Model method
  # ...
end
```

**Business rules:**
```ruby
# Bad - in view
<% if user.role == "owner" || user.role == "admin" %>

# Good - in model
<% if user.admin? %>

# Model implementation
def admin?
  super || owner?  # Owners are also admins
end
```

**HTML generation with many attributes:**
```ruby
# Bad - in view
<article id="<%= dom_id(card) %>"
         class="card <%= 'golden' if card.golden? %> <%= 'postponed' if card.postponed? %>"
         data-controller="beacon lightbox"
         data-beacon-url="<%= card_reading_path(card) %>">

# Good - in helper
<%= card_article_tag(card) do %>
  <%= card.title %>
<% end %>
```

**Data transformation:**
```ruby
# Bad - in view
<% sorted_users = users.sort_by { |u| [u.role_priority, u.name] } %>

# Good - in model scope or helper
<%= render users.by_role_and_name %>
```

## Display Variants Pattern

**Problem:** Different contexts need different HTML for the same model.

**Solution:** Separate partial directories for each variant.

```
app/views/cards/display/
├── common/           # Shared across variants
│   └── _assignees.html.erb
├── preview/          # List item (compact)
│   ├── _meta.html.erb
│   └── _assignees.html.erb
├── perma/            # Detail view (full)
│   ├── _meta.html.erb
│   └── _assignees.html.erb
└── mini/             # Very compact
    └── _meta.html.erb
```

**Usage:**
```erb
<!-- List view -->
<%= render "cards/display/preview/meta", card: card %>

<!-- Detail view -->
<%= render "cards/display/perma/meta", card: card %>

<!-- Both use common assignees -->
<%= render "cards/display/common/assignees", card: card %>
```

**Benefits:**
- Same partial name (`_meta.html.erb`) with different implementations
- Common components shared
- No conditional logic choosing layouts
- Easy to add new variants

## Turbo/Hotwire Patterns

### Turbo Stream Responses

**File location:** `app/views/cards/create.turbo_stream.erb`

```erb
<%# Replace with morphing for smooth transitions %>
<%= turbo_stream.replace dom_id(@card, :container),
    partial: "cards/container",
    method: :morph,
    locals: { card: @card.reload } %>

<%# Multiple updates in one response %>
<%= turbo_stream.before [card, :new_comment],
    partial: "cards/comments/comment",
    locals: { comment: @comment } %>

<%= turbo_stream.update [card, :new_comment],
    partial: "cards/comments/new",
    locals: { card: card } %>
```

**Common operations:**
- `replace` - Swap element (use `method: :morph` for smooth transitions)
- `update` - Replace inner HTML
- `append`/`prepend` - Add to list
- `remove` - Remove element
- `before`/`after` - Insert adjacent

### Turbo Frames

**Lazy loading pattern:**
```erb
<%= turbo_frame_tag :board_menu,
    src: board_menu_path(@board),
    loading: :lazy,
    target: "_top" do %>
  Loading...
<% end %>
```

**Custom frame helpers:**
```ruby
# app/helpers/boards_helper.rb
def column_frame_tag(id, src:, **options)
  turbo_frame_tag id,
                  src: src,
                  loading: :lazy,
                  data: { turbo_action: "advance" },
                  **options
end
```

**Benefits:**
- Deferred loading for performance
- Independent navigation within frames
- Optimistic UI updates

### Broadcasting for Real-Time Updates

```erb
<%# app/views/cards/show.html.erb %>
<%= turbo_stream_from @card %>
<%= turbo_stream_from @card, :activity %>

<div id="<%= dom_id(@card, :container) %>">
  <%= render "cards/container", card: @card %>
</div>
```

**In model:**
```ruby
# app/models/card.rb
after_update_commit do
  broadcast_replace_to self,
                       target: dom_id(self, :container),
                       partial: "cards/container",
                       locals: { card: self }
end
```

### Turbo-Specific Helpers

**Prevent caching for dynamic content:**
```erb
<% turbo_exempts_page_from_cache %>
```

**Break out of frame context:**
```erb
<%= link_to "View Full Page", card_path(card), data: { turbo_frame: "_top" } %>
```

**Preserve elements across page loads:**
```erb
<div data-turbo-permanent id="flash-messages">
  <%= render "shared/flash" %>
</div>
```

### Integration with Stimulus

**Attaching controllers:**
```erb
<div data-controller="drag-drop navigable-list"
     data-action="dragstart->drag-drop#dragStart
                  dragover->drag-drop#dragOver
                  drop->drag-drop#drop
                  keydown->navigable-list#navigate">
```

**Passing values to Stimulus:**
```erb
<%= card_article_tag @card,
    data: {
      beacon_url_value: card_reading_path(@card),
      lightbox_target: "container"
    } %>
```

**Pattern:** Views attach Stimulus controllers, controllers handle behavior, Turbo handles updates.

## Content Blocks & Layout Customization

### content_for Pattern

**In view:**
```erb
<%# app/views/cards/show.html.erb %>
<% content_for :head do %>
  <meta property="og:title" content="<%= @card.title %>">
  <meta property="og:description" content="<%= @card.description %>">
<% end %>

<% content_for :header do %>
  <%= link_to "← Back", board_path(@card.board) %>
<% end %>
```

**In layout:**
```erb
<%# app/views/layouts/application.html.erb %>
<head>
  <%= yield :head %>
</head>

<body>
  <header>
    <%= yield :header %>
  </header>

  <main>
    <%= yield %>
  </main>
</body>
```

**Common content blocks:**
- `:head` - Meta tags, page-specific styles/scripts
- `:header` - Page-specific header content
- `:footer` - Page-specific footer content
- `:sidebar` - Sidebar content

## Caching Strategies

### Fragment Caching

**Simple caching:**
```erb
<% cache card do %>
  <%= render "cards/display/preview", card: card %>
<% end %>
```

**Collection caching:**
```erb
<%= render partial: "cards/card",
           collection: @cards,
           cached: true %>
```

**Custom cache key:**
```erb
<%= render partial: "boards/column",
           collection: @columns,
           cached: ->(column) { [column, column.leftmost?] } %>
```

**Cache dependencies:**
```erb
<% cache [card, card.assignees.maximum(:updated_at)] do %>
  <%= render "cards/assignees", card: card %>
<% end %>
```

## Key Architectural Insights

1. **Helpers are semantic** - `card_article_tag` not generic `article_tag`
2. **Locals over instance variables** - Explicit dependencies in partials
3. **Display variants over conditionals** - Separate directories for contexts
4. **Composition via yield** - Partials accept blocks for customization
5. **Turbo Frames for lazy loading** - Deferred rendering for performance
6. **Stimulus for behavior** - Views declare controllers, JavaScript handles interaction
7. **Cache aggressively** - Fragment cache partials with cache keys
8. **Content blocks for layouts** - `content_for` instead of complex template inheritance

## Common Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: Business Logic in Views

```erb
<!-- Bad -->
<% if user.role == "owner" || user.role == "admin" %>
  <%= link_to "Settings", settings_path %>
<% end %>

<!-- Good -->
<% if user.admin? %>
  <%= link_to "Settings", settings_path %>
<% end %>
```

### ❌ Anti-Pattern 2: Complex Helpers

```ruby
# Bad - doing too much
def render_card_with_full_details(card, options = {})
  # 100 lines of HTML generation
end

# Good - compose smaller helpers
def card_article_tag(card, **options, &block)
  # Simple tag builder
end

# Use in view
<%= card_article_tag(card) do %>
  <%= render "cards/content", card: card %>
<% end %>
```

### ❌ Anti-Pattern 3: Deep Nesting

```erb
<!-- Bad - hard to follow -->
<% if condition1 %>
  <% if condition2 %>
    <% collection.each do |item| %>
      <% if item.published? %>
        <!-- content -->
      <% end %>
    <% end %>
  <% end %>
<% end %>

<!-- Good - extract to partials -->
<% if condition1 && condition2 %>
  <%= render partial: "items/item", collection: published_items %>
<% end %>
```

### ❌ Anti-Pattern 4: Instance Variables in Partials

```erb
<!-- Bad - implicit dependency -->
<%# _card.html.erb %>
<div class="card">
  <%= @card.title %>  <!-- Where does @card come from? -->
</div>

<!-- Good - explicit dependency -->
<%# _card.html.erb %>
<div class="card">
  <%= card.title %>  <!-- Passed as local -->
</div>

<!-- Usage -->
<%= render "card", card: @card %>
```

## References

- [Rails Layouts and Rendering Guide](https://guides.rubyonrails.org/layouts_and_rendering.html)
- [Action View Helpers](https://api.rubyonrails.org/classes/ActionView/Helpers.html)
- [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)
