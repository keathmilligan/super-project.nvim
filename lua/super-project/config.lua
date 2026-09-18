local util = require("super-project.util")

local M = {}

M.defaults = {
  discovery = {
    roots = {},
    excludes = {},
    observe_git_cwd = true,
    symlinks = "resolve",
  },
  storage = {
    directory = vim.fn.stdpath("data") .. "/super-project",
  },
  startup = {
    fallback = "last",
    defer_when_dashboard = false,
  },
  sessions = {
    scope = "project",
    filetype_delay_ms = 200,
    exclude = {
      directories = { vim.fn.expand("~"), "/tmp" },
      filetypes = {
        "ccc-ui",
        "dap-repl",
        "dap-view",
        "dap-view-term",
        "gitcommit",
        "gitrebase",
        "qf",
        "toggleterm",
      },
      buftypes = {},
    },
  },
  terminals = {
    keep_alive = true,
  },
  integrations = {
    neo_tree = true,
    super_tree = true,
    barbar = true,
  },
  selector = {
    backend = "builtin",
    forget_bindings = { insert = "<C-d>", normal = "d" },
    display = {
      project_details = true,
      git_state = true,
      fetch_remote = false,
      hidden_entries = true,
    },
    backend_options = {},
  },
  logging = {
    level = "warn",
  },
}

M.options = vim.deepcopy(M.defaults)

local function expect(errors, condition, path, expected)
  if not condition then
    errors[#errors + 1] = string.format("%s must be %s", path, expected)
  end
end

local function one_of(value, values)
  return util.list_contains(values, value)
end

local function collect_unknown(value, defaults, prefix, errors)
  if type(value) ~= "table" or type(defaults) ~= "table" or next(defaults) == nil then
    return
  end
  for key, child in pairs(value) do
    local expected = defaults[key]
    local name = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
    if expected == nil then
      errors[#errors + 1] = name .. " is not a recognized option"
    elseif
      type(child) == "table"
      and type(expected) == "table"
      and not util.is_list(expected)
      and name ~= "selector.backend_options"
    then
      collect_unknown(child, expected, name, errors)
    end
  end
end

local function merge(defaults, values)
  if values == nil then
    return vim.deepcopy(defaults)
  end
  if type(defaults) ~= "table" or type(values) ~= "table" then
    return vim.deepcopy(values)
  end
  if util.is_list(defaults) then
    return vim.deepcopy(values)
  end
  local result = vim.deepcopy(defaults)
  for key, value in pairs(values) do
    result[key] = merge(defaults[key], value)
  end
  return result
end

function M.validate(options)
  local errors = {}
  local discovery = type(options.discovery) == "table" and options.discovery or {}
  local storage = type(options.storage) == "table" and options.storage or {}
  local startup = type(options.startup) == "table" and options.startup or {}
  local sessions = type(options.sessions) == "table" and options.sessions or {}
  local excludes = type(sessions.exclude) == "table" and sessions.exclude or {}
  local terminals = type(options.terminals) == "table" and options.terminals or {}
  local integrations = type(options.integrations) == "table" and options.integrations or {}
  local selector = type(options.selector) == "table" and options.selector or {}
  local selector_display = type(selector.display) == "table" and selector.display or {}
  local logging = type(options.logging) == "table" and options.logging or {}

  expect(errors, type(options.discovery) == "table", "discovery", "a table")
  expect(errors, util.is_list(discovery.roots), "discovery.roots", "a list")
  expect(errors, util.is_list(discovery.excludes), "discovery.excludes", "a list")
  for _, name in ipairs({ "roots", "excludes" }) do
    for index, value in ipairs(discovery[name] or {}) do
      expect(
        errors,
        type(value) == "string",
        string.format("discovery.%s[%d]", name, index),
        "a string"
      )
    end
  end
  expect(
    errors,
    type(discovery.observe_git_cwd) == "boolean",
    "discovery.observe_git_cwd",
    "a boolean"
  )
  expect(
    errors,
    one_of(discovery.symlinks, { "resolve", "prefix", "preserve" }),
    "discovery.symlinks",
    '"resolve", "prefix", or "preserve"'
  )
  expect(
    errors,
    type(storage.directory) == "string" and storage.directory ~= "",
    "storage.directory",
    "a non-empty string"
  )
  expect(
    errors,
    one_of(startup.fallback, { "last", "empty" }),
    "startup.fallback",
    '"last" or "empty"'
  )
  expect(
    errors,
    type(startup.defer_when_dashboard) == "boolean",
    "startup.defer_when_dashboard",
    "a boolean"
  )
  expect(
    errors,
    one_of(sessions.scope, { "project", "branch" }),
    "sessions.scope",
    '"project" or "branch"'
  )
  expect(
    errors,
    type(sessions.filetype_delay_ms) == "number" and sessions.filetype_delay_ms >= 0,
    "sessions.filetype_delay_ms",
    "a non-negative number"
  )
  for _, name in ipairs({ "directories", "filetypes", "buftypes" }) do
    expect(errors, util.is_list(excludes[name]), "sessions.exclude." .. name, "a list")
    for index, value in ipairs(excludes[name] or {}) do
      expect(
        errors,
        type(value) == "string",
        string.format("sessions.exclude.%s[%d]", name, index),
        "a string"
      )
    end
  end
  expect(errors, type(terminals.keep_alive) == "boolean", "terminals.keep_alive", "a boolean")
  for _, name in ipairs({ "neo_tree", "super_tree", "barbar" }) do
    expect(errors, type(integrations[name]) == "boolean", "integrations." .. name, "a boolean")
  end
  expect(
    errors,
    one_of(selector.backend, { "builtin", "telescope", "fzf-lua", "snacks" }),
    "selector.backend",
    '"builtin", "telescope", "fzf-lua", or "snacks"'
  )
  expect(errors, type(selector.backend_options) == "table", "selector.backend_options", "a table")
  expect(errors, type(selector.forget_bindings) == "table", "selector.forget_bindings", "a table")
  for mode, key in
    pairs(type(selector.forget_bindings) == "table" and selector.forget_bindings or {})
  do
    expect(
      errors,
      type(mode) == "string" and type(key) == "string",
      "selector.forget_bindings",
      "string keys and values"
    )
  end
  for _, name in ipairs({ "project_details", "git_state", "fetch_remote", "hidden_entries" }) do
    expect(
      errors,
      type(selector_display[name]) == "boolean",
      "selector.display." .. name,
      "a boolean"
    )
  end
  expect(
    errors,
    one_of(logging.level, { "off", "error", "warn", "info", "debug" }),
    "logging.level",
    '"off", "error", "warn", "info", or "debug"'
  )
  return #errors == 0, errors
end

function M.setup(options)
  options = options or {}
  local unknown = {}
  collect_unknown(options, M.defaults, "", unknown)
  if #unknown > 0 then
    error("super-project configuration error:\n- " .. table.concat(unknown, "\n- "))
  end
  local merged = merge(M.defaults, options)
  local valid, errors = M.validate(merged)
  if not valid then
    error("super-project configuration error:\n- " .. table.concat(errors, "\n- "))
  end
  local storage_directory = vim.fn.fnamemodify(vim.fn.expand(merged.storage.directory), ":p")
  if storage_directory ~= "/" then
    storage_directory = storage_directory:gsub("/+$", "")
  end
  merged.storage.directory = storage_directory
  M.options = merged
  return merged
end

return M
