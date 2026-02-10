# Language
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export SHELL="/bin/zsh"

# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Look in ~/.oh-my-zsh/themes/
ZSH_THEME="brianfoshee"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git)

source $ZSH/oh-my-zsh.sh

# configure oh-my-zsh updates
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 14

# If Apple Silicon use new homebrew path
una="$(uname -a)"
if [[ $una == *"arm64"* ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# setup rbenv.
# When entering tmux, this will add a duplicate entry into PATH. However, it's
# needed because otherwise rbenv will come after the system ruby path.
if command -v rbenv &>/dev/null; then
  eval "$(rbenv init - zsh)"
fi

# setup mise for runtime version management
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# for setting up git / pgp
# https://gist.github.com/troyfontaine/18c9146295168ee9ca2b30c00bd1b41e
export GPG_TTY=`tty`

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
export HISTCONTROL=erasedups  # Ignore duplicate entries in history
export HISTFILE=~/.zsh_history
export HISTSIZE=10000         # Increases size of history
export SAVEHIST=10000
export HISTIGNORE="&:ls:ll:la:l.:tns:tls:tas:gc:ga:pwd:exit:clear:clr:[bf]g:history"

export GOPATH=$HOME/Code
export PATH="$HOME/Code/bin:$PATH"
if command -v brew &>/dev/null; then
  export BREW_PREFIX="$(brew --prefix)"
  export HOMEBREW_CASK_OPTS="--appdir=/Applications"
  export HOMEBREW_BUNDLE_NO_LOCK=true
  export EDITOR=$BREW_PREFIX/bin/vim
  export PSQL_EDITOR=$EDITOR
  export THOR_MERGE=$BREW_PREFIX/bin/vimdiff
fi

# up/down keys use history search using everything up to cursor, not just the
# first word (which would be history-search-backward and history-search-forward
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward
bindkey "^?" backward-delete-char

# export a github api token for:
#   - so homebrew commands don't hit api limits
#   - For claude to run gh cli commands and access the github MCP server
if [[ -s ${HOME}/.github-api-token ]]; then
  source $HOME/.github-api-token
fi

if type brew &>/dev/null; then
  FPATH=$BREW_PREFIX/share/zsh/site-functions:$FPATH
fi

# add uv binaries to path
export PATH="/Users/brian/.local/bin:$PATH"

# autoload -U +X bashcompinit && bashcompinit

# add ssh key for use with git commit signing
if [[ "$(uname -s)" == "Darwin" ]]; then
  ssh-add --apple-use-keychain ~/.ssh/github &>/dev/null
fi

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/brian/.lmstudio/bin"
# End of LM Studio CLI section
