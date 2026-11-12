#!/bin/zsh
# PreToolUse guard (Bash | Edit | Write | MultiEdit | NotebookEdit). Turns workspace rules (your CLAUDE.md and the
# PR command) into checks the harness enforces, instead of prose the model has to remember. Decisions:
#   deny — never allowed (committing a yalc-linked package.json)
#   ask  — the user may allow it in the prompt: PR without checks / cases, edits in a main checkout,
#          prod / secret / deploy commands, destructive git.
# Silent (exit 0, no output) when nothing matches. Never blocks on its own errors.
# Config: ~/.config/agentic-dev/workspace.conf (WORKSPACE, REPOS); optional GUARD_PROD_PROFILE_RE (default "prod").
# Test: print -r -- '{"tool_name":"Bash","cwd":"…","tool_input":{"command":"gh pr create …"}}' | zsh guard.zsh
emulate -L zsh
setopt extendedglob
local input tool cwd cmd fp
input=$(cat)
tool=$(print -r -- "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
cwd=$(print -r -- "$input" | jq -r '.cwd // empty' 2>/dev/null)
local conf=${AGENTIC_DEV_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agentic-dev/workspace.conf}
local WORKSPACE="" PROD_RE=${GUARD_PROD_PROFILE_RE:-prod}
local -a REPOS
[[ -r $conf ]] && source "$conf"
[[ -n $WORKSPACE ]] || exit 0                 # not configured → no rules to enforce
WORKSPACE=${WORKSPACE/#\~/$HOME}
local NOTES=$WORKSPACE/tasks/_notes
local -a MAIN_REPOS=($REPOS)

decide() {  # decide <deny|ask> <reason>
  jq -n --arg d "$1" --arg r "guard: $2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# Directory a command runs in: `cd <dir> &&` prefix or `git -C <dir>`, else the session cwd.
cmd_dir() {
  local c=$1 d=""
  [[ $c =~ '(^|[;&|][[:space:]]*)cd[[:space:]]+("[^"]+"|[^[:space:];&|]+)' ]] && d=${match[2]//\"/}
  [[ -z $d && $c =~ 'git[[:space:]]+-C[[:space:]]+("[^"]+"|[^[:space:]]+)' ]] && d=${match[1]//\"/}
  d=${d/#\~/$HOME}
  [[ -n $d && $d != /* ]] && d=$cwd/$d
  print -r -- "${d:-$cwd}"
}

# Task name of a task worktree path (tasks/<repo>/<task>[-main|-dev]), else empty.
task_of() {
  local top=$1
  [[ $top == $WORKSPACE/tasks/*/* ]] || return 0
  local rel=${top#$WORKSPACE/tasks/} n
  n=${${rel#*/}%%/*}
  n=${n%-main}; n=${n%-dev}
  print -r -- "$n"
}

# Text of one "## <name>" section of a notes file (up to the next "## ").
section() {
  awk -v h="## $2" 'index($0,h)==1{on=1;next} on&&/^## /{on=0} on' "$1" 2>/dev/null
}

# ---- sandbox mode (evaluation runs of agent skills) ----
# AGENTIC_SANDBOX=<dir> is set by the eval wrapper on the agent process it starts; the hook inherits it from that
# process, so a command inside the session cannot unset it. Blocks workspace tools, network/cloud CLIs, git remotes,
# edits outside the sandbox and any Bash command naming a home path (~, $HOME, /Users/). Best effort for Bash —
# a command can still be built to escape; the runner also refuses to start without AGENTIC_SANDBOX.
if [[ -n ${AGENTIC_SANDBOX-} ]]; then
  local sb=${AGENTIC_SANDBOX:A}
  local NET='(^|[^[:alnum:]_-])(wt(-[a-z]+)?|ro-[a-z]+|gh|aws|gclean|contract-link|contract-unlink|curl|wget|ssh|scp|psql|sqlplus|npx|yarn|docker)([[:space:]]|$)'
  local PATHS='(/notes/|\.aws|\.ssh|\.config/gh|\$HOME|\$\{HOME|/Users/)'
  case $tool in
    Edit|Write|MultiEdit|NotebookEdit)
      fp=$(print -r -- "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
      [[ -z $fp || ${fp:A} == $sb/* ]] || decide deny "sandbox run: edits only inside $sb (got $fp)."
      ;;
    Bash)
      cmd=$(print -r -- "$input" | jq -r '.tool_input.command // empty')
      # Fake data tools: ro-sql/ro-pg/ro-es/board → $sb/.stubs/<tool> (the eval runner installs them; data per
      # scenario, outside the scenario dir). The real ones may be shell functions, so PATH order cannot be
      # trusted — the command itself is rewritten to the stub's absolute path, then checked like any other.
      local stub=$sb/.stubs
      if [[ -x $stub/ro-sql && $cmd =~ '(^|[^[:alnum:]_/.-])(ro-sql|ro-pg|ro-es|board)([[:space:]]|$)' ]]; then
        local new chk
        new=$(print -r -- "$cmd" | sed -E "s#(^|[^[:alnum:]_/.-])(ro-(sql|pg|es)|board)([[:space:]]|\$)#\\1$stub/\\2\\4#g")
        new=$(print -r -- "$new" | sed -E "s#(^|[^[:alnum:]_/.-])(ro-(sql|pg|es)|board)([[:space:]]|\$)#\\1$stub/\\2\\4#g")   # twice: adjacent matches share a separator
        chk=${new//$stub\/ro-/STUB-}
        chk=${chk//$stub\/board/STUB-board}
        if [[ $chk =~ $NET || $chk =~ 'git[[:space:]].*(push|remote|fetch|pull|clone)' \
           || $chk =~ $PATHS || $chk =~ '(^|[[:space:]=:"])~(/|[[:space:]]|$)' ]]; then
          decide deny "sandbox run: workspace / network / cloud commands are not allowed here."
        fi
        print -r -- "$input" | jq --arg c "$new" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"guard: sandbox data tool",updatedInput:(.tool_input|.command=$c)}}'
        exit 0
      fi
      if [[ $cmd =~ $NET || $cmd =~ 'git[[:space:]].*(push|remote|fetch|pull|clone)' \
         || $cmd =~ $PATHS || $cmd =~ '(^|[[:space:]=:"])~(/|[[:space:]]|$)' ]]; then
        decide deny "sandbox run: workspace / network / cloud commands are not allowed here."
      fi
      ;;
  esac
  exit 0
fi

case $tool in
  Edit|Write|MultiEdit|NotebookEdit)
    fp=$(print -r -- "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    [[ -n $fp ]] || exit 0
    local r
    for r in $MAIN_REPOS; do
      if [[ $fp == $WORKSPACE/$r/* ]]; then
        decide ask "$fp is in the MAIN checkout $WORKSPACE/$r (stays on the base branch; feature edits belong in tasks/$r/<task>). Allow only if you meant to edit the main checkout."
      fi
    done
    # Build gate: source edits in a task worktree need a case matrix or an explicit skip in the notes — in
    # practice agents skipped case discovery entirely unless something enforced it. Tests, docs, notes and config
    # are not gated.
    if [[ $fp == $WORKSPACE/tasks/*/*/(services|apps|libs|packages)/*.(ts|tsx|js|jsx|sql|prisma) && $fp != *(.spec.|.test.|.e2e-spec.|/test/|/tests/|/__tests__/)* ]]; then
      local tk=$(task_of "${fp%%/(services|apps|libs|packages)/*}")
      local nf=$NOTES/$tk.md
      if [[ -n $tk && -f $nf ]] && ! grep -qiE '^Cases: *(n/a|skip)' "$nf" && ! section "$nf" "Cases" | grep -qE '^\| *C[0-9]+ '; then
        decide ask "task '$tk' has no ## Cases matrix — build gate: run the case-discovery command first, or (with the user's OK) write 'Cases: n/a — <reason, user OK, date>' under the notes title."
      fi
    fi
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(print -r -- "$input" | jq -r '.tool_input.command // empty')
[[ -n $cmd ]] || exit 0

# ---- file writes via Bash in a main checkout → same ask as Edit/Write there ----
# Observed in eval runs: an agent patched code with `python3 - <<EOF … open(p,'w')`, which the Edit/Write rule
# above never sees. Heuristic: in-place editors, script file writes, tee, and `>` redirects to a file path.
# Redirects to /dev/null and temp dirs are ignored. Ask, never deny (false positives are fine).
() {
  local wd=${$(cmd_dir "$cmd"):A} r c=$cmd
  c=${c//[0-9&]#>>#[[:space:]]#\/dev\/null/}
  c=${c//[0-9&]#>>#[[:space:]]#[\"\']#(\/tmp|\/private\/tmp|\/var\/folders|\$TMPDIR|\$\{TMPDIR\})[^[:space:];&|]#/}
  for r in $MAIN_REPOS; do
    [[ $wd/ == $WORKSPACE/$r/* || $c == *$WORKSPACE/$r/* ]] || continue
    if [[ $c =~ '(^|[[:space:];&|])(sed|perl)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*i' \
       || $c =~ '(write_text|write_bytes|writeFileSync|writeFile\(|open\([^)]*,[[:space:]]*.[wa]\+?.)' \
       || $c =~ '(^|[[:space:];&|])tee[[:space:]]' \
       || $c =~ '(^|[^0-9&>=<-])>>?[[:space:]]*["'"'"']?[A-Za-z0-9_.~/-]*[A-Za-z0-9_-]\.[A-Za-z]{1,6}([[:space:];&|"'"'"']|$)' ]]; then
      decide ask "Bash writes files in the MAIN checkout $WORKSPACE/$r (sed -i / script write / tee / > file). Feature edits belong in tasks/$r/<task>; read-only investigation never writes. Allow only if the user meant it."
    fi
  done
}

# ---- prod / secrets / deploys → the user decides ----
if [[ $cmd =~ '--with-decryption' ]]; then
  decide ask "reads secret values (--with-decryption)."
fi
if [[ $cmd =~ 'aws[[:space:]].*ssm[[:space:]]+(put|delete)-parameter' \
   || $cmd =~ 'aws[[:space:]].*ecs[[:space:]]+(update-service|run-task|stop-task|delete-service)' ]]; then
  decide ask "deploy / parameter-store write / container-service change — the user's call (propose the command, don't run it)."
fi
# ro-sql / ro-pg / ro-es are read-only by construction (READ ONLY transaction, default_transaction_read_only,
# an endpoint allowlist), so they may be pre-approved even for prod. Raw cloud CLI on prod still asks.
if [[ $cmd =~ "(--profile[= ]$PROD_RE|AWS_PROFILE=$PROD_RE)" ]]; then
  decide ask "touches PROD (prod cloud profile)."
fi

# ---- destructive / outward git → the user decides ----
local G='(^|[[:space:];&|(])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'
if [[ $cmd =~ "${G}push([[:space:]]|\$)" ]]; then
  if [[ $cmd =~ '(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[^[:space:]]+)' ]]; then
    decide ask "FORCE push — rewrites the remote branch."
  fi
  decide ask "git push — push only when the user asked for it in this conversation."
fi
if [[ $cmd =~ "${G}reset[[:space:]].*--hard" ]]; then
  decide ask "git reset --hard discards uncommitted work."
fi
if [[ $cmd =~ "${G}clean[[:space:]]+(-[a-zA-Z]*f|--force)" ]]; then
  decide ask "git clean -f deletes untracked files."
fi
if [[ $cmd =~ "${G}branch[[:space:]]+(.*[[:space:]])?(-D|--delete[[:space:]]+--force|-d[[:space:]]+-f)([[:space:]]|\$)" ]]; then
  decide ask "git branch -D deletes a branch even if unmerged."
fi
if [[ $cmd =~ "${G}(checkout|restore)[[:space:]]+(--[[:space:]]+)?\\.([[:space:]]|\$)" || $cmd =~ "${G}checkout[[:space:]]+-f([[:space:]]|\$)" ]]; then
  decide ask "discards working-tree changes (checkout/restore .)."
fi

# ---- git commit with a yalc-linked package.json → never ----
if [[ $cmd =~ '(^|[[:space:];&|])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' ]]; then
  local d top f
  d=$(cmd_dir "$cmd")
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n $top ]]; then
    # Every package.json that differs from HEAD, staged OR not: the hook runs before the command, so a chained
    # `git add -A && git commit` / `commit -a` would stage it after this check. Unlink before ANY commit.
    for f in ${(f)"$( { git -C "$top" diff --cached --name-only; git -C "$top" diff --name-only; } 2>/dev/null | sort -u)"}; do
      [[ ${f:t} == package.json ]] || continue
      { git -C "$top" show ":$f" 2>/dev/null; cat "$top/$f" 2>/dev/null; } | grep -q 'file:\.yalc' && \
        decide deny "$f links a dependency to file:.yalc — run contract-unlink before committing (never commit yalc pins)."
    done
    # Observed in eval runs: under time pressure the agent committed code without any test. In a task worktree,
    # a commit that changes source under services/apps/libs/packages but no test file → ask.
    if [[ -n $(task_of "$top") ]]; then
      local -a chg=(${(f)"$( { git -C "$top" diff --cached --name-only; [[ $cmd =~ '(add[[:space:]]+(-A|--all|\.)|commit[^|;&]*[[:space:]]-[a-zA-Z]*a)' ]] && git -C "$top" diff --name-only; [[ $cmd =~ 'add[[:space:]]+(-A|--all|\.)' ]] && git -C "$top" ls-files --others --exclude-standard; } 2>/dev/null | sort -u)"})
      local -a src=(${(M)chg:#(services|apps|libs|packages)/*.(ts|tsx|js|jsx)}) tst=(${(M)chg:#*(.spec.|.test.|.e2e-spec.|/test/|/tests/|/__tests__/)*})
      src=(${src:#*(.spec.|.test.|.e2e-spec.|/test/|/tests/|/__tests__/)*})
      (( ${#src} && ! ${#tst} )) && decide ask "commit changes ${#src} source file(s) and no test — test first. Allow only for a change no test can reach (say why in the commit body)."
      # Observed in eval runs: one commit for all cases, no ids. With a case matrix in the notes, a source commit
      # names the case(s) it covers: [C03] / [C01,C02].
      local nf=$NOTES/$(task_of "$top").md
      if (( ${#src} )) && [[ -f $nf ]] && section "$nf" "Cases" | grep -qE '^\| *C[0-9]+ ' && ! [[ $cmd =~ '\[C[0-9]+' ]]; then
        decide ask "commit message names no case id — one commit per case (group) ending in [C<id>]. Allow if this commit covers no case (say why)."
      fi
    fi
  fi
  exit 0
fi

# ---- gh pr create → checks on HEAD + case matrix, else ask ----
if [[ $cmd =~ '(^|[[:space:];&|])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' ]]; then
  local d top task notes head short checks cases problems=()
  d=$(cmd_dir "$cmd")
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)
  [[ -n $top ]] || exit 0
  task=$(task_of "$top")
  [[ -n $task ]] || decide ask "gh pr create outside a task worktree ($top) — PRs are opened from tasks/<repo>/<task> only."
  notes=$NOTES/$task.md
  [[ -f $notes ]] || decide ask "no notes file $notes — the PR command needs ## Checks run and ## Cases there."
  head=$(git -C "$top" rev-parse HEAD 2>/dev/null)
  short=${head[1,7]}
  [[ -z $(git -C "$top" status --porcelain 2>/dev/null) ]] || problems+=("worktree is dirty")
  checks=$(section "$notes" "Checks run")
  ok_lines=$(print -r -- "$checks" | grep -F "$short" | grep -vi 'quick' | grep -i 'dirty no')
  [[ ${top:t} == *-main ]] || ok_lines=$(print -r -- "$ok_lines" | grep -vi 'twin')
  [[ -n $ok_lines ]] || \
    problems+=("no verify entry for HEAD $short with 'dirty no' in ## Checks run (full; 'twin' only in a -main worktree; never 'quick')")
  if ! grep -qiE '^Cases: *(n/a|skip)' "$notes"; then
    cases=$(section "$notes" "Cases")
    if ! print -r -- "$cases" | grep -qE '^\| *C[0-9]+ '; then
      problems+=("no ## Cases matrix (run case discovery, or the user approves skipping → write 'Cases: n/a — <reason, user OK, date>' in the notes)")
    elif print -r -- "$cases" | grep -qE '\| *needs-PM *\|'; then
      problems+=("## Cases still has needs-PM rows ($(print -r -- "$cases" | grep -cE '\| *needs-PM *\|'))")
    fi
  fi
  (( ${#problems} )) && decide ask "PR gate for task '$task': ${(j:; :)problems}. Allow only if the user OKs skipping."
  exit 0
fi
exit 0
