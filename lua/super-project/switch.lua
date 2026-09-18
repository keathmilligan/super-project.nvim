local config = require("super-project.config")
local events = require("super-project.events")
local git = require("super-project.git")
local integrations = require("super-project.integrations")
local log = require("super-project.log")
local path = require("super-project.path")
local registry = require("super-project.registry")
local session = require("super-project.session")
local util = require("super-project.util")
local workspace = require("super-project.workspace")

local M = {}

local active
local workspaces = {}
local switching = false
local augroup
local head_watcher
local head_timer
local filetype_timer

local function context(project)
  return project
      and {
        root = project.root,
        display = project.display,
        branch = project.branch,
        key = project.key,
      }
    or nil
end

local function key_for(root, branch)
  if branch then
    return root .. "\0" .. branch
  end
  return root
end

local function describe(record)
  local branch
  if config.options.sessions.scope == "branch" then
    branch = git.branch(record.root)
    if not branch then
      return nil, "could not determine Git branch for " .. record.root
    end
  end
  return {
    root = record.root,
    display = record.display or path.display(record.root),
    branch = branch,
    key = key_for(record.root, branch),
  }
end

local function stop_branch_watcher()
  if head_timer and not head_timer:is_closing() then
    head_timer:stop()
    head_timer:close()
  end
  head_timer = nil
  if head_watcher and not head_watcher:is_closing() then
    head_watcher:stop()
    head_watcher:close()
  end
  head_watcher = nil
end

local function setup_branch_watcher()
  stop_branch_watcher()
  if not active or config.options.sessions.scope ~= "branch" then
    return
  end
  local head, err = git.head_path(active.root)
  if not head then
    log.warn("could not watch Git HEAD: " .. tostring(err), active.root)
    return
  end
  head_watcher = util.uv.new_fs_event()
  head_timer = util.uv.new_timer()
  if not head_watcher or not head_timer then
    stop_branch_watcher()
    return
  end
  local watched_root = active.root
  head_watcher:start(head, {}, function(watch_err)
    if watch_err then
      log.warn("Git HEAD watcher failed: " .. tostring(watch_err), watched_root)
      return
    end
    local timer = head_timer
    if not timer or timer:is_closing() then
      return
    end
    timer:stop()
    timer:start(
      350,
      0,
      vim.schedule_wrap(function()
        if active and active.root == watched_root and not switching then
          local branch = git.branch(watched_root)
          if branch and branch ~= active.branch then
            M.open(watched_root, { branch_change = true })
          end
        end
      end)
    )
  end)
end

local function delayed_filetype()
  local delay = config.options.sessions.filetype_delay_ms
  if delay <= 0 then
    return
  end
  if filetype_timer and not filetype_timer:is_closing() then
    filetype_timer:stop()
    filetype_timer:close()
  end
  filetype_timer = util.uv.new_timer()
  if not filetype_timer then
    return
  end
  filetype_timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      local timer = filetype_timer
      filetype_timer = nil
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      if vim.v.exiting == vim.NIL then
        pcall(vim.cmd, "silent doautocmd <nomodeline> FileType")
      end
    end)
  )
end

local function restore_previous(previous, snapshot, states, failed_root)
  pcall(workspace.park_current_best_effort, "__failed_target__", failed_root)
  local ok, err = workspace.restore(snapshot)
  if not ok then
    log.error("rollback layout failed: " .. tostring(err), previous and previous.key)
    return false
  end
  active = previous
  if active then
    pcall(vim.api.nvim_set_current_dir, active.root)
    workspace.activate(active.key, active.root)
    integrations.restore(states, context(active))
    setup_branch_watcher()
  end
  return true
end

local function fail_switch(message, previous, snapshot, states, parked, failed_root)
  if parked and previous and snapshot then
    restore_previous(previous, snapshot, states, failed_root)
  elseif previous and states then
    integrations.restore(states, context(previous))
  end
  switching = false
  events.emit("SuperProjectSwitchPost", {
    source = context(previous),
    target = nil,
    ok = false,
    error = tostring(message),
  })
  log.notify("error", "Project switch failed: " .. tostring(message))
  return false, message
end

function M.open(candidate, options)
  options = options or {}
  if switching then
    return false, "a project switch is already in progress"
  end

  local record = registry.find(candidate)
  local register_err
  local newly_registered = false
  if not record and options.register then
    record, register_err = registry.register(candidate, options.source or "manual")
    newly_registered = record ~= nil
  end
  if not record then
    return false, register_err or "project is not registered or is excluded"
  end
  local target, target_err = describe(record)
  if not target then
    return false, target_err
  end
  if active and active.key == target.key then
    vim.api.nvim_set_current_dir(target.root)
    registry.touch(target.root, "recent", target.display)
    registry.set_last(context(target))
    return true
  end

  switching = true
  local previous = active and vim.deepcopy(active) or nil
  local source_context = context(previous)
  local target_context = context(target)
  events.emit("SuperProjectSwitchPre", { source = source_context, target = target_context })

  local previous_snapshot
  local previous_states
  local parked = false
  if previous then
    events.emit("SuperProjectSavePre", { project = source_context })
    previous_states = integrations.capture_and_suspend(source_context)
    previous_snapshot, target_err = workspace.capture(previous.key, previous.root)
    if not previous_snapshot then
      return fail_switch(target_err, previous, nil, previous_states, false, target.root)
    end
    previous_snapshot.integrations = previous_states
    local saved, save_err = session.save(previous.key, { integrations = previous_states })
    events.emit("SuperProjectSavePost", {
      project = source_context,
      ok = saved,
      error = save_err,
    })
    if not saved then
      return fail_switch(save_err, previous, previous_snapshot, previous_states, false, target.root)
    end
    local parked_ok, park_err = workspace.park(previous_snapshot)
    if not parked_ok then
      return fail_switch(park_err, previous, previous_snapshot, previous_states, true, target.root)
    end
    parked = true
    workspaces[previous.key] = previous_snapshot
  end

  events.emit("SuperProjectLoadPre", { project = target_context })
  local target_states = {}
  local restored = true
  local restore_err
  pcall(vim.api.nvim_set_current_dir, target.root)

  if workspaces[target.key] then
    restored, restore_err = workspace.restore(workspaces[target.key])
    target_states = workspaces[target.key].integrations or {}
  elseif session.exists(target.key) then
    restored, restore_err = session.load(target.key)
    if restored then
      local metadata = session.load_metadata(target.key)
      target_states = metadata.integrations or {}
      workspace.claim_transition()
    end
  elseif previous then
    restored, restore_err = workspace.new_workspace(target.key)
  end

  if not restored then
    return fail_switch(
      restore_err,
      previous,
      previous_snapshot,
      previous_states,
      parked,
      target.root
    )
  end

  active = target
  pcall(vim.api.nvim_set_current_dir, target.root)
  workspace.activate(target.key, target.root, { mark_current_placeholder = previous == nil })
  target_states = integrations.seed(target_states, previous_states, target_context)
  integrations.restore(target_states, target_context)
  local touch_source = newly_registered and (options.source or "manual")
    or (options.source or "recent")
  local touched, touch_err = registry.touch(target.root, touch_source, target.display)
  if not touched then
    log.warn("could not update project recency: " .. tostring(touch_err), target.root)
  end
  registry.set_last(context(target))
  setup_branch_watcher()
  events.emit("SuperProjectLoadPost", { project = target_context })
  delayed_filetype()
  switching = false
  events.emit("SuperProjectSwitchPost", {
    source = source_context,
    target = target_context,
    ok = true,
  })
  return true
end

function M.current()
  return active and context(active) or nil
end

function M.is_switching()
  return switching
end

function M.workspaces()
  return workspaces
end

function M.previous(count)
  count = math.max(1, tonumber(count) or 1)
  local candidates = {}
  for _, project in ipairs(registry.list({ order = "recent" })) do
    if not active or project.root ~= active.root then
      candidates[#candidates + 1] = project
    end
  end
  local target = candidates[count] or candidates[#candidates]
  if not target then
    return false, "no previous project"
  end
  return M.open(target.root)
end

function M.save_active()
  if not active then
    return true
  end
  events.emit("SuperProjectSavePre", { project = context(active) })
  local states = integrations.capture_and_suspend(context(active))
  local ok, err = session.save(active.key, { integrations = states })
  events.emit("SuperProjectSavePost", { project = context(active), ok = ok, error = err })
  return ok, err
end

function M.setup()
  M.teardown(false)
  augroup = vim.api.nvim_create_augroup("SuperProjectRuntime", { clear = true })
  vim.api.nvim_create_autocmd("TermOpen", {
    group = augroup,
    callback = function(event)
      if active and config.options.terminals.keep_alive then
        workspace.claim_buffer(event.buf, active.key)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(event)
      if active and not switching then
        workspace.claim_buffer(event.buf, active.key)
        workspace.cleanup_placeholders(active.key)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TermClose", {
    group = augroup,
    callback = function(event)
      if vim.api.nvim_buf_is_valid(event.buf) then
        pcall(
          vim.api.nvim_buf_set_var,
          event.buf,
          "super_project_terminal_exited",
          vim.v.event.status
        )
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      M.save_active()
      stop_branch_watcher()
      registry.teardown()
    end,
  })
  setup_branch_watcher()
end

function M.teardown(clear_state)
  stop_branch_watcher()
  if filetype_timer and not filetype_timer:is_closing() then
    filetype_timer:stop()
    filetype_timer:close()
  end
  filetype_timer = nil
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
  augroup = nil
  switching = false
  if clear_state ~= false then
    active = nil
    workspaces = {}
  end
end

function M.reset_for_tests()
  M.teardown(true)
end

return M
