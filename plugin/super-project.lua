if vim.g.loaded_super_project then
  return
end
vim.g.loaded_super_project = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.schedule(function()
    vim.notify("super-project.nvim requires Neovim 0.10 or newer", vim.log.levels.ERROR)
  end)
end

local group = vim.api.nvim_create_augroup("SuperProjectBootstrap", { clear = true })
vim.api.nvim_create_autocmd("StdinReadPre", {
  group = group,
  callback = function()
    vim.g.super_project_started_with_stdin = true
  end,
})
