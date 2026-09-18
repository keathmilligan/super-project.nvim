local log = require("super-project.log")

local M = {}

local names = {
  "SuperProjectFind",
  "SuperProjectRecent",
  "SuperProjectOpen",
  "SuperProjectPrevious",
  "SuperProjectForget",
}

local function recreate(name, callback, options)
  if vim.fn.exists(":" .. name) == 2 then
    vim.api.nvim_del_user_command(name)
  end
  vim.api.nvim_create_user_command(name, callback, options)
end

local function report(ok, err)
  if not ok and err then
    log.notify("error", tostring(err))
  end
end

function M.setup(api)
  recreate("SuperProjectFind", function(args)
    api.find(args.args ~= "" and args.args or "source")
  end, {
    nargs = "?",
    complete = function()
      return { "source", "recent", "name", "path" }
    end,
  })

  recreate("SuperProjectRecent", function()
    api.recent()
  end, {})

  recreate("SuperProjectOpen", function(args)
    if args.args == "" then
      report(api.browse())
    else
      report(api.open(args.args))
    end
  end, {
    nargs = "?",
    complete = "dir",
  })

  recreate("SuperProjectPrevious", function(args)
    report(api.previous(args.args ~= "" and tonumber(args.args) or 1))
  end, { nargs = "?" })

  recreate("SuperProjectForget", function(args)
    if args.args == "" then
      api.recent({ forget_only = true })
    else
      report(api.forget(args.args, true))
    end
  end, {
    nargs = "?",
    complete = function()
      return vim.tbl_map(function(project)
        return project.root
      end, api.projects({ order = "recent" }))
    end,
  })
end

function M.teardown()
  for _, name in ipairs(names) do
    if vim.fn.exists(":" .. name) == 2 then
      pcall(vim.api.nvim_del_user_command, name)
    end
  end
end

return M
