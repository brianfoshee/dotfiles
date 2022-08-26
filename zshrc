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

# If Apple Silicon use new homebrew path
una="$(uname -a)"
if [[ $una == *"arm64"* ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# setup rbenv.
# When entering tmux, this will add a duplicate entry into PATH. However, it's
# needed because otherwise rbenv will come after the system ruby path.
eval "$(rbenv init - zsh)"

# for setting up git / pgp
# https://gist.github.com/troyfontaine/18c9146295168ee9ca2b30c00bd1b41e
export GPG_TTY=`tty`

# Aliases
alias gs='git status -s'
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

# History control
export HISTCONTROL=erasedups  # Ignore duplicate entries in history
export HISTFILE=~/.zsh_history
export HISTSIZE=10000         # Increases size of history
export SAVEHIST=10000
export HISTIGNORE="&:ls:ll:la:l.:tns:tls:tas:gc:ga:pwd:exit:clear:clr:[bf]g:history"

export BREW_PREFIX="$(brew --prefix)"
export HOMEBREW_CASK_OPTS="--appdir=/Applications"
export HOMEBREW_BUNDLE_NO_LOCK=true
export GOPATH=$HOME/Code
export EDITOR=$BREW_PREFIX/bin/vim
export PSQL_EDITOR=$EDITOR

# up/down keys use history search using everything up to cursor, not just the
# first word (which would be history-search-backward and history-search-forward
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward
bindkey "^?" backward-delete-char

if [[ -s ${HOME}/.homebrew-github-api-token ]]; then
  source $HOME/.homebrew-github-api-token
fi

if type brew &>/dev/null; then
  FPATH=$BREW_PREFIX/share/zsh/site-functions:$FPATH
fi

# autoload -U +X bashcompinit && bashcompinit

if [[ -s ${HOME}/.nytrc ]]; then
  source ${HOME}/.nytrc
fi
