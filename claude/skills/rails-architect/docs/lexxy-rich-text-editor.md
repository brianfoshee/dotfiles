# Lexxy Rich Text Editor for ActionText

Production-proven pattern for using Lexxy instead of Trix as the rich text editor in Rails applications with ActionText.

## Overview

**Lexxy** is a Basecamp-built rich text editor that wraps Facebook's Lexical framework. It provides a modern editing experience while integrating seamlessly with Rails ActionText.

**Why Lexxy over Trix:**
- Better mobile editing experience
- Built-in autocomplete prompt system for mentions, tags, links
- Code block syntax highlighting
- More extensible architecture
- Modern JavaScript (web components)

## Setup

### Gem Installation

```ruby
# Gemfile
gem "lexxy", github: "basecamp/lexxy"
```

### JavaScript Import

```ruby
# config/importmap.rb
pin "lexxy"
pin "@rails/actiontext", to: "actiontext.esm.js"
```

```javascript
// app/javascript/application.js
import "lexxy"
import "@rails/actiontext"
```

Import both Lexxy and ActionText JS. Lexxy provides the editor, ActionText JS handles attachment uploads and blob signing.

## Model Usage

Standard ActionText declarations work unchanged:

```ruby
class Card < ApplicationRecord
  has_rich_text :description
end

class Comment < ApplicationRecord
  has_rich_text :body
end

class Board < ApplicationRecord
  has_rich_text :public_description
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
      placeholder: "Add notes, @mention people, or #reference cards..." do %>
  <%= mentions_prompt(@card.board) %>
  <%= cards_prompt %>
  <%= code_language_picker %>
<% end %>
```

## Prompt System

Lexxy's prompt system enables autocomplete triggered by specific characters. Each `<lexxy-prompt>` element defines a trigger and data source.

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

  def tags_prompt
    content_tag "lexxy-prompt", "",
      trigger: "#",
      src: prompts_tags_path,
      name: "tag"
  end

  def cards_prompt
    content_tag "lexxy-prompt", "",
      trigger: "#",
      src: prompts_cards_path,
      name: "card",
      "insert-editable-text": true,
      "remote-filtering": true,
      "supports-space-in-searches": true
  end

  def code_language_picker
    content_tag "lexxy-code-language-picker"
  end

  def general_prompts(board)
    safe_join([mentions_prompt(board), cards_prompt, code_language_picker])
  end
end
```

### Prompt Attributes

| Attribute | Description |
|-----------|-------------|
| `trigger` | Character that activates the prompt (e.g., `@`, `#`) |
| `src` | URL endpoint returning prompt items |
| `name` | Identifier for the prompt type |
| `insert-editable-text` | Insert as editable text vs attachment |
| `remote-filtering` | Server-side filtering vs client-side |
| `supports-space-in-searches` | Allow spaces in search queries |

### Prompt Endpoint Response

Return HTML with `<lexxy-prompt-item>` elements:

```erb
<%# app/views/prompts/boards/users/_user.html.erb %>
<lexxy-prompt-item
  value="<%= sgid_for(user) %>"
  label="<%= user.name %>"
  search="<%= user.name %> <%= user.email %>">
  <div class="prompt-item">
    <%= avatar_tag(user, size: :small) %>
    <span><%= user.name %></span>
  </div>
</lexxy-prompt-item>
```

```erb
<%# app/views/prompts/cards/_card.html.erb %>
<lexxy-prompt-item
  value="#<%= card.number %>"
  label="#<%= card.number %> <%= card.title %>"
  search="<%= card.number %> <%= card.title %>">
  <div class="prompt-item">
    <span class="card-number">#<%= card.number %></span>
    <span class="card-title"><%= truncate(card.title, length: 40) %></span>
  </div>
</lexxy-prompt-item>
```

### Prompt Controller

```ruby
# app/controllers/prompts/boards/users_controller.rb
class Prompts::Boards::UsersController < ApplicationController
  def index
    @users = @board.accessible_users.search(params[:query]).limit(10)
    render layout: false
  end
end
```

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
| `lexxy:change` | Content changed |
| `lexxy:focus` | Editor gained focus |
| `lexxy:blur` | Editor lost focus |
| `lexxy:ready` | Editor initialized |
| `lexxy:insert-link` | Link inserted |

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

**Validation on change:**
```erb
<%= form.rich_textarea :body,
      data: { action: "lexxy:change->form#disableSubmitWhenInvalid" } %>
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

### Accessing Event Details

Lexxy events include details in `event.detail`:

```javascript
handleChange(event) {
  const { previousContent, newContent } = event.detail
  // ...
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

**Options for callbacks:**
- `{ attachment: true }` - render as non-editable content
- `{ attachment: { sgid: "your-sgid" } }` - provide a custom SGID for ActionText

**Callbacks pattern:** Pass `event.detail` as a callbacks object to keep your async code clean:

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

      if (!response.ok) return // Fall back to plain link

      const { html, sgid } = await response.json()
      callbacks.replaceLinkWith(html, { attachment: { sgid } })
    } catch (error) {
      console.error("Unfurl failed:", error)
      // Fall back to default link behavior
    }
  }

  get csrfToken() {
    return document.querySelector("[name='csrf-token']").content
  }
}
```

**Wiring the controller:**

```erb
<%= form_with model: @post, data: { controller: "link-unfurl" } do |form| %>
  <%= form.rich_text_area :body,
        data: { action: "lexxy:insert-link->link-unfurl#handleLink" } %>
<% end %>
```

Or with controller on the editor element directly:

```erb
<%= form.rich_text_area :body,
      data: {
        controller: "link-unfurl",
        action: "lexxy:insert-link->link-unfurl#handleLink"
      } %>
```

## Syntax Highlighting

Lexxy includes syntax highlighting for code blocks. Apply it to rendered content:

```javascript
// app/javascript/controllers/syntax_highlight_controller.js
import { Controller } from "@hotwired/stimulus"
import { highlightAll } from "lexxy"

export default class extends Controller {
  connect() {
    highlightAll(this.element)
  }
}
```

```erb
<div data-controller="syntax-highlight">
  <%= @card.description %>
</div>
```

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

## Styling

### Editor Styles

```css
/* app/assets/stylesheets/lexxy.css */

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

/* Toolbar */
lexxy-toolbar {
  display: flex;
  gap: 0.25rem;
  padding: 0.5rem;
  border-bottom: 1px solid var(--border-color);
}

.lexxy-editor__toolbar-button {
  padding: 0.25rem 0.5rem;
  border: none;
  background: transparent;
  cursor: pointer;
}

.lexxy-editor__toolbar-button:hover {
  background: var(--hover-bg);
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
/* app/assets/stylesheets/rich-text-content.css */

.action-text-content {
  line-height: 1.6;
}

/* Headings */
.action-text-content h1 { font-size: 1.5rem; margin: 1.5rem 0 0.75rem; }
.action-text-content h2 { font-size: 1.25rem; margin: 1.25rem 0 0.5rem; }
.action-text-content h3 { font-size: 1.1rem; margin: 1rem 0 0.5rem; }

/* Code blocks */
.action-text-content pre {
  background: var(--code-bg);
  padding: 1rem;
  border-radius: 4px;
  overflow-x: auto;
}

.action-text-content code {
  font-family: monospace;
  font-size: 0.9em;
}

/* Attachments (mentions, embeds) */
.action-text-content action-text-attachment {
  display: inline;
}

.action-text-content action-text-attachment[content-type="mention"] {
  color: var(--link-color);
  font-weight: 500;
}
```

## HTML Sanitization

Extend allowed tags for Lexxy-generated content:

```ruby
# config/initializers/sanitization.rb
Rails::HTML5::SafeListSanitizer.allowed_tags.merge(
  %w[s table tr td th thead tbody details summary video source]
)

Rails::HTML5::SafeListSanitizer.allowed_attributes.merge(
  %w[data-turbo-frame data-lightbox-target controls type width]
)

ActionText::ContentHelper.allowed_tags =
  Rails::HTML5::SafeListSanitizer.allowed_tags.to_a +
  [ActionText::Attachment.tag_name, "figure", "figcaption"] +
  ActionText::ContentHelper.allowed_tags.to_a

ActionText::ContentHelper.allowed_attributes =
  Rails::HTML5::SafeListSanitizer.allowed_attributes.to_a +
  ActionText::Attachment::ATTRIBUTES +
  ActionText::ContentHelper.allowed_attributes.to_a
```

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
# test/system/comments_test.rb
class CommentsTest < ApplicationSystemTestCase
  test "creating a comment" do
    visit card_path(@card)

    fill_in_lexxy with: "This is my comment @david"
    click_button "Post"

    assert_text "This is my comment"
    assert_selector "action-text-attachment[content-type='mention']"
  end

  test "uploading an image" do
    visit card_path(@card)

    find("lexxy-editor").click
    attach_file "image.jpg", make_visible: true

    within "form lexxy-editor figure.attachment" do
      assert_selector "img"
    end
  end
end
```

## ActionText Configuration

Customize ActionText behavior for attachments:

```ruby
# config/initializers/action_text.rb
Rails.application.config.to_prepare do
  ActionText::RichText.class_eval do
    # Custom attachment storage
    has_many_attached :embeds do |attachable|
      attachable.variant :thumb, resize_to_limit: [200, 200]
      attachable.variant :medium, resize_to_limit: [800, 800]
    end
  end
end
```

## Content Rendering

Override the ActionText content partial:

```erb
<%# app/views/layouts/action_text/contents/_content.html.erb %>
<div class="action-text-content" data-controller="syntax-highlight">
  <%= format_html yield -%>
</div>
```

With a formatting helper:

```ruby
# app/helpers/html_helper.rb
module HtmlHelper
  def format_html(content)
    auto_link(content, html: { target: "_blank", rel: "noopener" })
  end
end
```

## Key Architectural Points

1. **Drop-in Trix replacement** - Same ActionText models, same `rich_textarea` helper
2. **Web component architecture** - `<lexxy-editor>`, `<lexxy-toolbar>`, `<lexxy-prompt>`
3. **Event-driven integration** - Custom DOM events for Stimulus controllers
4. **Prompt system for autocomplete** - Flexible trigger-based autocomplete
5. **Server-rendered prompt items** - Endpoints return HTML, not JSON
6. **Syntax highlighting built-in** - Import `highlightAll` from lexxy

## References

- [Lexxy GitHub Repository](https://github.com/basecamp/lexxy)
- [ActionText Guide](https://guides.rubyonrails.org/action_text_overview.html)
- [Lexical (underlying editor)](https://lexical.dev/)
