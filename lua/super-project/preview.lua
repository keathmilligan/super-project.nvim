local config = require("super-project.config")
local git = require("super-project.git")
local util = require("super-project.util")

local M = {}

local function visible(name)
  return config.options.selector.display.hidden_entries or name:sub(1, 1) ~= "."
end

local function scan(lines, directory, prefix, depth, budget)
  if depth > 2 or budget.count >= 200 then
    return
  end
  local handle = util.uv.fs_scandir(directory)
  if not handle then
    return
  end
  local entries = {}
  while true do
    local name, kind = util.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if visible(name) then
      entries[#entries + 1] = { name = name, kind = kind }
    end
  end
  table.sort(entries, function(a, b)
    if (a.kind == "directory") ~= (b.kind == "directory") then
      return a.kind == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)
  for _, entry in ipairs(entries) do
    if budget.count >= 200 then
      lines[#lines + 1] = prefix .. "…"
      return
    end
    budget.count = budget.count + 1
    local directory_entry = entry.kind == "directory"
    lines[#lines + 1] = prefix .. entry.name .. (directory_entry and "/" or "")
    if directory_entry then
      scan(lines, directory .. "/" .. entry.name, prefix .. "  ", depth + 1, budget)
    end
  end
end

function M.generate(project)
  local lines = {
    vim.fn.fnamemodify(project.root, ":t"),
    project.display or project.root,
  }
  if config.options.selector.display.git_state and git.available() then
    if config.options.selector.display.fetch_remote then
      git.run(project.root, { "fetch", "--quiet" }, 5000)
    end
    local status = git.status(project.root)
    if status then
      local counters = ""
      if status.ahead > 0 or status.behind > 0 then
        counters = string.format(" ↑%d ↓%d", status.ahead, status.behind)
      end
      lines[#lines + 1] = "Git: "
        .. (status.branch or "detached")
        .. counters
        .. (status.dirty and " (changes)" or " (clean)")
    end
  end
  lines[#lines + 1] = ""
  scan(lines, project.root, "", 0, { count = 0 })
  return lines
end

return M
