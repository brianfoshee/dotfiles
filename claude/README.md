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
  - Cleanup period (180 days - chat transcripts older than this are auto-removed)
  - Vim editor mode and fullscreen TUI
  - A `permissions.deny` list as a safety net under `auto` mode (blocks reading secret files, `git push`, and destructive `rm -rf`)

  The live `settings.json` is **not** tracked in git — Claude Code rewrites it at runtime (embedding transient state like survey timestamps), so it's `.gitignore`d to avoid churn. The tracked template is **`settings.json.example`**.

#### New machine setup

`install.sh` seeds `settings.json` from the template on first install (it won't overwrite an existing one). If you symlinked this directory manually instead, copy the template into place:

```bash
cp ~/.claude/settings.json.example ~/.claude/settings.json
```

Claude Code takes over the copy from there. Re-diff the two files periodically if you want to fold intentional setting changes back into the tracked template (skip runtime keys like `feedbackSurveyState`).

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
- **sessions/**: Saved session state
- **history.jsonl**: Global command history
- **session-env/**: Session-specific environment state
- **todos/**: Task tracking files
- **tasks/**: Background task state
- **jobs/**: Background job state
- **daemon/**, **daemon.***: Background daemon state, logs, and lock
- **file-history/**: File change tracking
- **debug/**: Debug logs and diagnostics
- **plans/**: Planning mode artifacts
- **shell-snapshots/**: Shell command snapshots
- **plugins/**: Plugin marketplace integrations
- **teams/**: Agent team state
- **cache/**, **paste-cache/**: Cached data
- **telemetry/**: Usage telemetry data
- **statsig/**: Feature flag configuration
