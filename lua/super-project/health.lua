local config = require("super-project.config")
local git = require("super-project.git")
local selector = require("super-project.selector")

local M = {}

function M.check()
  vim.health.start("super-project.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10 or newer")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end
  if git.available() then
    vim.health.ok("Git executable found")
  elseif config.options.discovery.observe_git_cwd or config.options.sessions.scope == "branch" then
    vim.health.warn("Git is unavailable; Git discovery and branch sessions cannot run")
  else
    vim.health.info("Git is not configured for required features")
  end
  if selector.available(config.options.selector.backend) then
    vim.health.ok("Selector backend available: " .. config.options.selector.backend)
  else
    vim.health.warn("Selector backend unavailable; builtin fallback will be used")
  end
  vim.health.info("Storage: " .. config.options.storage.directory)
end

return M
