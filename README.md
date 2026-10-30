# agentfork

Copy a Claude Code conversation in one pane, paste it as a fork in another.
Works in Rex, herdr and Ghostty; the clipboard is shared between them.

Needs `jq`. `fzf` is optional.

## herdr

```sh
herdr plugin install calebcauthon/handoff
```

Then detach and reattach.

## Rex

```sh
git clone https://github.com/calebcauthon/handoff && cd handoff
make install rex
```

## Ghostty

```sh
git clone https://github.com/calebcauthon/handoff && cd handoff
make install ghostty
```

## Keys

| | Rex | herdr | Ghostty |
| --- | --- | --- | --- |
| Copy | `ctrl+b c` | `prefix+c` | `cmd+alt+c` |
| Paste here | `ctrl+b v` | `prefix+v` | `cmd+alt+v` |
| Fork into a split | `ctrl+b →` | `prefix+→` | `cmd+alt+→` |

Fork copies the pane you're in and pastes it into a new split on the right.
Paste into a pane sitting at a shell prompt. The fork is `claude --resume <id>
--fork-session` in the original directory; the original is untouched.

Copy takes the focused pane's conversation. Where the terminal can't say what's
in the pane (Ghostty), it takes the one conversation active in the last 30
seconds, or asks.

## More

`make install` installs for every terminal found; `make uninstall` undoes it.
Keys already bound to something else are left alone and reported.

```
agentfork copy [--pid PID]... [--pick] [--notify] [--quiet]
agentfork paste [--print]
agentfork fork [--pid PID]... [--pick]     # copy + paste
agentfork list [--json]
agentfork show
```

Not yet: Codex.
