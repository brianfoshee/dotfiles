# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

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
alias dm='docker-machine'
alias dcp='docker-compose'
alias st='xcrun swift -F /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks'

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

plugins=(git github heroku)

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

export GOPATH=$HOME/Code/go

# Skip setting PATH inside tmux
if [[ -z $TMUX ]]; then
  PATH=/Applications/Postgres.app/Contents/Versions/9.4/bin:$PATH
  PATH=$PATH:/usr/local/go/bin
  PATH=$PATH:/usr/local/sbin
  PATH=$PATH:$GOPATH/bin

  source /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc
fi

# In order for gpg to find gpg-agent, gpg-agent must be running, and there must be an env
# variable pointing GPG to the gpg-agent socket. This little script, which must be sourced
# in your shell's init script (ie, .bash_profile, .zshrc, whatever), will either start
# gpg-agent or set up the GPG_AGENT_INFO variable if it's already running.

# Add the following to your shell init to set up gpg-agent automatically for every shell
if [ -f ~/.gnupg/.gpg-agent-info ] && [ -n "$(pgrep gpg-agent)" ]; then
    source ~/.gnupg/.gpg-agent-info
    export GPG_AGENT_INFO
else
    eval $(gpg-agent --daemon --write-env-file ~/.gnupg/.gpg-agent-info)
fi

source $HOME/.homebrew-github-api-token
