# Task worktrees — BY-REPO layout:
#   $WORKSPACE/<repo>                    main checkouts (stay on $BASE_BRANCH, no feature work)
#   $WORKSPACE/tasks/<repo>/<task>       feature worktree  (branch feat/<task>, off origin/$BASE_BRANCH)
#   $WORKSPACE/tasks/<repo>/<task>-main  main-PR twin      (branch feat/<task>-main, off origin/$MAIN_BRANCH)
#   $WORKSPACE/tasks/_notes/<task>.md    the task's notes (PRs, decisions, deploy gates)
# A task = every worktree named <task>, <task>-main or <task>-dev across the repos.
#
# Loaded by the one-line scripts in bin/ (wt, wt-setup, wt-state, wt-ls, wt-done, wt-open) and by the
# task-context hook. It is deliberately NOT sourced by interactive shells: an agent's shell snapshot keeps
# functions but drops plain variables, so functions defined that way ran with their settings empty. As scripts
# they load their own config and work from any shell (bash, subagents, CI).
# The one thing a script cannot do — cd the caller's shell — is done by the wrappers in functions.zsh,
# which pass WT_CD_FILE (see _wt_cd).
#
# Config: ~/.config/agentic-dev/workspace.conf (see workspace.conf.example).

AGENTIC_DEV_CONF=${AGENTIC_DEV_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic-dev/workspace.conf}
[[ -r $AGENTIC_DEV_CONF ]] && source "$AGENTIC_DEV_CONF"
if [[ -z $WORKSPACE ]]; then
  echo "wt: WORKSPACE is not set — create $AGENTIC_DEV_CONF (template: lib/wt/workspace.conf.example)" >&2
  return 1
fi
WORKSPACE=${WORKSPACE/#\~/$HOME}
: ${BASE_BRANCH:=dev}
: ${MAIN_BRANCH:=main}
(( ${+REPOS} )) || REPOS=()
WS_NOTES="$WORKSPACE/tasks/_notes"
WT_STATE_DIR=${WT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev/wt-setup}

# _wt_cd <dir> — cd here, and tell the calling shell's wrapper where to go (a script can't cd its caller)
_wt_cd() { [[ -n $WT_CD_FILE ]] && print -r -- "$1" >| "$WT_CD_FILE"; cd "$1"; }

_wt_base() {  # repo-dir flavour → base ref
  local d=$1 flavour=$2
  if [[ $flavour == main ]] || ! git -C "$d" rev-parse -q --verify "origin/$BASE_BRANCH" >/dev/null; then
    echo "origin/$MAIN_BRANCH"
  else
    echo "origin/$BASE_BRANCH"
  fi
}

# Worktrees live in tasks/<repo folder name>/<name>. The folder name is the main checkout's REAL basename
# (resolves a symlinked checkout), so every tool that derives the path agrees on it.
_wt_rdir() { print -r -- "${${:-$WORKSPACE/$1}:A:t}"; }          # repo → folder name used under tasks/
_wt_is_repo() {                                                   # is $1 a repo name or a repo folder name?
  [[ -n $1 && $1 != _* ]] || return 1
  [[ -e $WORKSPACE/$1/.git ]] && return 0
  local r; for r in "$WORKSPACE"/*(N-/); do [[ -e $r/.git && ${r:A:t} == $1 ]] && return 0; done
  return 1
}

# _wt_dirs [task] — every worktree dir of a task (or all), one per line
_wt_dirs() {
  local t=$1 d n r
  for d in "$WORKSPACE"/tasks/*/*(N/); do               # tasks/<repo>/<name>
    r=${d:h:t}; n=${d:t}
    _wt_is_repo "$r" || continue
    [[ -e $d/.git ]] || continue
    if [[ -z $t || $n == $t || $n == $t-main || $n == $t-dev ]]; then print -r -- "$d"; fi
  done
}

# _wt_task_of <dir> — the task a worktree dir belongs to
_wt_task_of() {
  local n=${1:t}
  n=${n%-main}; n=${n%-dev}; print -r -- "$n"
}

# _wt_label <dir> — repo/name for display
_wt_label() { print -r -- "${1:h:t}/${1:t}"; }

# _wt_pick <src> <dev-branch> <twin-dir> — cherry-pick the dev branch's OWN commits into the main twin.
# Own commits = first-parent, non-merge commits since the branch's start point (recorded by wt as
# branch.<b>.wtbase; else merge-base with origin/$BASE_BRANCH). --first-parent skips whatever came in via
# "merge origin/<base> into feat", so base-only work never reaches main. Already-picked commits (the
# "(cherry picked from commit …)" trailer from -x) are skipped, so re-running = sync new dev commits.
_wt_pick() {
  local src=$1 dev=$2 twin=$3 ref base c
  local -a todo picked
  if git -C "$src" rev-parse -q --verify "refs/heads/$dev" >/dev/null; then ref=$dev
  elif git -C "$src" rev-parse -q --verify "refs/remotes/origin/$dev" >/dev/null; then ref=origin/$dev
  else echo "wt: no dev branch $dev"; return 1; fi
  base=$(git -C "$src" config --get "branch.$dev.wtbase") || base=$(git -C "$src" merge-base "$ref" "origin/$BASE_BRANCH") || return 1
  todo=(${(f)"$(git -C "$src" rev-list --reverse --first-parent --no-merges "$base..$ref")"})
  picked=(${(f)"$(git -C "$twin" log --format=%b "origin/$MAIN_BRANCH..HEAD" | sed -n 's/^(cherry picked from commit \([0-9a-f]*\))$/\1/p')"})
  todo=(${todo:|picked})
  if (( ! ${#todo} )); then echo "wt: nothing new to pick from $ref"; return 0; fi
  echo "wt: picking ${#todo} commit(s) from $ref:"
  for c in $todo; do echo "  $(git -C "$src" log -1 --format='%h %s' "$c")"; done
  if ! git -C "$twin" cherry-pick -x --allow-empty --empty=drop $todo; then
    echo "wt: CONFLICT in ${twin/#$HOME/~} — resolve, then: git cherry-pick --continue  (or --abort);"
    echo "    if package.json / a lockfile was involved, run: wt-setup ${twin/#$HOME/~}"
    return 1
  fi
}

_wt_notes_template() {
  cat <<TPL
# $1
Goal: <!-- ONE line: the problem in user terms; it becomes the ticket title -->
<!-- One heading each: add to the existing section, never a second ## PRs / ## Checks run. Current state = OVERWRITE. -->

## Goal & acceptance criteria
<!-- why / who asked (1-2 lines) · "- AC1: <what the user sees> (C01)" bullets · "- Out of scope: ..." -->

## Current state → next action
<!-- overwrite on every change: 2-6 lines, the latest state + the ONE next action; history goes to Decisions / Handoff -->

## PRs

## Decisions

## Checks run (command · commit · result)

## Known failures / blockers

## Running services (port · pid · log)

## Deploy gates

## Outcome
<!-- success signal · query · baseline · check date · result: pending -->
TPL
}

# wt <task> <repo> [branch] [--main]
#   feature worktree off origin/$BASE_BRANCH; --main = main-PR twin off origin/$MAIN_BRANCH WITH the dev branch's
#   commits cherry-picked in (run it when the dev side is ready; re-run to pick newer dev commits)
wt() {
  local main=0 setup=1 reassign=0 args=() a
  for a in "$@"; do
    case $a in --main) main=1 ;; --no-setup) setup=0 ;; --reassign) reassign=1 ;; *) args+=("$a") ;; esac
  done
  local task=${args[1]} repo=${args[2]} branch=${args[3]:-feat/${args[1]}}
  if [[ -z $task || -z $repo ]]; then
    echo "usage: wt <task> <repo> [branch] [--main] [--no-setup] [--reassign]   repos: ${REPOS[*]}"; return 1
  fi
  [[ $task == *-main || $task == *-dev || $task == _* ]] && { echo "wt: task names may not end in -main/-dev or start with _"; return 1; }
  local src="$WORKSPACE/$repo"
  [[ -d $src/.git || -f $src/.git ]] || { echo "wt: no main checkout at $src"; return 1; }

  # --main without an explicit branch: use the branch of the task's existing dev worktree, whatever made it
  if (( main )) && [[ -z ${args[3]} ]]; then
    local found=$(git -C "$src" worktree list --porcelain | awk -v t="$task" '
      /^worktree /{ p=substr($0,10); n=split(p,a,"/") }
      /^branch /  { if (a[n]==t) { sub(/^branch refs\/heads\//,""); print; exit } }')
    [[ -n $found ]] && branch=$found
  fi
  local rdir=$(_wt_rdir "$repo")
  local dir="$WORKSPACE/tasks/$rdir/$task" dev=$branch flavour=dev
  if (( main )); then dir+="-main"; branch+="-main"; flavour=main; fi
  git -C "$src" fetch -q origin || return 1
  if (( main )) && ! git -C "$src" rev-parse -q --verify "origin/$BASE_BRANCH" >/dev/null; then
    echo "wt: $repo has no $BASE_BRANCH branch — one PR to $MAIN_BRANCH, no twin needed"; return 1
  fi
  if (( main )) && ! git -C "$src" rev-parse -q --verify "refs/heads/$dev" >/dev/null &&
     ! git -C "$src" rev-parse -q --verify "refs/remotes/origin/$dev" >/dev/null; then
    echo "wt: no dev branch '$dev' to cherry-pick from — create the dev side first (wt $task $repo), or pass the branch"
    return 1
  fi
  # task ownership — checked before anything else (new AND existing worktrees): a branch wt made for another task is refused, so the
  # record the context hook relies on is never silently rewritten
  local prev=$(git -C "$src" config --get "branch.$branch.wttask")
  if [[ -n $prev && $prev != $task ]] && (( ! reassign )); then
    echo "wt: branch '$branch' belongs to task '$prev' — use another branch name, or --reassign to move it to '$task'"
    return 1
  fi
  if [[ -e $dir ]]; then
    echo "wt: $dir exists"
    # same repository? (an unrelated checkout at this path must not be cherry-picked into)
    local dcommon=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    local scommon=$(git -C "$src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [[ -z $dcommon || ${dcommon:A} != ${scommon:A} ]]; then
      echo "wt: $dir is not a worktree of $repo — not touching it"; return 1
    fi
    local cur=$(git -C "$dir" branch --show-current 2>/dev/null)
    if [[ $cur != $branch ]]; then
      if (( main )); then   # never cherry-pick onto whatever branch the folder happens to be on
        echo "wt: $dir is on '${cur:-detached HEAD}', not '$branch' — not touching it (switch it back, or pass the branch)"
        return 1
      fi
      echo "wt: note — $dir is on '${cur:-detached HEAD}', not '$branch'"
    fi
    if [[ -n $prev && $prev != $task ]]; then   # --reassign, and every check above passed
      git -C "$src" config "branch.$branch.wttask" "$task"; echo "wt: branch '$branch' reassigned from task '$prev' to '$task'"
    fi
    _wt_cd "$dir"
    if (( main )); then
      local before=$(git -C "$dir" rev-parse HEAD)
      _wt_pick "$src" "$dev" "$dir" || return 1
      # newly picked commits changed dependencies → refresh node_modules so tests don't run on stale modules
      if (( setup )) && [[ -n $WT_SETUP ]] && git -C "$dir" diff --name-only "$before" HEAD | grep -qE '(^|/)(package\.json|yarn\.lock|package-lock\.json|pnpm-lock\.yaml|\.nvmrc)$'; then
        echo "wt: dependency files changed in the picked commits — refreshing setup"
        wt-setup "$dir" --bg
      fi
    fi
    return 0
  fi

  mkdir -p "$WORKSPACE/tasks/$rdir" "$WS_NOTES"
  if git -C "$src" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    git -C "$src" worktree add "$dir" "$branch"
  elif git -C "$src" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
    git -C "$src" worktree add --track -b "$branch" "$dir" "origin/$branch"
  else
    local base=$(_wt_base "$src" $flavour)
    git -C "$src" worktree add --no-track -b "$branch" "$dir" "$base" && echo "wt: $branch from $base" &&
      git -C "$src" config "branch.$branch.wtbase" "$(git -C "$src" rev-parse "$base")"
  fi || return 1
  [[ -n $prev && $prev != $task ]] && echo "wt: branch '$branch' reassigned from task '$prev' to '$task'"
  git -C "$src" config "branch.$branch.wttask" "$task"   # task identity: the hook trusts it over name guesses
  if [[ ! -f $WS_NOTES/$task.md ]]; then
    _wt_notes_template "$task" > "$WS_NOTES/$task.md"
    # first worktree of a new task → optional hook (e.g. board ticket In Progress); background, never blocks wt
    (( main )) || { [[ -n $WT_ON_TASK_START ]] && ( $WT_ON_TASK_START "$task" >/dev/null 2>&1 & ) }
  fi
  _wt_cd "$dir"
  if (( main )); then _wt_pick "$src" "$dev" "$dir" || return 1; fi   # cherry-picks first: they can change package.json / lockfiles
  (( setup )) && [[ -n $WT_SETUP ]] && wt-setup "$dir" --bg
  return 0
}

# _wt_state <worktree-dir> → prints state ("dirty 3", "unpushed 2", "no upstream", "upstream gone"), empty = clean.
# "upstream gone" = it WAS pushed and the remote branch is deleted now (normal after a PR merges, with
# fetch.prune) — informational, not blocking: wt-done keeps the branch, so no commit is lost.
_wt_state() {
  local d=$1 out=() n b
  n=$(git -C "$d" status --porcelain | wc -l | tr -d ' ')
  (( n )) && out+=("dirty $n")
  b=$(git -C "$d" branch --show-current)
  if git -C "$d" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
    n=$(git -C "$d" rev-list --count '@{u}..HEAD')
    (( n )) && out+=("unpushed $n")
  elif [[ -n $b && -n $(git -C "$d" config --get "branch.$b.merge") ]]; then
    out+=("upstream gone (merged?)")
  else
    out+=("no upstream")
  fi
  echo "${(j:, :)out}"
}
_wt_blocking() { [[ $1 == *dirty* || $1 == *unpushed* || $1 == *"no upstream"* ]]; }   # what wt-done refuses on

# wt-setup <dir> [--bg] — run the configured $WT_SETUP script for a worktree (deps install, env files).
# --bg: background, log + status under $WT_STATE_DIR. wt runs it automatically for new worktrees
# (skip: --no-setup). The status file is written HERE, so the setup script need not know about it.
wt-setup() {
  local d=${1:-$PWD}; d=${d:A}
  [[ -n $WT_SETUP && -x $WT_SETUP ]] || { echo "wt-setup: no executable WT_SETUP configured (${WT_SETUP:-unset})"; return 1; }
  local key=${d:h:t}__${d:t} log st
  mkdir -p "$WT_STATE_DIR"; log=$WT_STATE_DIR/$key.log; st=$WT_STATE_DIR/$key.status
  if [[ $2 == --bg ]]; then
    print running >| "$st"
    ( if "$WT_SETUP" "$d" >"$log" 2>&1; then print done >| "$st"; else print "failed: see ${log/#$HOME/~}" >| "$st"; fi ) &!
    echo "wt: running setup in the background → wt-ls shows 'setup running'; log: ${log/#$HOME/~}"
  else
    setopt localoptions pipefail   # tee would otherwise hide the setup script's exit status
    print running >| "$st"
    if "$WT_SETUP" "$d" 2>&1 | tee "$log"; then print done >| "$st"; else print "failed: see ${log/#$HOME/~}" >| "$st"; return 1; fi
  fi
}
# _wt_setup_state <dir> → "none" (never ran) / "running" / "done" / "failed: …"
_wt_setup_state() {
  local f=$WT_STATE_DIR/${1:A:h:t}__${1:t}.status
  if [[ -f $f ]]; then print -r -- "$(<$f)"; else print none; fi
}

# wt-state <dir> — print the worktree's setup state (none / running / done / failed: …)
# wt-state --wait <dir> [max-seconds=300] — block until it's no longer running; prints the final state;
#   exit 0 = finished (check the state!), 124 = still running at the limit. Run it in the background.
wt-state() {
  local wait=0 d max=300 i=0
  [[ $1 == --wait ]] && { wait=1; shift; }
  d=${1:-$PWD}; [[ -n $2 ]] && max=$2
  [[ -d $d ]] || { echo "usage: wt-state [--wait] <worktree-dir> [max-seconds]"; return 1; }
  if (( wait )); then
    while [[ $(_wt_setup_state "$d") == running ]]; do
      (( i >= max )) && { echo running; return 124; }
      sleep 10; (( i += 10 ))
    done
  fi
  _wt_setup_state "$d"
}

# wt-ls [--paths] [task] — worktrees grouped by task, with state; notes path when present
wt-ls() {
  local d t st paths=0
  local -a dirs tasks
  [[ $1 == --paths ]] && { paths=1; shift; }
  dirs=(${(f)"$(_wt_dirs "$1")"})
  if (( paths )); then (( ${#dirs} )) && print -rl -- $dirs; return 0; fi   # plain dirs, for scripts / wtcd
  for d in $dirs; do tasks+=("$(_wt_task_of "$d")"); done
  for t in ${(ou)tasks}; do
    print -P "%B$t%b$([[ -f $WS_NOTES/$t.md ]] && print -n "  %F{8}(notes: tasks/_notes/$t.md)%f")"
    for d in $dirs; do
      [[ $(_wt_task_of "$d") == $t ]] || continue
      st=$(_wt_state "$d")
      local ss=""
      if [[ -n $WT_SETUP ]]; then
        ss=$(_wt_setup_state "$d")
        case $ss in done) ss="" ;; none) ss="never ran" ;; esac   # done = quiet; never ran = wt-setup <dir>
      fi
      printf '  %-34s %-40s %s\n' "$(_wt_label "$d")" "$(git -C "$d" branch --show-current)" "${st:-✓ clean}${ss:+  · setup $ss}"
    done
  done
}

# wt-done <task> [--force] — remove every worktree of the task; refuses on dirty / unpushed /
# never-pushed unless --force ("upstream gone" after a merge is fine). Branches are kept (gclean deletes them
# after merge). Notes (<task>.md and the <task>/ folder with reports) are archived to ~/notes/tasks/.
wt-done() {
  local task=$1 force=0 bad=0 d st src
  [[ $2 == --force ]] && force=1
  local -a wts
  [[ -n $task ]] && wts=(${(f)"$(_wt_dirs "$task")"})
  wts=(${wts:#})
  if (( ! ${#wts} )); then
    # no worktrees left, but notes may still be there → just tidy those up
    if [[ -z $task || $task == _* ]] || _wt_is_repo "$task" || [[ ! -f $WS_NOTES/$task.md && ! -d $WS_NOTES/$task ]]; then
      echo "usage: wt-done <task> [--force]   (nothing found for '$task')"; return 1
    fi
    echo "wt-done: no worktrees for '$task' — archiving its notes only"
  fi
  for d in $wts; do
    st=$(_wt_state "$d")
    [[ -n $st ]] && echo "  ${d/#$HOME/~}: $st"
    _wt_blocking "$st" && bad=1
  done
  if (( bad && !force )); then echo "wt-done: refusing — push/commit first, or --force"; return 1; fi

  local -a fflag; (( force )) && fflag=(--force)
  for d in $wts; do
    if [[ $PWD == $d || $PWD == $d/* ]]; then cd "$WORKSPACE"; fi
  done
  for d in $wts; do
    src=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)
    git --git-dir="$src" worktree remove $fflag "$d" && echo "removed ${d/#$HOME/~}"
  done
  local nf dest i
  nf=$WS_NOTES/$task.md
  if [[ -f $nf ]]; then
    mkdir -p ~/notes/tasks
    dest=~/notes/tasks/$task.md; i=1
    while [[ -e $dest ]]; do dest=~/notes/tasks/$task-$(date +%Y%m%d)-$((i++)).md; done   # never overwrite an archive
    mv "$nf" "$dest" && echo "notes → ${dest/#$HOME/~}"
  fi
  if [[ -d $WS_NOTES/$task ]]; then                                        # task folder: QA reports, screenshots
    mkdir -p ~/notes/tasks
    dest=~/notes/tasks/$task; i=1
    while [[ -e $dest ]]; do dest=~/notes/tasks/$task-$(date +%Y%m%d)-$((i++)); done
    mv "$WS_NOTES/$task" "$dest" && echo "notes folder → ${dest/#$HOME/~}"
  fi
  return 0
}

# wt-open <task> [--lead <repo>|--per-repo] [--with-main] [--cmd "<command>"] [--prompt "<first instruction>"]
#         [--iterm|--terminal] [--dry-run]
# Default: ONE lead agent for the task, in the lead repo's worktree (--lead, else the first repo in $REPOS that
# has one), started with --add-dir for every sibling worktree AND the notes folder, so it can read + edit them
# without permission prompts (only for `claude`). --per-repo: one agent per worktree (only for independent
# parts). -main twins are skipped unless --with-main. Target: iTerm2 if installed, else Terminal.app (macOS).
wt-open() {
  local task="" withmain=0 dry=0 cmd="claude" prompt="" target="" perrepo=0 lead=""
  while (( $# )); do
    case $1 in
      --with-main) withmain=1 ;;
      --dry-run)   dry=1 ;;
      --cmd)       shift; cmd=$1 ;;
      --prompt)    shift; prompt=$1 ;;
      --per-repo)  perrepo=1 ;;
      --lead)      shift; lead=$1 ;;
      --iterm)     target=iterm ;;
      --terminal)  target=terminal ;;
      -*)          echo "wt-open: unknown option $1"; return 1 ;;
      *)           task=${task:-$1} ;;
    esac
    shift
  done
  local usage="usage: wt-open <task> [--lead <repo>|--per-repo] [--with-main] [--cmd \"…\"] [--prompt \"…\"] [--iterm|--terminal] [--dry-run]"
  [[ -n $task ]] || { echo "$usage"; return 1; }
  local is_claude=0; [[ ${cmd%% *} == claude ]] && is_claude=1   # decided once, before any prefix is added
  local d n=0 line
  local -a all wts targets
  all=(${(f)"$(_wt_dirs "$task")"}); all=(${all:#})
  for d in $all; do
    (( withmain )) || [[ ${d:t} != *-main ]] || continue
    wts+=("$d")
  done
  (( ${#wts} )) || { echo "wt-open: no worktrees for '$task'"; echo "$usage"; return 1; }
  if [[ -z $target ]]; then
    if [[ -d /Applications/iTerm.app ]]; then target=iterm; else target=terminal; fi
  fi
  if (( perrepo )); then
    targets=($wts)
  else
    local ld="" want=${lead:-${REPOS[1]}}
    for d in $wts; do
      if [[ ${d:h:t} == ($want|$(_wt_rdir "$want")) ]]; then ld=$d; break; fi
    done
    [[ -n $lead && -z $ld ]] && { echo "wt-open: no '$lead' worktree in task $task"; return 1; }
    [[ -z $ld ]] && ld=${wts[1]}
    targets=("$ld")
    if (( is_claude )); then
      for d in $wts; do [[ $d != $ld ]] && cmd+=" --add-dir ${(q)d}"; done
      [[ -d $WS_NOTES ]] && cmd+=" --add-dir ${(q)WS_NOTES}"
      cmd="CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 $cmd"   # also load the siblings' CLAUDE.md (repo-specific rules)
    fi
  fi
  # `--add-dir <directories...>` is variadic and would swallow the prompt → end options with `--` (claude)
  if [[ -n $prompt ]]; then
    if (( is_claude )); then cmd="$cmd -- ${(q)prompt}"; else cmd="$cmd ${(q)prompt}"; fi
  fi
  local base=$cmd name
  for d in $targets; do
    cmd=$base
    if (( is_claude )); then   # session display name → picker / terminal title
      name="task:$task"; (( perrepo )) && name+="/${d:h:t}"
      cmd=${base/claude/claude -n ${(q)name}}
    fi
    line="cd ${(q)d} && $cmd"
    if (( dry )); then
      echo "[$target] $(_wt_label "$d"): $line"
    elif [[ $target == iterm ]]; then
      osascript - "$line" <<'OSA' >/dev/null
on run argv
  tell application id "com.googlecode.iterm2"
    activate
    if (count of windows) = 0 then
      create window with default profile
    else
      tell current window to create tab with default profile
    end if
    tell current session of current window to write text (item 1 of argv)
  end tell
end run
OSA
    else
      osascript - "$line" <<'OSA' >/dev/null
on run argv
  tell application "Terminal"
    activate
    do script (item 1 of argv)
  end tell
end run
OSA
    fi
    (( n++ ))
  done
  (( dry )) || echo "opened $n agent(s) in $target$( (( perrepo )) || echo " (lead: $(_wt_label "${targets[1]}"); siblings + notes via --add-dir)")"
}
