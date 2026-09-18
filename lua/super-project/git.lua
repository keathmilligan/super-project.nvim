local log = require("super-project.log")
local path = require("super-project.path")
local util = require("super-project.util")

local M = {}

function M.available()
  return vim.fn.executable("git") == 1
end

local function command_args(directory, args)
  local result = { "git", "-C", directory }
  vim.list_extend(result, args)
  return result
end

local function parse_result(result)
  if not result or result.code ~= 0 then
    return nil, result and util.trim(result.stderr) or "git did not run"
  end
  local output = util.trim(result.stdout)
  if output == "" then
    return nil, "git returned no output"
  end
  return output
end

function M.run(directory, args, timeout)
  if not M.available() then
    return nil, "Git is not available"
  end
  local result = vim.system(command_args(directory, args), { text = true }):wait(timeout or 2000)
  return parse_result(result)
end

function M.run_async(directory, args, callback)
  if not M.available() then
    vim.schedule(function()
      callback(nil, "Git is not available")
    end)
    return nil
  end
  return vim.system(command_args(directory, args), { text = true }, function(result)
    local value, err = parse_result(result)
    vim.schedule(function()
      callback(value, err)
    end)
  end)
end

function M.root(directory)
  local root, err = M.run(directory, { "rev-parse", "--show-toplevel" })
  if not root then
    return nil, err
  end
  root = path.canonical(root)
  if not path.is_directory(root) then
    return nil, "Git root is not a directory"
  end
  return root
end

function M.root_async(directory, callback)
  return M.run_async(directory, { "rev-parse", "--show-toplevel" }, function(root, err)
    if root then
      root = path.canonical(root)
      if not path.is_directory(root) then
        root, err = nil, "Git root is not a directory"
      end
    end
    callback(root, err)
  end)
end

function M.branch(directory)
  local branch = M.run(directory, { "symbolic-ref", "--quiet", "--short", "HEAD" })
  if branch then
    return branch
  end
  local commit, err = M.run(directory, { "rev-parse", "--short=12", "HEAD" })
  if commit then
    return "detached-" .. commit
  end
  return nil, err
end

function M.head_path(directory)
  local head, err = M.run(directory, { "rev-parse", "--git-path", "HEAD" })
  if not head then
    return nil, err
  end
  if head:sub(1, 1) ~= "/" then
    head = directory .. "/" .. head
  end
  return path.absolute(head)
end

function M.status(directory)
  if not M.available() then
    return nil
  end
  local branch = M.branch(directory)
  local porcelain = M.run(directory, { "status", "--short", "--branch" }) or ""
  local lines = porcelain ~= "" and vim.split(porcelain, "\n", { plain = true }) or {}
  local summary = lines[1] or ""
  local files = {}
  for index = 2, #lines do
    if lines[index] ~= "" then
      files[#files + 1] = lines[index]
    end
  end
  return {
    branch = branch,
    dirty = #files > 0,
    ahead = tonumber(summary:match("ahead (%d+)")) or 0,
    behind = tonumber(summary:match("behind (%d+)")) or 0,
    lines = files,
  }
end

function M.log_negative(message)
  log.debug(message, "git")
end

return M
