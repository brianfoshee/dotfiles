# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is Brian's personal dotfiles repository containing shell configurations (zsh), editor configurations (vim), terminal multiplexer configuration (tmux), and Claude Code settings. Files are meant to be symlinked from home directory to their respective locations.

## Architecture

### Configuration Files

- **vimrc**: Vim configuration using vim-plug for plugin management. Plugins include vim-go, vim-fugitive, ctrlp, vim-airline, vim-terraform, vim-lsp, vim-ruby, vim-closetag. Includes custom autocmds for git stripspace on save (excluding .md, .tf, .go files), airline integration, and language-specific settings for Go, Ruby, HTML, and Terraform. Leader key is spacebar, arrow keys disabled, nofrils-dark color scheme.
- **zshrc**: Zsh configuration using oh-my-zsh framework with custom "brianfoshee" theme. Sets up mise (runtime version manager) and homebrew paths (with Apple Silicon detection). Git aliases: gs (status), gsc (switch -c for new branches), ga (add), gc (commit), gd (diff), gr (rm). Rails alias: `r='bin/rails'`. Includes LM Studio CLI integration and uv binary path setup. Uses `typeset -U path PATH fpath` to dedupe PATH/fpath defensively (prevents accumulation when zshrc is re-sourced or shells are nested). Sources `~/.zshrc.local` at the very end for machine-specific config (API tokens, VM secrets, host overrides) — that file is `chmod 600` and not tracked in this repo.
- **tmux.conf**: Tmux configuration with Control-Space prefix, vim-style pane navigation (h/j/k/l), mouse on, 1-indexed windows/panes (renumber on close). Sets `default-command "${SHELL}"` so panes are non-login shells (avoids re-running `/etc/zprofile` per pane). Uses `tmux-256color` with truecolor passthrough via `terminal-overrides`. New windows/splits inherit `pane_current_path`. Copy-mode uses vim bindings (v select, y copy to pbcopy). `prefix r` reloads the config; F12 toggles the outer prefix off for nested tmux sessions. Status bar is hand-rolled in `tmux.conf` (chartreuse accent on dark gray, hex truecolor); session block bg flips orange when prefix is held; `monitor-activity` highlights background windows.
- **claude/**: Claude Code configuration directory. Symlink this to `~/.claude` for global Claude settings. Contains CLAUDE.md (project-specific guidelines), settings.json, two custom skills (design-with-tailwind-plus and rails-architect), and plugin marketplace integration.
- **Brewfile**: Homebrew package manifest with 157 packages/taps for automated environment setup.
- **install.sh**: Automated dotfiles installation script with backup functionality for existing files.
- **Other configs**: psqlrc, sqliterc, gemrc, gitignore_global, hushlogin for database and shell customization.

### Key Patterns

**Vim Stripspace**: The vimrc includes a sophisticated autocmd that runs `git stripspace` on save, with exclusions for certain file types. It preserves cursor position and undo history using temporary undo files. Don't modify this pattern without testing thoroughly.

**Tmux Window Naming**: Tmux is configured to accept window name changes via escape sequences. Use `printf '\033k%s\033\\' "name"` to set window names programmatically. This is used by the global CLAUDE.md tmux window management rules.

**API Token Pattern**: Both GitHub and Anthropic API tokens are sourced from separate files (`~/.github-api-token`, `~/.anthropic-api-token`) in the home directory, not stored in this repo. These files should export the appropriate environment variables.

### Custom Claude Skills

The `claude/skills/` directory contains two specialized skills that extend Claude Code's capabilities:

**design-with-tailwind-plus**: Expert UI designer for building responsive, accessible web interfaces with Tailwind CSS v4 and Tailwind Plus components. Contains 657 pre-built component templates (23MB JSON database) covering application shells, forms, navigation, data display, overlays, e-commerce, and marketing sections. **CRITICAL**: This skill includes Tailwind Plus licensed components - you must emphasize license compliance when using these components.

**rails-architect**: Expert Ruby on Rails architect for reviewing Rails applications, suggesting architectural improvements, and designing new features following modern Rails best practices. Based on 37signals/Basecamp production patterns with comprehensive documentation and examples.

### 3rd Party Skills

Some skills are maintained in external repositories and cloned directly into `claude/skills/`. These cloned repos are gitignored since they are tracked in their own repositories.

**rails-audit-thoughtbot**: Cloned into `claude/skills/rails-audit-thoughtbot`. Performs comprehensive Rails application audits based on thoughtbot best practices (Ruby Science, Testing Rails). Source: [thoughtbot/rails-audit-thoughtbot](https://github.com/thoughtbot/rails-audit-thoughtbot).

**sosumi**: Single-file skill at `claude/skills/sosumi/SKILL.md` (tracked in this repo, not gitignored). Fetches Apple documentation as Markdown via Sosumi for API reference, Human Interface Guidelines, WWDC transcripts, and external Swift-DocC pages. Source: [sosumi.ai](https://sosumi.ai). Update with `curl -o claude/skills/sosumi/SKILL.md https://sosumi.ai/SKILL.md`.

**agent-browser**: Single-file skill at `claude/skills/agent-browser/SKILL.md` (tracked in this repo, not gitignored). Discovery stub for the `agent-browser` CLI — a Rust-based browser automation tool for AI agents (Chrome/Chromium via CDP, accessibility-tree snapshots, `@eN` element refs). Real workflow content is served at runtime by the CLI via `agent-browser skills get core`, so the stub never goes stale. Requires the CLI: `brew install agent-browser` then `agent-browser install` to fetch Chrome for Testing. Source: [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser). Update with `curl -o claude/skills/agent-browser/SKILL.md https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md`.

## Development Workflow

### Making Changes to Dotfiles

Since these files are symlinked from `~/.dotfiles` to the home directory (e.g., `~/.vimrc -> ~/.dotfiles/vimrc`), changes made to either location affect the same file. Always commit changes from the `~/.dotfiles` directory.

### Testing Configuration Changes

- **Vim**: Source changes with `:source ~/.vimrc` or restart vim
- **Zsh**: Source changes with `source ~/.zshrc` or start a new shell
- **Tmux**: Source changes with `tmux source-file ~/.tmux.conf` or use `prefix + :source-file ~/.tmux.conf`

### Vim Plugins

Plugins are managed by vim-plug. After adding a plugin to vimrc:
1. Restart vim or `:source ~/.vimrc`
2. Run `:PlugInstall` to install new plugins
3. Run `:PlugUpdate` to update existing plugins
4. Run `:PlugClean` to remove deleted plugins

### Installing/Updating Homebrew Packages

The Brewfile contains all homebrew packages, taps, and casks for environment setup:

```bash
# Install packages from Brewfile
brew bundle --file=~/.dotfiles/Brewfile

# Update Brewfile with currently installed packages
brew bundle dump --file=~/.dotfiles/Brewfile --force
```

### Installing Dotfiles

Use the `install.sh` script to symlink dotfiles to the home directory. The script creates `.backup` files for existing configurations before creating symlinks.

## Critical Rules

- NEVER modify the vim stripspace autocmd without explicit approval - it's carefully designed to preserve undo history and cursor position
- NEVER commit API tokens or sensitive credentials to this repository
- NEVER change whitespace handling in vimrc without testing on multiple file types
- ALWAYS emphasize Tailwind Plus license compliance when using the design-with-tailwind-plus skill - the components are licensed and require proper attribution
- The global `~/.claude/CLAUDE.md` file is the source of truth for Claude Code behavior - this file supplements it with dotfiles-specific context
