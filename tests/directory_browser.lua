local h = require("tests.helpers")
local root = h.tempdir("directory-browser")
local configured = root .. "/configured"
local explicit = root .. "/explicit"
local browser_root = root .. "/browser"
local browser_target = browser_root .. "/target"
vim.fn.mkdir(configured, "p")
vim.fn.mkdir(explicit, "p")
vim.fn.mkdir(browser_target, "p")
vim.fn.mkdir(browser_root .. "/other", "p")

local project = require("super-project").setup({
  discovery = { roots = { configured }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})

h.truthy(project.open(explicit), "public open registers an arbitrary directory")
h.equal(project.current().root, vim.fn.resolve(explicit), "explicit directory becomes active")
local explicit_record = require("super-project.registry").find(explicit)
h.truthy(explicit_record, "explicit directory persists in history")
h.equal(explicit_record.source, "manual", "explicit directory records its manual source")

local original_select = vim.ui.select
local selections = 0
vim.api.nvim_set_current_dir(browser_root)
vim.ui.select = function(items, options, callback)
  selections = selections + 1
  h.truthy(
    options.prompt:find("Open Directory as Project", 1, true),
    "browser has a directory prompt"
  )
  if selections == 1 then
    for _, item in ipairs(items) do
      if item.path == browser_target then
        callback(item)
        return
      end
    end
    h.fail("target directory is absent from browser")
  else
    h.equal(items[1].action, "open", "browser can open its current directory")
    callback(items[1])
  end
end

vim.cmd("SuperProjectOpen")
h.truthy(
  vim.wait(2000, function()
    return project.current() and project.current().root == vim.fn.resolve(browser_target)
  end, 10),
  "no-argument command browses and opens a directory"
)
h.equal(selections, 2, "selecting a child navigates before opening")
h.truthy(require("super-project.registry").find(browser_target), "browsed directory is registered")
vim.ui.select = original_select

local another = root .. "/command-argument"
vim.fn.mkdir(another, "p")
vim.cmd("SuperProjectOpen " .. vim.fn.fnameescape(another))
h.equal(project.current().root, vim.fn.resolve(another), "command argument opens any directory")

project._reset_for_tests()
h.cleanup(root)
print("directory_browser: ok")
