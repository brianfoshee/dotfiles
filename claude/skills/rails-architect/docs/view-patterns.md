# View Patterns in Rails Applications

How 37signals-style Rails apps organize views: declarative ERB, semantic helper
tag builders, and separate partials per display context instead of conditionals.

## Contents

- [Locals over instance variables](#locals-over-instance-variables)
- [Semantic tag builders](#semantic-tag-builders)
- [What belongs out of ERB](#what-belongs-out-of-erb)
- [Herb-safe templates](#herb-safe-templates)
- [Directory layout](#directory-layout)
- [Display variants](#display-variants)
- [Composition via yield](#composition-via-yield)
- [Turbo](#turbo)
- [Caching](#caching)
- [JSON](#json)
- [References](#references)

## Locals over instance variables

Controllers set instance variables for the main resource (`@card`). The
template sets the page metadata the layout reads (`<% @page_title = @card.title %>`).
Partials take locals — a partial that reads `@card` hides its dependencies and
can't be reused in another context.

```erb
<%= render "cards/container", card: @card, draggable: true %>
```

Optional locals get defaults via `local_assigns`, and `key?` distinguishes "not
passed" from "passed as nil":

```erb
<% draggable = local_assigns.fetch(:draggable, false) %>
<% show_board = local_assigns.fetch(:show_board, true) %>

<% if local_assigns.key?(:preview) %>
```

## Semantic tag builders

The main helper pattern: named builders that encapsulate an element's classes,
`dom_id`, and default data attributes, so markup structure lives in one place
and views read as intent.

```ruby
# app/helpers/cards_helper.rb
def card_article_tag(card, id: dom_id(card, :article), data: {}, **options, &block)
  classes = [
    options.delete(:class),
    ("golden-effect" if card.golden?),
    ("card--postponed" if card.postponed?)
  ].compact.join(" ")

  tag.article id: id, class: classes, data: data, **options, &block
end

# app/helpers/columns_helper.rb
def column_frame_tag(id, src: nil, data: {}, **options, &block)
  data = data.with_defaults(controller: "frame")
  options[:refresh] = :morph if src

  turbo_frame_tag id, src: src, data: data, **options, &block
end
```

```erb
<%= card_article_tag(card, data: { controller: "beacon lightbox", beacon_url_value: card_reading_path(card) }) do %>
  <%= render "cards/content", card: card %>
<% end %>
```

Take a `data:` hash and merge the caller's into the builder's defaults
(`with_defaults`, `token_list` for space-separated values) instead of
hard-coding wiring the caller can't extend. Page-specific Stimulus wiring stays
in the view.

Helpers are named for the domain (`cards_helper.rb`, `boards_helper.rb`) or the
UI concern (`avatars_helper.rb`, `pagination_helper.rb`). Keep them small and
composable — a `render_card_with_full_details` that emits a hundred lines of
HTML is a partial wearing a helper's clothes.

## What belongs out of ERB

Fine inline: state checks (`if card.golden?`), iteration, local assignment,
`dom_id` calls, and choosing which partial to render.

Move out when the view starts computing rather than displaying:

```erb
<%# a business rule — belongs in the model as user.admin? %>
<% if user.role == "owner" || user.role == "admin" %>

<%# a calculation — belongs in a model method behind avatar_tag(user) %>
<% color = "#" + Digest::MD5.hexdigest(user.email)[0..5] %>

<%# a transformation — belongs in a scope, users.by_role_and_name %>
<% sorted = users.sort_by { |u| [u.role_priority, u.name] } %>
```

Nesting more than a level or two of conditionals usually means a partial is
waiting to be extracted, or the collection should have been filtered upstream.

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
<label class="field-label" <%= tag.attributes(for: field_id) %>>

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

Run `bin/rails herb:check` in `bin/ci`; it compiles every HTML+ERB template,
lists each one that fails, and exits non-zero.

## Directory layout

```
app/views/cards/
├── index.html.erb
├── show.html.erb
├── _container.html.erb
├── comments/
│   ├── _comment.html.erb
│   └── create.turbo_stream.erb
├── display/                 # one directory per variant
│   ├── common/
│   ├── preview/
│   ├── perma/
│   └── mini/
└── container/
    ├── _content.html.erb
    └── footer/
        ├── _published.html.erb
        └── _draft.html.erb
```

Nested resources get subdirectories; Turbo Stream responses are named for the
action (`create.turbo_stream.erb`).

Extract a partial for a display variant, for something used in more than one
place, for a logical section of a long view, or for a collection you want
cached. Leave it inline when it's used once and isn't complex — indirection has
a cost too.

## Display variants

Different contexts need different markup for the same model. Rather than
branching inside one partial, give each variant its own directory and keep the
partial names identical:

```erb
<%= render "cards/display/preview/meta", card: card %>   <%# list item %>
<%= render "cards/display/perma/meta", card: card %>     <%# detail page %>
<%= render "cards/display/common/assignees", card: card %>
```

Adding a variant means adding a directory, and nothing selects a layout at
runtime.

## Composition via yield

Partials can take blocks, so a shared structural partial can host
variant-specific content:

```erb
<%# cards/display/common/_meta.html.erb %>
<div class="card-meta">
  <div class="card-meta__primary">
    <%= card.number %>
    <%= card.status %>
  </div>
  <div class="card-meta__secondary">
    <%= yield if block_given? %>
  </div>
</div>
```

```erb
<%= render "cards/display/common/meta", card: card do %>
  <%= render "cards/display/perma/assignees", card: card %>
<% end %>
```

Layouts use the same idea through `content_for :head` / `:header` / `:sidebar`
rather than template inheritance.

## Turbo

Stream templates go in `app/views/cards/create.turbo_stream.erb` and may carry
several operations. `method: :morph` on a replace preserves focus and scroll
position instead of blowing the element away:

```erb
<%= turbo_stream.replace dom_id(@card, :container),
    partial: "cards/container",
    method: :morph,
    locals: { card: @card.reload } %>

<%= turbo_stream.before [card, :new_comment],
    partial: "cards/comments/comment", locals: { comment: @comment } %>
```

For live updates, broadcast page refreshes and let the page re-render through
its normal templates, morphed in place. There are no broadcast partials to keep
in sync:

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

Worth knowing: `data: { turbo_frame: "_top" }` escapes a frame,
`data-turbo-permanent` preserves an element (flash containers, media players)
across navigations, and `turbo_exempts_page_from_cache` opts a dynamic page out
of preview caching.

Views declare Stimulus controllers and values; behavior lives in the controller,
updates come from Turbo. Bind global events declaratively too:

```erb
<div data-controller="drag-drop navigable-list"
     data-action="dragstart->drag-drop#dragStart
                  drop->drag-drop#drop
                  keydown@document->navigable-list#navigate">
```

When a controller must call `addEventListener`, bind the handler once, keep that
reference, and remove it in `disconnect()`; binding again on each connect leaks
listeners. Make JS requests with `@rails/request.js` and
`responseKind: "turbo-stream"` so the response goes through the same stream
templates.

## Caching

```erb
<% cache card do %>
  <%= render "cards/display/preview", card: card %>
<% end %>

<%= render partial: "cards/card", collection: @cards, cached: true %>
```

Child rows declare `belongs_to :card, touch: true`, so `cache card` already
covers comments and assignments. Wrap a write that mustn't bump the parent in
`Card.no_touching { ... }`.

When the rendering depends on state outside the record graph — a neighbor, the
viewer's time zone, a local that changes the markup — make it part of the key,
otherwise a change won't invalidate it. `locals:` are not in the `cached: true`
key:

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

The same controller action answers HTML, Turbo Stream and JSON through
`respond_to`; there is no separate API namespace or serializer layer. Put the
jbuilder template beside the HTML partial and nest with `partial:, as:`:

```ruby
# app/views/cards/_card.json.jbuilder
json.cache! card do
  json.(card, :id, :number, :title, :created_at)
  json.creator card.creator, partial: "users/user", as: :user
end
```

```ruby
respond_to do |format|
  format.turbo_stream
  format.json { render :show, status: :created }
end
```

## References

- [Layouts and Rendering](https://guides.rubyonrails.org/layouts_and_rendering.html)
- [Action View helpers](https://api.rubyonrails.org/classes/ActionView/Helpers.html)
- [Turbo handbook](https://turbo.hotwired.dev/handbook/introduction) · [Stimulus handbook](https://stimulus.hotwired.dev/handbook/introduction)
