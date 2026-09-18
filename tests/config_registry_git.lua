local h = require("tests.helpers")
local root = h.tempdir("registry")
local configured = root .. "/configured"
local ignored = root .. "/ignored-project"
local git_project = root .. "/git-project"
vim.fn.mkdir(configured, "p")
vim.fn.mkdir(ignored, "p")
h.git_repo(git_project)
vim.fn.mkdir(git_project .. "/nested", "p")

local config = require("super-project.config")
local ok, err = pcall(config.setup, { projects = { configured } })
h.truthy(
  not ok and tostring(err):find("projects is not a recognized option", 1, true),
  "legacy config keys are rejected"
)
local invalid_ok, invalid_err = pcall(config.setup, { discovery = false })
h.truthy(
  not invalid_ok and tostring(invalid_err):find("discovery must be a table", 1, true),
  "invalid sections report validation errors"
)

local project = require("super-project").setup({
  discovery = {
    roots = { root .. "/*" },
    excludes = { root .. "/ignored*" },
    observe_git_cwd = true,
  },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})

local listed = project.projects({ order = "name" })
local roots = {}
for _, item in ipairs(listed) do
  roots[item.root] = true
end
h.truthy(roots[vim.fn.resolve(configured)], "configured project is discovered")
h.truthy(roots[vim.fn.resolve(git_project)], "configured Git directory is discovered")
h.truthy(not roots[vim.fn.resolve(ignored)], "excluded directory is filtered")

local symlink = root .. "/configured-link"
if (vim.uv or vim.loop).fs_symlink(configured, symlink) then
  require("super-project.config").options.discovery.roots = { symlink }
  require("super-project.config").options.discovery.symlinks = "preserve"
  local preserved = require("super-project.path").expand_roots()
  h.equal(preserved[1].root, vim.fn.resolve(configured), "symlink project keeps canonical identity")
  h.truthy(
    preserved[1].display:find("configured-link", 1, true),
    "preserve mode keeps symlink display spelling"
  )
  require("super-project.config").options.discovery.roots = { root .. "/*" }
end

local original_cwd = vim.fn.getcwd()
vim.api.nvim_set_current_dir(git_project .. "/nested")
require("super-project.discovery").observe(vim.fn.getcwd())
h.truthy(
  vim.wait(3000, function()
    for _, item in ipairs(require("super-project.registry").state().projects or {}) do
      if item.root == vim.fn.resolve(git_project) and item.source == "git" then
        return true
      end
    end
    return false
  end, 20),
  "CWD observation registers the Git worktree root"
)

local registry = require("super-project.registry")
h.truthy(registry.touch(configured, "recent"))
h.equal(
  project.projects({ order = "recent" })[1].root,
  vim.fn.resolve(configured),
  "recent ordering follows access"
)
h.truthy(project.forget(configured, false))
-- Configured roots remain discoverable after forgetting history.
h.truthy(registry.find(configured), "forget does not suppress an explicitly configured root")

vim.api.nvim_set_current_dir(original_cwd)
project._reset_for_tests()
h.cleanup(root)
print("config_registry_git: ok")
