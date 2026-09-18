local h = require("tests.helpers")
local root = h.tempdir("terminal")
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
h.write(project_a .. "/a.txt", "alpha")
h.write(project_b .. "/b.txt", "beta")

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})

h.truthy(project.open(project_a))
vim.cmd("edit " .. vim.fn.fnameescape(project_a .. "/a.txt"))
vim.cmd("rightbelow vsplit")
vim.cmd("enew")
local terminal_buffer = vim.api.nvim_get_current_buf()
local marker = root .. "/heartbeat"
local job = h.termstart({
  "sh",
  "-c",
  "i=0; while [ $i -lt 30 ]; do i=$((i+1)); echo $i >> " .. marker .. "; sleep 0.05; done; sleep 2",
})
h.truthy(job > 0, "terminal job starts")
h.equal(vim.bo[terminal_buffer].buftype, "terminal", "buffer is a terminal")
local terminal_job = vim.b[terminal_buffer].terminal_job_id
local terminal_pid = vim.fn.jobpid(job)

h.truthy(project.open(project_b))
h.truthy(vim.api.nvim_buf_is_valid(terminal_buffer), "terminal buffer remains valid while parked")
h.equal(vim.fn.jobwait({ job }, 0)[1], -1, "terminal job remains active while parked")
h.equal(vim.fn.getcwd(), project_b, "target project becomes cwd")
vim.wait(250)
local before_return = #vim.fn.readfile(marker)
h.truthy(before_return > 1, "terminal continues producing background output")

h.truthy(project.open(project_a))
h.equal(
  vim.b[terminal_buffer].terminal_job_id,
  terminal_job,
  "terminal channel identity is unchanged"
)
h.equal(vim.fn.jobpid(job), terminal_pid, "terminal process identity is unchanged")
h.equal(vim.fn.jobwait({ job }, 0)[1], -1, "terminal process is still running after restore")
local visible = false
for _, win in ipairs(vim.fn.win_findbuf(terminal_buffer)) do
  visible = visible or vim.api.nvim_win_is_valid(win)
end
h.truthy(visible, "terminal buffer returns to a window")
h.truthy(#vim.fn.readfile(marker) >= before_return, "terminal output is retained")

h.truthy(project.open(project_b))
h.equal(vim.fn.jobwait({ job }, 6000)[1], 0, "terminal may finish while its project is parked")
h.truthy(project.open(project_a))
local replacement_buffer
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buffer = vim.api.nvim_win_get_buf(win)
  if vim.bo[buffer].buftype == "terminal" then
    replacement_buffer = buffer
  end
end
h.truthy(replacement_buffer, "completed terminal leaf is reopened")
h.truthy(
  replacement_buffer ~= terminal_buffer,
  "completed process is not presented as still running"
)
local replacement_job = vim.b[replacement_buffer].terminal_job_id
h.truthy(replacement_job ~= terminal_job, "reopened terminal has a fresh default shell")
h.equal(vim.fn.jobwait({ replacement_job }, 0)[1], -1, "fresh terminal process is running")
h.equal(#vim.fn.win_findbuf(terminal_buffer), 0, "completed terminal buffer is no longer displayed")

pcall(vim.fn.jobstop, job)
pcall(vim.fn.jobstop, replacement_job)
require("super-project")._reset_for_tests()
h.cleanup(root)
print("workspace_terminal: ok")
