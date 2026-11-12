#!/bin/zsh
# SessionStart hook (startup / compact / session restore): when the agent starts inside a task worktree, put the task's
# notes (tasks/_notes/<task>.md) and `wt-ls <task>` into its context, so it doesn't start blind on PR numbers,
# decisions and deploy gates. Silent (no output) anywhere else. Never fails the session.
emulate -L zsh
local input cwd top task notes ls lib
input=$(cat)
cwd=$(print -r -- "$input" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n $cwd && -d $cwd ]] || exit 0
# find lib/wt/lib.zsh: $AGENTIC_DEV_HOME, next to this hook's repo, or an installed copy
for lib in ${AGENTIC_DEV_HOME:+$AGENTIC_DEV_HOME/lib/wt/lib.zsh} "${0:A:h:h}/lib/wt/lib.zsh" ~/.local/lib/wt/lib.zsh; do
  [[ -r $lib ]] && break
  lib=""
done
[[ -n $lib ]] || exit 0
source "$lib" 2>/dev/null || exit 0
# wt-ls shells out to the same lib; make sure the bin/ next to it is on PATH for this hook
path=(${lib:h:h:h}/bin $path)
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ $top == $WORKSPACE/tasks/* ]] || exit 0
task=$(_wt_task_of "$top")
[[ -n $task ]] || exit 0

notes=""
[[ -f $WS_NOTES/$task.md ]] && notes=$(<"$WS_NOTES/$task.md")
ls=$(wt-ls "$task" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g')
# worktrees whose branch doesn't mention the task (a reused folder may hold another task's work)
local d b odd="" match=0
for d in ${(f)"$(_wt_dirs "$task")"}; do
  b=$(git -C "$d" branch --show-current 2>/dev/null)
  [[ -z $b ]] && continue
  local owner=$(git -C "$d" config --get "branch.$b.wttask" 2>/dev/null)
  if [[ -n $owner ]]; then                     # recorded by wt — authoritative
    match=1
    [[ $owner != $task ]] && odd+="  ${d/#$HOME/~} is on '$b', which wt created for task '$owner'"$'\n'
    continue
  fi
  [[ $b == *$task* ]] && match=1               # no record (made by hand) → name heuristic
  [[ $b != *$task* ]] && odd+="  ${d/#$HOME/~} is on '$b' — probably another task's work, not part of '$task'"$'\n'
done
(( match )) || odd=""   # nothing named after the task (e.g. a random branch name) — nothing to compare against
# what this worktree changed vs its base (origin/$MAIN_BRANCH for a -main twin or a repo without a base branch)
local base=origin/$BASE_BRANCH changed=""
[[ ${top:t} == *-main ]] || ! git -C "$top" rev-parse -q --verify "origin/$BASE_BRANCH" >/dev/null && base=origin/$MAIN_BRANCH
changed=$(git -C "$top" diff --name-only "$base...HEAD" 2>/dev/null; git -C "$top" status --porcelain 2>/dev/null | cut -c4-)
local svcs=$(print -r -- "$changed" | sed -nE 's#^(services|apps|packages|libs)/([^/]+)/.*#\1/\2#p' | sort -u | tr '\n' ' ')
local nfiles=$(print -r -- "$changed" | grep -c .)

{
  print -r -- "## Task: $task   (you are in ${top/#$HOME/~})"
  print -r -- ""
  print -r -- "Branch: $(git -C "$top" branch --show-current) · vs $base: $nfiles changed file(s)${svcs:+ in $svcs}"
  print -r -- ""
  print -r -- "Worktrees (wt-ls):"
  print -r -- "$ls"
  [[ -n $odd ]] && { print -r -- ""; print -r -- "WARNING branch mismatch:"; print -rn -- "$odd"; }
  print -r -- ""
  if [[ -n $notes ]]; then
    print -r -- "Task notes (${WS_NOTES/#$HOME/~}/$task.md) — keep them current (PRs, decisions, deploy gates):"
    if (( ${#notes} > 6000 )); then
      print -r -- "${notes[1,6000]}"
      print -r -- "… (notes truncated at 6000 chars — read the full file when you need the rest)"
    else
      print -r -- "$notes"
    fi
  else
    print -r -- "No notes file yet — create ${WS_NOTES/#$HOME/~}/$task.md (goal, PRs, decisions, deploy gates)."
  fi
} | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
