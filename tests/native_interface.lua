local h = require("tests.helpers")
local root = h.tempdir("interface")
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  selector = { backend = "builtin" },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})
h.truthy(package.loaded["super-tree"] == nil, "optional integrations are not eagerly loaded")
for _, command in ipairs({ "Find", "Recent", "Open", "Previous", "Forget" }) do
  h.equal(vim.fn.exists(":SuperProject" .. command), 2, "native command exists")
end
h.equal(vim.fn.exists(":NeovimProjectDiscover"), 0, "legacy commands are not exposed")
local legacy = pcall(require, "neovim-project")
h.truthy(not legacy, "legacy setup module is not exposed")

local selected
local original_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  selected = items[1]
  callback(items[1])
end
project.find("name")
h.truthy(selected ~= nil, "builtin selector receives projects")
h.equal(project.current().root, selected.root, "builtin selection opens the project")
vim.ui.select = original_select

-- An unavailable external backend falls back to the builtin selector.
require("super-project.config").options.selector.backend = "telescope"
local fallback_selected
local original_notify = vim.notify
vim.notify = function() end
vim.ui.select = function(items, _, callback)
  fallback_selected = items[1]
  callback(nil)
end
project.recent()
vim.ui.select = original_select
vim.notify = original_notify
h.truthy(fallback_selected ~= nil, "missing external selector falls back to vim.ui.select")

local projects = project.projects({ order = "recent" })
h.truthy(
  type(projects[1].name) == "string" and projects[1].active,
  "public provider records identify current project"
)
h.equal(project.current().root, projects[1].root)

project._reset_for_tests()
h.cleanup(root)
print("native_interface: ok")
