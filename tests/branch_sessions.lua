local h = require("tests.helpers")
local root = h.tempdir("branch")
local repo = root .. "/repo"
h.git_repo(repo)
local original_branch = vim.trim(h.run({ "git", "branch", "--show-current" }, repo))

local project = require("super-project").setup({
  discovery = { roots = { repo }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  sessions = { scope = "branch", filetype_delay_ms = 0 },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})
h.truthy(project.open(repo))
h.equal(project.current().branch, original_branch)
vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/README.md"))
local original_buffer = vim.api.nvim_get_current_buf()

h.run({ "git", "checkout", "-qb", "feature/project-state" }, repo)
h.truthy(
  vim.wait(5000, function()
    return project.current() and project.current().branch == "feature/project-state"
  end, 20),
  "HEAD watcher switches to a branch-scoped workspace"
)
h.truthy(vim.api.nvim_buf_is_valid(original_buffer), "prior branch buffers remain resident")

h.run({ "git", "checkout", "-q", original_branch }, repo)
h.truthy(
  vim.wait(5000, function()
    return project.current() and project.current().branch == original_branch
  end, 20),
  "returning branch restores its workspace"
)
h.truthy(#vim.fn.win_findbuf(original_buffer) > 0, "original branch buffer returns to a window")

project._reset_for_tests()
h.cleanup(root)
print("branch_sessions: ok")
