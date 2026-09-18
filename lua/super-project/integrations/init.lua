local config = require("super-project.config")
local log = require("super-project.log")

local M = {}

local adapter_names = { "neo_tree", "super_tree", "barbar" }
local adapters = {}
local public_api
local augroup

local function adapter(name)
  if not adapters[name] then
    adapters[name] = require("super-project.integrations." .. name)
  end
  return adapters[name]
end

local function call(name, method, ...)
  local instance = adapter(name)
  if type(instance[method]) ~= "function" then
    return nil
  end
  local arguments = { ... }
  local ok, result = xpcall(function()
    return instance[method](unpack(arguments))
  end, debug.traceback)
  if not ok then
    log.notify(
      "warn",
      string.format("%s integration %s failed: %s", name, method, result),
      name .. "-" .. method
    )
    return nil
  end
  return result
end

local function register_super_tree()
  if config.options.integrations.super_tree and public_api then
    call("super_tree", "register_provider", public_api)
  end
end

function M.setup(api)
  M.teardown()
  public_api = api
  adapters = {}
  augroup = vim.api.nvim_create_augroup("SuperProjectIntegrations", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = { "LazyLoad", "SuperTreeOpen" },
    callback = function(event)
      if
        event.match == "SuperTreeOpen"
        or event.data == "super-tree.nvim"
        or event.data == "super-tree"
      then
        vim.schedule(register_super_tree)
      elseif event.data == "neo-tree.nvim" or event.data == "neo-tree" then
        vim.schedule(function()
          call("neo_tree", "restore_pending")
        end)
      elseif event.data == "barbar.nvim" or event.data == "barbar" then
        vim.schedule(function()
          call("barbar", "restore_pending")
        end)
      end
    end,
  })
  vim.schedule(register_super_tree)
end

function M.teardown()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = nil
  for name in pairs(adapters) do
    call(name, "teardown")
  end
  adapters = {}
end

function M.capture_and_suspend(context)
  local states = {}
  for _, name in ipairs(adapter_names) do
    if config.options.integrations[name] then
      local state = call(name, "capture", context)
      if state ~= nil then
        states[name] = state
        call(name, "suspend", context, state)
      end
    end
  end
  return states
end

function M.restore(states, context)
  states = type(states) == "table" and states or {}
  for _, name in ipairs(adapter_names) do
    if config.options.integrations[name] and states[name] ~= nil then
      call(name, "restore", context, states[name])
    end
  end
  register_super_tree()
end

function M.seed(states, source_states, context)
  states = type(states) == "table" and states or {}
  source_states = type(source_states) == "table" and source_states or {}
  for _, name in ipairs(adapter_names) do
    if config.options.integrations[name] and states[name] == nil and source_states[name] ~= nil then
      local seeded = call(name, "seed", context, source_states[name])
      if seeded ~= nil then
        states[name] = seeded
      end
    end
  end
  return states
end

return M
