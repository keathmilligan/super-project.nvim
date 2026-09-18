local h = require("tests.helpers")
local root = h.tempdir("cold")
local repo = vim.fn.getcwd()
local project_a = root .. "/a"
local project_b = root .. "/b"
local data = root .. "/data"
local sentinel = root .. "/terminal-starts"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
h.write(project_a .. "/saved.txt", "saved buffer")
h.write(project_a .. "/ignored.txt", "ignored buffer")

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = data },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})
h.truthy(project.open(project_a))
vim.cmd("edit " .. vim.fn.fnameescape(project_a .. "/saved.txt"))
vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(project_a .. "/ignored.txt"))
vim.bo.filetype = "gitcommit"
vim.cmd("rightbelow split")
vim.cmd("enew")
local job = h.termstart({ "sh", "-c", "echo first >> " .. sentinel .. "; sleep 3" })
h.truthy(job > 0)
h.equal(vim.bo.buftype, "terminal", "first buffer is a terminal")
vim.cmd("rightbelow split")
vim.cmd("enew")
local second_job = h.termstart({ "sh", "-c", "echo second >> " .. sentinel .. "; sleep 3" })
h.truthy(second_job > 0)
h.equal(vim.bo.buftype, "terminal", "second buffer is a terminal")
h.truthy(vim.wait(1000, function()
  return vim.fn.filereadable(sentinel) == 1 and #vim.fn.readfile(sentinel) == 2
end, 10))
local sessionoptions = vim.o.sessionoptions
h.truthy(project.open(project_b))
h.equal(vim.o.sessionoptions, sessionoptions, "sessionoptions is restored after saving")

local session = require("super-project.session")
h.truthy(session.exists(vim.fn.resolve(project_a)))
h.truthy(
  not session.contains_terminal_entry(vim.fn.resolve(project_a)),
  "cold session omits terminal commands"
)
local session_text =
  table.concat(vim.fn.readfile(session.paths(vim.fn.resolve(project_a)).session), "\n")
h.truthy(
  not session_text:find("ignored.txt", 1, true),
  "excluded filetypes are omitted from cold sessions"
)
h.truthy(not session_text:find("echo first", 1, true), "native session omits terminal commands")
h.truthy(not session_text:find("sleep 3", 1, true), "native session omits terminal arguments")
local metadata = session.load_metadata(vim.fn.resolve(project_a))
h.equal(#metadata.terminals, 2, "cold sidecar records both terminal leaves")
local sidecar_text =
  table.concat(vim.fn.readfile(session.paths(vim.fn.resolve(project_a)).sidecar), "\n")
h.truthy(not sidecar_text:find("echo first", 1, true), "sidecar omits terminal commands")
h.truthy(not sidecar_text:find("sleep 3", 1, true), "sidecar omits terminal arguments")
h.equal(#vim.fn.readfile(sentinel), 2)

local child = root .. "/cold-child.lua"
h.write(child, {
  string.format("vim.opt.runtimepath:prepend(%q)", repo),
  string.format(
    "local project = require('super-project').setup({ discovery = { roots = { %q, %q }, observe_git_cwd = false }, storage = { directory = %q }, startup = { defer_when_dashboard = true }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    project_a,
    project_b,
    data
  ),
  string.format("assert(project.open(%q))", project_a),
  string.format("assert(#vim.fn.readfile(%q) == 2, 'terminal command restarted')", sentinel),
  "local found = false",
  string.format(
    "for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == %q then found = true end end",
    project_a .. "/saved.txt"
  ),
  "assert(found, 'saved file buffer was not restored')",
  "local terminals = {}",
  "for _, win in ipairs(vim.api.nvim_list_wins()) do local b = vim.api.nvim_win_get_buf(win); if vim.bo[b].buftype == 'terminal' then terminals[b] = true end end",
  "local count = 0",
  "for b in pairs(terminals) do count = count + 1; local job = vim.b[b].terminal_job_id; assert(vim.fn.jobwait({ job }, 0)[1] == -1, 'fresh terminal is not running') end",
  "assert(count == 2, 'cold load did not restore terminal leaves')",
})
local result = vim
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
h.equal(result.code, 0, "fresh Neovim loads cold session: " .. (result.stderr or ""))
h.equal(#vim.fn.readfile(sentinel), 2, "fresh cold load does not restart prior commands")

local cleanup_key = vim.fn.resolve(project_b) .. "-cleanup-regression"
local cleanup_path = session.paths(cleanup_key).session
h.write(cleanup_path, {
  "let s:wipebuf = 999999",
  "silent exe 'bwipe ' . s:wipebuf",
  "unlet! s:wipebuf",
})
local cleanup_ok, cleanup_err = session.load(cleanup_key)
h.truthy(cleanup_ok, "stale scratch cleanup is harmless: " .. tostring(cleanup_err))
local cleanup_text = table.concat(vim.fn.readfile(cleanup_path), "\n")
h.truthy(
  cleanup_text:find("silent! exe 'bwipe '", 1, true),
  "existing sessions are hardened on load"
)

pcall(vim.fn.jobstop, job)
pcall(vim.fn.jobstop, second_job)
project._reset_for_tests()
h.cleanup(root)
print("session_cold: ok")
