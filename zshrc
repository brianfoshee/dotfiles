# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
ZSH_THEME="crakalakin"

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
alias dm='docker-machine'
alias dcp='docker-compose'
alias gt='go test $(go list ./... | grep -v /vendor/)'

export UPDATE_ZSH_DAYS=7
export EDITOR="/usr/local/bin/vim"
export PSQL_EDITOR=$EDITOR
export HOMEBREW_CASK_OPTS="--appdir=/Applications"

# ARM/nrf51822 stuff
export SDK_PATH=$HOME/Code/nordic/nrf51_sdk_v5_2_0_39364/nrf51822/
export TEMPLATE_PATH=$HOME/Code/nordic/nrf51-pure-gcc-setup/template/
export USE_SOFTDEVICE=s110
export JLINK_DIR=/usr/bin
export ARM_DIR=$HOME/Code/gcc-arm-none-eabi
export DEVICE=NRF51
export BOARD=BOARD_PCA10000

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git ruby rails rbenv github heroku)

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

# Allow numpad on external keyboard to work
# 0 . Enter
bindkey -s "^[Op" "0"
bindkey -s "^[On" "."
bindkey -s "^[OM" "^M"
# 1 2 3
bindkey -s "^[Oq" "1"
bindkey -s "^[Or" "2"
bindkey -s "^[Os" "3"
# 4 5 6
bindkey -s "^[Ot" "4"
bindkey -s "^[Ou" "5"
bindkey -s "^[Ov" "6"
# 7 8 9
bindkey -s "^[Ow" "7"
bindkey -s "^[Ox" "8"
bindkey -s "^[Oy" "9"
# + -  * /
bindkey -s "^[Ol" "+"
bindkey -s "^[Om" "-"
bindkey -s "^[Oj" "*"
bindkey -s "^[Oo" "/"

export GOPATH=$HOME/Code/go

# Setup docker machine
export DOCKER_TLS_VERIFY="1"
export DOCKER_HOST="tcp://192.168.225.129:2376"
export DOCKER_CERT_PATH="/Users/brian/.docker/machine/machines/dev"
export DOCKER_MACHINE_NAME="dev"

# Skip setting PATH inside tmux
if [[ -z $TMUX ]]; then
  PATH=/usr/local/go/bin:$PATH
  PATH=$GOPATH/bin:$PATH
  PATH=/usr/local/sbin:$PATH
  PATH=/Applications/Postgres.app/Contents/Versions/9.4/bin:$PATH
  PATH=$HOME/Code/gcc-arm-none-eabi/bin:$PATH
fi
