rex.bind("ctrl+space>ctrl+space", "pane.send_key", { key = "ctrl+space" })

rex.bind("alt+z>left", "client.tab.previous")
rex.bind("alt+z>right", "client.tab.next")
rex.bind("alt+z>shift+c", "client.tab.new")
rex.bind("alt+z>v", "pane.split", { direction = "right" })
rex.bind("alt+z>alt+z", "pane.send_key", { key = "alt+z" })

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
    local process, err = rex.block.call("com.superlogical.terminal", "process", {})
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
        flavor = "com.superlogical.terminal.shell",
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
