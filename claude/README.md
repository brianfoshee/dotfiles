# Claude Code Configuration

This directory contains configuration and customization for Claude Code (claude.ai/code).

## Installation

Symlink this directory to your home directory:

```bash
ln -s ~/.dotfiles/claude ~/.claude
```

## What's Inside

### Core Configuration

- **CLAUDE.md**: Project-specific guidelines and rules for Claude Code when working in this repository. Defines coding standards, commit message format, testing requirements, and collaboration patterns. Inspired by [github.com/obra/dotfiles](https://github.com/obra/dotfiles/blob/main/.claude/CLAUDE.md).

- **settings.json**: Claude Code settings including:
  - Custom status line command (shows user, cwd, git branch, and dirty status)
  - Cleanup period (99999 days - essentially never auto-cleanup)
  - Default model (sonnet with 1M context)

### Custom Skills

The `skills/` directory contains specialized agent skills that extend Claude Code's capabilities:

#### design-with-tailwind-plus

Expert UI designer for building responsive, accessible web interfaces with Tailwind CSS v4 and Tailwind Plus components. Contains 657 pre-built component templates covering:
- Application shells and layouts
- Forms and navigation
- Data display and overlays
- E-commerce checkout flows and product pages
- Marketing heroes and pricing sections

**Important**: The `tailwind_all_components.json` file (23MB) is intentionally not in git because these components require a [Tailwind Plus](https://tailwindcss.com/plus) account. The components are licensed and you must have an active subscription to use them.

#### rails-architect

Expert Ruby on Rails architect for reviewing existing Rails applications, suggesting architectural improvements, and designing new features following modern Rails best practices. Based on 37signals/Basecamp production patterns. Includes comprehensive documentation and examples for Rails application design.

### Runtime Directories

These directories are created and managed by Claude Code:

- **projects/**: Per-project conversation history and context
- **history.jsonl**: Global command history
- **session-env/**: Session-specific environment state
- **todos/**: Task tracking files
- **file-history/**: File change tracking
- **debug/**: Debug logs and diagnostics
- **plans/**: Planning mode artifacts
- **shell-snapshots/**: Shell command snapshots
- **plugins/**: Plugin marketplace integrations
- **telemetry/**: Usage telemetry data
- **statsig/**: Feature flag configuration
