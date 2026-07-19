# Tailwind CSS v4 Reference

A working reference for Tailwind CSS v4: CSS-first configuration, directives, variants, and the utilities most likely to be missed. For version-specific currency, see https://github.com/tailwindlabs/tailwindcss/releases and https://tailwindcss.com/docs.

## Table of Contents
- [Installation](#installation)
- [Arbitrary Values and Escapes](#arbitrary-values-and-escapes)
- [Responsive Design](#responsive-design)
- [Container Queries](#container-queries)
- [State Variants](#state-variants)
- [Dark Mode](#dark-mode)
- [CSS-First Customization](#css-first-customization)
- [Directives](#directives)
- [Functions](#functions)
- [Additional Utilities](#additional-utilities)
- [Colors](#colors)
- [Quick Reference](#quick-reference)
- [Common Pitfalls](#common-pitfalls)
- [Accessibility](#accessibility)
- [Resources](#resources)

---

## Installation

Requires Node.js 20 or higher. Tailwind v4 ships as separate packages per build system:

- `tailwindcss` — core
- `@tailwindcss/vite` — Vite plugin
- `@tailwindcss/postcss` — PostCSS plugin (in v3 the `tailwindcss` package itself was the PostCSS plugin; that moved here)
- `@tailwindcss/cli` — standalone CLI

**Vite (recommended):**
```typescript
// vite.config.ts
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [tailwindcss()],
})
```

Then import Tailwind in your main CSS file — this single line replaces v3's `@tailwind base/components/utilities`:
```css
@import "tailwindcss";
```

**PostCSS** uses `@tailwindcss/postcss` in `postcss.config.js`; **CLI** runs `npx @tailwindcss/cli -i input.css -o output.css --watch`.

**Play CDN (prototyping only):**
```html
<script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
```
NEVER use `cdn.tailwindcss.com` — it only serves Tailwind v3.

---

## Arbitrary Values and Escapes

When the theme lacks a value, use square-bracket notation (use sparingly — see [Common Pitfalls](#common-pitfalls)):

```html
<div class="bg-[#316ff6]">                          <!-- arbitrary value -->
<div class="top-[117px] grid-cols-[24rem_2.5rem_minmax(0,1fr)]">
<div class="[mask-type:luminance] hover:[mask-type:alpha]"> <!-- arbitrary property -->
<div class="[&:nth-child(3)]:py-0 [&_p]:mt-4">      <!-- arbitrary variant -->
<div class="[@media(width>=800px)]:text-center">   <!-- arbitrary media query -->
```

Reference a CSS variable as a value with parentheses (shorthand for `[var(--...)]`):
```html
<div class="bg-(--brand) w-(--sidebar-width)">
```

**Escaping:** underscores become spaces (`content-['Hello_World']`); backslash-escape special characters (`content-['\2022']`).

---

## Responsive Design

Tailwind is **mobile-first**: unprefixed utilities apply at all sizes; a breakpoint prefix applies at that width **and up**. Write base styles unprefixed and layer larger breakpoints on top — never use `sm:` to mean "mobile."

| Prefix | Min width | Media query |
|--------|-----------|-------------|
| `sm` | 40rem (640px) | `@media (width >= 40rem)` |
| `md` | 48rem (768px) | `@media (width >= 48rem)` |
| `lg` | 64rem (1024px) | `@media (width >= 64rem)` |
| `xl` | 80rem (1280px) | `@media (width >= 80rem)` |
| `2xl` | 96rem (1536px) | `@media (width >= 96rem)` |

```html
<img class="w-16 md:w-32 lg:w-48">
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
<div class="flex flex-col md:flex-row">
```

**Breakpoint ranges** — combine with `max-*` to bound on both sides:
```html
<div class="md:max-xl:flex">          <!-- md through xl only -->
<div class="block lg:max-2xl:hidden">  <!-- hidden lg to 2xl -->
```

**One-off breakpoints:**
```html
<div class="max-[600px]:bg-sky-300 min-[320px]:text-center">
```

Custom named breakpoints are defined in `@theme` — see [CSS-First Customization](#css-first-customization).

---

## Container Queries

Style elements by their **container's** size rather than the viewport. Mark an ancestor `@container`, then use `@`-prefixed variants on descendants:

```html
<div class="@container">
  <div class="@md:flex @lg:text-xl @2xl:text-3xl">Responsive to container</div>
</div>
```

| Variant | Min width | | Variant | Min width |
|---------|-----------|---|---------|-----------|
| `@3xs` | 16rem (256px) | | `@xl` | 36rem (576px) |
| `@2xs` | 18rem (288px) | | `@2xl` | 42rem (672px) |
| `@xs` | 20rem (320px) | | `@3xl` | 48rem (768px) |
| `@sm` | 24rem (384px) | | `@4xl` | 56rem (896px) |
| `@md` | 28rem (448px) | | `@5xl` | 64rem (1024px) |
| `@lg` | 32rem (512px) | | `@6xl` | 72rem (1152px) |
|  |  | | `@7xl` | 80rem (1280px) |

Use `@max-md:` for max-width container queries, and name containers to target a specific ancestor:
```html
<div class="@container/main">
  <div class="@lg/main:text-xl">
```

`@container` establishes an inline-size container. Use `@container-size` when children need block-direction container units (`cqb`, `cqh`).

---

## State Variants

Variants prefix a utility to apply it conditionally. Stack them (read right-to-left: `dark:md:hover:bg-blue-500` = hover, at `md`+, in dark mode).

**Interactive:** `hover:` `active:` `focus:` `focus-visible:` `focus-within:`
```html
<button class="bg-violet-500 hover:bg-violet-600 active:bg-violet-700">
<button class="focus:outline-none focus-visible:ring-2">
```
Prefer `focus-visible:` over `focus:` for keyboard focus rings so they don't show on mouse clicks.

**Form:** `disabled:` `required:` `invalid:` `valid:` `checked:` `indeterminate:` `read-only:` `placeholder-shown:` — plus `user-valid:` / `user-invalid:` which apply validation styling only after the user has interacted.
```html
<input class="disabled:opacity-50 invalid:border-pink-500 user-invalid:border-red-500">
<input type="checkbox" class="checked:bg-blue-500 indeterminate:bg-gray-300">
```

**Structural:** `first:` `last:` `odd:` `even:` `empty:` `only:` `nth-[3]:` `nth-last-[2]:`
```html
<tr class="odd:bg-white even:bg-gray-50">
<div class="empty:hidden">
```

**Group and peer** — style based on a parent or previous sibling's state. Mark the parent `group` (or a sibling `peer`), then use `group-*` / `peer-*`. Only *previous* siblings work with `peer` (CSS can't select earlier elements). Name them (`group/card`, `peer/email`) to disambiguate when nested:
```html
<a href="#" class="group">
  <svg class="stroke-sky-500 group-hover:stroke-white"/>
  <h3 class="group-hover:text-white">New project</h3>
</a>

<input type="email" class="peer" />
<p class="invisible peer-invalid:visible">Invalid email</p>
```

**Pseudo-elements:** `before:` `after:` `placeholder:` `file:` `selection:` `first-line:` `first-letter:` `marker:`
```html
<span class="after:content-['*'] after:text-red-500">Required</span>
<input type="file" class="file:mr-4 file:py-2 file:px-4 file:border-0">
<p class="selection:bg-fuchsia-300 first-letter:text-7xl">
```

**Media / feature queries:** `motion-safe:` `motion-reduce:` `contrast-more:` `print:` `portrait:` `landscape:` `supports-[…]:` `noscript:` `inverted-colors:`, plus pointer-device targeting `pointer-fine:` / `pointer-coarse:` (and `any-pointer-*` for any attached device) and `details-content:` for `<details>` content.
```html
<button class="motion-safe:animate-spin motion-reduce:animate-none">
<div class="supports-[display:grid]:grid print:hidden">
<fieldset class="pointer-coarse:grid-cols-3 pointer-fine:grid-cols-6">
<div class="hidden noscript:block">Please enable JavaScript</div>
```

Use `not-*` for inverse conditions: `not-focus:hover:opacity-50`.

---

## Dark Mode

By default `dark:` follows `prefers-color-scheme` — no configuration needed:
```html
<div class="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">
```

**Manual (class or data attribute) toggle** — override the `dark` variant in CSS:
```css
@import "tailwindcss";
@custom-variant dark (&:where(.dark, .dark *));
/* or: @custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *)); */
```
```javascript
document.documentElement.classList.toggle('dark')
```

**Three-way (light / dark / system):** store the choice in `localStorage`, apply the `dark` class when stored value is `dark` or (`system` and the media query matches), and listen for `prefers-color-scheme` changes to re-apply while on `system`.

**Image swaps:**
```html
<img class="block dark:hidden" src="logo-light.png">
<img class="hidden dark:block" src="logo-dark.png">
```

Test both themes and ensure contrast holds in each (see [Accessibility](#accessibility)).

---

## CSS-First Customization

Tailwind v4 has no `tailwind.config.js`. Configure the design system in CSS with `@theme`, which defines tokens as CSS variables. Each token namespace (`--color-*`, `--spacing-*`, `--font-*`, `--breakpoint-*`, `--shadow-*`, etc.) generates the corresponding utilities.

```css
@import "tailwindcss";

@theme {
  /* Colors — generates bg-brand-500, text-brand-500, etc. */
  --color-brand-500: oklch(0.60 0.20 250);
  --color-brand-900: oklch(0.25 0.15 250);
  --color-primary: var(--color-brand-500);

  /* Spacing — --spacing is the base unit multiplied across the scale */
  --spacing: 0.25rem;
  --spacing-18: 4.5rem;

  /* Typography — font families, sizes, weights */
  --font-display: 'Lato', system-ui, sans-serif;
  --text-2xs: 0.625rem;
  --font-extra-bold: 850;

  /* Custom named breakpoints — generates xs: and 3xl: variants */
  --breakpoint-xs: 30rem;
  --breakpoint-3xl: 120rem;

  /* Shadows and animation */
  --shadow-glow: 0 0 20px rgb(59 130 246 / 0.5);
  --ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55);
  --animate-slide-in: slide-in 0.5s var(--ease-bounce);
}

@keyframes slide-in {
  from { transform: translateX(-100%); }
  to { transform: translateX(0); }
}
```

Every theme value is also a plain CSS variable, usable directly in custom CSS:
```css
.custom { background: var(--color-brand-500); padding: var(--spacing-4); }
```

---

## Directives

**`@import "tailwindcss";`** — inlines Tailwind (and any other CSS files you import).

**`@theme { … }`** — defines design tokens; see [CSS-First Customization](#css-first-customization).

**`@layer base | components | utilities`** — organizes custom CSS by cascade layer (specificity increases base → components → utilities):
```css
@layer base { h1 { @apply text-3xl font-bold; } }
@layer components { .btn { @apply px-4 py-2 rounded font-semibold; } }
@layer utilities { .content-auto { content-visibility: auto; } }
```

**`@apply`** — inlines existing utilities into custom CSS. Use it for third-party overrides, semantic class names required by a CMS/templating language, or base element styles. Do NOT use it as the default styling approach or merely to make markup look "cleaner" — that defeats the utility-first model. Prefer components (React/Vue/partials) or loops for reuse.

**`@utility name-* { … }`** — registers custom utilities that respond to variants. Use `--value(...)` for functional values and `--default(...)` for a valueless fallback:
```css
@utility tab-* {
  tab-size: --value(integer, --default(4));
}
@utility interactive {
  cursor: pointer;
  &:hover { opacity: 0.8; }
}
```

**`@variant name { … }`** — applies a Tailwind variant inside custom CSS. Stack with `:` (both must match) or list with `,` (either matches):
```css
.button {
  @variant dark { background: black; }
  @variant hover:focus { outline: 2px solid currentColor; }  /* both */
  @variant hover, focus { background: var(--color-blue-50); } /* either */
}
```

**`@custom-variant name (…)`** — defines a project-specific variant:
```css
@custom-variant theme-midnight (&:where([data-theme=midnight], [data-theme=midnight] *));
@custom-variant reduced-motion (@media (prefers-reduced-motion: reduce));
```

**`@source "…"`** — explicitly add files to content detection when auto-scanning misses them (e.g. an external component library). `@source not "…"` excludes paths; `@source inline("…")` force-generates specific classes (a safelist).

**`@reference "tailwindcss";`** — makes theme variables and utilities available to a scoped/isolated stylesheet (e.g. a Vue `<style scoped>` block or CSS module) without duplicating Tailwind's output:
```vue
<style scoped>
@reference "tailwindcss";
.custom { color: var(--color-blue-500); }
</style>
```

---

## Functions

**`--alpha(color / opacity)`** — adjusts a color's opacity in custom CSS:
```css
.overlay { background: --alpha(var(--color-black) / 50%); }
```
In markup, the `/` opacity modifier does the same: `bg-black/50`, `text-blue-500/75`.

**`--spacing(n)`** — returns a value from the spacing scale (`n × --spacing`):
```css
.custom { margin: --spacing(6); }   /* 1.5rem when --spacing is 0.25rem */
```

---

## Additional Utilities

Utilities that are easy to overlook:

- **Text shadow:** `text-shadow-2xs` `text-shadow-xs` `text-shadow-sm` `text-shadow-md` `text-shadow-lg`, colorable (`text-shadow-sky-300`) and with opacity (`text-shadow-lg/50`).
- **Colored drop shadow:** `drop-shadow-<color>` and `drop-shadow-<color>/<opacity>`.
- **Masks:** composable `mask-*` utilities — edge gradients (`mask-t-from-50%`, `mask-b-to-black`) and radial masks (`mask-radial-from-transparent`, `mask-radial-at-center`).
- **Scrollbars:** width `scrollbar-thin` / `scrollbar-none` / `scrollbar-auto`, colors `scrollbar-thumb-*` / `scrollbar-track-*`, and `scrollbar-gutter-stable` / `-both` to prevent layout shift.
- **Logical properties:** block/inline-relative spacing, sizing, and insets — e.g. `mbs-*`/`mbe-*` (margin block start/end), `pbs-*`/`pbe-*`, `block-*`/`inline-*` (sizing), `inset-s-*`/`inset-e-*`.
- **Zoom:** `zoom-75` `zoom-100` `zoom-125`, arbitrary (`zoom-[1.1]`) and variable (`zoom-(--preview-zoom)`).
- **Tab size:** `tab-2` `tab-4` `tab-8`, arbitrary and variable.
- **Text wrapping:** `wrap-break-word` and `wrap-anywhere` for `overflow-wrap`.
- **Safe alignment:** `justify-center-safe` / `items-center-safe` fall back to `start` when content overflows; `items-baseline-last` / `self-baseline-last` align to the last text baseline.

---

## Colors

Tailwind's default palette uses the **OKLCH** color space (perceptually uniform, so shades read as evenly spaced across hues and behave predictably in both light and dark modes). Every color is a `--color-*` CSS variable:
```css
.custom { color: var(--color-blue-500); background: var(--color-slate-50); }
```

The palette ships **26 color families**, each with 11 shades (`50`, `100`–`900` in hundreds, `950`).

**Chromatic (17):** `red` `orange` `amber` `yellow` `lime` `green` `emerald` `teal` `cyan` `sky` `blue` `indigo` `violet` `purple` `fuchsia` `pink` `rose`

**Neutrals (9):** `slate` `gray` `zinc` `neutral` `stone` `mauve` `olive` `mist` `taupe`

**Special:** `black` `white` `transparent` `current` `inherit`

Shades: `50` is lightest, `500` the base tone, `950` darkest. Apply opacity with the `/` modifier: `bg-black/75`, `text-blue-500/50`.

---

## Quick Reference

**Layout:** `flex` `grid` `block` `inline-block` `hidden` `container` `mx-auto`
**Flexbox:** `justify-{start|center|end|between|around}` `items-{start|center|end|stretch}` `flex-{row|col}` `flex-wrap`
**Grid:** `grid-cols-{n}` `col-span-{n}` `gap-{size}` `gap-x-{size}` `gap-y-{size}`
**Spacing:** `p-{size}` `px/py/pt/pr/pb/pl-{size}` `m-{size}` `mx/my/mt/mr/mb/ml-{size}`
**Sizing:** `w-{size}` `h-{size}` `max-w-{size}` `min-h-{size}`
**Typography:** `text-{size}` `font-{weight}` `leading-{height}` `text-{left|center|right}` `uppercase`
**Colors:** `text-{color}-{shade}` `bg-{color}-{shade}` `border-{color}-{shade}`
**Borders:** `border` `border-{size}` `border-{t|r|b|l}` `rounded` `rounded-{size}`
**Effects:** `shadow-{size}` `opacity-{value}` `transition` `duration-{time}`

**Spacing scale:**

| Class | Value | | Class | Value |
|-------|-------|---|-------|-------|
| `0` | 0 | | `5` | 1.25rem (20px) |
| `px` | 1px | | `6` | 1.5rem (24px) |
| `0.5` | 0.125rem (2px) | | `8` | 2rem (32px) |
| `1` | 0.25rem (4px) | | `10` | 2.5rem (40px) |
| `2` | 0.5rem (8px) | | `12` | 3rem (48px) |
| `3` | 0.75rem (12px) | | `16` | 4rem (64px) |
| `4` | 1rem (16px) | | `24` | 6rem (96px) |

---

## Common Pitfalls

**Using `sm:` for mobile styles.** `sm:` starts at 640px. Mobile styles are unprefixed.
```html
<div class="block sm:hidden">   <!-- shown on mobile, hidden at sm+ -->
```

**Overusing `@apply`.** It re-introduces the CSS you left behind. Keep utilities in markup; reach for components/loops when you need reuse.
```html
<div class="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow">
```

**`!important` to win specificity.** Resolve the conflict in your logic instead of forcing it.
```html
<div class={isActive ? "text-blue-500" : "text-red-500"}>
```

**Arbitrary values everywhere.** Each unique `[…]` value emits its own CSS and drifts from the design system. Prefer theme values; extend `@theme` when you need a new token.
```html
<div class="w-80 h-48 text-blue-800">   <!-- not w-[342px] text-[#3a5f7d] -->
```

---

## Accessibility

- Use semantic HTML (`<button>`, `<nav>`, `<main>`) over `<div>` with handlers.
- Always provide a visible focus style; prefer `focus-visible:` (see [State Variants](#state-variants)).
- Give icon-only controls an accessible name (`aria-label`) and `sr-only` text; mark decorative icons `aria-hidden="true"`.
- Meet contrast targets in **both** light and dark modes: WCAG AA is 4.5:1 for normal text and 3:1 for large text (AAA: 7:1 / 4.5:1). Check with the [WebAIM contrast checker](https://webaim.org/resources/contrastchecker/).

```html
<button class="bg-blue-500 hover:bg-blue-600 focus-visible:ring-2 focus-visible:ring-blue-500
               disabled:opacity-50" aria-label="Save changes">
  <svg class="w-5 h-5" aria-hidden="true">...</svg>
  <span class="sr-only">Save changes</span>
</button>
```

---

## Resources

- Docs: https://tailwindcss.com/docs
- Releases (source of truth for what's current): https://github.com/tailwindlabs/tailwindcss/releases
- Playground: https://play.tailwindcss.com
