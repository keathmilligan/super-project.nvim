local h = require("tests.helpers")
local root = h.tempdir("startup")
local repo = root .. "/repo"
local worktree = root .. "/linked-worktree"
h.git_repo(repo)
h.run({ "git", "worktree", "add", "-qb", "linked-test", worktree }, repo)
vim.fn.mkdir(worktree .. "/nested", "p")
local git = require("super-project.git")
h.equal(
  git.root(worktree .. "/nested"),
  vim.fn.resolve(worktree),
  "linked worktree has an independent root"
)
h.truthy(git.branch(worktree) == "linked-test", "worktree branch is detected")

local script = root .. "/startup-child.lua"
local plugin_root = vim.fn.getcwd()
h.write(script, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format("vim.api.nvim_set_current_dir(%q)", worktree .. "/nested"),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = {}, observe_git_cwd = true }, storage = { directory = %q }, startup = { fallback = 'empty' }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    root .. "/data"
  ),
  string.format(
    "assert(vim.wait(3000, function() return p.current() and p.current().root == %q end, 20), 'startup Git root was not activated')",
    vim.fn.resolve(worktree)
  ),
})
local child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", script) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(child.code, 0, "startup activates observed worktree: " .. (child.stderr or ""))

local fallback_script = root .. "/fallback-child.lua"
h.write(fallback_script, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format("vim.api.nvim_set_current_dir(%q)", root),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = {}, observe_git_cwd = false }, storage = { directory = %q }, startup = { fallback = 'last' }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    root .. "/data"
  ),
  string.format(
    "assert(vim.wait(3000, function() return p.current() and p.current().root == %q end, 20), 'last project was not restored')",
    vim.fn.resolve(worktree)
  ),
})
local fallback_child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", fallback_script) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(
  fallback_child.code,
  0,
  "startup restores the last project: " .. (fallback_child.stderr or "")
)

local dashboard_script = root .. "/dashboard-child.lua"
h.write(dashboard_script, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format("vim.api.nvim_set_current_dir(%q)", worktree .. "/nested"),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = {}, observe_git_cwd = true }, storage = { directory = %q }, startup = { defer_when_dashboard = true }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    root .. "/data"
  ),
  string.format(
    "assert(vim.wait(3000, function() return p.current() and p.current().root == %q end, 20), 'cwd project was not opened in dashboard mode')",
    vim.fn.resolve(worktree)
  ),
})
local dashboard_child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", dashboard_script) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(
  dashboard_child.code,
  0,
  "dashboard mode still opens the cwd project: " .. (dashboard_child.stderr or "")
)

local dashboard_fallback_script = root .. "/dashboard-fallback-child.lua"
h.write(dashboard_fallback_script, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format("vim.api.nvim_set_current_dir(%q)", root),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = {}, observe_git_cwd = false }, storage = { directory = %q }, startup = { fallback = 'last', defer_when_dashboard = true }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    root .. "/data"
  ),
  "vim.wait(500, function() return p.current() ~= nil end, 20)",
  "assert(p.current() == nil, 'last project was restored in dashboard mode')",
})
local dashboard_fallback_child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", dashboard_fallback_script) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(
  dashboard_fallback_child.code,
  0,
  "dashboard mode skips the last-project fallback: " .. (dashboard_fallback_child.stderr or "")
)

local disabled_script = root .. "/disabled-child.lua"
h.write(disabled_script, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format("vim.api.nvim_set_current_dir(%q)", worktree .. "/nested"),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = {}, observe_git_cwd = true }, storage = { directory = %q }, startup = { open_cwd_project = false, fallback = 'last' }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    root .. "/data"
  ),
  "vim.wait(500, function() return p.current() ~= nil end, 20)",
  "assert(p.current() == nil, 'cwd project was opened despite open_cwd_project = false')",
})
local disabled_child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", disabled_script) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(
  disabled_child.code,
  0,
  "startup skips the cwd project when disabled: " .. (disabled_child.stderr or "")
)

h.cleanup(root)
print("startup_worktree: ok")
