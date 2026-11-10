# Say where this shell is. ~/.machine_role is written by install.sh. The factory
# box always shows "factory"; any other machine shows user@host over ssh.
_prompt_where=""
if [[ "$(cat ~/.machine_role 2>/dev/null)" == factory ]]; then
  _prompt_where='%{$fg_bold[magenta]%}factory%{$reset_color%} '
elif [[ -n "$SSH_CONNECTION" ]]; then
  _prompt_where='%{$fg[yellow]%}%n@%m%{$reset_color%} '
fi

PROMPT="${_prompt_where}"'%{$fg[white]%}⌁ %{$fg_bold[blue]%}[%c$(git_prompt_info)%{$fg_bold[blue]%}] %{$reset_color%}'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[grey]%}:%{$fg[blue]%}%{$fg_bold[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX=""
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[cyan]%}."
ZSH_THEME_GIT_PROMPT_CLEAN=""
