local h = require("tests.helpers")
local root = h.tempdir("buffer-isolation")
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
for _, filename in ipairs({ "a/one.txt", "a/two.txt", "a/hidden.txt", "b/one.txt", "b/two.txt" }) do
  h.write(root .. "/" .. filename, filename)
end

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

local function listed(buffer)
  return vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buflisted
end

local function listed_empty_buffers()
  local result = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buffer)
      and vim.bo[buffer].buflisted
      and vim.bo[buffer].buftype == ""
      and vim.api.nvim_buf_get_name(buffer) == ""
    then
      result[#result + 1] = buffer
    end
  end
  return result
end

h.truthy(project.open(project_a))
local a_one = show_file(project_a .. "/one.txt")
local a_hidden = vim.fn.bufadd(project_a .. "/hidden.txt")
vim.fn.bufload(a_hidden)
vim.bo[a_hidden].buflisted = true
vim.cmd("rightbelow vsplit")
local a_two = show_file(project_a .. "/two.txt")
vim.cmd("tab split")

h.truthy(project.open(project_b))
for _, buffer in ipairs({ a_one, a_two, a_hidden }) do
  h.truthy(vim.api.nvim_buf_is_valid(buffer), "parked project buffers remain loaded")
  h.truthy(not listed(buffer), "parked project buffers are absent from bufferline sources")
end

local b_one = show_file(project_b .. "/one.txt")
vim.cmd("tab split")
local b_two = show_file(project_b .. "/two.txt")

for _ = 1, 4 do
  h.truthy(project.open(project_a))
  h.truthy(listed(a_one), "first active project buffer is relisted")
  h.truthy(listed(a_two), "second active project buffer is relisted")
  h.truthy(listed(a_hidden), "hidden active project buffer is relisted")
  h.truthy(not listed(b_one) and not listed(b_two), "inactive project buffers stay unlisted")
  h.equal(#listed_empty_buffers(), 0, "hot restore does not leak listed [No Name] buffers")

  h.truthy(project.open(project_b))
  h.truthy(listed(b_one) and listed(b_two), "target project buffers are relisted")
  h.truthy(
    not listed(a_one) and not listed(a_two) and not listed(a_hidden),
    "source buffers are unlisted"
  )
  h.equal(#listed_empty_buffers(), 0, "repeated switching does not accumulate [No Name] buffers")
end

project._reset_for_tests()
h.cleanup(root)
print("workspace_buffer_isolation: ok")
