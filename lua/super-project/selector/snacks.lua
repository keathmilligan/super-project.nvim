local config = require("super-project.config")

local M = {}

function M.open(projects, options)
  local snacks = rawget(_G, "Snacks")
  if not snacks then
    local ok, module = pcall(require, "snacks")
    snacks = ok and module or nil
  end
  local picker = snacks and snacks.picker
  if not picker then
    error("Snacks picker is unavailable")
  end
  local items = {}
  for _, project in ipairs(projects) do
    items[#items + 1] = {
      text = (project.display or project.root),
      file = project.root,
      dir = true,
      project = project,
    }
  end
  local defaults = {
    source = "super-project",
    title = options.prompt,
    items = items,
    format = "filename",
    confirm = function(_, item)
      if item then
        options.on_select(item.project)
      end
    end,
    actions = {
      forget_project = function(instance, item)
        if item and options.on_forget(item.project) then
          for index, candidate in ipairs(items) do
            if candidate.project.root == item.project.root then
              table.remove(items, index)
              break
            end
          end
          instance:find()
        end
      end,
    },
    win = { input = { keys = {} }, list = { keys = {} } },
  }
  for mode, key in pairs(config.options.selector.forget_bindings or {}) do
    local snacks_mode = mode == "insert" and "i" or mode == "normal" and "n" or mode
    defaults.win.input.keys[key] = { "forget_project", mode = { snacks_mode } }
    defaults.win.list.keys[key] = { "forget_project", mode = { snacks_mode } }
  end
  picker.pick(vim.tbl_deep_extend("force", defaults, config.options.selector.backend_options or {}))
end

return M
