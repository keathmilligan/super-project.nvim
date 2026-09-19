local h = require("tests.helpers")
local root = h.tempdir("terminal-screen")
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  sessions = { filetype_delay_ms = 0 },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})

-- An idle alternate-screen application with content right up to its edges.
-- Resizes during synchronous layout construction may be coalesced into one
-- SIGWINCH with unchanged dimensions, so an app need not repaint afterwards.
local function start_screen(win)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
  local buffer = vim.api.nvim_get_current_buf()
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  local rows = {}
  local output = { "\27[?1049h\27[2J" }
  for row = 1, height do
    rows[row] = string.rep(string.char(64 + (row - 1) % 26 + 1), width)
    output[#output + 1] = string.format("\27[%d;1H%s", row, rows[row])
  end
  output[#output + 1] = "\27[3;4H"
  local job = h.termstart({
    "sh",
    "-c",
    "printf '%s' " .. vim.fn.shellescape(table.concat(output)) .. "; sleep 30",
  })
  h.truthy(job > 0)
  h.truthy(
    vim.wait(2000, function()
      return vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == rows[1]
    end, 10),
    "alternate screen is drawn"
  )
  vim.api.nvim_win_set_cursor(win, { 3, 3 })
  return { buffer = buffer, width = width, height = height, rows = rows, job = job }
end

local function assert_screen(screen)
  local count = vim.api.nvim_buf_line_count(screen.buffer)
  h.equal(
    vim.api.nvim_buf_get_lines(screen.buffer, count - screen.height, -1, false),
    screen.rows,
    "entire TUI screen survives switching"
  )
end

local function round_trip(screens)
  for _ = 1, 3 do
    h.truthy(project.open(project_b))
    vim.wait(100)
    for _, screen in ipairs(screens) do
      assert_screen(screen)
    end
    h.truthy(project.open(project_a))
    vim.wait(100)
    for _, screen in ipairs(screens) do
      local win = vim.fn.win_findbuf(screen.buffer)[1]
      h.truthy(win, "terminal window is restored")
      h.equal(vim.api.nvim_win_get_width(win), screen.width, "terminal width is restored")
      h.equal(vim.api.nvim_win_get_height(win), screen.height, "terminal height is restored")
      assert_screen(screen)
      h.equal(vim.b[screen.buffer].terminal_job_id, screen.job, "terminal job is retained")
      h.equal(vim.fn.jobwait({ screen.job }, 0)[1], -1, "terminal process is still running")
      local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
      h.equal(view.topline, 1, "TUI screen is fully visible")
      h.equal(vim.wo[win].winfixwidth, false, "temporary width lock is removed")
      h.equal(vim.wo[win].winfixheight, false, "temporary height lock is removed")
    end
  end
end

h.truthy(project.open(project_a))
vim.cmd("rightbelow vsplit")
vim.api.nvim_win_set_width(0, 55)
local screen = start_screen(vim.api.nvim_get_current_win())
round_trip({ screen })
pcall(vim.fn.jobstop, screen.job)
vim.api.nvim_buf_delete(screen.buffer, { force = true })

-- Nested uneven splits and terminals in both active and inactive tabs.
vim.cmd("rightbelow split")
vim.api.nvim_win_set_height(0, 7)
local bottom = vim.api.nvim_get_current_win()
vim.cmd("wincmd k")
local top = vim.api.nvim_get_current_win()
vim.cmd("tabnew")
local other_tab = vim.api.nvim_get_current_win()
local screens = { start_screen(top), start_screen(bottom), start_screen(other_tab) }
round_trip(screens)
for _, item in ipairs(screens) do
  pcall(vim.fn.jobstop, item.job)
end
require("super-project")._reset_for_tests()
h.cleanup(root)
print("workspace_terminal_screen: ok")
