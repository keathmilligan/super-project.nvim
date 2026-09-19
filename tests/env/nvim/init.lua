-- Isolated config for the containerized test environment.
-- Host plugins, packpath, and ~/.config/nvim are not used.

vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.number = true
vim.opt.signcolumn = "yes"
vim.opt.hidden = true
vim.opt.swapfile = false
vim.opt.shortmess:append("I")
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local plugin = vim.env.SUPER_PROJECT_ROOT or "/plugin"

vim.opt.runtimepath:prepend(plugin)
vim.cmd("runtime plugin/super-project.lua")

require("super-project").setup({
  discovery = {
    roots = { "/workspace/*" },
    excludes = { "/workspace/archive" },
    observe_git_cwd = true,
  },
  startup = {
    fallback = "last",
  },
  integrations = {
    neo_tree = false,
    super_tree = false,
    barbar = false,
  },
  selector = {
    backend = "builtin",
  },
  logging = {
    level = "debug",
  },
})

local function map(lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { desc = desc })
end
map("<leader>pf", "<Cmd>SuperProjectFind<CR>", "Find project")
map("<leader>pr", "<Cmd>SuperProjectRecent<CR>", "Recent projects")
map("<leader>pp", "<Cmd>SuperProjectPrevious<CR>", "Previous project")
map("<leader>po", "<Cmd>SuperProjectOpen<CR>", "Open / browse directory")
map("<leader>px", "<Cmd>SuperProjectForget<CR>", "Forget project")

if vim.fn.argc() == 0 and vim.fn.filereadable("README.md") == 1 then
  vim.cmd("edit README.md")
end
