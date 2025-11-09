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
ln -s ~/.dotfiles/tmuxline-snapshot ~/.tmuxline-snapshot
ln -s ~/.dotfiles/vimrc ~/.vimrc
ln -s ~/.dotfiles/zshrc ~/.zshrc
ln -s ~/.dotfiles/nofrils-dark.vim ~/.vim/colors/nofrils-dark.vim

# Claude Code configuration
ln -s ~/.dotfiles/claude ~/.claude

# oh-my-zsh theme
ln -s ~/.dotfiles/brianfoshee.zsh-theme ~/.oh-my-zsh/themes/brianfoshee.zsh-theme
```

## Tmuxline Snapshot

To generate Tmuxline snapshot file:

```
Tmuxline airline
TmuxlineSnapshot! ~/.dotfiles/tmuxline-snapshot
```
