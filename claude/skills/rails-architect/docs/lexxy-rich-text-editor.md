# Lexxy Rich Text Editor for ActionText

Lexxy is Basecamp's ActionText editor, wrapping Meta's Lexical. Over Trix it
brings an autocomplete prompt system (mentions, tags, slash commands), code
highlighting, tables, markdown-on-paste, and real `<p>` semantics, and it imports
existing Trix HTML so migration is content-compatible.

## Contents

- [Setup](#setup)
- [Editor attributes](#editor-attributes)
- [Forms and models](#forms-and-models)
- [SGIDs and attachables](#sgids-and-attachables)
- [Prompt system](#prompt-system)
- [Events and Stimulus](#events-and-stimulus)
- [Link unfurling](#link-unfurling)
- [JavaScript configuration](#javascript-configuration)
- [Custom upload handling](#custom-upload-handling)
- [Canonical HTML](#canonical-html)
- [Sanitization](#sanitization)
- [Editor registry](#editor-registry)
- [Extensions](#extensions)
- [Styling](#styling)
- [Syntax highlighting](#syntax-highlighting)
- [System testing](#system-testing)
- [References](#references)

## Setup

```ruby
gem "lexxy", "~> 0.9"
```

Import maps with Propshaft:

```ruby
# config/importmap.rb
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"  # for attachments
```

```javascript
import "lexxy"                 // bundlers: import "@37signals/lexxy"
```

```erb
<%= stylesheet_link_tag "lexxy" %>
```

### Two integration paths

Lexxy picks its ActionText integration at load time based on what the Rails
version supports. `Lexxy.supports_editor_adapter?` is the switch — it returns
true when `ActionText::Editor#editor_tag` accepts a block (rails/rails#56926).

**Rails 8.2+ — adapter path.** Lexxy registers itself through the
`ActionText::Editor` interface (0.9.5+), so `form.rich_textarea` emits
`<lexxy-editor>` directly. There's no override flag; opt out by naming another
registered adapter, per model or globally:

```ruby
class Article < ApplicationRecord
  has_rich_text :content, editor: :trix
end

config.action_text.editor = :trix
```

**Rails 8.0/8.1 — monkey-patch fallback.** Lexxy prepends modules onto the
ActionText tag helpers. Opt out and call its helper explicitly instead:

```ruby
config.lexxy.override_action_text_defaults = false  # then form.lexxy_rich_text_area :content
```

Check the live state with `Rails.application.config.action_text.editor`.

## Editor attributes

`<lexxy-editor>` is a form-associated custom element with native validation.

| Attribute     | Description                                    |
|---------------|------------------------------------------------|
| `preset`      | Named configuration preset (default `"default"`) |
| `placeholder` | Placeholder text                               |
| `single-line` | Single-line mode, suppresses Enter             |
| `autofocus`   | Focus on mount                                 |
| `required`    | Native form validation                         |
| `rows`        | Height in line-height units (default `8`)      |
| `name`        | Form field name                                |
| `value`       | Initial HTML content                           |

```erb
<%= form.rich_textarea :title, "single-line": true, required: true, rows: 2 %>
```

## Forms and models

`has_rich_text` is unchanged, and the standard helper renders Lexxy. Prompts go
in a block:

```erb
<%= form.rich_textarea :description,
      placeholder: "Add notes, @mention people, or /music to add a song..." do %>
  <%= mentions_prompt(@card.board) %>
  <%= music_prompt %>
  <%= code_language_picker %>
<% end %>
```

## SGIDs and attachables

A signed GlobalID links an attachment to a record. It's signed with the app's
key and scoped to the purpose `"attachable"`, so it can't be forged or reused.

```ruby
person.attachable_sgid                  # embed this in the prompt item
ActionText::Attachable.from_node(node)  # resolves it back to the record
```

Any model can be embedded:

```ruby
class Person < ApplicationRecord
  include ActionText::Attachable

  # Required — how ActionText categorizes the attachment
  def content_type = "application/vnd.actiontext.mention"

  def to_attachable_partial_path = "people/mention"
  def attachable_plain_text_representation(caption = nil) = "@#{name}"

  # Fallback when the record is gone
  def self.to_missing_attachable_partial_path = "people/deleted_mention"
end
```

## Prompt system

Each `<lexxy-prompt>` binds a trigger string to a data source and generates its
own content type, `application/vnd.actiontext.{name}`. Triggers are arbitrary
strings, not just single characters — `@`, `#`, `/music`, `by:` all work — and
any number of prompts can coexist in one editor.

```erb
<%= form.rich_textarea :body do %>
  <lexxy-prompt trigger="@" name="mention">
    <%= render partial: "people/prompt_item", collection: Person.all %>
  </lexxy-prompt>

  <lexxy-prompt trigger="/video" name="video" src="<%= videos_path %>" remote-filtering>
  </lexxy-prompt>
<% end %>
```

| `<lexxy-prompt>` attribute   | Description                                  |
|------------------------------|----------------------------------------------|
| `trigger`                    | String that activates the prompt             |
| `name`                       | Sets content type `application/vnd.actiontext.{name}` |
| `src`                        | URL to load items from                       |
| `empty-results`              | No-match message (default "Nothing found")   |
| `remote-filtering`           | Filter server-side on each keystroke         |
| `insert-editable-text`       | Insert as editable text, not an attachment   |
| `supports-space-in-searches` | Allow spaces in the query                    |

`<lexxy-prompt-item>` takes `search` (text to match) and `sgid`. It holds two
templates: `type="menu"` for the dropdown, `type="editor"` for what lands in the
editor on selection.

```erb
<%# app/views/people/_prompt_item.html.erb %>
<lexxy-prompt-item search="<%= "#{person.name} #{person.email}" %>"
                   sgid="<%= person.attachable_sgid %>">
  <template type="menu">
    <%= image_tag person.avatar, class: "avatar" %>
    <span><%= person.name %></span>
  </template>

  <template type="editor">
    <%= render "people/mention", person: person %>
  </template>
</lexxy-prompt-item>
```

Render `type="editor"` from the same partial as the published output, so the
mention looks identical while editing and after saving.

**Loading strategy** scales with the dataset: render items inline for small
collections, point `src` at an endpoint that returns the partials for medium
ones, and add `remote-filtering` for large ones so the server filters per
keystroke. Prompt endpoints return HTML partials, not JSON, and render with
`layout: false`.

Helpers keep the markup out of views:

```ruby
module RichTextHelper
  def mentions_prompt(board)
    content_tag "lexxy-prompt", "", trigger: "@", name: "mention",
      src: prompts_board_users_path(board)
  end

  def music_prompt
    content_tag "lexxy-prompt", "", trigger: "/music", name: "music",
      src: prompts_songs_path, "remote-filtering": true,
      "supports-space-in-searches": true
  end

  def cards_prompt
    content_tag "lexxy-prompt", "", trigger: "#", name: "card",
      src: prompts_cards_path, "insert-editable-text": true, "remote-filtering": true
  end

  def code_language_picker = content_tag("lexxy-code-language-picker")
end
```

## Events and Stimulus

Lexxy's events bubble, so the Stimulus controller goes on the *form* while the
actions are declared on the `rich_textarea`.

```erb
<%= form_with model: card, data: { controller: "auto-save local-save" } do |form| %>
  <%= form.rich_textarea :description,
        data: {
          local_save_target: "input",
          action: "lexxy:change->auto-save#change
                   lexxy:change->local-save#save
                   keydown.meta+enter->form#submit:prevent
                   focusout->auto-save#submit"
        } %>
<% end %>
```

| Event                   | Fires when                                      |
|-------------------------|-------------------------------------------------|
| `lexxy:initialize`      | Editor attached and ready                       |
| `lexxy:change`          | Content changed                                 |
| `lexxy:focus` / `:blur` | Focus gained / lost                             |
| `lexxy:file-accept`     | File dropped or inserted — `preventDefault()` cancels |
| `lexxy:upload-start`    | Upload began                                    |
| `lexxy:upload-progress` | Progress update                                 |
| `lexxy:upload-end`      | Upload finished                                 |
| `lexxy:insert-link`     | Plain-text link pasted                          |
| `lexxy:insert-markdown` | Markdown pasted                                 |

Restoring a draft into the editor programmatically needs a synthetic event —
setting `.value` alone won't notify listeners:

```javascript
if (this.inputTarget.tagName === "LEXXY-EDITOR") {
  this.inputTarget.dispatchEvent(new CustomEvent("lexxy:change", {
    bubbles: true,
    detail: { previousContent: "", newContent: newValue }
  }))
}
```

Global hotkey handlers should bail out inside the editor:

```javascript
if (event.target.closest("lexxy-editor")) return
```

## Link unfurling

`lexxy:insert-link` fires on paste. `event.detail` carries `url`,
`replaceLinkWith(html, options)`, and `insertBelowLink(html, options)`. Pass
`{ attachment: true }` to render non-editable, or
`{ attachment: { sgid } }` to bind it to a record. Returning without calling
either leaves the default link behavior alone.

```javascript
async handleLink(event) {
  const { url, replaceLinkWith } = event.detail
  if (!url.includes("open.spotify.com")) return

  const response = await fetch("/songs/unfurl", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url })
  })
  if (!response.ok) return

  const { html, sgid } = await response.json()
  replaceLinkWith(html, { attachment: { sgid } })
}
```

## JavaScript configuration

```javascript
import * as Lexxy from "lexxy"

Lexxy.configure({
  global: {
    attachmentTagName: "action-text-attachment",  // must match ActionText
    attachmentContentTypeNamespace: "actiontext", // application/vnd.{ns}.{name}
    authenticatedUploads: false,                  // for authenticated AS controllers
    extensions: []
  },

  default: {
    toolbar: true, attachments: true, markdown: true,
    multiLine: true, richText: true,
    highlight: {
      buttons: {
        color: [1,2,3,4,5,6,7,8,9].map(n => `var(--highlight-${n})`),
        "background-color": [1,2,3,4,5,6,7,8,9].map(n => `var(--highlight-bg-${n})`)
      },
      permit: { color: [], "background-color": [] }  // extra colors allowed on paste
    }
  },

  simple: { toolbar: false, richText: false },
  comment: { toolbar: true, attachments: false, multiLine: true }
})
```

Select a preset per editor with `<lexxy-editor preset="simple">`.

## Custom upload handling

Uploads create Active Storage blobs by default. To have them create your own
model instead — for metadata, access control, or a processing pipeline — point
the direct-upload URL at your own endpoint:

```erb
<%= form.rich_textarea :body,
      data: {
        direct_upload_url: images_upload_path,
        blob_url_template: rails_blob_url(":signed_id", ":filename")
      } %>
```

```ruby
class ImagesController < ApplicationController
  def upload
    blob = ActiveStorage::Blob.create_and_upload!(
      io: request.body,
      filename: request.headers["X-Upload-Filename"] || "upload",
      content_type: request.headers["Content-Type"]
    )
    image = Image.create!(file: blob)

    render json: {
      attachable_sgid: image.attachable_sgid,  # the Image's SGID, not the blob's
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      previewable: image.previewable_attachable?,
      url: url_for(image.file.variant(resize_to_limit: [1024, 1024]))
    }
  end
end
```

Lexxy only cares about that JSON shape — `attachable_sgid` decides what gets
embedded, whether it points at a blob or your own record. The model needs
`include ActionText::Attachable`, a `content_type`, and
`previewable_attachable?` returning true for in-editor previews.

For validation before the upload starts, listen for `lexxy:file-accept` and call
`preventDefault()` to reject the file entirely; let it through to fall back to
the configured endpoint.

## Canonical HTML

Lexxy writes the format ActionText already expects:

```html
<action-text-attachment sgid="BAh7CEk..." content-type="image/jpeg"
  url="https://..." filename="photo.jpg" filesize="123456"
  width="800" height="600" previewable="true" presentation="gallery">
</action-text-attachment>

<action-text-attachment sgid="BAh7CEk..."
  content-type="application/vnd.actiontext.mention"
  content="<span class=\"mention\">@Jane Doe</span>">
</action-text-attachment>
```

Permitted attributes are `ActionText::Attachment::ATTRIBUTES`: `sgid`,
`content-type`, `url`, `href`, `filename`, `filesize`, `width`, `height`,
`previewable`, `presentation`, `caption`, `content`.

Consecutive image attachments group into galleries automatically, marked with
`presentation="gallery"`. Tables are plain `<table>`/`<tr>`/`<td>`.

## Sanitization

Two independent allowlists, which is the source of a confusing failure mode.

**Server-side** governs published content. Lexxy's engine extends it, shown here
for reference:

```ruby
Rails.application.config.to_prepare do
  ActionText::ContentHelper.allowed_tags += %w[video audio source embed table tbody tr th td]
  ActionText::ContentHelper.allowed_attributes += %w[controls poster data-language style value]
  Loofah::HTML5::SafeList::ALLOWED_CSS_FUNCTIONS << "var"
end
```

**Editor-side** is DOMPurify, run over every custom attachment's `innerHtml`
before it's shown in the in-place preview. Its allowlist comes from each active
extension's `allowedElements` plus a fixed set of global attributes (`class`,
`contenteditable`, `href`, `src`, `style`, `title`).

So an attachment partial emitting `<iframe>` — Spotify, Apple Music, YouTube —
renders correctly once saved but looks broken *while editing*, because only the
server-side list permits it. Register an extension to fix the editor side, and
make sure both lists permit the tag:

```javascript
class EmbedIframeExtension extends Lexxy.Extension {
  get allowedElements() {
    return [{ tag: "iframe",
              attributes: ["width", "height", "allow", "allowfullscreen",
                           "frameborder", "loading", "sandbox"] }]
  }
}

Lexxy.configure({ global: { extensions: [EmbedIframeExtension] } })
```

Entries are either a bare tag string or `{ tag, attributes }`; the global
attributes apply on top, so `class`/`src`/`style` survive unlisted.

## Editor registry

Rails 8.2 extracts `ActionText::Editor` as a base class, decoupling ActionText
from Trix; `ActionText::TrixEditor` is the reference implementation. Lexxy
registers itself on this path:

```ruby
# lib/lexxy/engine.rb, for reference
initializer "lexxy.action_text_editor", before: "action_text.editors" do |app|
  app.config.action_text.editors[:lexxy] = {}
  app.config.action_text.editor = :lexxy
end
```

A custom editor subclasses `ActionText::Editor` and implements the two
transformations between editor HTML and stored canonical HTML. Lexxy's are
identity functions because it already emits the canonical format:

```ruby
class ActionText::Editor::LexxyEditor < ActionText::Editor
  def as_canonical(editable_fragment) = editable_fragment
  def as_editable(canonical_fragment) = canonical_fragment
end
```

`to_trix_html` is deprecated in favor of `to_editor_html`, which delegates to the
configured editor's `as_editable`.

## Extensions

```javascript
import { Extension } from "lexxy"

class MyExtension extends Extension {
  get enabled() { return true }              // false disables based on config
  get lexicalExtension() { return null }     // a Lexical extension: nodes, plugins
  get allowedElements() { return [] }        // see Sanitization
  initializeToolbar(lexxyToolbar) { }        // custom toolbar buttons
}

Lexxy.configure({ global: { extensions: [MyExtension] } })  // the class, not an instance
```

Registered automatically from config: `AttachmentsExtension`,
`HighlightExtension`, `TablesExtension`, `TrixContentExtension` (imports legacy
Trix HTML), `ProvisionalParagraphExtension`.

Lexxy also ships `ActionText::Attachables::RemoteVideo`, which resolves
`<action-text-attachment>` nodes whose content type matches `/^video/` into
YouTube/Vimeo embeds with no ActiveRecord model behind them. Define your own
attachable model instead when you need metadata or access control.

## Styling

Everything is exposed as CSS custom properties on `:root`.

| Group        | Properties                                                        |
|--------------|-------------------------------------------------------------------|
| Ink          | `--lexxy-color-ink`, `-medium`, `-light`, `-lighter`, `-lightest`, `-inverted` |
| Accent       | `--lexxy-color-accent-dark`, `-medium`, `-light`, `-lightest`     |
| Named        | `--lexxy-color-red`, `-green`, `-blue`, `-purple`                 |
| Semantic     | `--lexxy-color-canvas`, `-text`, `-text-subtle`, `-link`, `-selected`, `-code-bg` |
| Code tokens  | `--lexxy-color-code-token-att`, `-comment`, `-function`, `-operator`, `-property`, `-punctuation`, `-selector`, `-variable` |
| Tables       | `--lexxy-color-table-header-bg`, `-cell-border`, `-cell-selected`, `-cell-selected-border`, `-cell-add`, `-cell-toggle`, `-cell-remove` |
| Typography   | `--lexxy-font-base` (system-ui), `--lexxy-font-mono` (ui-monospace), `--lexxy-text-small`, `--lexxy-content-margin` |
| Editor       | `--lexxy-editor-padding`, `--lexxy-editor-rows`, `--lexxy-toolbar-gap`, `--lexxy-toolbar-spacing` |
| Misc         | `--lexxy-radius`, `--lexxy-shadow`, `--lexxy-z-popup`, `--lexxy-focus-ring-color`, `--lexxy-toolbar-button-size` |

Highlighting offers nine text colors and nine background colors, overridable:

```css
--highlight-1: rgb(136, 118, 38);   /* yellow */
--highlight-2: rgb(185, 94, 6);     /* orange */
--highlight-3: rgb(207, 0, 0);      /* red */
--highlight-4: rgb(216, 28, 170);   /* pink */
--highlight-5: rgb(144, 19, 254);   /* purple */
--highlight-6: rgb(5, 98, 185);     /* blue */
--highlight-7: rgb(17, 138, 15);    /* green */
--highlight-8: rgb(148, 82, 22);    /* brown */
--highlight-9: rgb(102, 102, 102);  /* gray */

--highlight-bg-1: rgba(229, 223, 6, 0.3);
--highlight-bg-2: rgba(255, 185, 87, 0.3);
/* ...through --highlight-bg-9 */
```

Which of them appear as toolbar buttons, and which survive a paste, is set
separately in the JS preset. Structural hooks for your own CSS: `lexxy-editor`,
`.lexxy-editor__content`, `.lexxy-editor--empty::before` (renders the
`placeholder` attribute), `.lexxy-prompt-menu`, `.lexxy-prompt-menu__item`,
`.lexxy-prompt-menu__item--selected`.

Wrap published content by overriding the ActionText content partial:

```erb
<%# app/views/layouts/action_text/contents/_content.html.erb %>
<div class="lexxy-content" data-controller="syntax-highlight">
  <%= yield -%>
</div>
```

## Syntax highlighting

```javascript
import { highlightCode } from "lexxy"  // or "@37signals/lexxy/helpers"

export default class extends Controller {
  connect() { highlightCode() }
}
```

## System testing

```ruby
def fill_in_lexxy(selector = "lexxy-editor", with:)
  editor = find(selector)
  editor.click
  editor.send_keys(with)
end
```

```ruby
test "using a slash command" do
  visit card_path(@card)
  fill_in_lexxy with: "/music"
  find(".lexxy-prompt-menu__item", text: "Never Gonna Give You Up").click

  assert_selector "action-text-attachment[content-type*='music']"
end
```

## References

- [Lexxy](https://github.com/basecamp/lexxy) · [docs](https://basecamp.github.io/lexxy)
- [ActionText guide](https://guides.rubyonrails.org/action_text_overview.html) · [edge](https://edgeguides.rubyonrails.org/action_text_overview.html)
- [Lexical](https://lexical.dev/)
