local config = require("super-project.config")
local log = require("super-project.log")
local util = require("super-project.util")

local M = {}

M.VERSION = 1

function M.registry_path()
  return config.options.storage.directory .. "/registry.json"
end

function M.default()
  return {
    version = M.VERSION,
    revision = 0,
    last = nil,
    projects = {},
  }
end

function M.load()
  local data, read_err = util.read_file(M.registry_path())
  if not data then
    if read_err then
      log.debug("registry not present: " .. tostring(read_err), "store")
    end
    return M.default()
  end
  local decoded, decode_err = util.json_decode(data)
  if not decoded or decoded.version ~= M.VERSION or type(decoded.projects) ~= "table" then
    log.notify(
      "warn",
      "Ignoring invalid Super Project registry: " .. tostring(decode_err or "unsupported format"),
      "bad-registry"
    )
    return M.default()
  end
  decoded.revision = tonumber(decoded.revision) or 0
  return decoded
end

local function project_map(projects)
  local result = {}
  for _, project in ipairs(projects or {}) do
    if type(project) == "table" and type(project.root) == "string" then
      result[project.root] = project
    end
  end
  return result
end

function M.merge(base, incoming)
  local merged = M.default()
  merged.revision = math.max(base.revision or 0, incoming.revision or 0)
  merged.last = incoming.last or base.last
  local by_root = project_map(base.projects)
  for root, project in pairs(project_map(incoming.projects)) do
    local existing = by_root[root]
    if not existing or (tonumber(project.rank) or 0) >= (tonumber(existing.rank) or 0) then
      by_root[root] = project
    end
  end
  for _, project in pairs(by_root) do
    merged.projects[#merged.projects + 1] = project
  end
  table.sort(merged.projects, function(a, b)
    return (tonumber(a.rank) or 0) < (tonumber(b.rank) or 0)
  end)
  return merged
end

function M.save(state)
  state.version = M.VERSION
  state.revision = (tonumber(state.revision) or 0) + 1
  local encoded, encode_err = util.json_encode(state)
  if not encoded then
    return false, encode_err
  end
  local ok, write_err = util.atomic_write(M.registry_path(), encoded .. "\n")
  if not ok then
    log.error("registry write failed: " .. tostring(write_err), "store")
  end
  return ok, write_err
end

return M
