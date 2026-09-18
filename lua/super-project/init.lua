local commands = require("super-project.commands")
local config = require("super-project.config")
local directory = require("super-project.directory")
local discovery = require("super-project.discovery")
local git = require("super-project.git")
local integrations = require("super-project.integrations")
local log = require("super-project.log")
local path = require("super-project.path")
local registry = require("super-project.registry")
local selector = require("super-project.selector")
local session = require("super-project.session")
local switch = require("super-project.switch")

local M = {}

local initialized = false
local startup_generation = 0

local function confirm_forget(project)
  local choice = vim.fn.confirm(
    string.format("Forget project '%s'?", project.display or project.root),
    "&Yes\n&No",
    2
  )
  return choice == 1
end

local function selector_options(prompt, forget_only)
  return {
    prompt = prompt,
    on_select = function(project)
      if forget_only then
        M.forget(project.root, true)
      else
        local ok, err = M.open(project.root)
        if not ok then
          log.notify("error", tostring(err))
        end
      end
    end,
    on_forget = function(project)
      return M.forget(project.root, true)
    end,
  }
end

function M.projects(options)
  options = options or {}
  local current = switch.current()
  local projects = registry.list({ order = options.order or "source" })
  for _, project in ipairs(projects) do
    project.name = vim.fn.fnamemodify(project.root, ":t")
    project.active = current ~= nil and current.root == project.root
  end
  return projects
end

function M.current()
  return switch.current()
end

function M.open(root)
  return switch.open(root, { register = true })
end

function M.browse(start_directory)
  return directory.browse(start_directory, function(root)
    local ok, err = M.open(root)
    if not ok and err then
      log.notify("error", tostring(err))
    end
  end)
end

function M.previous(count)
  return switch.previous(count)
end

function M.find(order, options)
  order = order or "source"
  if not vim.tbl_contains({ "source", "recent", "name", "path" }, order) then
    order = "source"
  end
  local picker_options = selector_options("Find Projects", false)
  picker_options.picker_options = options
  selector.open(M.projects({ order = order }), picker_options)
end

function M.recent(options)
  options = options or {}
  selector.open(
    M.projects({ order = "recent" }),
    selector_options(
      options.forget_only and "Forget Project" or "Recent Projects",
      options.forget_only
    )
  )
end

function M.forget(root, confirm)
  local project = registry.find(root)
    or { root = path.canonical(root), display = path.display(root) }
  if not project.root then
    return false, "invalid project path"
  end
  if confirm and not confirm_forget(project) then
    return false, nil
  end
  local sessions_ok, sessions_err = session.delete_project(project.root)
  if not sessions_ok then
    return false, sessions_err
  end
  return registry.forget(project.root)
end

local function startup(generation)
  if generation ~= startup_generation or switch.current() then
    return
  end
  if
    vim.fn.argc() > 0
    or vim.g.super_project_started_with_stdin
    or config.options.startup.defer_when_dashboard
  then
    return
  end

  local cwd = path.canonical(vim.fn.getcwd())
  local project
  if config.options.discovery.observe_git_cwd and git.available() then
    local root = git.root(cwd)
    if root and not path.is_excluded(root) then
      project = registry.register(root, "git")
    end
  end
  project = project or registry.closest(cwd)
  if project then
    local ok, err = switch.open(project.root)
    if not ok then
      log.notify("error", "Could not open startup project: " .. tostring(err))
    end
    return
  end

  if config.options.startup.fallback == "last" then
    local last = registry.last()
    if last and registry.find(last.root) then
      local ok, err = switch.open(last.root)
      if not ok then
        log.notify("warn", "Could not restore last project: " .. tostring(err))
      end
    end
  end
end

function M.setup(options)
  if vim.fn.has("nvim-0.10") ~= 1 then
    error("super-project.nvim requires Neovim 0.10 or newer")
  end
  config.setup(options)
  if config.options.sessions.scope == "branch" and not git.available() then
    error("super-project: sessions.scope='branch' requires Git")
  end
  log.reset()
  if config.options.discovery.observe_git_cwd and not git.available() then
    log.notify(
      "warn",
      "Git is unavailable; observed-CWD project discovery is disabled",
      "missing-git"
    )
  end

  startup_generation = startup_generation + 1
  discovery.teardown()
  integrations.teardown()
  commands.teardown()
  registry.setup()
  switch.setup()
  integrations.setup(M)
  discovery.setup(switch.is_switching)
  commands.setup(M)
  initialized = true

  local generation = startup_generation
  if vim.v.vim_did_enter == 1 then
    vim.schedule(function()
      startup(generation)
    end)
  else
    local group = vim.api.nvim_create_augroup("SuperProjectStartup", { clear = true })
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      nested = true,
      callback = function()
        startup(generation)
      end,
    })
  end
  return M
end

function M.is_initialized()
  return initialized
end

function M._reset_for_tests()
  startup_generation = startup_generation + 1
  discovery.teardown()
  integrations.teardown()
  commands.teardown()
  switch.reset_for_tests()
  registry.teardown()
  initialized = false
end

return M
