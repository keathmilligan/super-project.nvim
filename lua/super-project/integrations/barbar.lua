local path = require("super-project.path")

local M = {}
local pending

local function loaded()
  local state = package.loaded["barbar.state"]
  return type(state) == "table" and state or nil
end

function M.capture(context)
  local state = loaded()
  if not state or type(state.export_buffers) ~= "function" then
    return nil
  end
  local exported = state.export_buffers()
  local buffers = {}
  for _, item in ipairs(exported or {}) do
    local name = type(item) == "table" and item.name or item
    local absolute = path.absolute(name)
    if absolute and path.is_within(context.root, absolute) then
      buffers[#buffers + 1] = {
        path = path.relative(context.root, absolute),
        pinned = type(item) == "table" and item.pinned or nil,
      }
    end
  end
  return { version = 1, buffers = buffers }
end

function M.suspend() end

function M.restore(context, payload)
  if type(payload) ~= "table" or payload.version ~= 1 then
    return
  end
  local state = loaded()
  if not state then
    local ok, result = pcall(require, "barbar.state")
    state = ok and result or nil
  end
  if not state or type(state.restore_buffers) ~= "function" then
    pending = { context = vim.deepcopy(context), payload = vim.deepcopy(payload) }
    return
  end
  local buffers = {}
  for _, item in ipairs(payload.buffers or {}) do
    local absolute = path.from_relative(context.root, item.path)
    if absolute and (vim.fn.bufnr(absolute) >= 0 or vim.fn.filereadable(absolute) == 1) then
      buffers[#buffers + 1] = { name = absolute, pinned = item.pinned or nil }
    end
  end
  state.restore_buffers(buffers)
  pending = nil
  pcall(vim.cmd, "redrawtabline")
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
