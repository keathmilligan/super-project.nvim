local h = require("tests.helpers")
local root = h.tempdir("super-tree")
local repo = vim.fn.getcwd()
local super_tree_root = vim.env.SUPER_TREE_ROOT or (repo .. "/../super-tree.nvim")
if vim.fn.isdirectory(super_tree_root) ~= 1 then
  print("super_tree_integration: skipped (set SUPER_TREE_ROOT to run)")
  return
end
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a .. "/src", "p")
vim.fn.mkdir(project_b .. "/lib", "p")
h.write(project_a .. "/src/a.lua", "return 'a'")
h.write(project_b .. "/lib/b.lua", "return 'b'")

vim.opt.runtimepath:prepend(super_tree_root)
local super_tree = require("super-tree")
super_tree.setup({
  mode = "sidebar",
  buffers = { enable = false },
  projects = { enable = true, height = 6 },
  git = { enable = false },
  diagnostics = { enable = false },
  fade = { enable = false },
})

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = false, super_tree = true, barbar = false },
})

h.truthy(project.open(project_a))
super_tree.open()
local tree = require("super-tree.tree")
tree.expanded_paths[project_a .. "/src"] = true
tree.show_hidden = true

local projects_module = require("super-tree.projects")
local listed = projects_module.collect()
local target
for _, item in ipairs(listed) do
  if item.root == vim.fn.resolve(project_b) then
    target = item
  end
end
h.truthy(target and projects_module.open(target), "Super Tree switches through the native provider")
h.truthy(super_tree.is_open(), "an open Super Tree is seeded into a new workspace")
h.equal(vim.fn.getcwd(), project_b, "Super Tree restores against the target root")
h.equal(projects_module.provider_name(), "super-project", "native provider is registered")
listed = projects_module.collect()
h.equal(#listed, 2, "Super Tree Projects pane receives Super Project entries")
local stored_state =
  require("super-project.session").load_metadata(vim.fn.resolve(project_a)).integrations.super_tree
h.equal(stored_state.expanded_paths[1], "src", "Super Tree sidecar stores project-relative paths")
tree.expanded_paths[project_b .. "/lib"] = true
tree.show_hidden = false

local child = root .. "/super-tree-child.lua"
h.write(child, {
  string.format("vim.opt.runtimepath:prepend(%q)", repo),
  string.format("vim.opt.runtimepath:prepend(%q)", super_tree_root),
  "local tree_plugin = require('super-tree')",
  "tree_plugin.setup({ mode = 'sidebar', buffers = { enable = false }, projects = { enable = true }, git = { enable = false }, diagnostics = { enable = false }, fade = { enable = false } })",
  string.format(
    "local project = require('super-project').setup({ discovery = { roots = { %q, %q }, observe_git_cwd = false }, storage = { directory = %q }, startup = { defer_when_dashboard = true }, integrations = { neo_tree = false, super_tree = true, barbar = false } })",
    project_a,
    project_b,
    root .. "/data"
  ),
  string.format("assert(project.open(%q))", project_a),
  "assert(tree_plugin.is_open(), 'cold restore did not reopen Super Tree')",
  string.format(
    "assert(require('super-tree.tree').expanded_paths[%q], 'cold restore lost expansion state')",
    project_a .. "/src"
  ),
  "assert(require('super-tree.tree').show_hidden, 'cold restore lost hidden-entry state')",
})
local child_result = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", child) .. ")",
    "-c",
    "qa!",
  }, { text = true, cwd = repo })
  :wait(10000)
h.equal(child_result.code, 0, "Super Tree cold state restores: " .. (child_result.stderr or ""))

h.truthy(project.open(project_a))
h.truthy(super_tree.is_open(), "Super Tree reopens with the workspace")
h.truthy(tree.expanded_paths[project_a .. "/src"], "expanded paths are restored per project")
h.truthy(
  not tree.expanded_paths[project_b .. "/lib"],
  "target expansion does not leak across projects"
)
h.truthy(tree.show_hidden, "hidden-entry state is restored")
h.equal(vim.fn.getcwd(), project_a, "saved Super Tree root is restored")

super_tree.close()
project._reset_for_tests()
h.cleanup(root)
print("super_tree_integration: ok")
