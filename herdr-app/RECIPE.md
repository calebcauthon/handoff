# Handoff

Copy the Claude Code conversation in the focused terminal, paste it as a fork
into another pane, or fork it straight into a split on the right. One key
opens a small popup that shows what's on the fork clipboard; the next key does
the work. The clipboard is shared with Rex, Ghostty and the Herdr TUI, so a
conversation copied in one terminal can be pasted in another.

![Handoff](preview.png)

This file is the brief: enough to build Handoff from an empty folder. The
files next to it are one build of it.

## What you see

- A popup near the top of the window, 460px wide and 168px high, 64px down,
  in the theme's `popover` color with `foreground` text at 12px, 14px padding
  and 8px gaps. Nothing is added to the layout itself.
- A heading, **Handoff** (semibold), with "Esc cancel" on the right in `muted`.
- One line: "clipboard" in `dim`, then what's copied, truncated: "`<name>` in
  `~/Code/app` · “the last thing you typed”", or "nothing copied yet" in
  `muted`.
- Three rows, the key in `accent` in a 28px column and its action beside it:
  `c` Copy this terminal's conversation; `v` Paste the copied conversation
  here, as a fork; `→` Fork this conversation into a split on the right.

## How it behaves

- `cmd-alt-a` opens the popup (in a terminal or anywhere) and it takes the
  keyboard. It waits without a timeout. Escape closes it. Any key below
  closes it and acts; other keys do nothing.
- **c** takes the conversation running in the focused terminal and saves it to
  the fork clipboard. A toast says what was copied. If the terminal isn't
  running Claude and several conversations could be meant, a split opens
  below it with a picker; choosing one copies it and the split closes.
- **v** types `agentfork paste` into the focused terminal and presses Enter,
  which starts `claude --resume <id> --fork-session` in the copied
  conversation's directory. Use it on a terminal sitting at a shell prompt.
  With nothing copied, a toast says so.
- **→** (or `f`): copy, then a new split on the right that runs the paste.
  When a picker is needed, the split runs it and then starts the fork.
- The original conversation is never touched; the fork is a new session.
- No animation; agent statuses aren't shown.

## Built from

- **One mod**, `mods/handoff/` (`main.js`, `mod.json` with `place: "none"`
  and `overlay: { kind: "popup", at: "top", offset: 64, width: 460, height:
  168 }`). No `layouts/` folder: shipped layouts can't dock a new mod, so a
  popup is how it gets keys there (as the tmux-prefix example does).
- **A `keys.json` snippet**, merged into the person's: `cmd-alt-a` →
  `mod.open:handoff` in both `global` and `terminal`.
- **The agentfork CLI**, `~/.local/bin/agentfork` from
  github.com/calebcauthon/handoff (`make install` links it). It finds
  conversations through Claude Code's `~/.claude/sessions/<pid>.json` files
  and keeps the clipboard at `~/.local/state/agentfork/clipboard.json`. The
  mod runs it with `exec`:
  - copy: `agentfork copy --quiet --pid <foreground pid> --pid <shell pid>
    --cwd <folder>`; exit 0 copied, 3 needs a picker.
  - The pids come from `hc get <terminal> --json` (`foreground.pid`, `pid`),
    the folder from `focused().cwd`.
- **Herdr calls:** a focusable `v_flex` (`cx.focus_handle()`, `track_focus`,
  `on_key_down`, `closeOverlay(props().overlay)`), `focused()` for the
  terminal and pane, `hc(["get", …])`, `hc(["send", terminal, "<agentfork>
  paste"])` for paste, `run("pane.split", {direction, pane, argv})` for the
  picker (`down`, `sh -c "exec agentfork copy --pick --notify"`) and the fork
  (`right`, `agentfork paste` or `agentfork fork --pick`), `notify()` for
  results, `readTextFile` for the clipboard line, `theme()` for colors.
  Docked by a layout instead of opened, the same code takes `handoff.copy`,
  `handoff.paste` and `handoff.fork` through `nextCommand()`.
- Everything is local: no network. It runs programs (`agentfork` and `hc`).

## Watch out

- The mod needs `~/.local/bin/agentfork`; without it every action toasts an
  error. `make install herdr` from the repo installs both.
- Copy is exact only because herdr-core reports the terminal's foreground pid.
  Without pids it falls back to the folder, then to the one conversation
  active in the last 30 seconds, then to the picker.
- Start the work before closing the popup only through `exec`/`hc`, which
  start their programs at the call: the view's tasks are cancelled when the
  overlay closes. The build spawns the action and then closes.
- `cmd-alt-a` is free in Herdr's defaults; `cmd-alt-c/v` were left alone
  because they're the Ghostty adapter's keys and `cmd-alt-h` hides other
  apps on macOS. On Linux and Windows bind `ctrl-alt-a` instead.
- Only this machine: the clipboard and `~/.claude` are local, so a remote
  machine's space isn't supported. Only Claude Code; Codex has no
  pid-to-session file.
- `herdr-app check` writes `gpui-kit.d.ts` and `jsconfig.json` next to the
  mod; don't ship them.

## Done when

- `herdr-app check mods/handoff` passes.
- `cmd-alt-a` opens the popup over a terminal; Escape closes it without
  typing anything.
- With Claude running in the focused terminal, `cmd-alt-a` `c` toasts
  "Copied: <name> in <folder>" and the next popup shows it on the clipboard
  line.
- `cmd-alt-a` `v` on a shell prompt starts `claude --resume … --fork-session`
  in the copied conversation's directory.
- `cmd-alt-a` `→` opens a split on the right that starts the fork; the
  original terminal keeps running untouched.
- `cmd-alt-a` `c` on a shell with several conversations active opens a picker
  split below; picking one copies it and closes the split.
