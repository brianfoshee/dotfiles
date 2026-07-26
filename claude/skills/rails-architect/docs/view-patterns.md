# View Patterns in Rails Applications

How 37signals-style Rails apps organize views: declarative ERB, semantic helper
tag builders, and separate partials per display context instead of conditionals.

## Contents

- [Locals over instance variables](#locals-over-instance-variables)
- [Semantic tag builders](#semantic-tag-builders)
- [What belongs out of ERB](#what-belongs-out-of-erb)
- [Directory layout](#directory-layout)
- [Display variants](#display-variants)
- [Composition via yield](#composition-via-yield)
- [Turbo](#turbo)
- [Caching](#caching)
- [References](#references)

## Locals over instance variables

Controllers set instance variables for the main resource and page metadata
(`@card`, `@page_title`, `@header_class`). Partials take locals — a partial that
reads `@card` hides its dependencies and can't be reused in another context.

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
`dom_id`, and Stimulus wiring, so markup structure lives in one place and views
read as intent.

```ruby
# app/helpers/cards_helper.rb
def card_article_tag(card, id: dom_id(card, :article), **options, &block)
  classes = [
    options.delete(:class),
    ("golden-effect" if card.golden?),
    ("card--postponed" if card.postponed?)
  ].compact.join(" ")

  data = { controller: "beacon lightbox", beacon_url_value: card_reading_path(card) }

  tag.article id: id, class: classes, data: data, **options, &block
end

def column_frame_tag(id, src:, **options)
  turbo_frame_tag id, src: src, loading: :lazy,
                  data: { turbo_action: "advance" }, **options
end
```

```erb
<%= card_article_tag(card) do %>
  <%= render "cards/content", card: card %>
<% end %>
```

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

Broadcast from the model for live updates, with the page subscribing:

```erb
<%= turbo_stream_from @card %>
```

```ruby
after_update_commit do
  broadcast_replace_to self,
    target: dom_id(self, :container),
    partial: "cards/container", locals: { card: self }
end
```

Worth knowing: `data: { turbo_frame: "_top" }` escapes a frame,
`data-turbo-permanent` preserves an element (flash containers, media players)
across navigations, and `turbo_exempts_page_from_cache` opts a dynamic page out
of preview caching.

Views declare Stimulus controllers and values; behavior lives in the controller,
updates come from Turbo.

```erb
<div data-controller="drag-drop navigable-list"
     data-action="dragstart->drag-drop#dragStart
                  drop->drag-drop#drop
                  keydown->navigable-list#navigate">
```

## Caching

```erb
<% cache card do %>
  <%= render "cards/display/preview", card: card %>
<% end %>

<%= render partial: "cards/card", collection: @cards, cached: true %>
```

When the rendering depends on more than the record itself, make the extra state
part of the key — otherwise a neighbor's change won't invalidate it:

```erb
<%= render partial: "boards/column",
           collection: @columns,
           cached: ->(column) { [column, column.leftmost?, column.rightmost?] } %>

<% cache [card, card.assignees.maximum(:updated_at)] do %>
```

## References

- [Layouts and Rendering](https://guides.rubyonrails.org/layouts_and_rendering.html)
- [Action View helpers](https://api.rubyonrails.org/classes/ActionView/Helpers.html)
- [Turbo handbook](https://turbo.hotwired.dev/handbook/introduction) · [Stimulus handbook](https://stimulus.hotwired.dev/handbook/introduction)
