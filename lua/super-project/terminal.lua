local util = require("super-project.util")

local M = {}

function M.is_running(buffer, job)
  if not util.valid_buf(buffer) or not job or vim.bo[buffer].buftype ~= "terminal" then
    return false
  end
  local ok, statuses = pcall(vim.fn.jobwait, { job }, 0)
  return ok and statuses[1] == -1
end

function M.apply_cwd(window, cwd, scope)
  if not util.valid_win(window) or not cwd or vim.fn.isdirectory(cwd) ~= 1 then
    return
  end
  vim.api.nvim_win_call(window, function()
    if scope == 2 then
      vim.cmd("silent tcd " .. vim.fn.fnameescape(cwd))
    elseif scope == 1 then
      vim.cmd("silent lcd " .. vim.fn.fnameescape(cwd))
    end
  end)
end

function M.open_fresh(window, cwd, scope)
  if not util.valid_win(window) then
    return nil, "terminal window is invalid"
  end
  M.apply_cwd(window, cwd, scope)
  local ok, buffer = xpcall(function()
    return vim.api.nvim_win_call(window, function()
      vim.cmd("terminal")
      return vim.api.nvim_get_current_buf()
    end)
  end, debug.traceback)
  if not ok then
    return nil, buffer
  end
  return buffer
end

return M
