#!/usr/bin/env bash
# Install agentfork and wire it into the terminals found on this machine.
#
#   ./install.sh                  install for every supported terminal found
#   ./install.sh rex ghostty      install for only these (herdr, herdr-tui, rex, ghostty)
#   ./install.sh --uninstall      undo everything install.sh did
#
# herdr is the desktop app (a mod in ~/.config/herdr-app); herdr-tui is the
# terminal one (a plugin).
#
# Every config file it changes gets one line added, and is backed up first to
# <file>.agentfork-backup.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${AGENTFORK_BIN_DIR:-$HOME/.local/bin}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

REX_DIR="$CONFIG_HOME/rex"
# pcall keeps init.lua loading on machines without agentfork, so it can be
# shared through dotfiles. The plain require is what older installs added.
REX_LINE='pcall(require, "agentfork")'
REX_OLD_LINE='require("agentfork")'
# Ghostty keys are skhd hotkeys (see adapters/ghostty/agentfork.skhdrc).
SKHD_LINE=".load \"$repo/adapters/ghostty/agentfork.skhdrc\""
# What installs before 0.3 added to Ghostty's own config.
GHOSTTY_OLD_LINE="config-file = ?$repo/adapters/ghostty/agentfork.ghostty"
HERDR_KEYS="$repo/adapters/herdr/keys.sh"
# The Herdr app: its mods and keys live here.
APP_HOME="${HERDR_APP_HOME:-$CONFIG_HOME/herdr-app}"
APP_MOD="$APP_HOME/mods/handoff"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

rex_cli() {
  # The Mac app doesn't put rex on PATH.
  local app="$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
  if command -v rex >/dev/null 2>&1 && rex config --help >/dev/null 2>&1; then
    printf 'rex'
  elif [ -x "$app" ]; then
    printf '%s' "$app"
  else
    return 1
  fi
}

ghostty_config() {
  local mac="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
  local xdg="$CONFIG_HOME/ghostty/config"
  if [ "$(uname)" = Darwin ] && [ -f "$mac" ]; then
    printf '%s' "$mac"
  else
    printf '%s' "$xdg"
  fi
}

# skhd reads ~/.config/skhd/skhdrc, or the older ~/.skhdrc.
skhd_config() {
  if [ -f "$CONFIG_HOME/skhd/skhdrc" ] || [ ! -f "$HOME/.skhdrc" ]; then
    printf '%s' "$CONFIG_HOME/skhd/skhdrc"
  else
    printf '%s' "$HOME/.skhdrc"
  fi
}

has_rex() { [ -d "$REX_DIR" ] || rex_cli >/dev/null || ls -d /Applications/Rex*.app >/dev/null 2>&1; }
has_ghostty() { command -v ghostty >/dev/null 2>&1 || [ -d /Applications/Ghostty.app ]; }
has_herdr_tui() { command -v herdr >/dev/null 2>&1; }
has_herdr_app() { command -v herdr-app >/dev/null 2>&1 || [ -d "$APP_HOME" ]; }

backup() {
  [ -f "$1" ] && [ ! -f "$1.agentfork-backup" ] && cp "$1" "$1.agentfork-backup"
  return 0
}

add_line() { # file line
  mkdir -p "$(dirname "$1")"
  if [ -f "$1" ] && grep -qxF "$2" "$1"; then
    say "already in $1"
    return 0
  fi
  backup "$1"
  { [ ! -s "$1" ] || [ -z "$(tail -c1 "$1")" ] || echo; echo "$2"; } >>"$1"
  say "added to $1: $2"
}

remove_line() { # file line; returns 1 when the line wasn't there
  [ -f "$1" ] && grep -qxF "$2" "$1" || return 1
  backup "$1"
  grep -vxF "$2" "$1" >"$1.agentfork-tmp" || true
  mv "$1.agentfork-tmp" "$1"
  say "removed from $1: $2"
}

link() { # target link
  mkdir -p "$(dirname "$2")"
  ln -sfn "$1" "$2"
  say "linked $2 -> $1"
}

unlink_ours() { # link
  if [ -L "$1" ] && [ "$(readlink "$1")" = "${2:-}" ]; then
    rm "$1"
    say "removed $1"
  fi
}

reload_rex() {
  local cli
  cli="$(rex_cli)" || { say "reload Rex with: rex config reload"; return 0; }
  "$cli" config reload >/dev/null 2>&1 && say "reloaded Rex config" ||
    say "couldn't reload Rex; run: rex config reload"
}

reload_ghostty() {
  command -v osascript >/dev/null 2>&1 || { say "reload Ghostty's config to pick up the keys"; return 0; }
  [ "$(osascript -e 'application "Ghostty" is running' 2>/dev/null)" = true ] || return 0
  osascript -e 'tell application "Ghostty" to perform action "reload_config" on focused terminal of selected tab of front window' \
    >/dev/null 2>&1 && say "reloaded Ghostty config" ||
    say "reload Ghostty's config with cmd+shift+, to pick up the keys"
}

install_core() {
  step "agentfork"
  command -v jq >/dev/null 2>&1 || { say "agentfork needs jq: brew install jq"; exit 1; }
  command -v fzf >/dev/null 2>&1 || say "tip: install fzf for a nicer picker (brew install fzf)"
  link "$repo/bin/agentfork" "$BIN_DIR/agentfork"
  case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "warning: $BIN_DIR is not on your PATH" ;; esac
}

install_rex() {
  step "Rex"
  link "$repo/adapters/rex/agentfork.lua" "$REX_DIR/agentfork.lua"
  if [ -f "$REX_DIR/init.lua" ] && grep -qxF "$REX_OLD_LINE" "$REX_DIR/init.lua"; then
    say "already in $REX_DIR/init.lua: $REX_OLD_LINE"
  else
    add_line "$REX_DIR/init.lua" "$REX_LINE"
  fi
  reload_rex
  say "keys: ctrl+b>c copy, ctrl+b>v paste, ctrl+b>right fork into a split"
}

reload_skhd() {
  if skhd -r >/dev/null 2>&1; then
    say "reloaded skhd"
  elif skhd --restart-service >/dev/null 2>&1; then
    say "restarted skhd"
  else
    say "reload skhd with: skhd -r"
  fi
}

install_ghostty() {
  step "Ghostty"
  if ! command -v skhd >/dev/null 2>&1; then
    say "Ghostty's keybindings can't run programs, so agentfork needs skhd:"
    say "  brew install jackielii/tap/skhd-zig && skhd --install-service"
    say "then run this again."
    return 0
  fi
  link "$repo/adapters/ghostty/ghostty.sh" "$BIN_DIR/agentfork-ghostty"
  add_line "$(skhd_config)" "$SKHD_LINE"
  reload_skhd
  if remove_line "$(ghostty_config)" "$GHOSTTY_OLD_LINE"; then
    reload_ghostty
  fi
  say "keys: cmd+alt+c copy, cmd+alt+v paste, cmd+alt+right fork into a split"
}

# The mod's keys, merged into the app's keys.json: a key already bound to
# something else is left alone and reported.
app_keys() { # add | remove
  local file="$APP_HOME/keys.json" ours tmp
  ours="$repo/herdr-app/keys.json"
  [ -f "$file" ] || echo '{}' >"$file"
  backup "$file"
  tmp="$file.agentfork-tmp"
  if [ "$1" = add ]; then
    jq -r 'to_entries[] | .key as $s | .value | to_entries[] | "\($s)\t\(.key)\t\(.value)"' "$ours" |
      while IFS=$'\t' read -r section key action; do
        have="$(jq -r --arg s "$section" --arg k "$key" '.[$s][$k] // empty' "$file")"
        if [ -z "$have" ]; then
          jq --arg s "$section" --arg k "$key" --arg a "$action" '.[$s][$k] = $a' "$file" >"$tmp" && mv "$tmp" "$file"
          say "bound $key to $action ($section)"
        elif [ "$have" != "$action" ]; then
          say "$key is already bound ($have) in $section, so $action is not bound to it."
        fi
      done
  else
    jq 'with_entries(if (.value | type) == "object" then .value |= with_entries(select(.value | test("^(mod\\.open:)?handoff\\b") | not)) else . end)' "$file" >"$tmp" && mv "$tmp" "$file"
    say "removed handoff keys from $file"
  fi
}

install_herdr_app() {
  step "Herdr"
  if ! has_herdr_app; then
    say "the Herdr app isn't installed (herdr.dev); skipping"
    return 0
  fi
  # Copy, not link: the app reloads files it sees change in its own folder.
  if [ -d "$APP_MOD" ] && [ ! -f "$APP_MOD/.handoff" ]; then
    say "$APP_MOD exists and isn't from here; leaving it alone"
  else
    mkdir -p "$APP_MOD"
    cp "$repo/herdr-app/mods/handoff/"* "$APP_MOD/"
    : >"$APP_MOD/.handoff"
    say "installed mod to $APP_MOD"
  fi
  app_keys add
  if command -v herdr-app >/dev/null 2>&1; then
    herdr-app check "$APP_MOD" >/dev/null 2>&1 && say "herdr-app check: ok" || say "herdr-app check failed; run: herdr-app check $APP_MOD"
  fi
  say "keys: cmd+alt+a, then c copy, v paste, right fork into a split"
}

install_herdr_tui() {
  step "Herdr TUI"
  # A checkout installed with `herdr plugin install` is herdr's to manage, so
  # linking is only for a local clone.
  if herdr plugin list 2>/dev/null | grep -q '^- agentfork '; then
    say "plugin already installed"
  else
    herdr plugin link "$repo" >/dev/null && say "linked herdr plugin agentfork"
  fi
  # herdr runs this itself as the plugin's build step on `herdr plugin
  # install`, but not for a linked plugin.
  bash "$HERDR_KEYS"
}

uninstall() {
  step "uninstall"
  unlink_ours "$BIN_DIR/agentfork" "$repo/bin/agentfork"
  unlink_ours "$REX_DIR/agentfork.lua" "$repo/adapters/rex/agentfork.lua"
  if [ -f "$REX_DIR/init.lua" ] && grep -qxF -e "$REX_LINE" -e "$REX_OLD_LINE" "$REX_DIR/init.lua"; then
    remove_line "$REX_DIR/init.lua" "$REX_LINE" || true
    remove_line "$REX_DIR/init.lua" "$REX_OLD_LINE" || true
    reload_rex
  fi
  unlink_ours "$BIN_DIR/agentfork-ghostty" "$repo/adapters/ghostty/ghostty.sh"
  if remove_line "$(skhd_config)" "$SKHD_LINE"; then
    reload_skhd
  fi
  if remove_line "$(ghostty_config)" "$GHOSTTY_OLD_LINE"; then
    reload_ghostty
  fi
  if has_herdr_tui && herdr plugin list 2>/dev/null | grep -q '^- agentfork .*local:'; then
    herdr plugin unlink agentfork >/dev/null && say "unlinked herdr plugin agentfork"
  fi
  bash "$HERDR_KEYS" --remove
  if [ -f "$APP_MOD/.handoff" ]; then
    rm -rf "$APP_MOD" && say "removed $APP_MOD"
  fi
  [ ! -f "$APP_HOME/keys.json" ] || app_keys remove
}

if [ "${1:-}" = --uninstall ]; then
  uninstall
  exit 0
fi

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  has_herdr_app && targets+=(herdr)
  has_herdr_tui && targets+=(herdr-tui)
  has_rex && targets+=(rex)
  has_ghostty && targets+=(ghostty)
fi

install_core
for t in ${targets[@]+"${targets[@]}"}; do
  case "$t" in
    herdr | herdr-app) install_herdr_app ;;
    herdr-tui) install_herdr_tui ;;
    rex) install_rex ;;
    ghostty) install_ghostty ;;
    *) say "unknown terminal '$t' (want herdr, herdr-tui, rex or ghostty)"; exit 2 ;;
  esac
done
[ ${#targets[@]} -gt 0 ] || say "no supported terminal found; agentfork itself is installed."
