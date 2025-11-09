#!/bin/bash
# Dotfiles installation script - creates symbolic links for all configuration files

set -e

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Function to create a symbolic link with backup
link_file() {
    local source="$1"
    local target="$2"
    local target_dir=$(dirname "$target")

    # Create target directory if it doesn't exist
    if [ ! -d "$target_dir" ]; then
        echo "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi

    # Backup existing file if it exists and is not already a symlink to our dotfiles
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$(readlink "$target")" != "$source" ]; then
            echo "Backing up existing file: $target"
            mkdir -p "$BACKUP_DIR"
            mv "$target" "$BACKUP_DIR/"
        else
            echo "Already linked: $target"
            return
        fi
    fi

    echo "Linking: $source -> $target"
    ln -s "$source" "$target"
}

echo "Installing dotfiles from $DOTFILES_DIR"
echo

# Core configuration files
link_file "$DOTFILES_DIR/gemrc" "$HOME/.gemrc"
link_file "$DOTFILES_DIR/gitignore_global" "$HOME/.gitignore_global"
link_file "$DOTFILES_DIR/hushlogin" "$HOME/.hushlogin"
link_file "$DOTFILES_DIR/psqlrc" "$HOME/.psqlrc"
link_file "$DOTFILES_DIR/sqliterc" "$HOME/.sqliterc"
link_file "$DOTFILES_DIR/tmux.conf" "$HOME/.tmux.conf"
link_file "$DOTFILES_DIR/tmuxline-snapshot" "$HOME/.tmuxline-snapshot"
link_file "$DOTFILES_DIR/vimrc" "$HOME/.vimrc"
link_file "$DOTFILES_DIR/zshrc" "$HOME/.zshrc"

# Vim color scheme
link_file "$DOTFILES_DIR/nofrils-dark.vim" "$HOME/.vim/colors/nofrils-dark.vim"

# Claude Code configuration
link_file "$DOTFILES_DIR/claude" "$HOME/.claude"

# oh-my-zsh theme (only if oh-my-zsh is installed)
if [ -d "$HOME/.oh-my-zsh/themes" ]; then
    link_file "$DOTFILES_DIR/brianfoshee.zsh-theme" "$HOME/.oh-my-zsh/themes/brianfoshee.zsh-theme"
else
    echo "Skipping oh-my-zsh theme (oh-my-zsh not installed)"
fi

echo
echo "Dotfiles installation complete!"

if [ -d "$BACKUP_DIR" ]; then
    echo "Backups saved to: $BACKUP_DIR"
fi
