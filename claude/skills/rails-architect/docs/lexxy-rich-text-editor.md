# Lexxy Rich Text Editor for ActionText

Production-proven pattern for using Lexxy instead of Trix as the rich text editor in Rails applications with ActionText.

## Overview

**Lexxy** is a Basecamp-built rich text editor that wraps Meta's Lexical framework. It provides a modern editing experience while integrating seamlessly with Rails ActionText.

**Why Lexxy over Trix:**
- Better mobile editing experience
- Built-in autocomplete prompt system for mentions, tags, slash commands
- Code block syntax highlighting
- More extensible architecture (Lexical extensions)
- Modern JavaScript (web components)
- Proper HTML semantics (real `<p>` tags, not `<div>`)
- Markdown support with auto-formatting

## Setup

### Gem Installation

```ruby
# Gemfile
gem "lexxy", "~> 0.1.26.beta"
```

### JavaScript Import

**Import Maps (with Propshaft):**

```ruby
# config/importmap.rb
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"  # for attachments
```

```javascript
// app/javascript/application.js
import "lexxy"
```

**Bundlers (esbuild/webpack):**

```bash
yarn add @37signals/lexxy
yarn add @rails/activestorage
```

```javascript
import "@37signals/lexxy"
```

### CSS

```erb
<%= stylesheet_link_tag "lexxy" %>
```

### Configuration

By default, Lexxy overrides ActionText helpers. To opt out:

```ruby
# config/application.rb
config.lexxy.override_action_text_defaults = false
```

Then use explicitly: `form.lexxy_rich_text_area :content`

## Model Usage

Standard ActionText declarations work unchanged:

```ruby
class Card < ApplicationRecord
  has_rich_text :description
end

class Comment < ApplicationRecord
  has_rich_text :body
end
```

## Form Rendering

Use Rails' built-in `rich_textarea` helper. Lexxy automatically renders as a `<lexxy-editor>` web component:

```erb
<%= form_with model: @card do |form| %>
  <%= form.rich_textarea :description,
        class: "card__description rich-text-content",
        placeholder: "Add some notes..." %>
<% end %>
```

### With Prompts (Autocomplete)

Pass prompts as a block to enable autocomplete features:

```erb
<%= form.rich_textarea :description,
      placeholder: "Add notes, @mention people, or /music to add a song..." do %>
  <%= mentions_prompt(@card.board) %>
  <%= music_prompt %>
  <%= video_prompt %>
  <%= code_language_picker %>
<% end %>
```

---

## The SGID System

**SGID (Signed Global ID)** is the core mechanism linking attachments to records in ActionText.

### How It Works

```ruby
# Any model can generate an SGID
person.attachable_sgid  # => "BAh7CEkiCGdpZAY6BkVU..."

# ActionText resolves SGIDs back to records
ActionText::Attachable.from_node(node)  # Uses node["sgid"] to find record
```

The SGID is:
- A cryptographically signed identifier
- Unique to your application
- Cannot be forged
- Has a purpose string ("attachable") preventing reuse for other purposes

### Making Models Attachable

Include `ActionText::Attachable` in any model you want to embed in rich text:

```ruby
class Person < ApplicationRecord
  include ActionText::Attachable

  # Required: determines how ActionText categorizes this attachment
  def content_type
    "application/vnd.actiontext.mention"
  end

  # Optional: custom partial for rendered output
  def to_attachable_partial_path
    "people/mention"
  end

  # Optional: plain text for search/excerpts
  def attachable_plain_text_representation(caption = nil)
    "@#{name}"
  end

  # Optional: fallback when record is deleted
  def self.to_missing_attachable_partial_path
    "people/deleted_mention"
  end
end
```

---

## Prompt System

Lexxy's prompt system enables autocomplete triggered by specific strings. Each `<lexxy-prompt>` element defines a trigger and data source.

### Trigger Capabilities

**Triggers are NOT limited to single characters.** They can be any string:

| Trigger | Use Case |
|---------|----------|
| `@` | Mentions |
| `#` | Tags or card references |
| `/music` | Insert a song |
| `/video` | Insert a video |
| `/gif` | Insert a GIF |
| `by:` | Filter by assignee |

### Multiple Prompts with Different Content Types

Each `<lexxy-prompt>` is independent. You can have multiple prompts with different triggers and content types:

```erb
<%= form.rich_textarea :body do %>
  <%# Single-character trigger %>
  <lexxy-prompt trigger="@" name="mention">
    <%= render partial: "people/prompt_item", collection: Person.all %>
  </lexxy-prompt>

  <%# Multi-character slash commands %>
  <lexxy-prompt trigger="/music" name="music">
    <%= render partial: "songs/prompt_item", collection: Song.limit(50) %>
  </lexxy-prompt>

  <lexxy-prompt trigger="/video" name="video" src="<%= videos_path %>" remote-filtering>
  </lexxy-prompt>

  <lexxy-prompt trigger="/gif" name="gif" src="<%= gifs_path %>" remote-filtering supports-space-in-searches>
  </lexxy-prompt>
<% end %>
```

Each prompt generates its own content type: `application/vnd.actiontext.{name}`

### Prompt Attributes

#### `<lexxy-prompt>` Element

| Attribute | Description |
|-----------|-------------|
| `trigger` | String that activates the prompt (e.g., `@`, `/music`, `by:`) |
| `name` | Identifier determining content type (`application/vnd.actiontext.{name}`) |
| `src` | URL to load items remotely |
| `empty-results` | Message when no matches found (default: "Nothing found") |
| `remote-filtering` | Enable server-side filtering |
| `insert-editable-text` | Insert as editable text instead of attachment |
| `supports-space-in-searches` | Allow spaces in search queries |

#### `<lexxy-prompt-item>` Element

| Attribute | Description |
|-----------|-------------|
| `search` | Text to match when filtering |
| `sgid` | Signed GlobalID for the attachable (from `attachable_sgid`) |

#### `<template>` Elements

Each prompt item contains two templates:

| Type | Description |
|------|-------------|
| `type="menu"` | How item appears in dropdown |
| `type="editor"` | How item appears in editor after selection |

### Prompt Item Structure

```erb
<%# app/views/people/_prompt_item.html.erb %>
<lexxy-prompt-item
  search="<%= "#{person.name} #{person.email}" %>"
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

**Key point:** Use the same partial for `type="editor"` as you use for rendered output. This ensures consistency between how mentions look in the editor and in the final rendered content.

### Loading Strategies

#### 1. Inline (Small Datasets)

All items rendered in HTML:

```erb
<lexxy-prompt trigger="@" name="mention">
  <%= render partial: "people/prompt_item", collection: Person.all %>
</lexxy-prompt>
```

#### 2. Remote (Medium Datasets)

Items loaded once from server, filtered client-side:

```erb
<lexxy-prompt trigger="@" name="mention" src="<%= mentions_path %>">
</lexxy-prompt>
```

```ruby
# app/controllers/mentions_controller.rb
class MentionsController < ApplicationController
  def index
    @people = Person.all
    render layout: false
  end
end
```

#### 3. Remote Filtering (Large Datasets)

Server filters on each keystroke:

```erb
<lexxy-prompt trigger="@" name="mention" src="<%= mentions_path %>" remote-filtering supports-space-in-searches>
</lexxy-prompt>
```

```ruby
class MentionsController < ApplicationController
  def index
    @people = Person.search(params[:query]).limit(10)
    render layout: false
  end
end
```

### Helper Implementation

```ruby
# app/helpers/rich_text_helper.rb
module RichTextHelper
  def mentions_prompt(board)
    content_tag "lexxy-prompt", "",
      trigger: "@",
      src: prompts_board_users_path(board),
      name: "mention"
  end

  def music_prompt
    content_tag "lexxy-prompt", "",
      trigger: "/music",
      src: prompts_songs_path,
      name: "music",
      "remote-filtering": true,
      "supports-space-in-searches": true
  end

  def video_prompt
    content_tag "lexxy-prompt", "",
      trigger: "/video",
      src: prompts_videos_path,
      name: "video",
      "remote-filtering": true
  end

  def cards_prompt
    content_tag "lexxy-prompt", "",
      trigger: "#",
      src: prompts_cards_path,
      name: "card",
      "insert-editable-text": true,
      "remote-filtering": true
  end

  def code_language_picker
    content_tag "lexxy-code-language-picker"
  end
end
```

---

## Example: Music and Video Slash Commands

### Model Setup

```ruby
# app/models/song.rb
class Song < ApplicationRecord
  include ActionText::Attachable

  def content_type
    "application/vnd.actiontext.music"
  end

  def to_attachable_partial_path
    "songs/embed"
  end

  def attachable_plain_text_representation(caption = nil)
    "[#{title} by #{artist}]"
  end
end

# app/models/video.rb
class Video < ApplicationRecord
  include ActionText::Attachable

  def content_type
    "application/vnd.actiontext.video"
  end

  def to_attachable_partial_path
    "videos/embed"
  end
end
```

### Prompt Items

```erb
<%# app/views/songs/_prompt_item.html.erb %>
<lexxy-prompt-item
  search="<%= "#{song.title} #{song.artist} #{song.album}" %>"
  sgid="<%= song.attachable_sgid %>">

  <template type="menu">
    <%= image_tag song.album_art, class: "album-art" %>
    <div>
      <strong><%= song.title %></strong>
      <span><%= song.artist %></span>
    </div>
  </template>

  <template type="editor">
    <%= render "songs/embed", song: song %>
  </template>
</lexxy-prompt-item>
```

### Embed Partials

```erb
<%# app/views/songs/_embed.html.erb %>
<div class="song-embed">
  <%= image_tag song.album_art, class: "song-embed__art" %>
  <div class="song-embed__info">
    <strong><%= song.title %></strong>
    <span><%= song.artist %></span>
  </div>
</div>

<%# app/views/videos/_embed.html.erb %>
<div class="video-embed">
  <%= image_tag video.thumbnail_url, class: "video-embed__thumb" %>
  <span class="video-embed__title"><%= video.title %></span>
</div>
```

---

## Editor Events and Stimulus Integration

Lexxy dispatches custom DOM events that bubble up through the DOM. Stimulus controllers catch these events using standard `data-action` wiring.

### Wiring Pattern

**Key insight:** The Stimulus controller lives on the form, and actions are declared on the `rich_textarea`. Events bubble from the `<lexxy-editor>` up to the form where Stimulus catches them.

```erb
<%# Controller on the form, actions on the editor %>
<%= form_with model: card, data: { controller: "auto-save local-save" } do |form| %>
  <%= form.rich_textarea :description,
        data: {
          local_save_target: "input",
          action: "lexxy:change->auto-save#change
                   lexxy:change->local-save#save
                   focusout->auto-save#submit"
        } do %>
    <%= general_prompts(card.board) %>
  <% end %>
<% end %>
```

### Available Events

| Event | Description |
|-------|-------------|
| `lexxy:initialize` | Editor attached to DOM and ready |
| `lexxy:change` | Content changed |
| `lexxy:focus` | Editor gained focus |
| `lexxy:blur` | Editor lost focus |
| `lexxy:file-accept` | File dropped/inserted (call `preventDefault()` to cancel) |
| `lexxy:insert-link` | Plain text link pasted |

### Production Examples

**Auto-save on change with debounced submission:**
```erb
<%= form_with model: card, data: { controller: "auto-save" } do |form| %>
  <%= form.rich_textarea :description,
        data: { action: "lexxy:change->auto-save#change focusout->auto-save#submit" } %>
<% end %>
```

**Local storage backup with form submission:**
```erb
<%= form_with model: @card,
      data: { controller: "form local-save",
              local_save_key_value: "card-#{@card.id}",
              action: "turbo:submit-end->local-save#submit" } do |form| %>
  <%= form.rich_textarea :description,
        data: {
          local_save_target: "input",
          action: "lexxy:change->local-save#save
                   turbo:morph-element->local-save#restoreContent
                   keydown.ctrl+enter->form#submit:prevent
                   keydown.meta+enter->form#submit:prevent
                   keydown.esc->form#cancel:stop"
        } %>
<% end %>
```

### Auto-Save Controller

```javascript
// app/javascript/controllers/auto_save_controller.js
import { Controller } from "@hotwired/stimulus"
import { submitForm } from "helpers/form_helpers"

const AUTOSAVE_INTERVAL = 3000

export default class extends Controller {
  #timer

  disconnect() {
    this.submit()
  }

  submit() {
    if (this.#dirty) {
      this.#save()
    }
  }

  change(event) {
    if (event.target.form === this.element && !this.#dirty) {
      this.#scheduleSave()
    }
  }

  #scheduleSave() {
    this.#timer = setTimeout(() => this.#save(), AUTOSAVE_INTERVAL)
  }

  async #save() {
    this.#resetTimer()
    await submitForm(this.element)
  }

  #resetTimer() {
    clearTimeout(this.#timer)
    this.#timer = null
  }

  get #dirty() {
    return !!this.#timer
  }
}
```

### Local Save Controller (Draft Recovery)

```javascript
// app/javascript/controllers/local_save_controller.js
import { Controller } from "@hotwired/stimulus"
import { debounce, nextFrame } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = ["input"]
  static values = { key: String }

  initialize() {
    this.save = debounce(this.save.bind(this), 300)
  }

  connect() {
    this.restoreContent()
  }

  submit({ detail: { success } }) {
    if (success) {
      this.#clear()
    }
  }

  save() {
    const content = this.inputTarget.value
    if (content) {
      localStorage.setItem(this.keyValue, content)
    } else {
      this.#clear()
    }
  }

  async restoreContent() {
    await nextFrame()
    const savedContent = localStorage.getItem(this.keyValue)

    if (savedContent) {
      this.inputTarget.value = savedContent
      this.#triggerChangeEvent(savedContent)
    }
  }

  #clear() {
    localStorage.removeItem(this.keyValue)
  }

  #triggerChangeEvent(newValue) {
    if (this.inputTarget.tagName === "LEXXY-EDITOR") {
      this.inputTarget.dispatchEvent(new CustomEvent('lexxy:change', {
        bubbles: true,
        detail: { previousContent: '', newContent: newValue }
      }))
    }
  }
}
```

### Link Unfurling with `lexxy:insert-link`

Fired when a plain text link is pasted into the editor. Use this to convert URLs into rich embeds.

**`event.detail` contains:**

| Property | Description |
|----------|-------------|
| `url` | The pasted URL |
| `replaceLinkWith(html, options)` | Replace the link with custom HTML |
| `insertBelowLink(html, options)` | Insert HTML below the link |

**Options:**
- `{ attachment: true }` - render as non-editable content
- `{ attachment: { sgid: "your-sgid" } }` - provide a custom SGID

```javascript
// app/javascript/controllers/link_unfurl_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleLink(event) {
    const { url, ...callbacks } = event.detail

    if (this.isMusicUrl(url)) {
      this.unfurlMusic(url, callbacks)
    }
    // Non-matching URLs fall through to default link behavior
  }

  isMusicUrl(url) {
    return url.includes("open.spotify.com") || url.includes("music.apple.com")
  }

  async unfurlMusic(url, callbacks) {
    try {
      const response = await fetch("/songs/unfurl", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ url })
      })

      if (!response.ok) return

      const { html, sgid } = await response.json()
      callbacks.replaceLinkWith(html, { attachment: { sgid } })
    } catch (error) {
      console.error("Unfurl failed:", error)
    }
  }

  get csrfToken() {
    return document.querySelector("[name='csrf-token']").content
  }
}
```

```erb
<%= form_with model: @post, data: { controller: "link-unfurl" } do |form| %>
  <%= form.rich_text_area :body,
        data: { action: "lexxy:insert-link->link-unfurl#handleLink" } %>
<% end %>
```

---

## Syntax Highlighting

Lexxy includes syntax highlighting for code blocks. Apply it to rendered content:

```javascript
// app/javascript/controllers/syntax_highlight_controller.js
import { Controller } from "@hotwired/stimulus"
import { highlightCode } from "lexxy"
// Or: import { highlightCode } from "@37signals/lexxy/helpers"

export default class extends Controller {
  connect() {
    highlightCode()
  }
}
```

```erb
<div data-controller="syntax-highlight">
  <%= @card.description %>
</div>
```

---

## JavaScript Configuration

```javascript
import * as Lexxy from "lexxy"

Lexxy.configure({
  global: {
    // Must match ActionText's tag name
    attachmentTagName: "action-text-attachment",

    // Namespace for content types (application/vnd.{namespace}.{name})
    attachmentContentTypeNamespace: "actiontext",

    // For authenticated Active Storage controllers
    authenticatedUploads: false,

    // Custom extensions
    extensions: []
  },

  // Default preset for all editors
  default: {
    toolbar: true,
    attachments: true,
    markdown: true,
    multiLine: true,
    richText: true
  },

  // Custom presets
  simple: {
    toolbar: false,
    richText: false
  },

  comment: {
    toolbar: true,
    attachments: false,
    multiLine: true
  }
})
```

Use presets:

```html
<lexxy-editor preset="simple"></lexxy-editor>
```

---

## Custom Upload Handling (Image Models)

By default, file uploads create Active Storage blobs. You can intercept uploads to create custom models (e.g., an `Image` model) instead.

### The Problem

When a user uploads an image to a Lexxy editor:
1. File uploads via Active Storage Direct Upload
2. Creates an `ActiveStorage::Blob`
3. Attachment references the blob's SGID

But you might want uploads to create your own `Image` model for:
- Custom metadata (dimensions, EXIF, alt text)
- Access control
- Processing pipelines
- Analytics/tracking

### Solution: Custom Upload Endpoint

Override `data-direct-upload-url` to point to your own endpoint:

```erb
<%= form.rich_textarea :body,
      data: {
        direct_upload_url: images_upload_path,
        blob_url_template: rails_blob_url(":signed_id", ":filename")
      } %>
```

### Image Model

```ruby
# app/models/image.rb
class Image < ApplicationRecord
  include ActionText::Attachable

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { Current.account }

  has_one_attached :file

  def content_type
    "application/vnd.actiontext.image"
  end

  def previewable_attachable?
    true
  end

  def to_attachable_partial_path
    "images/embed"
  end

  def attachable_plain_text_representation(caption = nil)
    "[Image: #{caption || file.filename}]"
  end
end
```

### Upload Controller

Your endpoint receives the file via Active Storage Direct Upload protocol and returns JSON that Lexxy expects:

```ruby
# app/controllers/images_controller.rb
class ImagesController < ApplicationController
  def upload
    # Create blob from Direct Upload
    blob = ActiveStorage::Blob.create_and_upload!(
      io: request.body,
      filename: request.headers["X-Upload-Filename"] || "upload",
      content_type: request.headers["Content-Type"]
    )

    # Create your Image model
    image = Image.create!(file: blob)

    # Return response in the shape Lexxy expects
    render json: {
      attachable_sgid: image.attachable_sgid,  # Image's SGID, not blob's
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      previewable: image.previewable_attachable?,
      url: url_for(image.file.variant(resize_to_limit: [1024, 1024]))
    }
  end
end
```

### Response Shape

Lexxy's upload handler expects this JSON structure:

```javascript
{
  attachable_sgid: "BAh7CEk...",  // Can be ANY model's SGID
  filename: "photo.jpg",
  content_type: "image/jpeg",
  byte_size: 123456,
  previewable: true,
  url: "https://..."  // Preview URL for editor display
}
```

As long as your endpoint returns this shape, Lexxy doesn't care if it's a blob or your custom model. The `attachable_sgid` determines what gets embedded.

### Embed Partial

```erb
<%# app/views/images/_embed.html.erb %>
<figure class="image-embed">
  <%= image_tag image.file.variant(resize_to_limit: [800, 600]),
        alt: image.alt_text,
        loading: "lazy" %>
  <% if image.caption.present? %>
    <figcaption><%= image.caption %></figcaption>
  <% end %>
</figure>
```

### Alternative: Intercept with `lexxy:file-accept`

For more control, intercept uploads before they start:

```javascript
// app/javascript/controllers/image_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  intercept(event) {
    const file = event.detail.file

    // Only intercept images, let other files use default upload
    if (!file.type.startsWith("image/")) return

    // Optionally validate
    if (file.size > 10 * 1024 * 1024) {
      event.preventDefault()
      alert("Image must be under 10MB")
      return
    }

    // Let default upload proceed (to your custom endpoint)
    // Or preventDefault() and handle entirely custom
  }
}
```

```erb
<%= form_with model: @post, data: { controller: "image-upload" } do |form| %>
  <%= form.rich_textarea :body,
        data: {
          action: "lexxy:file-accept->image-upload#intercept",
          direct_upload_url: images_upload_path
        } %>
<% end %>
```

### When to Use Each Approach

| Approach | Use When |
|----------|----------|
| Custom upload endpoint | You want all uploads to create custom models |
| `lexxy:file-accept` + custom endpoint | You want to validate/filter before upload |
| `lexxy:file-accept` + `preventDefault()` | You need completely custom upload handling |

---

## Canonical HTML Format

Lexxy generates the same HTML format ActionText expects:

### File Attachments

```html
<action-text-attachment
  sgid="BAh7CEk..."
  content-type="image/jpeg"
  url="https://example.com/rails/active_storage/blobs/abc123/photo.jpg"
  filename="photo.jpg"
  filesize="123456"
  width="800"
  height="600"
  previewable="true"
  presentation="gallery">
</action-text-attachment>
```

### Custom Attachables (Mentions)

```html
<action-text-attachment
  sgid="BAh7CEk..."
  content-type="application/vnd.actiontext.mention"
  content="<span class=\"mention\">@Jane Doe</span>">
</action-text-attachment>
```

### Allowed Attributes

```ruby
ActionText::Attachment::ATTRIBUTES = %w(
  sgid content-type url href filename filesize
  width height previewable presentation caption content
)
```

---

## HTML Sanitization

Extend allowed tags for Lexxy-generated content:

```ruby
# config/initializers/lexxy.rb
# Lexxy's engine adds these automatically, but for reference:

Rails.application.config.to_prepare do
  # Additional tags Lexxy supports
  ActionText::ContentHelper.allowed_tags += %w[
    video audio source embed table tbody tr th td
  ]

  # Additional attributes
  ActionText::ContentHelper.allowed_attributes += %w[
    controls poster data-language style
  ]

  # CSS variables support
  Loofah::HTML5::SafeList::ALLOWED_CSS_FUNCTIONS << "var"
end
```

---

## Content Rendering

Override the ActionText content partial:

```erb
<%# app/views/layouts/action_text/contents/_content.html.erb %>
<div class="lexxy-content" data-controller="syntax-highlight">
  <%= yield -%>
</div>
```

---

## Styling

### Editor Styles

```css
/* Editor container */
lexxy-editor {
  display: block;
  min-height: 150px;
  border: 1px solid var(--border-color);
  border-radius: 4px;
}

/* Editor content area */
.lexxy-editor__content {
  padding: 1rem;
  outline: none;
}

/* Empty state placeholder */
.lexxy-editor--empty::before {
  content: attr(placeholder);
  color: var(--placeholder-color);
  pointer-events: none;
}

/* Prompt menu */
.lexxy-prompt-menu {
  position: absolute;
  background: white;
  border: 1px solid var(--border-color);
  border-radius: 4px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  max-height: 300px;
  overflow-y: auto;
}

.lexxy-prompt-menu__item {
  padding: 0.5rem 1rem;
  cursor: pointer;
}

.lexxy-prompt-menu__item:hover,
.lexxy-prompt-menu__item--selected {
  background: var(--hover-bg);
}
```

### Rendered Content Styles

```css
.lexxy-content {
  line-height: 1.6;
}

/* Code blocks */
.lexxy-content pre {
  background: var(--code-bg);
  padding: 1rem;
  border-radius: 4px;
  overflow-x: auto;
}

/* Attachments (mentions, embeds) */
.lexxy-content action-text-attachment {
  display: inline;
}

.lexxy-content action-text-attachment[content-type*="mention"] {
  color: var(--link-color);
  font-weight: 500;
}
```

---

## System Testing

### Fill Helper

```ruby
# test/application_system_test_case.rb
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  def fill_in_lexxy(selector = "lexxy-editor", with:)
    editor = find(selector)
    editor.click
    editor.send_keys(with)
  end
end
```

### Test Example

```ruby
class CommentsTest < ApplicationSystemTestCase
  test "creating a comment with mention" do
    visit card_path(@card)

    fill_in_lexxy with: "This is my comment @david"
    click_button "Post"

    assert_text "This is my comment"
    assert_selector "action-text-attachment[content-type*='mention']"
  end

  test "using slash command" do
    visit card_path(@card)

    fill_in_lexxy with: "/music"
    # Select from prompt menu
    find(".lexxy-prompt-menu__item", text: "Never Gonna Give You Up").click

    assert_selector "action-text-attachment[content-type*='music']"
  end
end
```

---

## Hotkey Handling

When implementing global hotkeys, check if the user is typing in a Lexxy editor:

```javascript
// app/javascript/controllers/hotkey_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleHotkey(event) {
    // Ignore hotkeys when typing in editor
    if (event.target.closest("lexxy-editor")) {
      return
    }

    // Handle hotkey...
  }
}
```

---

## Rails Main: Editor Registry (Future)

Rails main now has a pluggable editor system. This is the future integration path for Lexxy.

### Editor Interface

```ruby
class ActionText::Editor::LexxyEditor < ActionText::Editor
  # Convert editor HTML → canonical ActionText format
  def as_canonical(editable_fragment)
    # Lexxy already outputs canonical format, so this is a no-op
    editable_fragment
  end

  # Convert canonical format → editor HTML
  def as_editable(canonical_fragment)
    # Also a no-op since Lexxy uses the same format
    canonical_fragment
  end
end
```

### Future Configuration (Speculative)

```ruby
# config/application.rb
config.action_text.editors = {
  lexxy: { some_option: true }
}

# Per-model selection
class Article < ApplicationRecord
  has_rich_text :content, editor: :lexxy
end
```

---

## Key Architectural Points

1. **Drop-in Trix replacement** - Same ActionText models, same `rich_textarea` helper
2. **Web component architecture** - `<lexxy-editor>`, `<lexxy-toolbar>`, `<lexxy-prompt>`
3. **SGID-based attachments** - Secure, signed references to any ActiveRecord model
4. **Multi-character triggers** - Not limited to single characters (`/music`, `/video`, etc.)
5. **Multiple prompts** - Each prompt is independent with its own content type
6. **Event-driven integration** - Custom DOM events for Stimulus controllers
7. **Server-rendered prompt items** - Endpoints return HTML partials, not JSON
8. **Canonical HTML format** - Lexxy outputs the same format ActionText expects

---

## References

- [Lexxy GitHub Repository](https://github.com/basecamp/lexxy)
- [Lexxy Documentation](https://basecamp.github.io/lexxy)
- [ActionText Guide](https://guides.rubyonrails.org/action_text_overview.html)
- [ActionText Edge Guide](https://edgeguides.rubyonrails.org/action_text_overview.html)
- [Lexical (underlying editor)](https://lexical.dev/)
