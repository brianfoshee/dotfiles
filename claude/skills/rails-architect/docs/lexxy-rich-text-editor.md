# Lexxy Rich Text Editor for ActionText

Production-proven pattern for using Lexxy instead of Trix as the rich text editor in Rails applications with ActionText.

## Overview

**Lexxy** is a Basecamp-built rich text editor that wraps Meta's Lexical framework. It provides a modern editing experience while integrating seamlessly with Rails ActionText.

**Why Lexxy over Trix:**
- Better mobile editing experience
- Built-in autocomplete prompt system for mentions, tags, slash commands
- Code block syntax highlighting
- More extensible architecture (Lexical extensions)
- Modern JavaScript (form-associated web component with native validation)
- Proper HTML semantics (real `<p>` tags, not `<div>`)
- Markdown support with auto-formatting on paste
- Tables (insert, edit rows/columns, headers)
- Text highlighting (9 text colors + 9 background colors)
- Image galleries (consecutive images grouped automatically)
- Trix content backward compatibility (imports existing Trix HTML)

## Setup

### Gem Installation

```ruby
# Gemfile
gem "lexxy", "~> 0.9.0.beta"  # still beta at time of writing
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

Lexxy integrates with ActionText via one of two paths depending on the Rails version it detects at load time:

**Rails 8.2+ (adapter path).** Lexxy auto-registers itself as the ActionText editor adapter via `config.action_text.editor = :lexxy` (shipped in 0.9.5+). The standard `form.rich_textarea` / `form.rich_text_area` helpers emit `<lexxy-editor>` directly through the `ActionText::Editor` interface. No override flag exists on this path. To opt out for a specific model, set a different registered adapter:

```ruby
class Article < ApplicationRecord
  has_rich_text :content, editor: :trix
end
```

Or globally in `config/application.rb`:

```ruby
config.action_text.editor = :trix
```

**Rails 8.0/8.1 (monkey-patch fallback).** Lexxy prepends modules onto the ActionText tag helpers to override `rich_textarea` / `rich_text_area`. To opt out and call the lexxy-specific helpers explicitly instead:

```ruby
# config/application.rb
config.lexxy.override_action_text_defaults = false
```

Then use: `form.lexxy_rich_text_area :content`

`Lexxy.supports_editor_adapter?` (in `lib/lexxy.rb`) is the switch — it returns true when `ActionText::Editor#editor_tag` accepts a block (rails/rails#56926), which is the signal that the app is on the adapter path.

### Editor Attributes

`<lexxy-editor>` is a form-associated custom element. Key HTML attributes:

| Attribute | Description |
|-----------|-------------|
| `preset` | Named configuration preset (default: `"default"`) |
| `placeholder` | Placeholder text |
| `single-line` | Single-line mode (suppresses Enter) |
| `autofocus` | Auto-focus on mount |
| `required` | Native form validation |
| `rows` | Editor height in line-height units (default: `8`) |
| `name` | Form field name |
| `value` | Initial HTML content |

```erb
<%= form.rich_textarea :title,
      "single-line": true,
      placeholder: "Card title",
      required: true,
      rows: 2 %>
```

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
| `lexxy:upload-start` | Upload began |
| `lexxy:upload-progress` | Upload progress update |
| `lexxy:upload-end` | Upload completed |
| `lexxy:insert-link` | Plain text link pasted |
| `lexxy:insert-markdown` | Markdown content pasted |

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
          "Content-Type": "application/json"
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
    richText: true,
    highlight: {
      buttons: {
        color: [1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => `var(--highlight-${n})`),
        "background-color": [1, 2, 3, 4, 5, 6, 7, 8, 9].map(n => `var(--highlight-bg-${n})`)
      },
      permit: {
        color: [],              // additional colors allowed on paste
        "background-color": []  // additional bg colors allowed on paste
      }
    }
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
    controls poster data-language style value
  ]

  # CSS variables support
  Loofah::HTML5::SafeList::ALLOWED_CSS_FUNCTIONS << "var"
end
```

### Editor-Side Sanitization (DOMPurify)

**This is separate from the server-side Action Text sanitizer above.** Since 0.9.4, Lexxy runs DOMPurify over the `innerHtml` of every custom attachment before inserting it into the editor's in-place preview. 0.9.7 further tightened this pass. The client allowlist is built from each active extension's `allowedElements` getter plus a small set of globally-permitted attributes (`class`, `contenteditable`, `href`, `src`, `style`, `title`).

The practical consequence: if your custom attachment partial emits tags beyond the common block/inline set — most commonly `<iframe>` for Spotify / Apple Music / YouTube embeds — they'll be stripped in the *editor preview* even though the *saved/published* HTML is intact (because that goes through the server-side `ActionText::ContentHelper` allowlist, which is independent). Symptom: the attachment appears to render correctly after saving but looks broken or empty while editing.

Extend the editor-side allowlist by registering a Lexxy extension:

```javascript
// app/javascript/application.js
import * as Lexxy from "lexxy"

class EmbedIframeExtension extends Lexxy.Extension {
  get allowedElements() {
    return [
      {
        tag: "iframe",
        attributes: [
          "width", "height", "allow", "allowfullscreen",
          "frameborder", "loading", "sandbox"
        ]
      }
    ]
  }
}

Lexxy.configure({ global: { extensions: [EmbedIframeExtension] } })
```

`allowedElements` entries can be either a bare tag name string (just allowed, no extra per-tag attributes) or `{ tag, attributes }` objects. The globally-permitted attributes still apply on top, so `class`/`src`/`style` survive without being listed per tag.

Make sure the server-side allowlist in `config/initializers/lexxy.rb` (or equivalent) *also* permits the tag, or published content will silently drop it.

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

## Pluggable Editor Registry

Rails 8.2 extracts `ActionText::Editor` as a base class, decoupling ActionText from Trix. `ActionText::TrixEditor` is the built-in reference implementation.

Lexxy 0.9.5+ registers itself automatically on this path:

```ruby
# lib/lexxy/engine.rb (in Lexxy, for reference)
initializer "lexxy.action_text_editor", before: "action_text.editors" do |app|
  app.config.action_text.editors[:lexxy] = {}
  app.config.action_text.editor = :lexxy
end
```

So on Rails 8.2+ with lexxy installed, every `has_rich_text` field uses Lexxy by default. To use a different editor (globally or per-model), set `config.action_text.editor` or pass `editor:` on the model declaration. To confirm the current state at runtime: `Rails.application.config.action_text.editor`.

### Editor Interface

Custom editors subclass `ActionText::Editor` and implement two transformation methods:

```ruby
class ActionText::Editor::LexxyEditor < ActionText::Editor
  # Convert editor HTML → canonical ActionText storage format
  def as_canonical(editable_fragment)
    editable_fragment  # Lexxy already outputs canonical format
  end

  # Convert canonical format → editor-specific HTML for editing
  def as_editable(canonical_fragment)
    canonical_fragment  # Lexxy uses the same format
  end
end
```

### Per-Model Editor Selection

```ruby
class Article < ApplicationRecord
  has_rich_text :content, editor: :lexxy
end
```

### Deprecation Note

`to_trix_html` is deprecated in favor of `to_editor_html`, which delegates to the configured editor's `as_editable` method.

## Tables

Tables are rendered as standard HTML (`<table>`, `<tr>`, `<td>`) and stored in ActionText content. The toolbar inserts a 3x3 table with header row. Users can add/remove rows and columns, toggle header cells, and select cells. Add `table`, `tbody`, `tr`, `th`, `td` to your sanitizer's allowed tags (Lexxy's engine does this automatically).

## Image Galleries

Consecutive image attachments are automatically grouped into galleries. Gallery images use the `presentation="gallery"` attribute in the canonical HTML.

## Text Highlighting

Text highlighting supports 9 text colors and 9 background colors, configurable via CSS custom properties:

```css
/* Text colors: --highlight-1 through --highlight-9 */
--highlight-1: rgb(136, 118, 38);   /* yellow */
--highlight-2: rgb(185, 94, 6);     /* orange */
--highlight-3: rgb(207, 0, 0);      /* red */
--highlight-4: rgb(216, 28, 170);   /* pink */
--highlight-5: rgb(144, 19, 254);   /* purple */
--highlight-6: rgb(5, 98, 185);     /* blue */
--highlight-7: rgb(17, 138, 15);    /* green */
--highlight-8: rgb(148, 82, 22);    /* brown */
--highlight-9: rgb(102, 102, 102);  /* gray */

/* Background colors: --highlight-bg-1 through --highlight-bg-9 */
--highlight-bg-1: rgba(229, 223, 6, 0.3);   /* yellow */
--highlight-bg-2: rgba(255, 185, 87, 0.3);  /* orange */
/* ... same pattern through --highlight-bg-9 */
```

Override these in your stylesheet to change the available highlight palette. The toolbar buttons and permitted-on-paste colors are configured separately in the JS preset (see JavaScript Configuration above).

## CSS Custom Properties

Lexxy exposes all styling through CSS custom properties on `:root`. Key groups:

| Group | Properties |
|-------|-----------|
| **Ink** | `--lexxy-color-ink`, `-medium`, `-light`, `-lighter`, `-lightest`, `-inverted` |
| **Accent** | `--lexxy-color-accent-dark`, `-medium`, `-light`, `-lightest` |
| **Named** | `--lexxy-color-red`, `-green`, `-blue`, `-purple` |
| **Semantic** | `--lexxy-color-canvas`, `-text`, `-text-subtle`, `-link`, `-selected`, `-code-bg` |
| **Code tokens** | `--lexxy-color-code-token-att`, `-comment`, `-function`, `-operator`, `-property`, `-punctuation`, `-selector`, `-variable` |
| **Tables** | `--lexxy-color-table-header-bg`, `-cell-border`, `-cell-selected`, `-cell-selected-border`, `-cell-add`, `-cell-toggle`, `-cell-remove` |
| **Typography** | `--lexxy-font-base` (system-ui), `--lexxy-font-mono` (ui-monospace), `--lexxy-text-small`, `--lexxy-content-margin` |
| **Editor** | `--lexxy-editor-padding`, `--lexxy-editor-rows`, `--lexxy-toolbar-gap`, `--lexxy-toolbar-spacing` |
| **Misc** | `--lexxy-radius`, `--lexxy-shadow`, `--lexxy-z-popup`, `--lexxy-focus-ring-color`, `--lexxy-toolbar-button-size` |

## Extension System

Extensions add custom editor behavior. Subclass `Extension` (exported as `LexxyExtension` internally):

```javascript
import { Extension } from "lexxy"

class MyExtension extends Extension {
  // Return false to disable based on editor config
  get enabled() {
    return true
  }

  // Return a Lexical extension (nodes, plugins, etc.)
  get lexicalExtension() {
    return null
  }

  // Contribute tags/attributes to the editor's DOMPurify allowlist.
  // Each entry is either a bare tag string or { tag, attributes }.
  // See "Editor-Side Sanitization" under HTML Sanitization above.
  get allowedElements() {
    return [
      { tag: "iframe", attributes: ["width", "height", "allow", "allowfullscreen", "frameborder", "loading", "sandbox"] }
    ]
  }

  // Add custom toolbar buttons
  initializeToolbar(lexxyToolbar) {
  }
}

Lexxy.configure({
  global: {
    extensions: [MyExtension]  // pass the class, not an instance
  }
})
```

Built-in extensions (registered automatically based on config):
- `AttachmentsExtension` — file/image upload and attachment handling
- `HighlightExtension` — text and background color highlighting
- `TablesExtension` — table insertion and editing
- `TrixContentExtension` — backward-compatible import of existing Trix HTML
- `ProvisionalParagraphExtension` — placeholder paragraph management

## Remote Video Attachable

Lexxy includes a built-in `ActionText::Attachables::RemoteVideo` class for embedding remote videos (YouTube, Vimeo) without an ActiveRecord model. It resolves from `<action-text-attachment>` nodes with a video content type and URL:

```ruby
# Built-in: lib/action_text/attachables/remote_video.rb
# Automatically resolves from nodes with content-type matching /^video/
# Attributes: url, content_type, width, height, filename
# Renders via: action_text/attachables/_remote_video partial
```

For custom metadata or access control, create your own model instead:

```ruby
class RemoteVideo < ApplicationRecord
  include ActionText::Attachable

  validates :url, presence: true

  def content_type
    "application/vnd.actiontext.video"
  end

  def to_attachable_partial_path
    "remote_videos/embed"
  end

  def attachable_plain_text_representation(caption = nil)
    "[Video: #{caption || url}]"
  end
end
```

Use with a `/video` prompt trigger or link unfurling via `lexxy:insert-link`.

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
