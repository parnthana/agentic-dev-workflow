# Interactive-shell helpers for the task worktree tooling. Source this from ~/.zshrc:
#   source /path/to/agentic-dev-workflow/lib/wt/functions.zsh
# The wt commands themselves are scripts (bin/); only things that must change THIS shell live here:
#   wt      — the script writes the worktree dir to $WT_CD_FILE; we cd there
#   wt-done — if it removed the folder we're in, step out to $WORKSPACE
#   wtcd    — fzf picker over worktrees and main checkouts
#   gclean  — delete local branches whose work is done (dry run unless -y)
# Config comes from ~/.config/agentic-dev/workspace.conf (see workspace.conf.example).

_wt_fn_conf() {
  local c=${AGENTIC_DEV_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic-dev/workspace.conf}
  [[ -r $c ]] && source "$c"
  WORKSPACE=${WORKSPACE/#\~/$HOME}
  : ${BASE_BRANCH:=dev} ${MAIN_BRANCH:=main}
}

wt() {
  local f rc
  f=$(mktemp -t wt-cd) || return 1
  WT_CD_FILE=$f command wt "$@"; rc=$?
  [[ -s $f ]] && cd "$(<$f)"
  rm -f "$f"
  return $rc
}

# wtcd [query] — fzf-pick a task worktree or main checkout and cd there (one match → no prompt)
wtcd() {
  _wt_fn_conf
  local J=$WORKSPACE d r
  d=$( { command wt-ls --paths; for r in "$J"/*(N-/); do [[ -e $r/.git ]] && print -r -- "$r"; done; } \
       | sed "s|^$J/||" \
       | fzf --height=40% --reverse --query="$*" --select-1 --exit-0 --prompt='worktree> ' \
             --preview "d={}; [[ \$d == /* ]] || d='$J'/\$d; git -C \$d status -sb | head -20; echo; git -C \$d log --oneline -8" ) || return
  [[ $d == /* ]] || d=$J/$d
  cd "$d"
}

wt-done() {
  command wt-done "$@"; local rc=$?
  _wt_fn_conf
  [[ -d $PWD ]] || cd "$WORKSPACE"
  return $rc
}

# gclean [-y] [--no-gh] — delete local branches whose work is done. Dry run unless -y.
# "Done" = any of: merged into origin/$BASE_BRANCH|origin/$MAIN_BRANCH · upstream gone after fetch --prune ·
#          its PR is MERGED on GitHub and the branch tip is that PR's head (catches squash merges; a reused
#          branch name with newer commits is kept; one gh query, skip with --no-gh).
# Never touches: the base/main/master branches, the current branch, branches checked out in a worktree,
#                branches with commits that exist nowhere else (unpushed, no merged PR) — listed as "kept".
# Also: prunes stale worktree entries, lists stashes older than 30 days (never drops them).
gclean() {
  _wt_fn_conf
  local yes=0 usegh=1 a
  for a in "$@"; do case $a in -y) yes=1 ;; --no-gh) usegh=0 ;; *) echo "usage: gclean [-y] [--no-gh]"; return 1 ;; esac; done
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "gclean: not a git repo"; return 1; }
  git fetch --prune -q origin || return 1
  (( yes )) && git worktree prune      # dry run stays read-only (besides the fetch)
  local cur=$(git branch --show-current) b reason tip o
  local -a bases protect del kept
  local -A merged gone prmerged wt
  for b in origin/$BASE_BRANCH origin/$MAIN_BRANCH; do git rev-parse -q --verify $b >/dev/null && bases+=($b); done
  for b in ${(f)"$(git branch --format='%(refname:short)' --merged ${bases[1]} 2>/dev/null)"} ${(f)"$(git branch --format='%(refname:short)' --merged ${bases[2]:-${bases[1]}} 2>/dev/null)"}; do [[ -n $b ]] && merged[$b]=1; done
  for b in ${(f)"$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2=="[gone]"{print $1}')"}; do [[ -n $b ]] && gone[$b]=1; done
  for b in ${(f)"$(git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2}')"}; do wt[$b]=1; done
  if (( usegh )) && command -v gh >/dev/null; then
    local name oid
    gh pr list --state merged --author @me --limit 1000 --json headRefName,headRefOid \
        -q '.[] | "\(.headRefName) \(.headRefOid)"' 2>/dev/null | while read -r name oid; do
      [[ -n $name ]] && prmerged[$name]+=" $oid"
    done
  fi
  for b in ${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads)"}; do
    [[ $b == ($MAIN_BRANCH|$BASE_BRANCH|master) || $b == $cur || -n ${wt[$b]} ]] && continue
    reason=""
    [[ -n ${merged[$b]} ]] && reason="merged"
    if [[ -z $reason && -n ${prmerged[$b]} ]]; then
      tip=$(git rev-parse "$b")
      for o in ${=prmerged[$b]}; do
        if [[ $o == $tip ]] || git merge-base --is-ancestor "$tip" "$o" 2>/dev/null; then reason="PR merged"; break; fi
      done
      if [[ -z $reason ]]; then kept+=("$b  (a PR with this name was merged, but the branch has commits after it)"); continue; fi
    fi
    [[ -z $reason && -n ${gone[$b]} ]] && reason="remote gone"
    if [[ -z $reason ]]; then continue; fi
    # gone-but-not-merged with commits found on no remote → keep, someone may still need them
    if [[ $reason == "remote gone" ]] && [[ -n $(git log --oneline "$b" --not --remotes 2>/dev/null | head -1) ]]; then
      kept+=("$b  (remote gone, commits exist nowhere else — squash-merged? gh would know; else unpushed work)"); continue
    fi
    del+=("$b|$reason")
  done
  local n_m=0 n_p=0 n_g=0 d; for d in $del; do case ${d#*|} in merged) ((n_m++));; "PR merged") ((n_p++));; *) ((n_g++));; esac; done
  echo "gclean: ${#del} branch(es) done — merged: $n_m · PR merged: $n_p · remote gone: $n_g   (protected/current/worktree skipped)"
  (( ${#kept} )) && { echo "kept — not safe to delete automatically (check, then git branch -D <b>):"; printf '  %s\n' $kept; }
  if (( ${#del} )); then
    echo "$( (( yes )) && echo deleting || echo 'would delete'):"
    if (( yes )); then
      for d in $del; do git branch -D -q "${d%%|*}" && echo "  deleted ${d%%|*}  (${d#*|})"; done
    else
      printf '  %s\n' ${del[1,20]//|/  ← }; (( ${#del} > 20 )) && echo "  … and $(( ${#del} - 20 )) more"
      echo "dry run — delete with: gclean -y"
    fi
  fi
  local old=$(git stash list --format='%ct %gd %s' | awk -v c=$(( $(date +%s) - 30*86400 )) '$1<c' | wc -l | tr -d ' ')
  (( old )) && echo "note: $old stash(es) older than 30 days — review: git stash list --date=relative"
  return 0
}
