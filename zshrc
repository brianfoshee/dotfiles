# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
ZSH_THEME="brianfoshee"

# Language
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export SHELL="/bin/zsh"
alias gs='git status -s'
alias ga='git add'
alias gc='git commit'
alias gd='git diff'
alias gr='git rm'
alias be='bundle exec'
alias befs='bundle exec foreman start'
alias befrc='bundle exec foreman run rails console'
alias berc='bundle exec rails console'
alias bers='bundle exec rails server'
alias bert='bundle exec rake test'
alias befr='bundle exec foreman run'
alias la='ls -alh'
alias vi='vim'
alias objcopy="gobjcopy"
alias objdump="gobjdump"
alias swift='xcrun swift -v -sdk $(xcrun --show-sdk-path --sdk macosx)'
alias tls='tmux list-sessions'
alias ta='tmux att -t'
alias tns='tmux new -s'

export UPDATE_ZSH_DAYS=7
export EDITOR="/usr/local/bin/vim"
export PSQL_EDITOR=$EDITOR
export HOMEBREW_CASK_OPTS="--appdir=/Applications"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git)

source $ZSH/oh-my-zsh.sh

# When in vi mode, 0.1 timeout after hitting ESC
export KEYTIMEOUT=1

# History control
export HISTCONTROL=erasedups  # Ignore duplicate entries in history
export HISTFILE=~/.zsh_history
export HISTSIZE=10000         # Increases size of history
export SAVEHIST=10000
export HISTIGNORE="&:ls:ll:la:l.:tns:tls:tas:gc:ga:pwd:exit:clear:clr:[bf]g:history"

# up/down keys use history search using everything up to cursor, not just the
# first word (which would be history-search-backward and history-search-forward
bindkey '\e[A' history-beginning-search-backward
bindkey '\e[B' history-beginning-search-forward
bindkey "^?" backward-delete-char

export GOPATH=$HOME/Code

# heroku autocomplete setup
HEROKU_AC_ZSH_SETUP_PATH=/Users/brian/Library/Caches/heroku/autocomplete/zsh_setup && test -f $HEROKU_AC_ZSH_SETUP_PATH && source $HEROKU_AC_ZSH_SETUP_PATH;

# Skip setting PATH inside tmux
if [[ -z $TMUX ]]; then
  PATH=/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH
  PATH=$PATH:/usr/local/go/bin
  PATH=$PATH:/usr/local/sbin
  PATH=$PATH:$GOPATH/bin
fi

source $HOME/.homebrew-github-api-token

if type brew &>/dev/null; then
  # this used to be: $(brew --prefix)/share
  FPATH=/usr/local/share/zsh/site-functions:$FPATH
fi

autoload -U +X bashcompinit && bashcompinit

if [[ -s ${HOME}/.nytrc ]]; then
  source ${HOME}/.nytrc
fi
