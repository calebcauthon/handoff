# agentfork

Copy a Claude Code conversation and paste it as a fork into another pane, in
**Rex**, **herdr** or **Ghostty**. The clipboard is shared, so you can copy in
one terminal and paste in another.

A fork is `claude --resume <id> --fork-session`, started in the original
conversation's directory. The original conversation is never touched.

Needs `jq`. `fzf` makes the picker nicer but is optional.

## Install for herdr

```sh
herdr plugin install calebcauthon/handoff
```

That clones this repo into herdr's plugin directory and, as the plugin's build
step, binds the keys below in `~/.config/herdr/config.toml` (the file is
backed up to `config.toml.agentfork-backup` first). A key that is already
bound to something else is left alone and reported, so you can choose another.
New keys apply once herdr's client restarts (detach and reattach).

The actions are `agentfork.copy`, `agentfork.paste`, `agentfork.fork` (tab)
and `agentfork.fork-split`. To bind one yourself:

```toml
[[keys.command]]
key = "prefix+c"
type = "plugin_action"
command = "agentfork.copy"
```

## Install for Rex

Rex has no plugin manager; `init.lua` loads Lua files that sit beside it. So:

```sh
git clone https://github.com/calebcauthon/handoff
cd handoff
make install rex
```

This links `bin/agentfork` into `~/.local/bin`, links
`adapters/rex/agentfork.lua` to `~/.config/rex/agentfork.lua`, adds
`pcall(require, "agentfork")` to `init.lua` (backed up first), and reloads Rex.
The keys below come with it; rebind them in `init.lua` after the `require`.

`make install` alone installs for every supported terminal found on this
machine, `make install herdr` links a local clone as the herdr plugin and binds
its keys, `make install ghostty` adds one `config-file` line to Ghostty's
config, and `make uninstall` undoes all of it.

## Keys

| | Rex | herdr | Ghostty |
| --- | --- | --- | --- |
| Copy | `ctrl+b c` | `prefix+c` | `cmd+alt+c` |
| Paste here | `ctrl+b v` | `prefix+v` | `cmd+alt+v` |
| Fork to split | `ctrl+b shift+f`, `alt+shift+v` | `prefix+shift+f`, `alt+shift+v` | `cmd+alt+f` |
| Fork to tab | `ctrl+b f` | `prefix+f` | `cmd+alt+t` |

"Paste here" types the fork command into the focused pane, so use it on a
pane sitting at a shell prompt.

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
herdr-plugin.toml          the herdr plugin manifest
adapters/herdr/herdr.sh    herdr actions
adapters/herdr/keys.sh     binds the herdr keys (the plugin's build step)
adapters/rex/agentfork.lua Rex actions and keys
adapters/ghostty/          Ghostty keybindings
Makefile, install.sh       install and uninstall
tests/run.sh               tests against a fake ~/.claude and herdr config
```

## Not yet

- Codex. It has no pid-to-session file, so finding its session needs
  another approach (the rollout file the process has open).
