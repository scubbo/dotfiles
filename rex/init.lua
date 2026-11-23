rex.bind("ctrl+space>ctrl+space", "pane.send_key", { key = "ctrl+space" })

rex.bind("alt+z>left", "client.tab.previous")
rex.bind("alt+z>right", "client.tab.next")
rex.bind("alt+z>shift+c", "client.tab.new")
rex.bind("alt+z>v", "pane.split", { direction = "right" })
rex.bind("alt+z>alt+z", "pane.send_key", { key = "alt+z" })

local terminal = "com.superlogical.terminal"
local shell = "com.superlogical.terminal.shell"

-- Like Herdr: one session per repo, one tab per worktree.
rex.action{
  name = "new_worktree_tab",
  title = "New Worktree Tab",
  description = "Prompt for a topic, create or reuse a Git worktree, and open it in this session.",
  category = "Tab",
  keywords = "git branch worktree topic",
  args = { type = "object", additionalProperties = false },
  run = function(ctx, args)
    if not ctx.session_id or not ctx.block_id then
      error("Run New Worktree Tab from a terminal in a Rex session.", 0)
    end

    -- Capture the source directory before the popup becomes the focused pane.
    local process, err = rex.block.call(terminal, "process", {})
    if not process then error(err, 0) end
    local cwd = process.foreground and process.foreground.cwd
    if not cwd and process.ancestors and process.ancestors[1] then
      cwd = process.ancestors[1].cwd
    end
    if not cwd then error("Could not determine the focused terminal's directory.", 0) end

    local source
    source, err = rex.session.describe_block{ block_id = ctx.block_id }
    if not source then error(err, 0) end
    local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
    local popup
    popup, err = rex.session.new_layer{
      window_id = source.block.window_id,
      bounds = { 0.2, 0.35, 0.6, 0.3 },
      focus = true,
      layout = rex.layout.block{
        flavor = shell,
        label = "New worktree tab",
        options = {
          cwd = cwd,
          command = { "bash", config_home .. "/rex/new-worktree-tab.sh", ctx.session_id, cwd, ctx.client_id or "" },
        },
      },
    }
    if not popup then error(err, 0) end
    return popup
  end,
}

rex.bind("alt+z>c", "new_worktree_tab")

-- A fork made inside the fx shell replaces the original on screen. A fork made
-- from outside with `fx session fork` keeps the original running, so the copy
-- can go beside it.
rex.action{
  name = "fork_agent_pane",
  title = "Fork Agent into Split Pane",
  description = "Copy the fx conversation in this pane and open the copy in a pane beside it.",
  category = "Pane",
  keywords = "fx agent fork conversation session split",
  args = { type = "object", additionalProperties = false },
  run = function(ctx, args)
    if not ctx.session_id or not ctx.block_id then
      error("Run Fork Agent into Split Pane from a terminal in a Rex session.", 0)
    end

    local process, err = rex.block.call(terminal, "process", {})
    if not process then error(err, 0) end
    local agent = process.foreground
    if not agent or agent.name ~= "fx" then
      error("The pane is running " .. (agent and agent.name or "nothing") .. ", not fx.", 0)
    end

    -- fx keeps <FX_HOME>/sessions/v2/<id>/lock open for each conversation it
    -- has open, including its subagents' conversations.
    local open_files
    open_files, err = rex.exec({ "lsof", "-a", "-p", tostring(agent.pid), "-Fn" })
    if not open_files then error(err, 0) end
    local fx_home
    local open_conversations = {}
    for line in open_files.stdout:gmatch("[^\n]+") do
      local home, id = line:match("^n(.*)/sessions/v2/([^/]+)/lock$")
      if id then
        fx_home = home
        open_conversations[id] = true
      end
    end
    if not fx_home then error("The fx in this pane has no saved conversation yet.", 0) end

    local fx_errors = {
      -- An fx without `session fork` reads "fork" as a malformed session id.
      InvalidSessionDetailArgs = "The fx in this pane has no `session fork` command. Upgrade fx.",
    }
    local function fx(...)
      local result, exec_err = rex.exec({ agent.path, ... }, { env = { FX_HOME = fx_home }, timeout = 20 })
      if not result then error(exec_err, 0) end
      local reply = rex.json.decode(result.stdout)
      if not reply then error("fx " .. table.concat({ ... }, " ") .. " failed: " .. result.stderr, 0) end
      if reply.error then error(fx_errors[reply.code] or reply.error, 0) end
      return reply
    end

    -- The live list names subagents under their parent, so its top level
    -- holds only the conversations a person can resume.
    local source_id
    for _, conversation in ipairs(fx("sessions", "--live", "--all", "--json").sessions) do
      if open_conversations[conversation.id] then
        if source_id then error("This fx has several conversations open, so there is no single one to fork.", 0) end
        source_id = conversation.id
      end
    end
    if not source_id then error("fx does not list this pane's conversation as open.", 0) end

    -- `session fork` reads the conversation without taking its lock, so the
    -- agent in this pane is not interrupted. The copy ends at the last
    -- finished turn, so a turn that is still running stays out of it and is
    -- not run a second time.
    local fork_id = fx("session", "fork", "--id", source_id, "--json").fork_id

    local command = { agent.path, "--resume", fork_id }
    if fx_home ~= os.getenv("HOME") .. "/.fx" then
      command = { "env", "FX_HOME=" .. fx_home, unpack(command) }
    end
    local split
    split, err = rex.session.new_split{
      anchor_id = ctx.block_id,
      direction = "horizontal",
      side = "after",
      focus = true,
      layout = rex.layout.block{
        flavor = shell,
        -- Read ~/.zshrc so the copy gets the environment of an fx started by hand.
        options = { cwd = agent.cwd, command = command, interactive = true },
      },
    }
    if not split then
      error("Saved the fork, but could not open a pane for it: " .. err ..
        "\nOpen it with: fx --resume " .. fork_id, 0)
    end
    return { block_id = split.block_ids[1], fx_session_id = fork_id }
  end,
}

rex.bind("alt+z>f", "fork_agent_pane")
