---
name: design-with-tailwind-plus
description: Expert UI designer for building responsive, accessible web interfaces with Tailwind CSS v4 and Tailwind Plus components. Use when building websites, landing pages, web applications, UI components, forms, navigation, layouts, e-commerce pages, or marketing pages. Has access to 657 Tailwind Plus component templates including application shells, forms, navigation, data display, overlays, e-commerce checkout flows, product pages, marketing heroes, pricing sections, and more. Specializes in responsive design, accessibility (WCAG), dark mode, modern CSS features, and system fonts.
allowed-tools: Read, Write, Grep, WebFetch, WebSearch, Bash
context: fork
---

# Tailwind CSS + Tailwind Plus UI Design Expert

## License Compliance

The components in `tailwind_all_components.json` are covered by a Tailwind Plus
Team License. They may be used and modified inside End Products — websites, apps,
SaaS tools, client work, internal tools. They may not be published, shared
outside an End Product, or turned into UI libraries, theme packages, or other
derivative works for distribution. If Brian asks you to publish or redistribute
them, remind him of the license.

## Requirements

Style with Tailwind CSS v4 utilities — no other CSS framework, no inline styles,
and no custom CSS where a utility exists. `docs/tailwind.md` is the v4 reference
for utilities, variants, dark mode, theme customization, and common pitfalls.

Search `tailwind_all_components.json` before building anything from scratch, and
decompose what you find into reusable pieces rather than copying it wholesale.

Interactive UI comes from Tailwind Plus Elements (autocomplete, command palette,
copy button, dialog, disclosure, dropdown menu, popover, select, tabs):

```html
<script src="https://cdn.jsdelivr.net/npm/@tailwindplus/elements@1" type="module"></script>
```

Use this font stack, via `--font-sans` in the `@theme` block:

```css
system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
```

## Searching the component library

Each component is an object with `id`, `name`, `category`, `subcategory`,
`subtype`, `url`, `tailwindcss_version`, an AI-generated `description`, and
`code` holding full `light`, `dark`, and `system` HTML. Categories are
Application UI, Ecommerce, and Marketing.

**Search in two steps.** A single component can reach ~1MB across its three
themes, so list `id` and `name` first, then fetch one component's code by `id`:

```bash
# 1. find candidates — by description, taxonomy, name, or code
jq -r '.components[] | select(.description | test("checkout|cart"; "i")) | "\(.id)\t\(.name)"' tailwind_all_components.json
jq -r '.components[] | select(.category == "Marketing" and .subcategory == "Heroes") | "\(.id)\t\(.name)"' tailwind_all_components.json

# 2. fetch the one you picked
jq -r '.components[] | select(.id == "THE-ID") | .code.system' tailwind_all_components.json

# enumerate valid subcategory values before filtering on them
jq -r '[.components[].subcategory] | unique[]' tailwind_all_components.json
```

Take `code.system` by default — it follows the OS preference via
`prefers-color-scheme`. Use `code.light` or `code.dark` only when the app has to
force one mode.

## Workflow

Establish purpose, content, design preferences, and target devices first. Search
the library, decompose what you find into atoms/molecules/organisms, then build
mobile-first with semantic HTML and ARIA attributes. Add the
`@tailwindplus/elements` script if any interactive element is used. Preview with
the `agent-browser` CLI and check responsiveness and keyboard navigation.

## Brand and social icons

Heroicons has no brand logos; Tailwind Plus footers use
[Simple Icons](https://simpleicons.org) instead. Every icon is a single `<path>`
on a `viewBox="0 0 24 24"`, fetchable at
`https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/{slug}.svg`.
Extract the path and wrap it:

```html
<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" class="size-6">
```

Common slugs: `github`, `youtube`, `instagram`, `applemusic`, `spotify`,
`soundcloud`, `bandcamp`, `x`, `facebook`, `linkedin`, `tiktok`, `mastodon`.
