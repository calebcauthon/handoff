#!/usr/bin/env bash
# agentfork for Ghostty. Usage: ghostty.sh copy|paste|fork
#
# Ghostty keybindings can't run programs, and a chained `text:` action types
# into the pane the key was pressed in, which is Claude's prompt. So skhd runs
# this script (adapters/ghostty/agentfork.skhdrc), and it drives Ghostty over
# AppleScript: the focused terminal's directory picks the conversation, and a
# new split gets its command as initial input.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${AGENTFORK_BIN:-$(cd "$here/../../bin" && pwd)/agentfork}"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

fail() {
  echo "agentfork: $1" >&2
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "agentfork"' \
    -e 'end run' "$1" >/dev/null 2>&1 || true
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "'jq' is required but was not found on PATH."

q() { printf '%q' "$1"; }

# The focused terminal's id and working directory, one per line.
focused() {
  osascript -e 'tell application "Ghostty"' \
    -e 'set t to focused terminal of selected tab of front window' \
    -e 'return (id of t) & linefeed & (working directory of t)' \
    -e 'end tell' 2>/dev/null || fail "could not find Ghostty's focused terminal."
}

# Type a command into terminal $1 and press enter.
type_into() {
  osascript - "$1" "$2" <<'EOF' >/dev/null
on run argv
  tell application "Ghostty"
    set t to first terminal whose id is (item 1 of argv)
    input text (item 2 of argv) to t
    send key "enter" to t
  end tell
end run
EOF
}

# Split terminal $1 towards $2 ("right" or "down"); the new shell runs $3.
split_run() {
  osascript - "$1" "$2" "$3" <<'EOF' >/dev/null
on run argv
  tell application "Ghostty"
    set t to first terminal whose id is (item 1 of argv)
    set c to {initial input:(item 3 of argv) & return}
    if (item 2 of argv) is "down" then
      split t direction down with configuration c
    else
      split t direction right with configuration c
    end if
  end tell
end run
EOF
}

# Copy the focused terminal's conversation. Returns 0 when copied and 3 when
# the user has to pick.
copy() {
  local cwd="$1" rc=0
  "$BIN" copy --notify --quiet --cwd "$cwd" 2>/dev/null || rc=$?
  case "$rc" in
    0 | 3) return "$rc" ;;
    *) fail "copy failed; see 'agentfork copy'." ;;
  esac
}

{ read -r id; read -r cwd; } <<<"$(focused)"
[ -n "$id" ] || fail "could not find Ghostty's focused terminal."

case "${1:-}" in
  copy)
    rc=0
    copy "$cwd" || rc=$?
    # exec, so the picker's pane closes once a conversation is chosen.
    [ "$rc" != 3 ] || split_run "$id" down "exec $(q "$BIN") copy --pick --notify"
    ;;
  paste)
    type_into "$id" "$(q "$BIN") paste"
    ;;
  fork)
    # Copy this terminal's conversation and paste it into a split on the right.
    rc=0
    copy "$cwd" || rc=$?
    if [ "$rc" = 0 ]; then
      split_run "$id" right "$(q "$BIN") paste"
    else
      split_run "$id" right "$(q "$BIN") fork --pick"
    fi
    ;;
  *)
    echo "usage: ghostty.sh copy|paste|fork" >&2
    exit 2
    ;;
esac
