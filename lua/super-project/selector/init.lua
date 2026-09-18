local config = require("super-project.config")
local log = require("super-project.log")

local M = {}

local modules = {
  builtin = "super-project.selector.builtin",
  telescope = "super-project.selector.telescope",
  ["fzf-lua"] = "super-project.selector.fzf_lua",
  snacks = "super-project.selector.snacks",
}

local requirements = {
  telescope = "telescope",
  ["fzf-lua"] = "fzf-lua",
  snacks = "snacks",
}

function M.available(backend)
  backend = backend or config.options.selector.backend
  if backend == "builtin" then
    return true
  end
  if backend == "snacks" and rawget(_G, "Snacks") then
    return true
  end
  return pcall(require, requirements[backend])
end

function M.open(projects, options)
  if #projects == 0 then
    log.notify("info", "No projects are available")
    return
  end
  local backend = config.options.selector.backend
  if not M.available(backend) then
    log.notify(
      "warn",
      string.format("Selector '%s' is unavailable; using vim.ui.select", backend),
      "missing-selector-" .. backend
    )
    backend = "builtin"
  end
  return require(modules[backend]).open(projects, options)
end

return M
