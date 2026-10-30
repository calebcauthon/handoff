# handoff

Copy a Claude Code conversation in one pane, paste it as a fork in another.
Works in Rex, herdr and Ghostty; the clipboard is shared between them.

Needs `jq`. `fzf` is optional.

## Herdr

Ask your agent, in Herdr:

```
Read ~/.config/herdr-app/AGENTS.md, then add this mod: herdr.dev/mods/calebcauthon/handoff
```

or from a clone:

```sh
git clone https://github.com/calebcauthon/handoff && cd handoff
make install herdr
```

Keys: `cmd+alt+c` copy, `cmd+alt+v` paste, `cmd+alt+f` fork into a split.
A strip at the bottom shows what's on the fork clipboard.

## Herdr TUI

```sh
herdr plugin install calebcauthon/handoff
herdr server reload-config
```

Keys: `prefix+c` copy, `prefix+v` paste, `prefix+→` fork into a split.

## Rex

```sh
git clone https://github.com/calebcauthon/handoff && cd handoff
make install rex
```

Keys: `ctrl+b c` copy, `ctrl+b v` paste, `ctrl+b →` fork into a split.

## Ghostty

Needs [skhd](https://github.com/jackielii/skhd.zig), since Ghostty's own
keybindings can't run programs.

```sh
git clone https://github.com/calebcauthon/handoff && cd handoff
make install ghostty
```

Keys: `cmd+alt+c` copy, `cmd+alt+v` paste, `cmd+alt+→` fork into a split.

## How it works

Fork copies the pane you're in and pastes it into a new split on the right.
Paste into a pane sitting at a shell prompt. The fork is `claude --resume <id>
--fork-session` in the original directory; the original is untouched.

Copy takes the focused pane's conversation. Where the terminal can't say what's
in the pane (Ghostty), it goes by the pane's directory, then the one
conversation active in the last 30 seconds, then asks.

## More

`make install` installs for every terminal found; `make uninstall` undoes it.
Keys already bound to something else are left alone and reported.

The CLI behind the keys is `agentfork`:

```
agentfork copy [--pid PID]... [--pick] [--notify] [--quiet]
agentfork paste [--print]
agentfork fork [--pid PID]... [--pick]     # copy + paste
agentfork list [--json]
agentfork show
```

Not yet: Codex.
