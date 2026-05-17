# Language
export LANG="en_US.UTF-8"

# Dedupe PATH and fpath (tmux launches login shells per pane, which causes
# zshrc to re-prepend entries to an already-populated PATH on every nested
# shell start).
typeset -U path PATH fpath

# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Look in ~/.oh-my-zsh/themes/
ZSH_THEME="brianfoshee"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git brew gh mise golang)

source $ZSH/oh-my-zsh.sh

# configure oh-my-zsh updates
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 14

# If Apple Silicon use new homebrew path
una="$(uname -a)"
if [[ $una == *"arm64"* ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# setup mise for runtime version management
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# for setting up git / pgp
# https://gist.github.com/troyfontaine/18c9146295168ee9ca2b30c00bd1b41e
export GPG_TTY=$(tty)

# Aliases
alias gs='git status -s'
alias gsc='git switch -c' # new way to git checkout -b
alias ga='git add'
alias gc='git commit'
alias gd='git diff'
alias gr='git rm'
alias la='ls -alh'
alias vi='vim'
alias swiftrepl='xcrun swift -v -sdk $(xcrun --show-sdk-path --sdk macosx)'
alias tls='tmux list-sessions'
alias ta='tmux att -t'
alias tns='tmux new -s'
# This overwrites the existing zsh function r which is an alias for `fc -e -`
# https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html
alias r='bin/rails'
# setup ESP IDF for building for ESP
alias export-idf='. $HOME/Code/esp/esp-idf/export.sh'

# History control
export HISTFILE=~/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
HISTORY_IGNORE='(ls|ll|la|l.|tns|tls|ta|gc|ga|pwd|exit|clear|clr|bg|fg|history)'

export GOPATH=$HOME/Code
export PATH="$HOME/Code/bin:$PATH"
if command -v brew &>/dev/null; then
  export BREW_PREFIX="$(brew --prefix)"
  export HOMEBREW_CASK_OPTS="--appdir=/Applications"
  export EDITOR=$BREW_PREFIX/bin/vim
  export PSQL_EDITOR=$EDITOR
  export THOR_MERGE=$BREW_PREFIX/bin/vimdiff
fi

# up/down keys use history search using everything up to cursor, not just the
# first word (which would be history-search-backward and history-search-forward
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward

# export a github api token for:
#   - so homebrew commands don't hit api limits
#   - For claude to run gh cli commands and access the github MCP server
if [[ -s ${HOME}/.github-api-token ]]; then
  source $HOME/.github-api-token
fi

# add uv binaries to path
export PATH="$HOME/.local/bin:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section
