# agentfork

Copy a Claude Code conversation and paste it as a fork into another pane, in
**Rex**, **herdr** or **Ghostty**. The clipboard is shared, so you can copy in
one terminal and paste in another.

A fork is `claude --resume <id> --fork-session`, started in the original
conversation's directory. The original conversation is never touched.

## Install

```sh
./install.sh            # every supported terminal found on this machine
./install.sh rex        # or just some: rex, herdr, ghostty
./install.sh --uninstall
```

Needs `jq`. `fzf` makes the picker nicer but is optional.

The installer links `bin/agentfork` into `~/.local/bin` and adds one line to
each terminal's config, backing the file up to `<file>.agentfork-backup`
first:

| Terminal | What it changes |
| --- | --- |
| Rex | links `~/.config/rex/agentfork.lua`, adds `pcall(require, "agentfork")` to `init.lua`, reloads |
| Ghostty | adds `config-file = ?…/adapters/ghostty/agentfork.ghostty` to its config, reloads |
| herdr | `herdr plugin link adapters/herdr`; you add the keys (see below) |

## Keys

| | Rex | herdr | Ghostty |
| --- | --- | --- | --- |
| Copy | `ctrl+b c` | your choice | `cmd+alt+c` |
| Paste here | `ctrl+b v` | your choice | `cmd+alt+v` |
| Fork to split | `ctrl+b shift+f`, `alt+shift+v` | your choice | `cmd+alt+f` |
| Fork to tab | `ctrl+b f` | your choice | `cmd+alt+t` |

"Paste here" types the fork command into the focused pane, so use it on a
pane sitting at a shell prompt.

herdr's keys usually belong to something already, so the installer only
links the plugin. To bind its actions, add them to
`~/.config/herdr/config.toml` and restart herdr's client (detach and
reattach):

```toml
[[keys.command]]
key = "prefix+c"
type = "plugin_action"
command = "agentfork.copy"

[[keys.command]]
key = "prefix+v"
type = "plugin_action"
command = "agentfork.paste"
```

The actions are `agentfork.copy`, `agentfork.paste`, `agentfork.fork` (tab)
and `agentfork.fork-split`.

## Which conversation gets copied

Claude Code writes `~/.claude/sessions/<pid>.json` for every running
instance, holding its session ID and directory. So:

1. **Rex and herdr** report the foreground process of the focused pane, so
   copy takes exactly that pane's conversation.
2. **Anywhere else** (Ghostty can't report a pane's process, and neither can
   a plain shell): if only one conversation was active in the last 30
   seconds, that one. Otherwise a picker lists every running conversation,
   most recent first, with its directory and the last thing you typed.

A pane whose Claude has no messages yet is an error rather than a fallback,
so you never fork a conversation you didn't point at.

## The CLI

The adapters are thin. Everything about Claude lives in `bin/agentfork`:

```
agentfork copy [--pid PID]... [--pick] [--notify] [--quiet]
agentfork paste [--print]
agentfork fork [--pid PID]... [--pick]     # copy + paste
agentfork list [--json]
agentfork show
```

`copy` exits with status 3 when it would need to ask but has no terminal to
ask in. Adapters answer that by opening a pane that runs `agentfork copy
--pick`.

Environment: `AGENTFORK_ACTIVE_SECONDS` (default 30), `AGENTFORK_STATE_DIR`
(default `~/.local/state/agentfork`), `AGENTFORK_CLAUDE_HOME` (default
`~/.claude`), `AGENTFORK_CLAUDE_BIN` (default `claude`).

## Layout

```
bin/agentfork              the CLI: finding, copying and starting forks
adapters/rex/agentfork.lua Rex actions and keys
adapters/herdr/            herdr plugin
adapters/ghostty/          Ghostty keybindings
install.sh                 install and uninstall
tests/run.sh               tests against a fake ~/.claude
```

## Not yet

- Codex. It has no pid-to-session file, so finding its session needs
  another approach (the rollout file the process has open).
