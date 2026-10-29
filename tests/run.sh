#!/usr/bin/env bash
# Tests for bin/agentfork against a fake ~/.claude and a fake claude binary.
# Live "Claude processes" are sleep processes with session files pointing at
# them, so pid checks run for real.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AF="$here/../bin/agentfork"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/agentfork-test.XXXXXX")"
pids=()
cleanup() {
  for p in ${pids[@]+"${pids[@]}"}; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$tmp"
}
trap cleanup EXIT

export AGENTFORK_CLAUDE_HOME="$tmp/claude"
export AGENTFORK_STATE_DIR="$tmp/state"
export AGENTFORK_CLAUDE_BIN="$tmp/bin/claude"
export AGENTFORK_NO_TTY=1
mkdir -p "$AGENTFORK_CLAUDE_HOME/sessions" "$AGENTFORK_CLAUDE_HOME/projects" "$tmp/bin"

cat >"$tmp/bin/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/claude.argv"
pwd -P >"$tmp/claude.pwd"
EOF
chmod +x "$tmp/bin/claude"

fail=0
pass=0
check() { # name, then a command that must succeed
  local name="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$name"
  fi
}

proc_start() { TZ=UTC ps -o lstart= -p "$1" | tr -s ' ' | sed 's/ $//'; }

# session <pid> <id> <cwd> <updated-seconds-ago> [transcript: yes|no] [procStart]
session() {
  local pid="$1" id="$2" cwd="$3" ago="$4" transcript="${5:-yes}" start="${6:-}"
  [ -n "$start" ] || start="$(proc_start "$pid")"
  local updated=$((($(date +%s) - ago) * 1000))
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","name":"name-%s","status":"idle","kind":"interactive","updatedAt":%s,"procStart":"%s"}\n' \
    "$pid" "$id" "$cwd" "$id" "$updated" "$start" >"$AGENTFORK_CLAUDE_HOME/sessions/$pid.json"
  if [ "$transcript" = yes ]; then
    local dir="$AGENTFORK_CLAUDE_HOME/projects/$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
    mkdir -p "$dir"
    printf '{"type":"user","message":{"role":"user","content":"hello from %s"}}\n' "$id" >"$dir/$id.jsonl"
    # Backdate the transcript to match updatedAt.
    touch -t "$(date -r $(($(date +%s) - ago)) +%Y%m%d%H%M.%S 2>/dev/null || date -d @$(($(date +%s) - ago)) +%Y%m%d%H%M.%S)" "$dir/$id.jsonl"
  fi
}

spawn() { # start a fake Claude process and print its pid
  sleep 600 >/dev/null 2>&1 &
  pids+=($!)
  LAST=$!
}

reset() {
  rm -f "$AGENTFORK_CLAUDE_HOME"/sessions/*.json "$AGENTFORK_STATE_DIR/clipboard.json"
}

copied_id() { jq -r .session_id "$AGENTFORK_STATE_DIR/clipboard.json" 2>/dev/null; }

# --- copy --pid names the conversation exactly -------------------------------
spawn; a=$LAST
spawn; b=$LAST
session "$a" aaaa /work/one 5
session "$b" bbbb /work/two 5
"$AF" copy --quiet --pid "$b" >/dev/null
check "copy --pid picks that process" [ "$(copied_id)" = bbbb ]

# --- copy --pid finds Claude under the pane's shell --------------------------
reset
sh -c "sleep 600; :" >/dev/null 2>&1 &
shell=$!
pids+=("$shell")
sleep 0.2
child="$(pgrep -P "$shell" | head -1)"
session "$child" cccc /work/three 500
session "$a" aaaa /work/one 5
"$AF" copy --quiet --pid "$shell" >/dev/null
check "copy --pid finds a descendant" [ "$(copied_id)" = cccc ]

# --- a pane whose Claude has no messages is an error, not a fallback ---------
reset
session "$a" aaaa /work/one 5
session "$b" empty /work/two 5 no
out="$("$AF" copy --pid "$b" 2>&1)"
rc=$?
check "empty conversation fails" [ "$rc" = 1 ]
check "empty conversation explains" grep -q "no messages yet" <<<"$out"
check "empty conversation copies nothing" [ ! -f "$AGENTFORK_STATE_DIR/clipboard.json" ]

# --- stale session files (reused pid) are ignored ----------------------------
reset
session "$a" stale /work/one 5 yes "Mon Jan 1 00:00:00 2001"
session "$b" bbbb /work/two 500
"$AF" copy --quiet >/dev/null
check "stale pid file ignored" [ "$(copied_id)" = bbbb ]

# --- without a pid: the one active conversation wins -------------------------
reset
spawn; c=$LAST
session "$a" aaaa /work/one 300
session "$b" bbbb /work/two 3
session "$c" cccc /work/three 900
"$AF" copy --quiet >/dev/null
check "single active conversation is used" [ "$(copied_id)" = bbbb ]

# --- several active and no terminal: exit 3 so the adapter opens a picker ----
reset
session "$a" aaaa /work/one 2
session "$b" bbbb /work/two 4
session "$c" cccc /work/three 900
"$AF" copy --quiet >/dev/null 2>&1
check "ambiguous without a tty exits 3" [ $? = 3 ]

reset
session "$a" aaaa /work/one 300
session "$b" bbbb /work/two 900
"$AF" copy --quiet >/dev/null 2>&1
check "none active without a tty exits 3" [ $? = 3 ]

# --- one conversation in total needs no picker ------------------------------
reset
session "$a" only /work/one 9000
"$AF" copy --quiet >/dev/null
check "only conversation is used" [ "$(copied_id)" = only ]

# --- --pick never guesses ----------------------------------------------------
"$AF" copy --pick --quiet >/dev/null 2>&1
check "--pick without a tty exits 3" [ $? = 3 ]

# --- paste resumes as a fork in the original directory -----------------------
reset
mkdir -p "$tmp/my project"
session "$a" dddd "$tmp/my project" 5
"$AF" copy --quiet --pid "$a" >/dev/null
(cd / && "$AF" paste 2>/dev/null)
check "paste passes --resume and --fork-session" \
  [ "$(tr '\n' ' ' <"$tmp/claude.argv")" = "--resume dddd --fork-session " ]
check "paste runs in the conversation's directory" [ "$(cat "$tmp/claude.pwd")" = "$(cd "$tmp/my project" && pwd -P)" ]
printed="$("$AF" paste --print)"
check "paste --print quotes the directory" grep -q 'my\\ project' <<<"$printed"

# --- fork = copy + paste ----------------------------------------------------
reset
rm -f "$tmp/claude.argv"
session "$b" eeee /work/two 5
"$AF" fork --pid "$b" 2>/dev/null
check "fork starts the fork" grep -q eeee "$tmp/claude.argv"
check "fork also fills the clipboard" [ "$(copied_id)" = eeee ]

# --- list shows live conversations only -------------------------------------
reset
session "$a" aaaa /work/one 5
session "$b" nomsg /work/two 5 no
session 999999 gone /work/gone 5 yes "Mon Jan 1 00:00:00 2001"
lines="$("$AF" list --json)"
check "list shows forkable conversations" grep -q aaaa <<<"$lines"
check "list hides empty and dead ones" [ "$(printf '%s\n' "$lines" | grep -c .)" = 1 ]
check "list includes the last prompt" grep -q "hello from aaaa" <<<"$lines"

# --- paste with nothing copied ----------------------------------------------
reset
"$AF" paste >/dev/null 2>&1
check "paste with empty clipboard fails" [ $? = 1 ]

# --- herdr keys: added once, taken keys skipped, removed cleanly ------------
KEYS="$here/../adapters/herdr/keys.sh"
export AGENTFORK_HERDR_CONFIG="$tmp/herdr/config.toml"
mkdir -p "$tmp/herdr"
cat >"$AGENTFORK_HERDR_CONFIG" <<'EOF'
[keys]
new_tab = "prefix+f"

[[keys.command]]
key = "prefix+x"
type = "shell"
command = "echo hi"
EOF
out="$(bash "$KEYS")"
check "keys: binds free keys" grep -q 'command = "agentfork.copy"' "$AGENTFORK_HERDR_CONFIG"
check "keys: skips a taken key" grep -q 'prefix+f is already bound' <<<"$out"
check "keys: taken key stays unbound" [ "$(grep -c 'command = "agentfork.fork"$' "$AGENTFORK_HERDR_CONFIG")" = 0 ]
check "keys: backs the config up" [ -f "$AGENTFORK_HERDR_CONFIG.agentfork-backup" ]
check "keys: valid toml" python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$AGENTFORK_HERDR_CONFIG"
before="$(cat "$AGENTFORK_HERDR_CONFIG")"
bash "$KEYS" >/dev/null
check "keys: second run changes nothing" [ "$(cat "$AGENTFORK_HERDR_CONFIG")" = "$before" ]
bash "$KEYS" --remove >/dev/null
check "keys: --remove drops agentfork keys" [ "$(grep -c agentfork "$AGENTFORK_HERDR_CONFIG")" = 0 ]
check "keys: --remove keeps other keys" grep -q 'echo hi' "$AGENTFORK_HERDR_CONFIG"
check "keys: --remove keeps [keys] table" grep -q 'new_tab = "prefix+f"' "$AGENTFORK_HERDR_CONFIG"

rm -f "$AGENTFORK_HERDR_CONFIG"
bash "$KEYS" >/dev/null
check "keys: creates a missing config" grep -q 'agentfork.paste' "$AGENTFORK_HERDR_CONFIG"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
