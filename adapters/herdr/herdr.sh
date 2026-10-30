#!/usr/bin/env bash
# agentfork for herdr. Usage: herdr.sh copy|paste
#
# herdr reports the processes in a pane, so copy always takes the focused
# pane's conversation. When the pane isn't running Claude and the choice is
# ambiguous, a picker opens in a split below.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${AGENTFORK_BIN:-$(cd "$here/../../bin" && pwd)/agentfork}"
HERDR="${HERDR_BIN_PATH:-herdr}"

notify() {
  "$HERDR" notification show "$1" --body "$2" >/dev/null 2>&1 || true
}

fail() {
  echo "agentfork: $1" >&2
  notify "agentfork" "$1"
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "'jq' is required but was not found on PATH."

# The pane the action was invoked from.
pane_id() {
  local pane
  pane="$(printf '%s' "${HERDR_PANE_ID:-}" | tr -d '[:space:]')"
  if [ -z "$pane" ] && [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
    pane="$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '
      .focused_pane_id // .pane_id // .focused_pane.pane_id // .pane.pane_id
      // .context.pane_id // empty' 2>/dev/null || true)"
  fi
  [ -n "$pane" ] || fail "could not determine the current pane."
  printf '%s' "$pane"
}

q() { printf '%q' "$1"; }

# Copy the pane's conversation. Returns 0 when copied and 3 when the user has
# to pick.
copy() {
  local pane="$1" info args=() pid out rc=0
  info="$("$HERDR" pane process-info --pane "$pane" 2>/dev/null || true)"
  for pid in $(printf '%s' "$info" | jq -r '.result.process_info
      | ([.foreground_processes[]?.pid] + [.shell_pid]) | .[] | select(. != null)' 2>/dev/null); do
    args+=(--pid "$pid")
  done
  out="$("$BIN" copy ${args[@]+"${args[@]}"} 2>&1)" || rc=$?
  case "$rc" in
    0) notify "Conversation copied" "${out#copied }" ;;
    3) ;;
    *) fail "${out#agentfork: }" ;;
  esac
  return "$rc"
}

# Run a command in a new split below the pane.
open_below() {
  local pane="$1" command="$2" out new
  out="$("$HERDR" pane split --pane "$pane" --direction down --focus)"
  new="$(printf '%s' "$out" | jq -r --arg old "$pane" '
    [.. | objects | .pane_id? // empty | select(. != $old)][0] // empty')"
  [ -n "$new" ] || fail "could not open a new pane."
  "$HERDR" pane run "$new" "$command" >/dev/null
}

case "${1:-}" in
  copy)
    pane="$(pane_id)"
    rc=0
    copy "$pane" || rc=$?
    # exec, so the picker's pane closes once a conversation is chosen.
    [ "$rc" != 3 ] || open_below "$pane" "exec $(q "$BIN") copy --pick --notify"
    ;;
  paste)
    "$HERDR" pane run "$(pane_id)" "$(q "$BIN") paste" >/dev/null
    ;;
  *)
    echo "usage: herdr.sh copy|paste" >&2
    exit 2
    ;;
esac
