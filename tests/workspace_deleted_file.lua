local h = require("tests.helpers")
local root = h.tempdir("deleted-file")
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
h.write(project_a .. "/gone-one.txt", "gone one")
h.write(project_a .. "/gone-two.txt", "gone two")
h.write(project_b .. "/stay.txt", "stay")

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  sessions = { filetype_delay_ms = 0 },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})

local function show_file(filename)
  local buffer = vim.fn.bufadd(filename)
  vim.fn.bufload(buffer)
  vim.bo[buffer].buflisted = true
  vim.api.nvim_win_set_buf(0, buffer)
  return buffer
end

h.truthy(project.open(project_a))
local gone_one = show_file(project_a .. "/gone-one.txt")
vim.cmd("rightbelow vsplit")
local gone_two = show_file(project_a .. "/gone-two.txt")

h.truthy(project.open(project_b))
show_file(project_b .. "/stay.txt")

-- Files removed while project A was parked; its buffers remain loaded.
vim.fn.delete(project_a .. "/gone-one.txt")
vim.fn.delete(project_a .. "/gone-two.txt")

-- Two deleted buffers guarantee Neovim's hard-error path: the first missing
-- file only produces a message, later ones raise E211 from nvim_win_set_buf.
h.truthy(project.open(project_a), "restore tolerates buffers whose files were deleted")

local shown = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  shown[vim.api.nvim_win_get_buf(win)] = true
end
h.truthy(shown[gone_one] and shown[gone_two], "windows keep the deleted-file buffers")
h.equal(
  vim.api.nvim_buf_get_lines(gone_one, 0, 1, false)[1],
  "gone one",
  "deleted-file buffer contents are intact"
)
h.equal(
  vim.api.nvim_buf_get_lines(gone_two, 0, 1, false)[1],
  "gone two",
  "second deleted-file buffer contents are intact"
)

h.cleanup(root)
