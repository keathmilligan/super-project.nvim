local config = require("super-project.config")
local util = require("super-project.util")

local M = {}

local levels = { off = 99, error = 1, warn = 2, info = 3, debug = 4 }
local notify_levels = {
  error = vim.log.levels.ERROR,
  warn = vim.log.levels.WARN,
  info = vim.log.levels.INFO,
  debug = vim.log.levels.DEBUG,
}
local notified = {}

local function enabled(level)
  return levels[level] <= (levels[config.options.logging.level] or levels.warn)
end

function M.path()
  return config.options.storage.directory .. "/super-project.log"
end

function M.write(level, message, context)
  if not enabled(level) then
    return
  end
  local line = string.format(
    "%s %-5s %s%s\n",
    os.date("!%Y-%m-%dT%H:%M:%SZ"),
    level:upper(),
    tostring(message),
    context and (" [" .. tostring(context) .. "]") or ""
  )
  local path = M.path()
  util.ensure_dir(vim.fn.fnamemodify(path, ":h"))
  local fd = util.uv.fs_open(path, "a", 384)
  if fd then
    util.uv.fs_write(fd, line, -1)
    util.uv.fs_close(fd)
  end
end

function M.notify(level, message, once_key)
  M.write(level, message)
  if once_key and notified[once_key] then
    return
  end
  if once_key then
    notified[once_key] = true
  end
  vim.notify(message, notify_levels[level] or vim.log.levels.INFO, { title = "Super Project" })
end

function M.error(message, context)
  M.write("error", message, context)
end

function M.warn(message, context)
  M.write("warn", message, context)
end

function M.info(message, context)
  M.write("info", message, context)
end

function M.debug(message, context)
  M.write("debug", message, context)
end

function M.reset()
  notified = {}
end

return M
