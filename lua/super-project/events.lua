local log = require("super-project.log")
local util = require("super-project.util")

local M = {}

function M.emit(pattern, data)
  local ok, err = util.safe_autocmd(pattern, data)
  if not ok then
    log.error("event failed: " .. tostring(err), pattern)
  end
  return ok
end

return M
