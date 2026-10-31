# View Patterns

How 37signals-style Rails apps organize views: declarative ERB, semantic helper
tag builders, and separate partials per display context instead of conditionals.

## Contents

- [Locals and instance variables](#locals-and-instance-variables)
- [Semantic tag builders](#semantic-tag-builders)
- [Herb-safe templates](#herb-safe-templates)
- [Directory layout and display variants](#directory-layout-and-display-variants)
- [Turbo](#turbo)
- [Caching](#caching)
- [JSON](#json)

## Locals and instance variables

Controllers set instance variables for the main resource (`@card`). The
template sets the page metadata the layout reads (`<% @page_title = @card.title %>`).
Partials take locals only — a partial that reads `@card` hides its dependencies
and can't be reused in another context.

## Semantic tag builders

Named builders encapsulate an element's classes, `dom_id`, and default data
attributes, so markup structure lives in one place and views read as intent.
Take a `data:` hash and merge the caller's into the builder's defaults
(`with_defaults`, `token_list` for space-separated values) instead of
hard-coding wiring the caller can't extend; page-specific Stimulus wiring stays
in the view.

```ruby
# app/helpers/columns_helper.rb
def column_frame_tag(id, src: nil, data: {}, **options, &block)
  data = data.with_defaults(controller: "frame")
  options[:refresh] = :morph if src

  turbo_frame_tag id, src: src, data: data, **options, &block
end
```

Helpers are named for the domain (`cards_helper.rb`) or the UI concern
(`avatars_helper.rb`). A helper that emits a hundred lines of HTML is a partial
wearing a helper's clothes.

## Herb-safe templates

Herb compiles `.html.erb` as one HTML-and-Ruby tree, so markup has to be
well-formed in every branch, and `bin/rails herb:check` rejects `<%= %>` output
in a tag's attribute list. `docs/rails-8-modern-stack.md` covers the engine.
Three patterns cover what that rules out.

**Boolean attributes** use control flow, not output:

```erb
<%# rejected: ERB output in attribute position %>
<option value="<%= value %>" <%= "selected" if selected %>>

<option value="<%= value %>" <% if selected %>selected<% end %>>
```

**Computed attributes** go through `tag.attributes`, which omits nil values and
includes or omits boolean attributes by truthiness:

```erb
<select <%= tag.attributes(id: id,
                           "aria-invalid": ("true" if errors),
                           "aria-describedby": (desc_id if help)) %>>
```

`tag.attributes` must be unconditional. `<%= tag.attributes(...) if x %>` is
rejected as well; write `<% if x %><%= tag.attributes(...) %><% end %>`.

**Conditional wrappers** capture the body once and choose the wrapper in Ruby,
instead of opening a `<div>` in one `<% if %>` and closing it in another:

```erb
<% body = capture do %>
  <%= render "cards/content", card: card %>
<% end %>

<%= wrap ? tag.div(body, class: wrapper_class) : body %>
```

**Hand-built attribute strings** are what these patterns replace. `<%= %>`
HTML-escapes its output, so `<%= "id=\"#{id}\"" if id %>` renders
`id=&quot;email&quot;`, the browser reads an `id` containing literal quotes, and
every `<label for>` pointing at it silently stops matching. The same goes for
element markup: interpolating into a string and calling `html_safe` leaves
escaping to the author, and one missed `h` is an XSS hole. Build each piece with
a tag helper and join with `safe_join` or the view helper `to_sentence`
(`Array#to_sentence` returns a plain String, so its markup renders escaped):

```erb
<%# BAD %>
<%= names.map { "<strong>#{h it}</strong>" }.join(", ").html_safe %>

<%# GOOD %>
<%= to_sentence(names.map { tag.strong(it) }) %>
```

## Directory layout and display variants

Different contexts need different markup for the same model. Rather than
branching inside one partial, give each variant its own directory and keep the
partial names identical, so adding a variant means adding a directory and
nothing selects a layout at runtime:

```
app/views/cards/
├── show.html.erb
├── _container.html.erb
├── comments/
│   ├── _comment.html.erb
│   └── create.turbo_stream.erb   # Turbo Stream responses named for the action
└── display/                      # one directory per variant
    ├── common/
    ├── preview/
    └── perma/
```

```erb
<%= render "cards/display/preview/meta", card: card %>   <%# list item %>
<%= render "cards/display/perma/meta", card: card %>     <%# detail page %>
```

Extract a partial for a display variant, for something used in more than one
place, or for a collection you want cached. Leave it inline when it's used once
and isn't complex — indirection has a cost too. Layouts compose through
`content_for :head` / `:header` / `:sidebar`, not template inheritance.

## Turbo

Stream templates may carry several operations. `method: :morph` on a replace
preserves focus and scroll position instead of blowing the element away:

```erb
<%= turbo_stream.replace dom_id(@card, :container),
    partial: "cards/container", method: :morph, locals: { card: @card.reload } %>
```

For live updates, broadcast page refreshes and let the page re-render through
its normal templates, morphed in place, so there are no broadcast partials to
keep in sync:

```ruby
class Card < ApplicationRecord
  broadcasts_refreshes
end

class Comment < ApplicationRecord
  belongs_to :card, touch: true   # the touch fires the card's refresh
end
```

```erb
<%# layout <head> %>
<%= turbo_refresh_method_tag :morph %>
<%= turbo_refresh_scroll_tag :preserve %>

<%# cards/show.html.erb %>
<%= turbo_stream_from @card %>
```

Keep targeted `broadcast_*_later_to` for per-user UI outside the page body (a
tray, a badge) that a refresh wouldn't reach.

Morphs need markup that survives them:

- A `data-turbo-permanent` element is never refreshed. That suits chrome and
  in-progress forms but freezes content other users change. For an edit form,
  add the attribute only while the form is connected.
- Guard an open `<dialog>` by cancelling `turbo:before-morph-attribute` with
  `preventDefault`.
- Re-run client-side formatting on `turbo:morph-element`.
- Give `src` frames `refresh: :morph` so a page refresh reloads them.

`turbo_exempts_page_from_cache` opts a dynamic page out of preview caching.
Make JS requests with `@rails/request.js` and `responseKind: "turbo-stream"` so
the response goes through the same stream templates.

## Caching

Child rows declare `belongs_to :card, touch: true`, so `cache card` already
covers comments and assignments. Wrap a write that mustn't bump the parent in
`Card.no_touching { ... }`.

When the rendering depends on state outside the record graph — a neighbor, the
viewer's time zone, a local that changes the markup — make it part of the key.
`locals:` are not in the `cached: true` key:

```erb
<%= render partial: "boards/column",
           collection: @columns,
           cached: ->(column) { [column, column.leftmost?, column.rightmost?] } %>

<%= render partial: "cards/card", collection: @cards,
           locals: { draggable: true }, cached: ->(card) { [card, :draggable] } %>
```

Keep viewer-specific output out of record-keyed fragments, so one fragment
serves every viewer:

- Owner-only controls carry `data-creator-id`; a per-user `<style>` (or a
  Stimulus controller reading a `current-user-id` meta tag) shows them.
- Times render as `<time datetime="...">` and are formatted in the browser.
- Anything else per-viewer goes in a lazy frame outside the cached fragment.

Template digests track `render` calls they can see. They miss helpers and
dynamically named partials, so declare `<%# Template Dependency: cards/display/preview %>`,
or bump a dated `<%# Helper Dependency Updated: column_tag 2026-10-14 %>`
comment when the helper changes.

Lazy-frame endpoints are cheap to revalidate: call `fresh_when` in the action
and let each concern add its piece to every ETag:

```ruby
class ApplicationController < ActionController::Base
  etag { "v1" }                    # bump to bust every ETag
  etag { Current.identity&.id }
  stale_when_importmap_changes
end
```

## JSON

The same action answers HTML, Turbo Stream and JSON through `respond_to`, with
the jbuilder template beside the HTML partial and nesting via `partial:, as:`:

```ruby
# app/views/cards/_card.json.jbuilder
json.cache! card do
  json.(card, :id, :number, :title, :created_at)
  json.creator card.creator, partial: "users/user", as: :user
end
```
