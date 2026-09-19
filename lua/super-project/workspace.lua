local config = require("super-project.config")
local path = require("super-project.path")
local terminal = require("super-project.terminal")
local util = require("super-project.util")

local M = {}

local OWNER_VAR = "super_project_workspace"
local PLACEHOLDER_VAR = "super_project_placeholder"
local TEMPORARY_VAR = "super_project_temporary"

local WINDOW_OPTIONS = {
  "colorcolumn",
  "concealcursor",
  "conceallevel",
  "cursorcolumn",
  "cursorline",
  "diff",
  "foldcolumn",
  "foldenable",
  "foldexpr",
  "foldignore",
  "foldlevel",
  "foldmarker",
  "foldmethod",
  "foldminlines",
  "foldnestmax",
  "list",
  "number",
  "relativenumber",
  "signcolumn",
  "spell",
  "statusline",
  "winbar",
  "winfixheight",
  "winfixwidth",
  "winhighlight",
  "wrap",
}

local function tab_var(tab, name, value)
  if value == nil then
    local ok, result = pcall(vim.api.nvim_tabpage_get_var, tab, name)
    return ok and result or nil
  end
  if value == vim.NIL then
    pcall(vim.api.nvim_tabpage_del_var, tab, name)
  else
    pcall(vim.api.nvim_tabpage_set_var, tab, name, value)
  end
end

local function transition_tabs()
  local result = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab_var(tab, "super_project_transition") then
      result[#result + 1] = tab
    end
  end
  return result
end

local function capture_options(win)
  local options = {}
  for _, name in ipairs(WINDOW_OPTIONS) do
    local ok, value = pcall(function()
      return vim.wo[win][name]
    end)
    if ok then
      options[name] = value
    end
  end
  return options
end

local function layout_snapshot(layout, windows, by_id)
  local kind = layout[1]
  if kind == "leaf" then
    local win = layout[2]
    local index = by_id[win]
    if not index then
      index = #windows + 1
      by_id[win] = index
      local buffer = vim.api.nvim_win_get_buf(win)
      local directory = vim.api.nvim_win_call(win, function()
        return { scope = vim.fn.haslocaldir(), cwd = vim.fn.getcwd() }
      end)
      local cursor = vim.api.nvim_win_get_cursor(win)
      -- A TUI's cursor can be anywhere on its live screen. Only cursors above
      -- that screen represent scrollback positions to preserve while parked.
      local following
      if vim.bo[buffer].buftype == "terminal" then
        local screen_start = math.max(
          1,
          vim.api.nvim_buf_line_count(buffer) - vim.api.nvim_win_get_height(win) + 1
        )
        following = cursor[1] >= screen_start
      end
      windows[index] = {
        buffer = buffer,
        view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
        cursor = cursor,
        following = following,
        width = vim.api.nvim_win_get_width(win),
        height = vim.api.nvim_win_get_height(win),
        options = capture_options(win),
        cwd = directory.cwd,
        cwd_scope = directory.scope,
      }
    end
    return { kind = "leaf", window = index }
  end
  local node = { kind = kind, children = {} }
  for _, child in ipairs(layout[2] or {}) do
    node.children[#node.children + 1] = layout_snapshot(child, windows, by_id)
  end
  return node
end

local function terminal_job(buffer)
  local ok, job = pcall(vim.api.nvim_buf_get_var, buffer, "terminal_job_id")
  return ok and job or nil
end

local function get_buffer_var(buffer, name)
  local ok, value = pcall(vim.api.nvim_buf_get_var, buffer, name)
  return ok and value or nil
end

local function set_buffer_var(buffer, name, value)
  if value == nil then
    pcall(vim.api.nvim_buf_del_var, buffer, name)
  else
    pcall(vim.api.nvim_buf_set_var, buffer, name, value)
  end
end

local function redraw_bufferline()
  pcall(vim.cmd, "redrawtabline")
end

local function is_workspace_buffer(buffer)
  if not util.valid_buf(buffer) then
    return false
  end
  local buftype = vim.bo[buffer].buftype
  return buftype == "" or buftype == "acwrite" or buftype == "terminal"
end

local function is_empty_unnamed(buffer)
  if
    not util.valid_buf(buffer)
    or vim.bo[buffer].buftype ~= ""
    or vim.bo[buffer].modified
    or vim.api.nvim_buf_get_name(buffer) ~= ""
  then
    return false
  end
  if not vim.api.nvim_buf_is_loaded(buffer) then
    return true
  end
  return vim.api.nvim_buf_line_count(buffer) == 1
    and vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == ""
end

local function remember_buffer(snapshot, buffer)
  if not util.valid_buf(buffer) or snapshot.protected[buffer] then
    return
  end
  snapshot.protected[buffer] = {
    bufhidden = vim.bo[buffer].bufhidden,
    buflisted = vim.bo[buffer].buflisted,
    terminal_job_id = vim.bo[buffer].buftype == "terminal" and terminal_job(buffer) or nil,
  }
end

function M.claim_buffer(buffer, key)
  if not key or not is_workspace_buffer(buffer) then
    return false
  end
  set_buffer_var(buffer, OWNER_VAR, key)
  return true
end

function M.cleanup_placeholders(key)
  local changed = false
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if
      util.valid_buf(buffer)
      and get_buffer_var(buffer, PLACEHOLDER_VAR) == key
      and #vim.fn.win_findbuf(buffer) == 0
      and is_empty_unnamed(buffer)
    then
      local ok = pcall(vim.api.nvim_buf_delete, buffer, { force = true })
      changed = changed or ok
    end
  end
  if changed then
    redraw_bufferline()
  end
  return changed
end

function M.activate(key, root, options)
  options = options or {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not tab_var(tab, "super_project_transition") then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_get_config(win).relative == "" then
          M.claim_buffer(vim.api.nvim_win_get_buf(win), key)
        end
      end
    end
  end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if util.valid_buf(buffer) then
      local name = vim.api.nvim_buf_get_name(buffer)
      if name ~= "" and root and path.is_within(root, name) then
        M.claim_buffer(buffer, key)
      end
    end
  end
  if options.mark_current_placeholder then
    local current = vim.api.nvim_get_current_buf()
    if is_empty_unnamed(current) then
      set_buffer_var(current, PLACEHOLDER_VAR, key)
    end
  end
  M.cleanup_placeholders(key)
end

function M.capture(key, root)
  local current_tab = vim.api.nvim_get_current_tabpage()
  local snapshot = {
    key = key,
    tabs = {},
    active_tab = 1,
    protected = {},
    disposable = {},
    integrations = {},
  }
  local visible = {}

  local managed_tabs = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not tab_var(tab, "super_project_transition") then
      managed_tabs[#managed_tabs + 1] = tab
    end
  end
  if #managed_tabs == 0 then
    return nil, "no workspace tabs to capture"
  end

  for tab_index, tab in ipairs(managed_tabs) do
    vim.api.nvim_set_current_tabpage(tab)
    local windows = {}
    local by_id = {}
    local layout = layout_snapshot(vim.fn.winlayout(), windows, by_id)
    local current_win = vim.api.nvim_get_current_win()
    snapshot.tabs[tab_index] = {
      layout = layout,
      windows = windows,
      active_window = by_id[current_win] or 1,
    }
    if tab == current_tab then
      snapshot.active_tab = tab_index
    end
    for _, win in ipairs(windows) do
      local buffer = win.buffer
      if util.valid_buf(buffer) then
        visible[buffer] = true
        remember_buffer(snapshot, buffer)
        M.claim_buffer(buffer, key)
      end
    end
  end

  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if util.valid_buf(buffer) then
      local owner = get_buffer_var(buffer, OWNER_VAR)
      local name = vim.api.nvim_buf_get_name(buffer)
      local belongs_to_root = name ~= "" and root and path.is_within(root, name)
      if owner == key or belongs_to_root then
        M.claim_buffer(buffer, key)
        if
          not visible[buffer]
          and get_buffer_var(buffer, PLACEHOLDER_VAR) == key
          and is_empty_unnamed(buffer)
        then
          snapshot.disposable[buffer] = true
        else
          remember_buffer(snapshot, buffer)
        end
      end
    end
  end

  vim.api.nvim_set_current_tabpage(current_tab)
  return snapshot
end

local function protect(snapshot)
  for buffer in pairs(snapshot.protected or {}) do
    if util.valid_buf(buffer) then
      if vim.bo[buffer].buftype ~= "terminal" or config.options.terminals.keep_alive then
        vim.bo[buffer].bufhidden = "hide"
      end
      vim.bo[buffer].buflisted = false
    end
  end
  for buffer in pairs(snapshot.disposable or {}) do
    if util.valid_buf(buffer) then
      vim.bo[buffer].buflisted = false
      vim.bo[buffer].bufhidden = "wipe"
    end
  end
  redraw_bufferline()
end

function M.create_transition()
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  tab_var(tab, "super_project_transition", true)
  local buffer = vim.api.nvim_get_current_buf()
  set_buffer_var(buffer, TEMPORARY_VAR, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].buflisted = false
  return tab
end

function M.park(snapshot)
  protect(snapshot)
  -- Detach terminals before tabnew/tabclose can resize their screens (for
  -- example when 'showtabline' changes from one tab to two). A temporary
  -- shrink discards alternate-screen cells even if the size is restored
  -- before the application handles SIGWINCH.
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not tab_var(tab, "super_project_transition") then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buffer = vim.api.nvim_win_get_buf(win)
        if vim.bo[buffer].buftype == "terminal" then
          local scratch = vim.api.nvim_create_buf(false, true)
          vim.bo[scratch].bufhidden = "wipe"
          vim.api.nvim_win_set_buf(win, scratch)
        end
      end
    end
  end
  local transition = M.create_transition()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if
      tab ~= transition
      and not tab_var(tab, "super_project_transition")
      and util.valid_tab(tab)
    then
      vim.api.nvim_set_current_tabpage(tab)
      local ok, err = pcall(vim.cmd, "silent tabclose!")
      if not ok then
        return false, err
      end
    end
  end
  if util.valid_tab(transition) then
    vim.api.nvim_set_current_tabpage(transition)
  end
  for buffer in pairs(snapshot.disposable or {}) do
    if util.valid_buf(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  if not config.options.terminals.keep_alive then
    for buffer, state in pairs(snapshot.protected or {}) do
      if state.terminal_job_id and util.valid_buf(buffer) then
        pcall(vim.api.nvim_buf_delete, buffer, { force = true })
      end
    end
  end
  redraw_bufferline()
  return true
end

local function apply_options(win, options)
  for name, value in pairs(options or {}) do
    pcall(function()
      vim.wo[win][name] = value
    end)
  end
end

local function apply_cwd(win, state)
  terminal.apply_cwd(win, state.cwd, state.cwd_scope)
end

-- Displaying a loaded buffer triggers Neovim's file-timestamp check, which
-- raises E211 as a hard error when the file was deleted while the project was
-- parked. The window still receives the buffer before that error is raised
-- and its contents are intact, so keep it; only substitute a scratch buffer
-- when the swap did not happen.
local function set_window_buffer(win, buffer)
  local ok = pcall(vim.api.nvim_win_set_buf, win, buffer)
  if not ok and vim.api.nvim_win_get_buf(win) ~= buffer then
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win, buffer)
  end
  return buffer
end

local function set_window_state(win, state, buffer_states, terminal_replacements)
  local buffer = state.buffer
  local buffer_state = buffer_states[buffer] or {}
  if
    buffer_state.terminal_job_id
    and not terminal.is_running(buffer, buffer_state.terminal_job_id)
  then
    buffer = terminal_replacements[state.buffer]
    if not util.valid_buf(buffer) then
      local terminal_err
      buffer, terminal_err = terminal.open_fresh(win, state.cwd, state.cwd_scope)
      if not buffer then
        error(terminal_err)
      end
      terminal_replacements[state.buffer] = buffer
    else
      set_window_buffer(win, buffer)
    end
  elseif not util.valid_buf(buffer) then
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win, buffer)
  else
    buffer = set_window_buffer(win, buffer)
  end
  apply_options(win, state.options)
  apply_cwd(win, state)
end

local function split(win, kind)
  vim.api.nvim_set_current_win(win)
  vim.cmd(kind == "row" and "rightbelow vsplit" or "rightbelow split")
  return vim.api.nvim_get_current_win()
end

local function build_layout(node, seed, leaves)
  if node.kind == "leaf" then
    leaves[node.window] = seed
    return
  end
  local child_windows = { seed }
  for index = 2, #node.children do
    child_windows[index] = split(child_windows[index - 1], node.kind)
  end
  for index, child in ipairs(node.children) do
    build_layout(child, child_windows[index], leaves)
  end
end

local function close_transition_tabs(except)
  for _, tab in ipairs(transition_tabs()) do
    if tab ~= except and util.valid_tab(tab) and #vim.api.nvim_list_tabpages() > 1 then
      vim.api.nvim_set_current_tabpage(tab)
      pcall(vim.cmd, "silent tabclose!")
    end
  end
end

-- Neovim follows terminal output only for windows that display the buffer
-- (adjust_topline() in terminal.c), so views captured before a project was
-- parked no longer describe a terminal's live screen. Restoring them verbatim
-- can leave a terminal window scrolled into stale scrollback, or beyond the
-- buffer end where it renders blank filler rows, until a resize or an entry
-- into Terminal-mode repositions it. Follow the live end for windows that
-- were following output and clamp scrollback positions to the buffer.
local function restore_view(win, state)
  local view = state.view or {}
  local buffer = vim.api.nvim_win_get_buf(win)
  if util.valid_buf(buffer) and vim.bo[buffer].buftype == "terminal" then
    local line_count = vim.api.nvim_buf_line_count(buffer)
    -- A terminal replaced because its job ended while parked has no
    -- continuity with the captured view; always show its live screen.
    local replaced = buffer ~= state.buffer
    if replaced or state.following ~= false then
      return {
        lnum = line_count,
        col = 0,
        topline = math.max(1, line_count - vim.api.nvim_win_get_height(win) + 1),
      }
    end
    view = vim.deepcopy(view)
    if view.lnum then
      view.lnum = math.min(view.lnum, line_count)
    end
    if view.topline then
      view.topline = math.max(1, math.min(view.topline, line_count))
    end
  end
  return view
end

function M.restore(snapshot)
  if not snapshot or type(snapshot.tabs) ~= "table" or #snapshot.tabs == 0 then
    return false, "workspace snapshot is empty"
  end
  local created_tabs = {}
  local tab_leaves = {}
  local terminal_replacements = {}
  local known_buffers = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    known_buffers[buffer] = true
  end
  local ok, err = xpcall(function()
    util.without_equalalways(function()
      for tab_index, tab_state in ipairs(snapshot.tabs) do
        vim.cmd("tabnew")
        local tab = vim.api.nvim_get_current_tabpage()
        local seed_buffer = vim.api.nvim_get_current_buf()
        if not known_buffers[seed_buffer] then
          known_buffers[seed_buffer] = true
          set_buffer_var(seed_buffer, TEMPORARY_VAR, true)
          vim.bo[seed_buffer].bufhidden = "wipe"
          vim.bo[seed_buffer].buflisted = false
        end
        created_tabs[tab_index] = tab
        local leaves = {}
        tab_leaves[tab_index] = leaves
        build_layout(tab_state.layout, vim.api.nvim_get_current_win(), leaves)
        for index, win_state in ipairs(tab_state.windows) do
          local win = leaves[index]
          if util.valid_win(win) then
            apply_options(win, win_state.options)
          end
        end
      end

      -- Build and size the entire workspace with inert buffers. Attaching a
      -- live terminal to an intermediate split size can irreversibly truncate
      -- its screen, with no repaint if the app sees the same final PTY size.
      close_transition_tabs()
      for tab_index, tab_state in ipairs(snapshot.tabs) do
        vim.api.nvim_set_current_tabpage(created_tabs[tab_index])
        local leaves = tab_leaves[tab_index]
        for index, win_state in ipairs(tab_state.windows) do
          local win = leaves[index]
          if util.valid_win(win) then
            pcall(vim.api.nvim_win_set_width, win, win_state.width)
            pcall(vim.api.nvim_win_set_height, win, win_state.height)
          end
        end
      end
      for tab_index, tab_state in ipairs(snapshot.tabs) do
        vim.api.nvim_set_current_tabpage(created_tabs[tab_index])
        local leaves = tab_leaves[tab_index]
        for index, win_state in ipairs(tab_state.windows) do
          local win = leaves[index]
          if util.valid_win(win) then
            set_window_state(win, win_state, snapshot.protected, terminal_replacements)
          end
        end
        for index, win_state in ipairs(tab_state.windows) do
          local win = leaves[index]
          if util.valid_win(win) then
            local view = restore_view(win, win_state)
            pcall(vim.api.nvim_win_call, win, function()
              vim.fn.winrestview(view)
            end)
          end
        end
        local active = leaves[tab_state.active_window]
        if util.valid_win(active) then
          vim.api.nvim_set_current_win(active)
        end
      end

      local active_tab = created_tabs[snapshot.active_tab] or created_tabs[1]
      if util.valid_tab(active_tab) then
        vim.api.nvim_set_current_tabpage(active_tab)
      end
      for buffer, state in pairs(snapshot.protected or {}) do
        if util.valid_buf(buffer) and not terminal_replacements[buffer] then
          vim.bo[buffer].bufhidden = state.bufhidden or ""
          if state.buflisted ~= nil then
            vim.bo[buffer].buflisted = state.buflisted
          end
        end
      end
      for replaced, replacement in pairs(terminal_replacements) do
        if replaced ~= replacement and util.valid_buf(replaced) then
          pcall(vim.api.nvim_buf_delete, replaced, { force = true })
        end
      end
      for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if
          util.valid_buf(buffer)
          and get_buffer_var(buffer, TEMPORARY_VAR)
          and #vim.fn.win_findbuf(buffer) == 0
        then
          pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        end
      end
    end)
  end, debug.traceback)
  if not ok then
    return false, err
  end
  redraw_bufferline()
  return true
end

function M.claim_transition()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab_var(tab, "super_project_transition") then
      tab_var(tab, "super_project_transition", vim.NIL)
    end
  end
end

function M.new_workspace(key)
  M.claim_transition()
  local buffer = vim.api.nvim_get_current_buf()
  if not util.valid_buf(buffer) or vim.bo[buffer].buftype ~= "" then
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buffer)
  else
    vim.bo[buffer].buflisted = true
    vim.bo[buffer].bufhidden = ""
  end
  set_buffer_var(buffer, TEMPORARY_VAR, nil)
  M.claim_buffer(buffer, key)
  if is_empty_unnamed(buffer) then
    set_buffer_var(buffer, PLACEHOLDER_VAR, key)
  end
  redraw_bufferline()
  return true
end

function M.park_current_best_effort(key, root)
  local snapshot = M.capture(key or "__partial__", root)
  if snapshot then
    return M.park(snapshot)
  end
  return false
end

function M.assert_terminal(snapshot, buffer)
  local expected = snapshot and snapshot.protected and snapshot.protected[buffer]
  if not expected or not expected.terminal_job_id or not util.valid_buf(buffer) then
    return false
  end
  return terminal_job(buffer) == expected.terminal_job_id
end

return M
