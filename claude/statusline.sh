#!/bin/bash
# Claude Code status line: user ➜ [cwd:branch.] model·ctx%·effort
# Receives session JSON on stdin; the first line of stdout is displayed.
# The branch styling (red branch, cyan "." when dirty) mirrors brianfoshee.zsh-theme.

# used_percentage is null early in a session; effort is absent for models
# without effort support. effort stays last because read collapses empty
# tab-separated fields.
IFS=$'\t' read -r cwd model pct effort < <(jq -r '[
  .workspace.current_dir,
  (.model.display_name | sub(" context\\)$"; ")")),
  (.context_window.used_percentage // 0 | floor),
  (.effort.level // "")
] | @tsv')

branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null ||
  git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
dirty=""
if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
  dirty="."
fi

printf "\033[0;37m%s \033[0m➜ \033[1;34m[%s" "$(whoami)" "${cwd/#$HOME/~}"
[ -n "$branch" ] && printf "\033[1;90m:\033[1;31m%s\033[0;36m%s" "$branch" "$dirty"
# context usage: green, yellow from 50%, red from 80%
pctcolor="0;32"
[ "$pct" -ge 50 ] && pctcolor="0;33"
[ "$pct" -ge 80 ] && pctcolor="0;31"
printf "\033[1;34m] \033[0m%s\033[1;37m·\033[${pctcolor}m%s%%\033[0m" "$model" "$pct"
[ -n "$effort" ] && printf "\033[1;37m·\033[0m%s" "$effort"
