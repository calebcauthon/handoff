-- agentfork for Rex: copy a Claude Code conversation and paste it as a fork.
--
-- Load it from ~/.config/rex/init.lua with:
--   require("agentfork")
-- (install.sh links this file there and adds the line.)
--
-- Rex reports the foreground process of every pane, so copy always takes the
-- conversation in the focused pane. When the focused pane isn't running
-- Claude and the choice is ambiguous, a picker opens in a split below.
--
-- Keys, matching the herdr fork plugin:
--   ctrl+b>c          copy the conversation in this pane
--   ctrl+b>v          paste: start the fork in this pane (at a shell prompt)
--   ctrl+b>f          fork into a new tab
--   ctrl+b>shift+f    fork into a split on the right
--   alt+shift+v       fork into a split on the right
-- Rebind them after the require; the actions are agentfork_copy,
-- agentfork_paste, agentfork_fork_tab and agentfork_fork_split.

local BIN = os.getenv("AGENTFORK_BIN") or (os.getenv("HOME") .. "/.local/bin/agentfork")
local TERMINAL = "com.superlogical.terminal"
local SHELL = "com.superlogical.terminal.shell"

-- Quote for a POSIX shell.
local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function foreground_pid(block_id)
  if block_id == nil then return nil end
  local p = rex.block.call(TERMINAL, "process", { block_id = block_id })
  return p and p.foreground and p.foreground.pid
end

-- Copy the conversation in block_id. Returns true when copied and false when
-- the user has to pick; raises on anything else.
local function copy(block_id)
  local argv = { BIN, "copy", "--notify", "--quiet" }
  local pid = foreground_pid(block_id)
  if pid then
    table.insert(argv, "--pid")
    table.insert(argv, tostring(pid))
  end
  local r, err = rex.exec(argv, { timeout = 15 })
  if r == nil then error(err, 0) end
  if r.ok then return true end
  if r.code == 3 then return false end
  error(r.stderr ~= "" and r.stderr or ("agentfork exited with status " .. r.code), 0)
end

-- Open a shell beside the block (or in a new tab) and type a command into it.
local function open(where, ctx, command)
  local layout = rex.layout.block{
    flavor  = SHELL,
    options = { initial_input = command .. "\r" },
  }
  local _, err
  if where == "tab" then
    _, err = rex.session.new_window{ layout = layout }
  else
    _, err = rex.session.new_split{
      anchor_id = ctx.block_id,
      direction = where == "down" and "vertical" or "horizontal",
      side      = "after",
      layout    = layout,
      focus     = true,
    }
  end
  if err ~= nil then error(err, 0) end
end

local function fork(where)
  return function(ctx)
    if copy(ctx.block_id) then
      open(where, ctx, q(BIN) .. " paste")
    else
      open(where, ctx, q(BIN) .. " fork --pick")
    end
  end
end

rex.action{
  name     = "agentfork_copy",
  title    = "Copy Conversation for Fork",
  category = "agentfork",
  keywords = "claude fork copy session",
  run      = function(ctx)
    if not copy(ctx.block_id) then
      -- exec, so the picker's pane closes once a conversation is chosen.
      open("down", ctx, "exec " .. q(BIN) .. " copy --pick --notify")
    end
  end,
}

rex.action{
  name     = "agentfork_paste",
  title    = "Paste Conversation as Fork",
  category = "agentfork",
  keywords = "claude fork paste session",
  run      = function(ctx)
    local _, err = rex.block.call(TERMINAL, "write", {
      block_id = ctx.block_id,
      data     = q(BIN) .. " paste\r",
    })
    if err ~= nil then error(err, 0) end
  end,
}

rex.action{
  name     = "agentfork_fork_tab",
  title    = "Fork Conversation into New Tab",
  category = "agentfork",
  keywords = "claude fork session",
  run      = fork("tab"),
}

rex.action{
  name     = "agentfork_fork_split",
  title    = "Fork Conversation into Split",
  category = "agentfork",
  keywords = "claude fork session",
  run      = fork("right"),
}

rex.bind("ctrl+b>c", "agentfork_copy")
rex.bind("ctrl+b>v", "agentfork_paste")
rex.bind("ctrl+b>f", "agentfork_fork_tab")
rex.bind("ctrl+b>shift+f", "agentfork_fork_split")
rex.bind("alt+shift+v", "agentfork_fork_split")
