local config = require("super-project.config")
local path = require("super-project.path")
local util = require("super-project.util")

local M = {}

local function directory_entries(directory)
  local entries = {
    {
      action = "open",
      path = directory,
      label = "Open this directory",
    },
  }
  local parent = vim.fs.dirname(directory)
  if parent and parent ~= directory then
    entries[#entries + 1] = {
      action = "browse",
      path = parent,
      label = "../",
    }
  end

  local children = {}
  local handle = util.uv.fs_scandir(directory)
  if handle then
    while true do
      local name, kind = util.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local child = directory == "/" and ("/" .. name) or (directory .. "/" .. name)
      local linked = kind == "link" and util.uv.fs_stat(child) or nil
      local is_directory = kind == "directory" or (linked and linked.type == "directory")
      if
        is_directory
        and (config.options.selector.display.hidden_entries or name:sub(1, 1) ~= ".")
      then
        children[#children + 1] = {
          action = "browse",
          path = path.absolute(child),
          label = name .. "/",
        }
      end
    end
  end
  table.sort(children, function(a, b)
    return a.label:lower() < b.label:lower()
  end)
  vim.list_extend(entries, children)
  return entries
end

function M.browse(directory, on_select)
  directory = path.absolute(directory or vim.fn.getcwd())
  if not directory or not path.is_directory(directory) then
    return false, "directory does not exist"
  end

  vim.ui.select(directory_entries(directory), {
    prompt = "Open Directory as Project: " .. path.display(directory),
    format_item = function(entry)
      return entry.label
    end,
  }, function(entry)
    if not entry then
      return
    end
    if entry.action == "open" then
      on_select(entry.path)
      return
    end
    vim.schedule(function()
      M.browse(entry.path, on_select)
    end)
  end)
  return true
end

return M
