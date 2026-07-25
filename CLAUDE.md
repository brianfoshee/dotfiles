# CLAUDE.md

Brian's personal dotfiles — zsh, vim, tmux, sqlite/psql/gem configs, and Claude
Code settings — symlinked into `$HOME` by `install.sh`, which backs up any
existing file to `*.backup` first. To learn what a config does, read it; the
files are short and this file only covers what reading them won't tell you.

## Gotchas

**Symlinks are two-way.** `~/.vimrc` and `~/.dotfiles/vimrc` are the same file,
so edits from either side are the same edit. Commit from `~/.dotfiles`.

**The vim stripspace autocmd.** `vimrc` runs `git stripspace` on save (excluding
`.md`, `.tf`, `.go`) and juggles temporary undo files to preserve undo history
and cursor position. Don't change it — or anything else about whitespace
handling — without approval and testing across several file types.

**Secrets live outside the repo.** `zshrc` sources `~/.zshrc.local` last for
machine-specific config; it's `chmod 600` and untracked. API tokens come from
`~/.github-api-token` and `~/.anthropic-api-token`. Nothing sensitive belongs in
this repo.

**`claude/` is a live directory,** symlinked to `~/.claude`, so it fills with
runtime state — sessions, projects, caches, daemon files. `claude/.gitignore`
excludes all of that plus `settings.json` itself; the tracked file is
`settings.json.example`, which `install.sh` seeds on first install. Check that
gitignore before adding anything under `claude/`.

**Skills are tracked three different ways.** In-repo skills
(`design-with-tailwind-plus`, `rails-architect`, `cloudflare-domain-setup`) are
normal source. `rails-audit-thoughtbot` is a clone of
[an external repo](https://github.com/thoughtbot/rails-audit-thoughtbot) and is
gitignored. `sosumi` and `agent-browser` are tracked single-file stubs refreshed
from upstream:

```bash
curl -o claude/skills/sosumi/SKILL.md https://sosumi.ai/SKILL.md
curl -o claude/skills/agent-browser/SKILL.md https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md
```

Conventions for writing skills live in `claude/skills/CLAUDE.md`.

**Tailwind Plus components are licensed.** `design-with-tailwind-plus` is backed
by an untracked 23MB `tailwind_all_components.json`. Raise license compliance
whenever those components get used.

## Commands

Reload after editing: `:source ~/.vimrc`, `source ~/.zshrc`,
`tmux source-file ~/.tmux.conf` (or `prefix r`). vim plugins are vim-plug.

```bash
brew bundle --file=~/.dotfiles/Brewfile              # install
brew bundle dump --file=~/.dotfiles/Brewfile --force # snapshot what's installed
```
