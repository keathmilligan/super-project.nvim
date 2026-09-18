local log = require("super-project.log")
local path = require("super-project.path")

local M = {}
local pending

local function loaded()
  local instance = package.loaded["super-tree"] or package.loaded["super-tree.init"]
  return type(instance) == "table" and instance or nil
end

local function obtain(demand)
  local instance = loaded()
  if instance or not demand then
    return instance
  end
  local ok, result = pcall(require, "super-tree")
  return ok and result or nil
end

function M.capture(context)
  local instance = obtain(false)
  if not instance or type(instance.capture_state) ~= "function" then
    return nil
  end
  local state = instance.capture_state()
  if type(state) ~= "table" then
    return nil
  end
  state = vim.deepcopy(state)
  state.root_relative = path.relative(context.root, state.root) or "."
  state.root = nil
  local expanded = {}
  for _, directory in ipairs(state.expanded_paths or {}) do
    local relative = path.relative(context.root, directory)
    if relative then
      expanded[#expanded + 1] = relative
    end
  end
  state.expanded_paths = expanded
  state.selected_path = state.selected_path and path.relative(context.root, state.selected_path)
    or nil
  state.selected_buffer = state.selected_buffer
      and path.relative(context.root, state.selected_buffer)
    or nil
  return state
end

function M.suspend(_, state)
  local instance = obtain(false)
  if instance and state and state.open and type(instance.close) == "function" then
    instance.close()
  end
end

function M.restore(context, state)
  if state then
    state = vim.deepcopy(state)
    state.root = path.from_relative(context.root, state.root_relative or ".") or context.root
    state.root_relative = nil
    local expanded = {}
    for _, directory in ipairs(state.expanded_paths or {}) do
      local absolute = path.from_relative(context.root, directory)
      if absolute then
        expanded[#expanded + 1] = absolute
      end
    end
    state.expanded_paths = expanded
    state.selected_path = state.selected_path
        and path.from_relative(context.root, state.selected_path)
      or nil
    state.selected_buffer = state.selected_buffer
        and path.from_relative(context.root, state.selected_buffer)
      or nil
  end
  local instance = obtain(state and state.open == true)
  if not instance then
    log.debug("Super Tree state is pending because the plugin is unavailable", "integration")
    pending = { context = vim.deepcopy(context), state = vim.deepcopy(state) }
    return
  end
  if type(instance.restore_state) == "function" then
    instance.restore_state(state)
    pending = nil
  end
end

function M.seed(context, source)
  if type(source) ~= "table" or not source.open then
    return nil
  end
  local state = vim.deepcopy(source)
  state.root_relative = "."
  state.root = nil
  state.expanded_paths = {}
  state.selected_path = nil
  state.selected_buffer = nil
  state.selected_project = context.root
  return state
end

function M.register_provider(api)
  local instance = obtain(false)
  if not instance or type(instance.register_project_provider) ~= "function" then
    return false
  end
  instance.register_project_provider("super-project", {
    manages_tree_state = true,
    projects = function(options)
      return api.projects(options)
    end,
    current = function()
      return api.current()
    end,
    open = function(root)
      return api.open(root)
    end,
  })
  if pending and type(instance.restore_state) == "function" then
    M.restore(pending.context, pending.state)
  end
  return true
end

function M.teardown()
  local instance = obtain(false)
  if instance and type(instance.unregister_project_provider) == "function" then
    instance.unregister_project_provider("super-project")
  end
  pending = nil
end

return M
