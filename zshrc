# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Look in ~/.oh-my-zsh/themes/
ZSH_THEME="brianfoshee"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git)

source $ZSH/oh-my-zsh.sh

# for setting up git / pgp
# https://gist.github.com/troyfontaine/18c9146295168ee9ca2b30c00bd1b41e
export GPG_TTY=`tty`

# Language
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export SHELL="/bin/zsh"

# Aliases
alias gs='git status -s'
alias ga='git add'
alias gc='git commit'
alias gd='git diff'
alias gr='git rm'
alias la='ls -alh'
alias vi='vim'
alias swift='xcrun swift -v -sdk $(xcrun --show-sdk-path --sdk macosx)'
alias tls='tmux list-sessions'
alias ta='tmux att -t'
alias tns='tmux new -s'

# When in vi mode, 0.1 timeout after hitting ESC
export KEYTIMEOUT=1

# History control
export HISTCONTROL=erasedups  # Ignore duplicate entries in history
export HISTFILE=~/.zsh_history
export HISTSIZE=10000         # Increases size of history
export SAVEHIST=10000
export HISTIGNORE="&:ls:ll:la:l.:tns:tls:tas:gc:ga:pwd:exit:clear:clr:[bf]g:history"

# Set is this is an ARM mac
una="$(uname -a)"
if [[ $una == *"arm64"* ]]; then
  # alias intel homebrew for brews that don't yet support arm
  alias ibrew='arch -x86_64 /usr/local/bin/brew'
  # make sure arm homebrew is before intel homebrew
  export PATH="/opt/homebrew/bin:$PATH"
fi

export BREW_PREFIX="$(brew --prefix)"
export EDITOR=$BREW_PREFIX/bin/vim
export PSQL_EDITOR=$EDITOR
export HOMEBREW_CASK_OPTS="--appdir=/Applications"
export GOPATH=$HOME/Code

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

# setup rbenv
eval "$(rbenv init -)"

if [[ -s ${HOME}/.nytrc ]]; then
  source ${HOME}/.nytrc
fi
