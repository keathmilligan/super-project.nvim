local config = require("super-project.config")
local events = require("super-project.events")
local log = require("super-project.log")
local path = require("super-project.path")
local store = require("super-project.store")
local util = require("super-project.util")

local M = {}

local state = store.default()
local dirty = false
local watcher
local writing = false

local function emit(reason, project)
  events.emit("SuperProjectRegistryChanged", {
    reason = reason,
    project = project and vim.deepcopy(project) or nil,
  })
end

local function max_rank(projects)
  local rank = 0
  for _, project in ipairs(projects or {}) do
    rank = math.max(rank, tonumber(project.rank) or 0)
  end
  return rank
end

local function reload_if_dirty()
  if not dirty then
    return
  end
  dirty = false
  state = store.load()
end

local function persist()
  writing = true
  local ok, err = store.save(state)
  writing = false
  if not ok then
    return false, err
  end
  return true
end

local function record_map(records)
  local result = {}
  for _, record in ipairs(records or {}) do
    result[record.root] = record
  end
  return result
end

local function valid_record(record)
  return type(record) == "table"
    and path.is_directory(record.root)
    and not path.is_excluded(record.root)
end

local function prune()
  local changed = false
  local projects = {}
  for _, project in ipairs(state.projects or {}) do
    if valid_record(project) then
      projects[#projects + 1] = project
    else
      changed = true
    end
  end
  state.projects = projects
  return changed
end

function M.setup()
  M.teardown()
  util.ensure_dir(config.options.storage.directory)
  state = store.load()
  prune()
  dirty = false

  watcher = util.uv.new_fs_event()
  if watcher then
    watcher:start(config.options.storage.directory, {}, function(err)
      if not err and not writing then
        dirty = true
      end
    end)
  end
end

function M.teardown()
  if watcher and not watcher:is_closing() then
    watcher:stop()
    watcher:close()
  end
  watcher = nil
end

function M.register(candidate, source, display)
  reload_if_dirty()
  local root = path.canonical(candidate)
  if not root or not path.is_directory(root) then
    return nil, "project directory does not exist"
  end
  if path.is_excluded(root) then
    return nil, "project is excluded"
  end

  local by_root = record_map(state.projects)
  local project = by_root[root]
  if not project then
    project = { root = root }
    state.projects[#state.projects + 1] = project
  end
  project.display = display or project.display or path.display(candidate)
  project.source = source or project.source or "observed"
  project.rank = max_rank(state.projects) + 1
  project.last_used = os.time()

  while #state.projects > 200 do
    table.sort(state.projects, function(a, b)
      return (tonumber(a.rank) or 0) < (tonumber(b.rank) or 0)
    end)
    table.remove(state.projects, 1)
  end

  local ok, err = persist()
  if not ok then
    return nil, err
  end
  emit("register", project)
  return vim.deepcopy(project)
end

function M.touch(candidate, source, display)
  return M.register(candidate, source or "recent", display)
end

function M.list(options)
  reload_if_dirty()
  options = options or {}
  local order = options.order or "source"
  local by_root = {}
  local result = {}

  for _, configured in ipairs(path.expand_roots()) do
    by_root[configured.root] = configured
    result[#result + 1] = configured
  end
  for _, stored in ipairs(state.projects or {}) do
    if valid_record(stored) then
      local existing = by_root[stored.root]
      if existing then
        existing.rank = stored.rank
        existing.last_used = stored.last_used
        existing.persisted_source = stored.source
        if not existing.display then
          existing.display = stored.display
        end
      else
        local copy = vim.deepcopy(stored)
        by_root[copy.root] = copy
        result[#result + 1] = copy
      end
    end
  end

  if order == "recent" then
    table.sort(result, function(a, b)
      local ar, br = tonumber(a.rank) or 0, tonumber(b.rank) or 0
      if ar ~= br then
        return ar > br
      end
      return (a.display or a.root) < (b.display or b.root)
    end)
  elseif order == "name" then
    table.sort(result, function(a, b)
      local an = vim.fn.fnamemodify(a.root, ":t"):lower()
      local bn = vim.fn.fnamemodify(b.root, ":t"):lower()
      if an ~= bn then
        return an < bn
      end
      return a.root < b.root
    end)
  elseif order == "path" then
    table.sort(result, function(a, b)
      return a.root < b.root
    end)
  else
    table.sort(result, function(a, b)
      local ai, bi = tonumber(a.source_index), tonumber(b.source_index)
      if ai and bi and ai ~= bi then
        return ai < bi
      elseif ai and bi then
        return (tonumber(a.source_order) or 0) < (tonumber(b.source_order) or 0)
      elseif ai ~= nil then
        return true
      elseif bi ~= nil then
        return false
      end
      return (tonumber(a.rank) or 0) > (tonumber(b.rank) or 0)
    end)
  end

  return vim.deepcopy(result)
end

function M.find(candidate)
  local root = path.canonical(candidate)
  if not root then
    return nil
  end
  for _, project in ipairs(M.list({ order = "source" })) do
    if project.root == root then
      return project
    end
  end
  return nil
end

function M.closest(candidate)
  return path.closest_project(M.list({ order = "source" }), candidate)
end

function M.forget(candidate)
  reload_if_dirty()
  local root = path.canonical(candidate)
  if not root then
    return false, "invalid project path"
  end
  local kept = {}
  local removed
  for _, project in ipairs(state.projects or {}) do
    if project.root == root then
      removed = project
    else
      kept[#kept + 1] = project
    end
  end
  state.projects = kept
  if state.last and state.last.root == root then
    state.last = nil
  end
  local ok, err = persist()
  if not ok then
    return false, err
  end
  emit("forget", removed or { root = root })
  return true
end

function M.set_last(project)
  reload_if_dirty()
  state.last = project and vim.deepcopy(project) or nil
  return persist()
end

function M.last()
  reload_if_dirty()
  return state.last and vim.deepcopy(state.last) or nil
end

function M.state()
  reload_if_dirty()
  return vim.deepcopy(state)
end

function M.reset_for_tests(value)
  state = value and vim.deepcopy(value) or store.default()
  dirty = false
end

return M
