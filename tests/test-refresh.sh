#!/usr/bin/env bash
# Runs refresh.sh (and refresh.ps1 when pwsh is available) against the fake gh
# in tests/fake-gh and checks the repository ends up as it started.
#
# Usage: bash tests/test-refresh.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/plugins/clean-contributors/scripts"
export PATH="$ROOT/tests/fake-gh:$PATH"
export FAKE_GH_DIR; FAKE_GH_DIR="$(mktemp -d)"
trap 'rm -rf "$FAKE_GH_DIR"' EXIT
chmod +x "$ROOT/tests/fake-gh/gh"

PASS=0; FAILED=0
RUNNERS=("bash $SCRIPTS/refresh.sh -y o/r" "bash $SCRIPTS/refresh.sh o/r -y")
if command -v pwsh >/dev/null; then
  RUNNERS+=("pwsh -NoProfile -File $SCRIPTS/refresh.ps1 o/r -Yes")
fi

# check NAME RUNNER INITIAL_STATE EXPECTED_EXIT EXPECTED_STATE [ENV...]
check() {
  local name=$1 runner=$2 initial=$3 want_exit=$4 want_state=$5; shift 5
  printf '%b\n' "$initial" > "$FAKE_GH_DIR/state"
  rm -f "$FAKE_GH_DIR/log" "$FAKE_GH_DIR/failed" "$FAKE_GH_DIR/renamed"
  env "$@" $runner > "$FAKE_GH_DIR/out" 2>&1
  local code=$? state; state=$(paste -sd, "$FAKE_GH_DIR/state")
  if [[ $code -eq $want_exit && $state == "$want_state" ]]; then
    PASS=$((PASS + 1)); echo "ok   ${runner%% *} | $name"
  else
    FAILED=$((FAILED + 1)); echo "FAIL ${runner%% *} | $name (exit $code, state $state)"
    sed 's/^/     /' "$FAKE_GH_DIR/out"
  fi
}

for r in "${RUNNERS[@]}"; do
  check "happy path"                  "$r" 'main\nmain' 0 main,main
  check "transient failure retried"   "$r" 'main\nmain' 0 main,main FAIL_AT=branches/main/rename
  check "create temp branch fails"    "$r" 'main\nmain' 1 main,main FAIL_AT=git/refs FAIL_ALWAYS=1
  check "switch default fails"        "$r" 'main\nmain' 1 main,main FAIL_AT='PATCH repos/o/r' FAIL_ALWAYS=1
  check "rename away fails"           "$r" 'main\nmain' 1 main,main FAIL_AT=branches/main/rename FAIL_ALWAYS=1
  check "delete temp fails"           "$r" 'main\nmain' 1 main,main,tmp-refresh-contributors FAIL_AT=DELETE FAIL_ALWAYS=1
  check "leftover temp branch"        "$r" 'main\nmain\ntmp-refresh-contributors' 1 main,main,tmp-refresh-contributors
  check "leftover old branch"         "$r" 'main\nmain\nmain-old-refresh' 1 main,main,main-old-refresh
  check "repo refreshed before"       "$r" 'main\nmain' 0 main,main FAKE_RENAMED=main-old-refresh
done

echo; echo "$PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
