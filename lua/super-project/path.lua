local config = require("super-project.config")
local util = require("super-project.util")

local M = {}

local function trim_separators(path)
  if path == "/" then
    return path
  end
  return path:gsub("[/\\]+$", "")
end

function M.absolute(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  local absolute = vim.fn.fnamemodify(expanded, ":p")
  if absolute == "" then
    return nil
  end
  return trim_separators(absolute:gsub("\\", "/"))
end

function M.canonical(path)
  local absolute = M.absolute(path)
  if not absolute then
    return nil
  end
  local real = util.uv.fs_realpath(absolute)
  return trim_separators((real or absolute):gsub("\\", "/"))
end

function M.display(path)
  local absolute = M.absolute(path)
  if not absolute then
    return nil
  end
  return vim.fn.fnamemodify(absolute, ":~")
end

function M.is_directory(path)
  return path ~= nil and vim.fn.isdirectory(path) == 1
end

function M.is_within(root, path)
  root = M.canonical(root)
  path = M.canonical(path)
  if not root or not path then
    return false
  end
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.relative(root, path)
  root = M.canonical(root)
  path = M.canonical(path)
  if not root or not path or not M.is_within(root, path) then
    return nil
  end
  if root == path then
    return "."
  end
  return path:sub(#root + 2)
end

function M.from_relative(root, relative)
  if type(relative) ~= "string" then
    return nil
  end
  local candidate = relative == "." and root or (root .. "/" .. relative)
  candidate = M.canonical(candidate)
  if candidate and M.is_within(root, candidate) then
    return candidate
  end
  return nil
end

local function glob_to_pattern(glob)
  glob = vim.fn.fnamemodify(glob, ":p")
  glob = trim_separators(glob)
  glob = glob:gsub("\\", "/")
  local result = { "^" }
  local index = 1
  while index <= #glob do
    local char = glob:sub(index, index)
    if char == "*" then
      if glob:sub(index + 1, index + 1) == "*" then
        result[#result + 1] = ".*"
        index = index + 2
      else
        result[#result + 1] = "[^/]*"
        index = index + 1
      end
    elseif char == "?" then
      result[#result + 1] = "[^/]"
      index = index + 1
    elseif char == "[" then
      local close = glob:find("]", index + 1, true)
      if close then
        local class = glob:sub(index + 1, close - 1)
        if class:sub(1, 1) == "!" then
          class = "^" .. class:sub(2)
        end
        result[#result + 1] = "[" .. class .. "]"
        index = close + 1
      else
        result[#result + 1] = "%["
        index = index + 1
      end
    else
      result[#result + 1] = char:gsub("([%%%.%+%-%^%$%(%)])", "%%%1")
      index = index + 1
    end
  end
  result[#result + 1] = "/?$"
  return table.concat(result)
end

local function configured_pattern(glob)
  local pattern = vim.fn.fnamemodify(glob, ":p")
  if config.options.discovery.symlinks ~= "prefix" then
    return pattern
  end
  local wildcard = pattern:find("[%*%?%[]")
  if not wildcard then
    return pattern
  end
  local before = pattern:sub(1, wildcard - 1)
  local slash = before:match("^.*()/")
  if not slash then
    return pattern
  end
  local prefix = before:sub(1, slash - 1)
  local resolved = util.uv.fs_realpath(prefix)
  if not resolved then
    return pattern
  end
  return resolved .. pattern:sub(slash)
end

function M.is_excluded(candidate)
  local absolute = M.absolute(candidate)
  local canonical = M.canonical(candidate)
  if not absolute or not canonical then
    return false
  end
  for _, glob in ipairs(config.options.discovery.excludes) do
    local pattern = glob_to_pattern(glob)
    if absolute:match(pattern) or canonical:match(pattern) then
      return true
    end
    for _, matched in ipairs(vim.fn.glob(glob, true, true, true)) do
      if M.canonical(matched) == canonical then
        return true
      end
    end
  end
  return false
end

function M.expand_roots()
  local projects = {}
  local seen = {}
  local source_order = 0
  for source_index, glob in ipairs(config.options.discovery.roots) do
    for _, candidate in ipairs(vim.fn.glob(configured_pattern(glob), true, true, true)) do
      if M.is_directory(candidate) and not M.is_excluded(candidate) then
        local root = M.canonical(candidate)
        if root and not seen[root] then
          seen[root] = true
          source_order = source_order + 1
          projects[#projects + 1] = {
            root = root,
            display = M.display(
              config.options.discovery.symlinks == "resolve" and root or candidate
            ),
            source = "configured",
            source_index = source_index,
            source_order = source_order,
          }
        end
      end
    end
  end
  return projects
end

function M.closest_project(projects, candidate)
  local absolute = M.canonical(candidate)
  if not absolute then
    return nil
  end
  local closest
  for _, project in ipairs(projects or {}) do
    if M.is_within(project.root, absolute) and (not closest or #project.root > #closest.root) then
      closest = project
    end
  end
  return closest
end

return M
