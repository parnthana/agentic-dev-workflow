#!/usr/bin/env bash
# Wrapper for the skill-compliance harness (vendored from affaan-m/ECC, MIT, see LICENSE).
# - Creates a private venv with pyyaml on first use (~/.cache/skill-comply/venv).
# - Sets COMPLY_SANDBOX so scenario sessions run in a throwaway directory; pair it with a pre-tool-use hook that
#   denies network/cloud/git-remote commands while that variable is set.
# Usage: run-evals.sh [--dry-run] [--model sonnet] [--gen-model haiku] [--spec f.yaml --scenarios f.yaml]
#                     [--repeat N] [--output report.md] <skill-or-command .md>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv="${COMPLY_VENV:-$HOME/.cache/skill-comply/venv}"
# resolve existing path arguments to absolute before changing directory
args=()
for a in "$@"; do
  if [[ -e "$a" ]]; then args+=("$(cd "$(dirname "$a")" && pwd)/$(basename "$a")"); else args+=("$a"); fi
done
cd "$here"
if [[ ! -x "$venv/bin/python" ]]; then
  py=""
  for cand in python3.13 python3.12 python3.11 python3; do
    if command -v "$cand" >/dev/null && "$cand" -c 'import sys; sys.exit(sys.version_info < (3,11))' 2>/dev/null; then py="$cand"; break; fi
  done
  [[ -n "$py" ]] || { echo "run-evals: need python >= 3.11" >&2; exit 1; }
  mkdir -p "$(dirname "$venv")"
  "$py" -m venv "$venv"
  "$venv/bin/pip" install -q 'pyyaml>=6.0'
fi
export COMPLY_SANDBOX="${TMPDIR:-/tmp}/skill-comply-sandbox-$(id -u)"
exec "$venv/bin/python" -m scripts.run ${args[@]+"${args[@]}"}
