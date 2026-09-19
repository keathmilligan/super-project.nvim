local path = require("super-project.path")
local util = require("super-project.util")

local M = {}

local pending
local subscribed = false

local function manager_loaded()
  return type(package.loaded["neo-tree.sources.manager"]) == "table"
end

local function manager(demand)
  local instance = package.loaded["neo-tree.sources.manager"]
  if instance or not demand then
    return instance
  end
  local ok, result = pcall(require, "neo-tree.sources.manager")
  return ok and result or nil
end

local function filesystem_state(demand)
  local instance = manager(demand)
  if not instance or type(instance.get_state) ~= "function" then
    return nil
  end
  local ok, state = pcall(instance.get_state, "filesystem")
  return ok and state or nil
end

local function is_open()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buffer = vim.api.nvim_win_get_buf(win)
      if vim.bo[buffer].filetype == "neo-tree" then
        return true, win
      end
    end
  end
  return false
end

local function restore_expanded(context, payload)
  local state = filesystem_state(false)
  if not state or not state.tree then
    pending = { context = context, payload = payload }
    return
  end
  state.explicitly_opened_nodes = state.explicitly_opened_nodes or {}
  local directories = {}
  for _, relative in ipairs(payload.expanded or {}) do
    local absolute = path.from_relative(context.root, relative)
    if absolute and vim.fn.isdirectory(absolute) == 1 then
      directories[#directories + 1] = absolute
    end
  end
  table.sort(directories, function(a, b)
    return select(2, a:gsub("/", "")) < select(2, b:gsub("/", ""))
  end)
  for _, directory in ipairs(directories) do
    state.explicitly_opened_nodes[directory] = true
    local node = state.tree:get_node(directory)
    if node and type(node.expand) == "function" then
      node:expand()
    end
    if state.commands and type(state.commands.refresh) == "function" then
      state.commands.refresh(state)
    end
  end
  if payload.selected then
    local selected = path.from_relative(context.root, payload.selected)
    if selected and state.tree.set_active_node then
      pcall(state.tree.set_active_node, state.tree, selected)
    end
  end
  pending = nil
end

local function subscribe()
  if subscribed then
    return
  end
  local ok, neo_events = pcall(require, "neo-tree.events")
  if not ok then
    return
  end
  subscribed = true
  neo_events.subscribe({
    event = neo_events.AFTER_RENDER,
    handler = function()
      if pending then
        restore_expanded(pending.context, pending.payload)
      end
    end,
  })
end

function M.capture(context)
  if not manager_loaded() then
    return nil
  end
  local open, win = is_open()
  local state = filesystem_state(false)
  local expanded = {}
  local selected
  if state then
    for directory, value in pairs(state.explicitly_opened_nodes or {}) do
      if value then
        local relative = path.relative(context.root, directory)
        if relative then
          expanded[#expanded + 1] = relative
        end
      end
    end
    if state.tree and state.tree.get_node then
      local ok, node = pcall(state.tree.get_node, state.tree)
      if ok and node then
        local id = type(node.get_id) == "function" and node:get_id() or node.id
        selected = id and path.relative(context.root, id) or nil
      end
    end
  end
  table.sort(expanded)
  return {
    version = 1,
    open = open,
    expanded = expanded,
    selected = selected,
    width = open and vim.api.nvim_win_get_width(win) or nil,
  }
end

function M.suspend(_, payload)
  if payload and payload.open then
    pcall(vim.cmd, "silent Neotree close")
  end
end

function M.restore(context, payload)
  if type(payload) ~= "table" or payload.version ~= 1 or not payload.open then
    return
  end
  local ok, command = pcall(require, "neo-tree.command")
  if not ok or type(command.execute) ~= "function" then
    pending = { context = vim.deepcopy(context), payload = vim.deepcopy(payload) }
    return
  end
  subscribe()
  command.execute({ action = "show", source = "filesystem", dir = context.root })
  vim.schedule(function()
    util.without_equalalways(function()
      restore_expanded(context, payload)
      local open, win = is_open()
      if open and payload.width then
        pcall(vim.api.nvim_win_set_width, win, payload.width)
      end
    end)
  end)
end

function M.restore_pending()
  if pending then
    local saved = pending
    pending = nil
    M.restore(saved.context, saved.payload)
  end
end

function M.teardown()
  pending = nil
end

return M
