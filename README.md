# Dotfiles Setup

## Initial Installation

When setting up a new computer, run the installation script to create all necessary symbolic links:

```bash
cd ~/.dotfiles
./install.sh
```

Or manually create individual symbolic links:

```bash
# Core configuration files
ln -s ~/.dotfiles/gemrc ~/.gemrc
ln -s ~/.dotfiles/gitignore_global ~/.gitignore_global
ln -s ~/.dotfiles/hushlogin ~/.hushlogin
ln -s ~/.dotfiles/psqlrc ~/.psqlrc
ln -s ~/.dotfiles/sqliterc ~/.sqliterc
ln -s ~/.dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/vimrc ~/.vimrc
ln -s ~/.dotfiles/zshrc ~/.zshrc
ln -s ~/.dotfiles/nofrils-dark.vim ~/.vim/colors/nofrils-dark.vim

# Claude Code configuration
ln -s ~/.dotfiles/claude ~/.claude

# oh-my-zsh theme
ln -s ~/.dotfiles/brianfoshee.zsh-theme ~/.oh-my-zsh/themes/brianfoshee.zsh-theme
```

## Machine-Specific Config

`~/.zshrc` sources `~/.zshrc.local` at the very end (if present) for host-specific config that doesn't belong in this repo — API tokens, VM secrets, per-machine PATH/alias overrides, etc. The file is `chmod 600` and not tracked here. Create it on each new machine and source whatever that host needs:

```zsh
# example ~/.zshrc.local
[[ -s ~/.github-api-token ]] && source ~/.github-api-token  # laptop
[[ -s ~/.exedevrc ]] && source ~/.exedevrc                  # exe.dev VM
```
