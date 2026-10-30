#!/usr/bin/env bash
# Bind agentfork's keys in herdr's config.toml, or take them out again.
#
#   keys.sh             add the keys (herdr runs this as the plugin's build step)
#   keys.sh --remove    remove every key bound to an agentfork action
#
# herdr plugins can't declare keys in their manifest; keys live only in
# ~/.config/herdr/config.toml as [[keys.command]] tables. This adds one per
# action, backs the file up to config.toml.agentfork-backup first, and never
# touches a key that is already bound to something, so it is safe to run again.
set -euo pipefail

CONFIG="${AGENTFORK_HERDR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml}"
MARK="# agentfork keys. Remove them with: bash adapters/herdr/keys.sh --remove"

# key | action | description
KEYS='prefix+c|copy|copy the conversation in this pane for agentfork
prefix+v|paste|paste the copied conversation here as a fork
prefix+right|fork|fork the conversation in this pane into a split on the right'

say() { printf '%s\n' "$*"; }

backup() {
  [ -f "$CONFIG" ] && [ ! -f "$CONFIG.agentfork-backup" ] && cp "$CONFIG" "$CONFIG.agentfork-backup"
  return 0
}

# Uncommented lines of the config.
live() { [ -f "$CONFIG" ] && grep -v '^[[:space:]]*#' "$CONFIG" || true; }

# What key $1 is bound to, if anything: the key appears as a quoted value, as
# in `key = "prefix+c"` under [[keys.command]] or `new_tab = "prefix+c"` under
# [keys].
bound_to() {
  live | grep -F "= \"$1\"" | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

has_action() {
  live | grep -qF "command = \"agentfork.$1\""
}

add() {
  local key action desc added=0 skipped=0 taken
  mkdir -p "$(dirname "$CONFIG")"
  backup
  while IFS='|' read -r key action desc; do
    [ -n "$key" ] || continue
    if has_action "$action" && live | grep -qF "key = \"$key\""; then
      continue
    fi
    taken="$(bound_to "$key")"
    if [ -n "$taken" ]; then
      say "agentfork: $key is already bound ($taken), so agentfork.$action is not bound to it."
      skipped=1
      continue
    fi
    {
      # A blank line before each table, and the marker above the first.
      [ ! -s "$CONFIG" ] || [ -z "$(tail -c1 "$CONFIG")" ] || echo
      [ ! -s "$CONFIG" ] || echo
      grep -qxF "$MARK" "$CONFIG" 2>/dev/null || echo "$MARK"
      printf '[[keys.command]]\nkey = "%s"\ntype = "plugin_action"\ncommand = "agentfork.%s"\ndescription = "%s"\n' \
        "$key" "$action" "$desc"
    } >>"$CONFIG"
    say "agentfork: bound $key to agentfork.$action"
    added=1
  done <<<"$KEYS"
  if [ "$added" = 1 ]; then
    say "agentfork: keys added to $CONFIG; they apply once herdr's client restarts (detach and reattach)."
  elif [ "$skipped" = 0 ]; then
    say "agentfork: keys already bound in $CONFIG"
  fi
  if [ "$skipped" = 1 ]; then
    say "agentfork: bind the skipped actions yourself with a [[keys.command]] table whose type is plugin_action."
  fi
}

remove() {
  [ -f "$CONFIG" ] || return 0
  live | grep -qF 'command = "agentfork.' || { say "agentfork: no keys to remove from $CONFIG"; return 0; }
  backup
  # Drop each [[keys.command]] table that binds an agentfork action, plus the
  # marker comment. A table runs from its header to the line before the next
  # header.
  awk -v mark="$MARK" '
    function flush() {
      if (held != "" && !drop) printf "%s", held
      held = ""; drop = 0
    }
    $0 == mark { next }
    /^[[:space:]]*\[/ { flush(); if ($0 ~ /^[[:space:]]*\[\[keys\.command\]\]/) { held = $0 "\n"; next } }
    held != "" {
      if ($0 ~ /^[[:space:]]*command[[:space:]]*=[[:space:]]*"agentfork\./) drop = 1
      held = held $0 "\n"; next
    }
    { print }
    END { flush() }
  ' "$CONFIG" | awk '
    # Without the blank line that led into the agentfork tables.
    { line[NR] = $0 }
    END { n = NR; while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print line[i] }
  ' >"$CONFIG.agentfork-tmp"
  mv "$CONFIG.agentfork-tmp" "$CONFIG"
  say "agentfork: removed agentfork keys from $CONFIG; herdr's client picks that up when it restarts."
}

case "${1:-}" in
  '') add ;;
  --remove) remove ;;
  *) say "usage: keys.sh [--remove]" >&2; exit 2 ;;
esac
