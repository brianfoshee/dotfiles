# Tailwind CSS v4.1 - Complete Reference

This document provides comprehensive coverage of Tailwind CSS v4.1 core concepts, patterns, and best practices.

## Table of Contents
- [Philosophy and Core Concepts](#philosophy-and-core-concepts)
- [Installation and Setup](#installation-and-setup)
- [Utility-First Fundamentals](#utility-first-fundamentals)
- [Responsive Design](#responsive-design)
- [State Variants](#state-variants)
- [Dark Mode](#dark-mode)
- [Customization](#customization)
- [Reusing Styles](#reusing-styles)
- [Directives and Functions](#directives-and-functions)
- [Best Practices](#best-practices)

---

## Philosophy and Core Concepts

### Utility-First Methodology

Tailwind CSS embraces a **utility-first approach** that fundamentally differs from traditional CSS frameworks. Rather than predefined components, developers combine single-purpose presentational classes directly in markup to construct interfaces.

**Key Principle**: Write HTML with utility classes instead of writing custom CSS.

```html
<!-- Traditional CSS approach -->
<button class="btn-primary">Save</button>

<!-- Tailwind utility-first approach -->
<button class="bg-sky-500 hover:bg-sky-700 px-4 py-2 rounded text-white">
  Save
</button>
```

### How Tailwind Works

The framework generates CSS dynamically by **scanning project files** for class names. When you write markup containing utility classes like `flex`, `p-6`, or `bg-white`, Tailwind creates only the necessary CSS—eliminating unused styles from the final bundle.

This results in:
- **Small CSS bundles**: Only used utilities are included
- **Fast builds**: Efficient scanning and generation
- **Zero runtime**: Pure CSS output with no JavaScript overhead

### Core Benefits

1. **Development Speed**: No CSS file switching or class naming decisions required
2. **Safety**: Modifying classes only affects that specific element, preventing cascading breaks
3. **Maintenance**: Changes are localized to visible markup
4. **Portability**: Complete styling context moves with HTML chunks
5. **Scalability**: CSS doesn't grow linearly; utilities are maximally reusable

### Utilities vs Inline Styles

Unlike inline styles, utilities offer:

- **Design constraints** from predefined theme variables
  - Inline: `style="padding: 13px"` (arbitrary)
  - Tailwind: `class="p-4"` (from spacing scale)

- **State support** (hover, focus, active states)
  - Inline: Requires JavaScript
  - Tailwind: `hover:bg-blue-600 focus:ring-2`

- **Responsive capabilities** via breakpoint prefixes
  - Inline: Requires media queries
  - Tailwind: `md:text-lg lg:text-xl`

---

## Installation and Setup

### System Requirements

- Node.js 14.x or higher
- npm, yarn, or pnpm package manager
- Modern build tool (Vite recommended)

### Installation Methods

Tailwind v4 offers several installation approaches:

1. **Using Vite** (recommended for modern frameworks)
2. Using PostCSS
3. Tailwind CLI
4. Framework-specific guides
5. Play CDN (prototyping only)

### Vite Installation (Recommended)

**Step 1: Create Project**
```bash
npm create vite@latest my-project
cd my-project
```

**Step 2: Install Dependencies**
```bash
npm install tailwindcss @tailwindcss/vite
```

**Step 3: Configure Vite Plugin**

Add to `vite.config.ts`:
```typescript
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [tailwindcss()],
})
```

**Step 4: Import Tailwind CSS**

Add to your main CSS file (e.g., `src/index.css`):
```css
@import "tailwindcss";
```

**Step 5: Run Development Server**
```bash
npm run dev
```

**Step 6: Use Utility Classes**
```html
<h1 class="text-3xl font-bold underline">
  Hello world!
</h1>
```

### PostCSS Installation

**Install dependencies:**
```bash
npm install tailwindcss @tailwindcss/postcss
```

**Configure PostCSS** (`postcss.config.js`):
```javascript
module.exports = {
  plugins: {
    '@tailwindcss/postcss': {}
  }
}
```

**Import in CSS:**
```css
@import "tailwindcss";
```

### Tailwind CLI

**Install globally or locally:**
```bash
npm install -D tailwindcss
```

**Build CSS:**
```bash
npx tailwindcss -i ./src/input.css -o ./dist/output.css --watch
```

---

## Utility-First Fundamentals

### Key Syntax Patterns

#### Basic Utilities

Utilities follow a consistent naming pattern:

```html
<!-- Layout -->
<div class="flex items-center justify-between">

<!-- Spacing -->
<div class="p-6 m-4">

<!-- Typography -->
<h1 class="text-2xl font-bold text-gray-900">

<!-- Colors -->
<div class="bg-white text-black border border-gray-200">
```

#### State Variants

Apply styles conditionally using prefixes:

```html
<!-- Hover states -->
<button class="bg-blue-500 hover:bg-blue-700">

<!-- Focus states -->
<input class="border border-gray-300 focus:border-blue-500 focus:ring-2">

<!-- Dark mode -->
<div class="bg-white dark:bg-gray-900">

<!-- Responsive -->
<div class="text-sm md:text-base lg:text-lg">
```

#### Composition

Multiple effects can be applied to single properties using CSS variables:

```html
<img class="blur-sm grayscale" src="...">
```

Tailwind handles layering automatically, preventing conflicts.

#### Arbitrary Values

Extend beyond predefined themes using square bracket notation:

```html
<!-- Custom colors -->
<div class="bg-[#316ff6]">

<!-- Custom spacing -->
<div class="top-[117px] left-[344px]">

<!-- Custom grid -->
<div class="grid-cols-[24rem_2.5rem_minmax(0,1fr)]">

<!-- Custom content -->
<div class="before:content-['Hello_World']">
```

**Escaping characters:**
- Use underscores for spaces: `content-['Hello_World']`
- Use backslashes for special characters: `content-['\2022']`

#### Arbitrary Properties

Use arbitrary CSS properties not covered by utilities:

```html
<!-- CSS property with value -->
<div class="[mask-type:luminance]">

<!-- With modifiers -->
<div class="hover:[mask-type:alpha]">
```

#### Arbitrary Variants

Create one-off variants:

```html
<!-- Custom selector -->
<div class="[&:nth-child(3)]:py-0">

<!-- Custom media query -->
<div class="[@media(width>=800px)]:text-center">

<!-- Target children -->
<div class="[&_p]:mt-4">
```

### Managing Conflicts

When utility classes conflict, **later stylesheet order wins**. The recommended approach is preventing conflicts through conditional logic rather than using `!important`:

```html
<!-- BAD: Using !important -->
<div class="text-red-500 !text-blue-500">

<!-- GOOD: Conditional rendering -->
<div class={isActive ? "text-blue-500" : "text-red-500"}>
```

---

## Responsive Design

### Mobile-First Breakpoint System

Tailwind uses a **mobile-first approach** where:
- **Unprefixed utilities** apply to all screen sizes
- **Prefixed utilities** apply at specified breakpoints and above

**CRITICAL**: Use unprefixed classes for mobile styles, NOT `sm:` prefixes.

### Default Breakpoints

| Prefix | Minimum Width | CSS Media Query |
|--------|---------------|-----------------|
| `sm` | 40rem (640px) | `@media (width >= 40rem)` |
| `md` | 48rem (768px) | `@media (width >= 48rem)` |
| `lg` | 64rem (1024px) | `@media (width >= 64rem)` |
| `xl` | 80rem (1280px) | `@media (width >= 80rem)` |
| `2xl` | 96rem (1536px) | `@media (width >= 96rem)` |

### Usage Examples

```html
<!-- Mobile: 16 units, Tablet: 32 units, Desktop: 48 units -->
<img class="w-16 md:w-32 lg:w-48" src="...">

<!-- Mobile: center, Tablet+: left align -->
<div class="text-center sm:text-left">

<!-- Mobile: block, Desktop: flex -->
<div class="block lg:flex">
```

### Common Patterns

**Stack to row layout:**
```html
<div class="flex flex-col md:flex-row">
  <div class="w-full md:w-1/2">Column 1</div>
  <div class="w-full md:w-1/2">Column 2</div>
</div>
```

**Responsive grid:**
```html
<!-- Mobile: 1 col, Tablet: 2 cols, Desktop: 3 cols -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
```

**Responsive spacing:**
```html
<div class="p-4 md:p-6 lg:p-8">
```

### Advanced Responsive Features

#### Targeting Breakpoint Ranges

Combine responsive variants with `max-*` variants:

```html
<!-- Applies only from md to xl -->
<div class="md:max-xl:flex">

<!-- Mobile and tablet only (not desktop) -->
<div class="block lg:max-2xl:hidden">
```

#### Custom Breakpoints

Define custom breakpoints via theme variables:

```css
@theme {
  --breakpoint-xs: 30rem;
  --breakpoint-3xl: 120rem;
}
```

```html
<div class="xs:text-sm 3xl:text-2xl">
```

#### Arbitrary Breakpoints

Use one-off breakpoints:

```html
<!-- Max-width breakpoint -->
<div class="max-[600px]:bg-sky-300">

<!-- Min-width breakpoint -->
<div class="min-[320px]:text-center">

<!-- Height-based breakpoint -->
<div class="min-h-[800px]:pt-12">
```

### Container Queries

Modern alternative to viewport-based breakpoints. Style elements based on their **container's size** rather than viewport width.

**Setup:**
```html
<!-- Mark container -->
<div class="@container">
  <!-- Style children based on container size -->
  <div class="@lg:text-xl @2xl:text-3xl">
    Responsive to container
  </div>
</div>
```

**Container query breakpoints:**
- `@sm` - 24rem (384px)
- `@md` - 28rem (448px)
- `@lg` - 32rem (512px)
- `@xl` - 36rem (576px)
- `@2xl` - 42rem (672px)
- `@3xl` - 48rem (768px)
- `@4xl` - 56rem (896px)
- `@5xl` - 64rem (1024px)
- `@6xl` - 72rem (1152px)
- `@7xl` - 80rem (1280px)

**Named containers:**
```html
<div class="@container/main">
  <div class="@lg/main:text-xl">
```

---

## State Variants

### Core Concept

Tailwind enables conditional styling through **variants** that prefix utility classes. Rather than modifying a single class for different states, you apply separate classes for each condition.

### Interactive State Variants

#### Mouse Interactions

```html
<!-- Hover -->
<button class="bg-violet-500 hover:bg-violet-600">

<!-- Active (while pressed) -->
<button class="bg-violet-500 active:bg-violet-700">
```

#### Focus States

```html
<!-- Focus (any method) -->
<input class="border-gray-300 focus:border-blue-500">

<!-- Focus-visible (keyboard only) -->
<button class="focus:outline-none focus-visible:ring-2">

<!-- Focus-within (element or descendants) -->
<div class="focus-within:ring-2">
  <input type="text">
</div>
```

**Best Practice**: Use `focus-visible:` for keyboard navigation styling to avoid showing focus rings on mouse clicks.

### Form State Variants

```html
<!-- Disabled -->
<input class="disabled:opacity-50 disabled:cursor-not-allowed">

<!-- Required -->
<input class="required:border-red-500">

<!-- Invalid -->
<input class="invalid:border-pink-500 focus:invalid:border-pink-500">

<!-- Valid -->
<input class="valid:border-green-500">

<!-- Checked (checkbox/radio) -->
<input type="checkbox" class="checked:bg-blue-500">

<!-- Indeterminate -->
<input type="checkbox" class="indeterminate:bg-gray-300">

<!-- Read-only -->
<input class="read-only:bg-gray-100">

<!-- Placeholder shown -->
<input class="placeholder-shown:border-gray-300">
```

### Structural Pseudo-Classes

```html
<!-- First/Last child -->
<li class="first:pt-0 last:pb-0">

<!-- Odd/Even children -->
<tr class="odd:bg-white even:bg-gray-50">

<!-- Specific positions -->
<div class="nth-[3]:bg-red-500">
<div class="nth-last-[2]:bg-blue-500">

<!-- Empty elements -->
<div class="empty:hidden">

<!-- Only child -->
<div class="only:mx-auto">
```

### Parent and Sibling Styling

#### Group Variants

Mark parent with `group` class, style children based on parent state:

```html
<a href="#" class="group">
  <svg class="stroke-sky-500 group-hover:stroke-white"/>
  <h3 class="text-gray-900 group-hover:text-white">New project</h3>
  <p class="text-gray-500 group-hover:text-gray-300">Description</p>
</a>
```

**Named groups** for nested scenarios:
```html
<div class="group/card">
  <div class="group/title">
    <h3 class="group-hover/card:text-blue-500 group-hover/title:underline">
      Title
    </h3>
  </div>
</div>
```

#### Peer Variants

Mark sibling with `peer` class, style based on sibling state:

```html
<input type="email" class="peer" />
<p class="invisible peer-invalid:visible text-red-500">
  Invalid email address
</p>
```

**Important**: Only **previous siblings** work due to CSS limitations (CSS can't select earlier elements).

**Named peers:**
```html
<input type="text" class="peer/email" />
<input type="text" class="peer/password" />
<p class="peer-invalid/email:block">Email error</p>
<p class="peer-invalid/password:block">Password error</p>
```

### Pseudo-Elements

```html
<!-- Before/After -->
<label class="before:content-['$'] before:mr-1">
  <span class="after:content-['*'] after:text-red-500">Required</span>
</label>

<!-- Placeholder -->
<input class="placeholder:text-gray-400 placeholder:italic">

<!-- File input button -->
<input type="file" class="file:mr-4 file:py-2 file:px-4 file:border-0">

<!-- Selection -->
<p class="selection:bg-fuchsia-300 selection:text-fuchsia-900">
  Select this text
</p>

<!-- First line/letter -->
<p class="first-line:uppercase first-line:tracking-widest">
<p class="first-letter:text-7xl first-letter:font-bold">

<!-- List marker -->
<ul class="marker:text-sky-400">
  <li>Item 1</li>
</ul>
```

### Media and Feature Queries

```html
<!-- Prefers reduced motion -->
<button class="motion-safe:animate-spin motion-reduce:animate-none">

<!-- Prefers contrast -->
<button class="contrast-more:border-2">

<!-- Supports -->
<div class="supports-[display:grid]:grid">

<!-- Print styles -->
<div class="print:hidden">

<!-- Portrait/Landscape -->
<div class="portrait:hidden landscape:block">
```

### Stacking Variants

Combine multiple variants for complex conditions:

```html
<!-- Dark mode + hover + medium breakpoint -->
<div class="dark:md:hover:bg-fuchsia-600">

<!-- Group hover + dark mode -->
<div class="group-hover:dark:text-white">

<!-- Peer checked + disabled -->
<div class="peer-checked:disabled:opacity-50">
```

**Variant order** (from right to left):
```
dark:md:hover:bg-blue-500
  │   │   │
  │   │   └─ hover: interaction state
  │   └───── md: responsive breakpoint
  └───────── dark: color scheme
```

### Best Practices

1. **Use utilities directly on elements** when possible instead of pseudo-elements
2. **Leverage `group` and `peer`** to reduce conditional template logic
3. **Prefer `focus-visible:`** over `focus:` for keyboard navigation styling
4. **Stack variants intelligently**: `dark:md:hover:bg-fuchsia-600`
5. **Use `not-` variants** for inverse conditions: `not-focus:hover:opacity-50`

---

## Dark Mode

### Overview

Tailwind includes a `dark:` variant as a **first-class feature** for styling sites differently when dark mode is activated.

### Default Implementation (Prefers Color Scheme)

By default, dark mode uses the `prefers-color-scheme` CSS media feature, automatically detecting the user's system preference:

```html
<div class="bg-white dark:bg-gray-900">
  <h1 class="text-gray-900 dark:text-white">
    Hello World
  </h1>
</div>
```

No configuration needed—dark mode works out of the box.

### Manual Toggle (Class-Based)

Override dark mode to use a CSS class for manual control:

**Configure custom variant** in your CSS:
```css
@import "tailwindcss";

@custom-variant dark (&:where(.dark, .dark *));
```

**Apply the class** to activate dark mode:
```html
<html class="dark">
  <body>
    <div class="bg-white dark:bg-black">
      Dark mode active
    </div>
  </body>
</html>
```

**Toggle with JavaScript:**
```javascript
// Enable dark mode
document.documentElement.classList.add('dark')

// Disable dark mode
document.documentElement.classList.remove('dark')
```

### Data Attribute Approach

Use a data attribute instead of a class:

**Configure:**
```css
@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));
```

**Usage:**
```html
<html data-theme="dark">
```

**Toggle:**
```javascript
document.documentElement.dataset.theme = 'dark'
```

### Three-Way Toggle (Light/Dark/System)

Support light, dark, and system preferences:

```javascript
// Check system preference
const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches

// Get stored preference
const storedTheme = localStorage.getItem('theme')

// Apply theme
function applyTheme(theme) {
  if (theme === 'dark' || (theme === 'system' && prefersDark)) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

// Listen for system changes
window.matchMedia('(prefers-color-scheme: dark)')
  .addEventListener('change', e => {
    if (localStorage.getItem('theme') === 'system') {
      applyTheme('system')
    }
  })
```

### Common Patterns

**Background and text:**
```html
<div class="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">
```

**Borders:**
```html
<div class="border border-gray-200 dark:border-gray-800">
```

**Semantic colors:**
```html
<button class="bg-blue-500 hover:bg-blue-600 dark:bg-blue-600 dark:hover:bg-blue-700">
```

**Images:**
```html
<!-- Show different images -->
<img class="block dark:hidden" src="logo-light.png">
<img class="hidden dark:block" src="logo-dark.png">

<!-- Adjust image opacity -->
<img class="dark:opacity-80" src="...">
```

**Combining with other variants:**
```html
<button class="bg-blue-500 hover:bg-blue-600 dark:bg-blue-600 dark:hover:bg-blue-700">
```

### Best Practices

1. **Test both modes** during development
2. **Ensure sufficient contrast** in both themes (WCAG AA: 4.5:1)
3. **Use semantic color names** that work in both modes
4. **Consider images and icons**—they may need adjustments
5. **Provide manual toggle** for better user experience
6. **Store preference** in localStorage to persist across sessions

---

## Customization

### Theme Customization with @theme

Tailwind v4 uses the **`@theme` directive** to customize design tokens via CSS variables.

**Basic structure:**
```css
@import "tailwindcss";

@theme {
  /* Define custom design tokens here */
}
```

### Customizing Colors

```css
@theme {
  /* Brand colors */
  --color-brand-50: oklch(0.98 0.01 250);
  --color-brand-100: oklch(0.95 0.03 250);
  --color-brand-500: oklch(0.60 0.20 250);
  --color-brand-900: oklch(0.25 0.15 250);

  /* Semantic colors */
  --color-primary: var(--color-brand-500);
  --color-success: oklch(0.70 0.15 145);
  --color-danger: oklch(0.65 0.25 25);
}
```

```html
<div class="bg-brand-500 text-white">
<button class="bg-primary hover:bg-brand-600">
```

### Customizing Spacing

```css
@theme {
  /* Custom spacing scale */
  --spacing-18: 4.5rem;
  --spacing-72: 18rem;

  /* Functional spacing */
  --spacing: 0.25rem; /* Base unit */
}
```

```html
<div class="p-18 m-72">
```

### Customizing Typography

```css
@theme {
  /* Font families */
  --font-display: 'Lato', system-ui, sans-serif;
  --font-body: 'Inter', system-ui, sans-serif;
  --font-mono: 'Fira Code', monospace;

  /* Font sizes */
  --text-2xs: 0.625rem;
  --text-3xs: 0.5rem;

  /* Font weights */
  --font-medium: 550;
  --font-extra-bold: 850;
}
```

```html
<h1 class="font-display text-3xl font-extra-bold">
<p class="font-body text-base">
<code class="font-mono text-2xs">
```

### Customizing Breakpoints

```css
@theme {
  --breakpoint-xs: 30rem;
  --breakpoint-3xl: 120rem;
}
```

```html
<div class="xs:text-sm 3xl:text-2xl">
```

### Customizing Shadows

```css
@theme {
  --shadow-glow: 0 0 20px rgba(59, 130, 246, 0.5);
  --shadow-brutal: 4px 4px 0 0 black;
}
```

```html
<div class="shadow-glow">
<div class="shadow-brutal">
```

### Customizing Animation

```css
@theme {
  --ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55);

  --animate-slide-in: slide-in 0.5s var(--ease-bounce);
}

@keyframes slide-in {
  from { transform: translateX(-100%); }
  to { transform: translateX(0); }
}
```

```html
<div class="animate-slide-in">
```

### Referencing Theme Values

Use CSS variables directly in custom CSS:

```css
.custom-component {
  background-color: var(--color-brand-500);
  padding: var(--spacing-4);
  font-family: var(--font-display);
}
```

---

## Reusing Styles

### Managing Duplication

Tailwind provides several strategies for reusing styles across your project.

### 1. Using Loops (Preferred)

The most common scenario involves rendering duplicate elements through code loops. Author the markup once within a loop structure:

```jsx
// React example
{items.map(item => (
  <div key={item.id} class="bg-white rounded-lg shadow-md p-6">
    <h3 class="text-lg font-bold text-gray-900">{item.title}</h3>
    <p class="text-gray-600">{item.description}</p>
  </div>
))}
```

```erb
<!-- Ruby ERB example -->
<% @items.each do |item| %>
  <div class="bg-white rounded-lg shadow-md p-6">
    <h3 class="text-lg font-bold text-gray-900"><%= item.title %></h3>
    <p class="text-gray-600"><%= item.description %></p>
  </div>
<% end %>
```

### 2. Multi-Cursor Editing

When duplicated class lists appear in a single file, use multi-cursor editing to select and edit the class list for each element simultaneously.

**VS Code**: `Cmd/Ctrl + D` to select next occurrence

```html
<!-- Select "bg-white p-6 rounded-lg" and edit all at once -->
<div class="bg-white p-6 rounded-lg">...</div>
<div class="bg-white p-6 rounded-lg">...</div>
<div class="bg-white p-6 rounded-lg">...</div>
```

### 3. Component Abstraction (Recommended for Multiple Files)

Create reusable components in your framework of choice:

**React:**
```jsx
function Card({ title, children }) {
  return (
    <div class="bg-white rounded-lg shadow-md p-6">
      <h3 class="text-lg font-bold text-gray-900">{title}</h3>
      <div class="text-gray-600">{children}</div>
    </div>
  )
}
```

**Vue:**
```vue
<template>
  <div class="bg-white rounded-lg shadow-md p-6">
    <h3 class="text-lg font-bold text-gray-900">{{ title }}</h3>
    <div class="text-gray-600">
      <slot />
    </div>
  </div>
</template>
```

**Template Partials** (Blade, ERB, Twig, Nunjucks):
```erb
<!-- _card.html.erb -->
<div class="bg-white rounded-lg shadow-md p-6">
  <h3 class="text-lg font-bold text-gray-900"><%= title %></h3>
  <div class="text-gray-600"><%= yield %></div>
</div>

<!-- Usage -->
<%= render 'card', title: 'Card Title' do %>
  Card content here
<% end %>
```

### 4. Custom CSS with @layer

When component abstractions feel excessive, write custom CSS using `@layer components`:

```css
@layer components {
  .btn-primary {
    @apply bg-blue-500 hover:bg-blue-600 text-white font-semibold py-2 px-4 rounded;
  }

  .card {
    @apply bg-white rounded-lg shadow-md p-6;
  }
}
```

**When to use `@layer components`:**
- Semantic class names needed for templating languages
- Third-party library overrides
- Component patterns too simple for framework components

**When NOT to use it:**
- Default approach—prefer inline utilities
- Only to reduce "visual clutter"
- Early abstraction before patterns emerge

### 5. Extracting Base Styles

Use `@layer base` for global element defaults:

```css
@layer base {
  h1 {
    @apply text-3xl font-bold;
  }

  h2 {
    @apply text-2xl font-semibold;
  }

  a {
    @apply text-blue-600 hover:text-blue-800 underline;
  }
}
```

**Warning**: This removes Tailwind's "blank slate" philosophy. Only use for content-heavy sites (blogs, documentation) where semantic HTML is critical.

---

## Directives and Functions

### Key Directives

#### @import

Inlines CSS files and Tailwind itself into your project:

```css
@import "tailwindcss";
@import "./custom-base.css";
@import "./custom-components.css";
```

#### @theme

Defines custom design tokens using CSS variables:

```css
@theme {
  --color-primary: oklch(0.60 0.20 250);
  --spacing-18: 4.5rem;
  --font-display: 'Lato', system-ui, sans-serif;
}
```

#### @layer

Organizes custom CSS into Tailwind's layers:

```css
/* Base layer - element defaults */
@layer base {
  h1 {
    @apply text-3xl font-bold;
  }
}

/* Components layer - reusable classes */
@layer components {
  .btn {
    @apply px-4 py-2 rounded font-semibold;
  }
}

/* Utilities layer - utility classes */
@layer utilities {
  .content-auto {
    content-visibility: auto;
  }
}
```

**Layer order** (specificity):
1. `base` (lowest specificity)
2. `components`
3. `utilities` (highest specificity)

#### @apply

Inlines existing utility classes into custom CSS:

```css
.btn-primary {
  @apply bg-blue-500 hover:bg-blue-600 text-white font-semibold py-2 px-4 rounded;
}
```

**When to use:**
- Third-party library overrides
- Component classes in templating languages
- Semantic class names for content editors

**When NOT to use:**
- Default styling approach (use inline utilities)
- Premature abstraction
- "Cleaner HTML" (defeats utility-first benefits)

#### @utility

Registers custom utilities that respond to variants:

```css
@utility tab-* {
  tab-size: *;
}

@utility content-* {
  content-visibility: *;
}
```

```html
<pre class="tab-4 hover:tab-8">
<div class="content-auto">
```

**Advanced custom utilities:**
```css
/* Functional utility */
@utility mask-image-* {
  mask-image: linear-gradient(*, black, transparent);
}

/* With nested selectors */
@utility interactive {
  cursor: pointer;
  user-select: none;

  &:hover {
    opacity: 0.8;
  }
}
```

#### @variant

Applies Tailwind variants to custom CSS:

```css
.custom-element {
  @variant dark {
    background-color: black;
  }

  @variant hover {
    opacity: 0.8;
  }
}
```

```html
<div class="custom-element dark:custom-element hover:custom-element">
```

#### @custom-variant

Creates project-specific variants:

```css
/* Data attribute variant */
@custom-variant theme-midnight (&:where([data-theme=midnight], [data-theme=midnight] *));

/* Media query variant */
@custom-variant reduced-motion (@media (prefers-reduced-motion: reduce));

/* Attribute selector variant */
@custom-variant optional (&:optional);
```

```html
<div class="theme-midnight:bg-black">
<div class="reduced-motion:transition-none">
<input class="optional:border-gray-300">
```

#### @source

Explicitly specifies source files for content detection:

```css
@import "tailwindcss";

@source "../../node_modules/my-ui-library/components/**/*.tsx";
```

Useful when automatic scanning doesn't cover external libraries.

#### @reference

Imports theme variables and utilities into component styles without duplicating CSS output:

```vue
<style scoped>
@reference "tailwindcss";

.custom-class {
  color: var(--color-blue-500);
  padding: var(--spacing-4);
}
</style>
```

### Build-Time Functions

#### --alpha()

Adjusts color opacity using `color-mix()`:

```css
.semi-transparent {
  background-color: color-mix(in oklab, var(--color-blue-500) var(--alpha, 100%), transparent);
}
```

```html
<div class="bg-blue-500/50"> <!-- 50% opacity -->
```

#### --spacing()

Generates spacing values based on theme:

```css
.custom-spacing {
  margin: calc(var(--spacing) * 6); /* 1.5rem if --spacing is 0.25rem */
}
```

---

## Best Practices

### General Principles

1. **Start with utilities in markup** - Don't prematurely extract to custom CSS
2. **Use design tokens** - Stick to theme values for consistency
3. **Mobile-first responsive design** - Base styles without prefixes, add `md:`, `lg:` as needed
4. **Leverage composition** - Combine utilities instead of writing custom CSS
5. **Create components when needed** - Extract to framework components for true reusability

### When to Use Different Approaches

**Inline utilities** (default):
```html
<button class="bg-blue-500 hover:bg-blue-600 text-white font-semibold py-2 px-4 rounded">
```
✅ Most cases
✅ One-off elements
✅ Rapid prototyping

**Loops** (preferred for duplication):
```jsx
{items.map(item => <Card key={item.id} {...item} />)}
```
✅ Lists and repeated elements
✅ Dynamic content

**Component abstraction**:
```jsx
function Button({ variant, children }) { ... }
```
✅ Used across multiple files
✅ Complex composition patterns
✅ Shared with team

**Custom CSS with `@layer`**:
```css
@layer components {
  .prose { ... }
}
```
✅ Third-party overrides
✅ Semantic class names for CMS
✅ Base element styles
⚠️ Use sparingly

### Color Contrast

Always ensure WCAG compliance:
- **WCAG AA**: 4.5:1 for normal text, 3:1 for large text
- **WCAG AAA**: 7:1 for normal text, 4.5:1 for large text

Test with tools:
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)
- Browser DevTools accessibility panel

### Performance

1. **Purge unused styles** - Tailwind does this automatically via content scanning
2. **Use arbitrary values sparingly** - They increase CSS bundle size
3. **Prefer utilities over custom CSS** - Better reusability and smaller bundles
4. **Minify in production** - Use build tools to compress output CSS

### Accessibility

1. **Use semantic HTML** - `<button>`, `<nav>`, `<main>`, not `<div>` with click handlers
2. **Include focus states** - Always style `focus:` and `focus-visible:`
3. **Provide ARIA labels** - Use `aria-label`, `aria-describedby` where needed
4. **Keyboard navigation** - Ensure interactive elements are keyboard accessible
5. **Screen reader text** - Use `sr-only` for icon-only buttons

```html
<!-- Good accessibility example -->
<button
  class="bg-blue-500 hover:bg-blue-600 focus-visible:ring-2 focus-visible:ring-blue-500
         disabled:opacity-50 disabled:cursor-not-allowed"
  aria-label="Save changes">
  <svg class="w-5 h-5" aria-hidden="true">...</svg>
  <span class="sr-only">Save changes</span>
</button>
```

### Maintainability

1. **Consistent naming** - Use theme variables instead of arbitrary values
2. **Document patterns** - Comment complex utility combinations
3. **Extract early patterns** - Once you use a combination 3+ times, consider extracting
4. **Version control** - Commit theme customizations with code changes
5. **Team conventions** - Establish utility ordering conventions (e.g., layout → spacing → typography → colors)

### Common Pitfalls to Avoid

❌ **Using `sm:` for mobile styles**
```html
<!-- WRONG -->
<div class="sm:block"> <!-- Applies at 640px+, not mobile -->

<!-- CORRECT -->
<div class="block sm:hidden"> <!-- Visible on mobile, hidden on tablet+ -->
```

❌ **Overusing `@apply`**
```css
/* WRONG - Defeats utility-first benefits */
.card {
  @apply bg-white rounded-lg shadow-md p-6 border border-gray-200 hover:shadow-lg transition-shadow;
}

<!-- CORRECT - Use utilities directly -->
<div class="bg-white rounded-lg shadow-md p-6 border border-gray-200 hover:shadow-lg transition-shadow">
```

❌ **Using `!important` utilities**
```html
<!-- WRONG -->
<div class="text-red-500 !text-blue-500">

<!-- CORRECT -->
<div class={isActive ? "text-blue-500" : "text-red-500"}>
```

❌ **Arbitrary values everywhere**
```html
<!-- WRONG - Creates bloated CSS -->
<div class="w-[342px] h-[197px] text-[#3a5f7d]">

<!-- CORRECT - Use theme values -->
<div class="w-80 h-48 text-blue-800">
```

---

## Quick Reference

### Most Common Utilities

**Layout:**
- `flex`, `grid`, `block`, `inline-block`, `hidden`
- `container`, `mx-auto`

**Flexbox:**
- `justify-start/center/end/between/around`
- `items-start/center/end/stretch`
- `flex-row/col`, `flex-wrap`

**Grid:**
- `grid-cols-{n}`, `col-span-{n}`
- `gap-{size}`, `gap-x-{size}`, `gap-y-{size}`

**Spacing:**
- `p-{size}`, `px-{size}`, `py-{size}`, `pt/pr/pb/pl-{size}`
- `m-{size}`, `mx-{size}`, `my-{size}`, `mt/mr/mb/ml-{size}`

**Sizing:**
- `w-{size}`, `h-{size}`
- `max-w-{size}`, `min-h-{size}`

**Typography:**
- `text-{size}`, `font-{weight}`, `leading-{height}`
- `text-left/center/right`, `uppercase/lowercase`

**Colors:**
- `text-{color}-{shade}`
- `bg-{color}-{shade}`
- `border-{color}-{shade}`

**Borders:**
- `border`, `border-{size}`, `border-t/r/b/l`
- `rounded`, `rounded-{size}`, `rounded-t/r/b/l`

**Effects:**
- `shadow`, `shadow-{size}`
- `opacity-{value}`
- `transition`, `duration-{time}`

### Spacing Scale

| Class | Value |
|-------|-------|
| `0` | 0 |
| `px` | 1px |
| `0.5` | 0.125rem (2px) |
| `1` | 0.25rem (4px) |
| `2` | 0.5rem (8px) |
| `3` | 0.75rem (12px) |
| `4` | 1rem (16px) |
| `5` | 1.25rem (20px) |
| `6` | 1.5rem (24px) |
| `8` | 2rem (32px) |
| `10` | 2.5rem (40px) |
| `12` | 3rem (48px) |
| `16` | 4rem (64px) |
| `20` | 5rem (80px) |
| `24` | 6rem (96px) |

### Default Color Palette

Tailwind includes **22 color families** organized into chromatic colors and neutrals:

**Chromatic Colors:**
- `red`, `orange`, `amber`, `yellow`, `lime`, `green`, `emerald`
- `teal`, `cyan`, `sky`, `blue`, `indigo`, `violet`, `purple`
- `fuchsia`, `pink`, `rose`

**Neutral Colors:**
- `slate` - Cool gray with blue undertones
- `gray` - True neutral gray
- `zinc` - Cool gray with slightly less saturation than slate
- `neutral` - Pure neutral gray
- `stone` - Warm gray with brown undertones

**Special Colors:**
- `black`, `white`, `transparent`, `current`, `inherit`

### Color Shade Scale

Each color family contains **11 shade levels** (except special colors):

- `50` - Lightest (near white)
- `100`, `200`, `300`, `400` - Light shades
- `500` - Base tone (default intensity)
- `600`, `700`, `800`, `900` - Dark shades
- `950` - Darkest (near black)

**Usage examples:**
```html
<div class="bg-blue-500 text-white">         <!-- Base blue background -->
<div class="bg-slate-50 text-slate-900">     <!-- Light slate background -->
<div class="border-red-600 text-red-700">    <!-- Darker red border/text -->
```

**Opacity modifiers:**
```html
<div class="bg-black/75">     <!-- 75% opacity -->
<div class="text-blue-500/50"> <!-- 50% opacity -->
```

### Color System

Tailwind uses the **OKLCH color space**, a modern perceptually uniform format that ensures:
- Consistent perceived brightness across all hues
- Better color quality in both light and dark modes
- More predictable color relationships
- Improved accessibility through perceptual uniformity

All colors are accessible via CSS variables in the `--color-*` namespace:
```css
.custom {
  color: var(--color-blue-500);
  background: var(--color-slate-50);
}
```

---

## Additional Resources

- **Official Docs**: https://tailwindcss.com/docs
- **GitHub**: https://github.com/tailwindlabs/tailwindcss
- **Playground**: https://play.tailwindcss.com
- **Component Libraries**: Tailwind UI, Headless UI, Tailwind Plus
- **Community**: Discord, GitHub Discussions
