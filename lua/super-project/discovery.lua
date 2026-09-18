local config = require("super-project.config")
local git = require("super-project.git")
local log = require("super-project.log")
local path = require("super-project.path")
local registry = require("super-project.registry")

local M = {}

local augroup
local generation = 0
local debounce_timer
local is_switching = function()
  return false
end

function M.observe(directory)
  if not config.options.discovery.observe_git_cwd or not git.available() then
    return
  end
  local observed = path.canonical(directory)
  if not observed then
    return
  end
  generation = generation + 1
  local request = generation
  debounce_timer = debounce_timer or (vim.uv or vim.loop).new_timer()
  if not debounce_timer then
    return
  end
  debounce_timer:stop()
  debounce_timer:start(
    100,
    0,
    vim.schedule_wrap(function()
      git.root_async(observed, function(root, err)
        if request ~= generation then
          return
        end
        local current = path.canonical(vim.fn.getcwd())
        if current ~= observed then
          return
        end
        if root and not path.is_excluded(root) then
          local _, register_err = registry.register(root, "git")
          if register_err then
            log.warn("could not register Git project: " .. tostring(register_err), root)
          end
        elseif err then
          git.log_negative(err)
        end
      end)
    end)
  )
end

function M.setup(switching_callback)
  M.teardown()
  is_switching = switching_callback or is_switching
  augroup = vim.api.nvim_create_augroup("SuperProjectDiscovery", { clear = true })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,
    callback = function()
      if not is_switching() then
        M.observe(vim.fn.getcwd())
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    once = true,
    callback = M.teardown,
  })
end

function M.teardown()
  generation = generation + 1
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
  debounce_timer = nil
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = nil
end

return M
