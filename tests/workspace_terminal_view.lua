local h = require("tests.helpers")
local root = h.tempdir("terminal-view")
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
vim.cmd("enew")
-- The second output phase runs while the project is parked.
local job = h.termstart({
  "sh",
  "-c",
  "i=0; while [ $i -lt 200 ]; do i=$((i+1)); echo phase-one-$i; sleep 0.01; done; "
    .. "sleep 1; "
    .. "while [ $i -lt 400 ]; do i=$((i+1)); echo phase-two-$i; sleep 0.01; done; "
    .. "sleep 30",
})
h.truthy(job > 0, "terminal job starts")
local terminal_buffer = vim.api.nvim_get_current_buf()
local terminal_window = vim.api.nvim_get_current_win()
h.equal(vim.bo[terminal_buffer].buftype, "terminal", "buffer is a terminal")

local function line_count(buffer)
  return vim.api.nvim_buf_line_count(buffer or terminal_buffer)
end

local function window_view(win)
  return vim.api.nvim_win_call(win, vim.fn.winsaveview)
end

h.truthy(
  vim.wait(5000, function()
    return line_count() >= 200
  end, 10),
  "first output phase arrives"
)

-- A terminal window that was following output must show the live screen when
-- the project returns, not the position captured before the switch.
vim.api.nvim_win_set_cursor(terminal_window, { line_count(), 0 })
local captured_lines = line_count()
h.truthy(project.open(project_b))
h.truthy(
  vim.wait(5000, function()
    return line_count() >= 400
  end, 10),
  "terminal output continues while parked"
)

-- The parked screen moved on and then shrank, making the captured position
-- invalid. Neovim cannot follow output for hidden buffers, so the restored
-- view must be recomputed instead of replayed.
vim.bo[terminal_buffer].scrollback = 100
h.truthy(
  vim.wait(2000, function()
    return line_count() < captured_lines
  end, 10),
  "scrollback trim shrinks the parked terminal buffer"
)
local parked_lines = line_count()

h.truthy(project.open(project_a))
local restored_window
for _, win in ipairs(vim.fn.win_findbuf(terminal_buffer)) do
  if vim.api.nvim_win_is_valid(win) then
    restored_window = win
  end
end
h.truthy(restored_window, "terminal buffer returns to a window")
h.truthy(captured_lines > parked_lines, "captured cursor is beyond the trimmed buffer")
local view = window_view(restored_window)
local height = vim.api.nvim_win_get_height(restored_window)
h.equal(view.lnum, parked_lines, "restored terminal cursor follows the live end")
h.equal(
  view.topline,
  math.max(1, parked_lines - height + 1),
  "restored terminal shows the live screen"
)

-- A window scrolled into scrollback keeps its position.
vim.api.nvim_win_call(restored_window, function()
  vim.fn.winrestview({ lnum = 5, topline = 5 })
end)
h.truthy(project.open(project_b))
h.truthy(project.open(project_a))
local scrolled_window
for _, win in ipairs(vim.fn.win_findbuf(terminal_buffer)) do
  if vim.api.nvim_win_is_valid(win) then
    scrolled_window = win
  end
end
h.truthy(scrolled_window, "scrolled terminal returns to a window")
local scrolled_view = window_view(scrolled_window)
h.equal(scrolled_view.lnum, 5, "scrolled terminal keeps its cursor line")
h.equal(scrolled_view.topline, 5, "scrolled terminal keeps its top line")

-- A terminal whose process exited while parked is reopened as a fresh shell;
-- the fresh terminal must follow its own live end, not the dead view.
h.truthy(project.open(project_b))
pcall(vim.fn.jobstop, job)
h.truthy(
  vim.wait(5000, function()
    return vim.fn.jobwait({ job }, 0)[1] ~= -1
  end, 10),
  "terminal process exits while parked"
)
h.truthy(project.open(project_a))
local replacement_buffer
local replacement_window
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buffer = vim.api.nvim_win_get_buf(win)
  if vim.bo[buffer].buftype == "terminal" and buffer ~= terminal_buffer then
    replacement_buffer = buffer
    replacement_window = win
  end
end
h.truthy(replacement_buffer, "completed terminal leaf is reopened")
-- Let the fresh shell print its prompt so the assertion is stable.
vim.wait(500)
local replacement_view = window_view(replacement_window)
local replacement_lines = line_count(replacement_buffer)
local replacement_height = vim.api.nvim_win_get_height(replacement_window)
h.equal(
  replacement_view.lnum,
  replacement_lines,
  "fresh terminal follows its own live end"
)
h.equal(
  replacement_view.topline,
  math.max(1, replacement_lines - replacement_height + 1),
  "fresh terminal shows its own live screen"
)

pcall(vim.fn.jobstop, vim.b[replacement_buffer].terminal_job_id)
require("super-project")._reset_for_tests()
h.cleanup(root)
print("workspace_terminal_view: ok")
