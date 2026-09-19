local config = require("super-project.config")
local log = require("super-project.log")
local terminal = require("super-project.terminal")
local util = require("super-project.util")

local M = {}

local function sessions_dir()
  return config.options.storage.directory .. "/sessions"
end

function M.hash(key)
  if vim.fn.exists("*sha256") == 1 then
    local ok, digest = pcall(vim.fn.sha256, key)
    if not ok or type(digest) ~= "string" then
      -- Neovim 0.10 sha256() rejects embedded NUL (E976).
      ok, digest = pcall(vim.fn.sha256, key:gsub("\0", "\n"))
    end
    if ok and type(digest) == "string" then
      return digest
    end
  end
  return key:gsub("[^%w_.-]", function(char)
    return string.format("_%02x", string.byte(char))
  end)
end

function M.paths(key)
  local base = sessions_dir() .. "/" .. M.hash(key)
  return { session = base .. ".vim", sidecar = base .. ".json" }
end

function M.exists(key)
  return util.uv.fs_stat(M.paths(key).session) ~= nil
end

local function safe_sessionoptions()
  local values = {}
  for value in vim.o.sessionoptions:gmatch("[^,]+") do
    if value ~= "terminal" and value ~= "buffers" and value ~= "blank" then
      values[#values + 1] = value
    end
  end
  return table.concat(values, ",")
end

local function root_from_key(key)
  return key:match("^([^%z]+)") or key
end

function M.should_save(key)
  local root = vim.fn.resolve(root_from_key(key))
  for _, directory in ipairs(config.options.sessions.exclude.directories or {}) do
    local normalized = vim.fn.fnamemodify(vim.fn.expand(directory), ":p"):gsub("/+$", "")
    local excluded = vim.fn.resolve(normalized)
    if root == excluded then
      return false
    end
  end
  return true
end

local function ignored_buffer(buffer)
  return vim.tbl_contains(config.options.sessions.exclude.filetypes, vim.bo[buffer].filetype)
    or vim.tbl_contains(config.options.sessions.exclude.buftypes, vim.bo[buffer].buftype)
end

local function hide_ignored_windows()
  local replaced = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      local buffer = vim.api.nvim_win_get_buf(win)
      if
        vim.api.nvim_buf_is_valid(buffer)
        and vim.bo[buffer].buftype ~= "terminal"
        and ignored_buffer(buffer)
      then
        local scratch = vim.api.nvim_create_buf(false, true)
        vim.bo[scratch].bufhidden = "wipe"
        replaced[#replaced + 1] =
          { win = win, buffer = buffer, view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
        vim.api.nvim_win_set_buf(win, scratch)
      end
    end
  end
  return replaced
end

local function restore_ignored_windows(replaced)
  for _, item in ipairs(replaced or {}) do
    if vim.api.nvim_win_is_valid(item.win) and vim.api.nvim_buf_is_valid(item.buffer) then
      vim.api.nvim_win_set_buf(item.win, item.buffer)
      pcall(vim.api.nvim_win_call, item.win, function()
        vim.fn.winrestview(item.view)
      end)
    end
  end
end

local function terminal_placeholder_name(key, index, nonce)
  return string.format(
    "%s/.terminal-%s-%s-%d",
    sessions_dir(),
    M.hash(key):sub(1, 16),
    nonce,
    index
  )
end

local function replace_terminal_windows(key)
  local records = {}
  local by_buffer = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        local buffer = vim.api.nvim_win_get_buf(win)
        if util.valid_buf(buffer) and vim.bo[buffer].buftype == "terminal" then
          local record = by_buffer[buffer]
          if not record then
            local directory = vim.api.nvim_win_call(win, function()
              return { cwd = vim.fn.getcwd(), scope = vim.fn.haslocaldir() }
            end)
            record = {
              buffer = buffer,
              bufhidden = vim.bo[buffer].bufhidden,
              cwd = directory.cwd,
              cwd_scope = directory.scope,
              windows = {},
            }
            by_buffer[buffer] = record
            records[#records + 1] = record
          end
          record.windows[#record.windows + 1] = {
            window = win,
            view = vim.api.nvim_win_call(win, vim.fn.winsaveview),
          }
        end
      end
    end
  end

  local nonce = tostring(util.uv.hrtime())
  for index, record in ipairs(records) do
    local placeholder = vim.api.nvim_create_buf(false, false)
    record.placeholder = placeholder
    record.marker = terminal_placeholder_name(key, index, nonce)
    vim.api.nvim_buf_set_name(placeholder, record.marker)
    vim.bo[placeholder].bufhidden = "wipe"
    vim.bo[placeholder].buflisted = false
    vim.bo[placeholder].swapfile = false
  end
  for _, record in ipairs(records) do
    vim.bo[record.buffer].bufhidden = "hide"
    for _, item in ipairs(record.windows) do
      vim.api.nvim_win_set_buf(item.window, record.placeholder)
    end
  end

  local payload = {}
  for _, record in ipairs(records) do
    payload[#payload + 1] = {
      marker = record.marker,
      cwd = record.cwd,
      cwd_scope = record.cwd_scope,
    }
  end
  return records, payload
end

local function restore_terminal_windows(records)
  for _, record in ipairs(records or {}) do
    for _, item in ipairs(record.windows) do
      if util.valid_win(item.window) and util.valid_buf(record.buffer) then
        vim.api.nvim_win_set_buf(item.window, record.buffer)
        pcall(vim.api.nvim_win_call, item.window, function()
          vim.fn.winrestview(item.view)
        end)
      end
    end
    if util.valid_buf(record.buffer) then
      vim.bo[record.buffer].bufhidden = record.bufhidden
    end
    if util.valid_buf(record.placeholder) then
      pcall(vim.api.nvim_buf_delete, record.placeholder, { force = true })
    end
  end
end

local function valid_terminal_marker(marker)
  if type(marker) ~= "string" then
    return false
  end
  local prefix = sessions_dir() .. "/.terminal-"
  local suffix = marker:sub(#prefix + 1)
  return marker:sub(1, #prefix) == prefix and suffix ~= "" and not suffix:find("/", 1, true)
end

local function restore_cold_terminals(payload)
  local current_window = vim.api.nvim_get_current_win()
  for _, state in ipairs(payload or {}) do
    if valid_terminal_marker(state.marker) then
      local placeholder = vim.fn.bufnr(state.marker)
      if placeholder >= 0 and util.valid_buf(placeholder) then
        local windows = vim.fn.win_findbuf(placeholder)
        if #windows > 0 then
          vim.bo[placeholder].buflisted = false
          vim.bo[placeholder].bufhidden = "wipe"
          local buffer, terminal_err = terminal.open_fresh(windows[1], state.cwd, state.cwd_scope)
          if not buffer then
            return false, terminal_err
          end
          for index = 2, #windows do
            if util.valid_win(windows[index]) then
              vim.api.nvim_win_set_buf(windows[index], buffer)
            end
          end
        end
        if util.valid_buf(placeholder) then
          pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
        end
      end
    end
  end
  if util.valid_win(current_window) then
    vim.api.nvim_set_current_win(current_window)
  end
  return true
end

local function remove_ignored_references(filename, replaced)
  local names = {}
  for _, item in ipairs(replaced or {}) do
    local name = vim.api.nvim_buf_get_name(item.buffer)
    if name ~= "" then
      names[#names + 1] = name
      names[#names + 1] = vim.fn.fnameescape(name)
      local short = vim.fn.fnamemodify(name, ":~")
      names[#names + 1] = short
      names[#names + 1] = vim.fn.fnameescape(short)
    end
  end
  if #names == 0 then
    return true
  end
  local data, read_err = util.read_file(filename)
  if not data then
    return false, read_err
  end
  local kept = {}
  for _, line in ipairs(vim.split(data, "\n", { plain = true })) do
    local ignored = false
    for _, name in ipairs(names) do
      if line:find(name, 1, true) then
        ignored = true
        break
      end
    end
    if not ignored then
      kept[#kept + 1] = line
    end
  end
  return util.atomic_write(filename, table.concat(kept, "\n"))
end

local function harden_scratch_cleanup(data)
  return data:gsub("silent%s+exe%s+'bwipe '%s+%.%s+s:wipebuf", "silent! exe 'bwipe ' . s:wipebuf")
end

local function harden_session_file(filename, data)
  data = data or util.read_file(filename)
  if not data then
    return false, "session could not be read"
  end
  local hardened, replacements = harden_scratch_cleanup(data)
  if replacements == 0 then
    return true, nil, data
  end
  local ok, err = util.atomic_write(filename, hardened)
  if not ok then
    return false, err
  end
  return true, nil, hardened
end

function M.save(key, metadata)
  if not M.should_save(key) then
    return true
  end
  local paths = M.paths(key)
  local ok, mkdir_err = util.ensure_dir(sessions_dir())
  if not ok then
    return false, mkdir_err
  end

  local original = vim.o.sessionoptions
  local replaced = hide_ignored_windows()
  local terminal_records, terminal_payload = replace_terminal_windows(key)
  local temporary = paths.session
    .. string.format(".%d.%s.tmp", vim.fn.getpid(), tostring(util.uv.hrtime()))
  local saved, save_err = xpcall(function()
    vim.o.sessionoptions = safe_sessionoptions()
    vim.cmd("silent mksession! " .. vim.fn.fnameescape(temporary))
  end, debug.traceback)
  vim.o.sessionoptions = original
  restore_terminal_windows(terminal_records)
  restore_ignored_windows(replaced)
  if not saved then
    pcall(util.uv.fs_unlink, temporary)
    return false, save_err
  end
  local sanitized, sanitize_err = remove_ignored_references(temporary, replaced)
  if not sanitized then
    pcall(util.uv.fs_unlink, temporary)
    return false, sanitize_err
  end
  local hardened, harden_err = harden_session_file(temporary)
  if not hardened then
    pcall(util.uv.fs_unlink, temporary)
    return false, harden_err
  end

  local payload = {
    version = 1,
    key = key,
    integrations = (metadata and metadata.integrations) or {},
    terminals = terminal_payload,
  }
  local encoded, encode_err = util.json_encode(payload)
  if not encoded then
    return false, encode_err
  end
  local sidecar_ok, sidecar_err = util.atomic_write(paths.sidecar, encoded .. "\n")
  if not sidecar_ok then
    pcall(util.uv.fs_unlink, temporary)
    return false, sidecar_err
  end
  local renamed, rename_err = util.uv.fs_rename(temporary, paths.session)
  if not renamed then
    pcall(util.uv.fs_unlink, temporary)
    return false, rename_err
  end
  pcall(util.uv.fs_chmod, paths.session, 384)
  return true
end

function M.load_metadata(key)
  local data = util.read_file(M.paths(key).sidecar)
  if not data then
    return { version = 1, key = key, integrations = {}, terminals = {} }
  end
  local payload, err = util.json_decode(data)
  if not payload or payload.version ~= 1 or payload.key ~= key then
    log.warn("invalid session sidecar: " .. tostring(err or "identity mismatch"), key)
    return { version = 1, key = key, integrations = {}, terminals = {} }
  end
  payload.integrations = type(payload.integrations) == "table" and payload.integrations or {}
  payload.terminals = type(payload.terminals) == "table" and payload.terminals or {}
  return payload
end

function M.load(key)
  local filename = M.paths(key).session
  local data, read_err = util.read_file(filename)
  if not data then
    return false, read_err or "session does not exist"
  end
  if data:find("term://", 1, true) then
    return false, "refusing to load a session containing terminal commands"
  end
  local hardened, harden_err, safe_data = harden_session_file(filename, data)
  if not hardened then
    return false, harden_err
  end
  data = safe_data
  local metadata
  local ok, source_err = xpcall(function()
    util.without_equalalways(function()
      vim.cmd("silent source " .. vim.fn.fnameescape(filename))
      metadata = M.load_metadata(key)
      local terminals_ok, terminal_err = restore_cold_terminals(metadata.terminals)
      if not terminals_ok then
        error(terminal_err)
      end
    end)
  end, debug.traceback)
  if not ok then
    return false, source_err
  end
  return true, metadata
end

function M.delete(key)
  local paths = M.paths(key)
  for _, filename in pairs(paths) do
    if util.uv.fs_stat(filename) then
      local ok, err = util.uv.fs_unlink(filename)
      if not ok then
        return false, err
      end
    end
  end
  return true
end

function M.delete_project(root)
  local directory = sessions_dir()
  local handle = util.uv.fs_scandir(directory)
  if not handle then
    return true
  end
  local sidecars = {}
  while true do
    local name, kind = util.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind == "file" and name:sub(-5) == ".json" then
      sidecars[#sidecars + 1] = directory .. "/" .. name
    end
  end
  for _, filename in ipairs(sidecars) do
    local data = util.read_file(filename)
    local payload = data and util.json_decode(data) or nil
    if
      payload
      and type(payload.key) == "string"
      and (payload.key == root or payload.key:sub(1, #root + 1) == root .. "\0")
    then
      local base = filename:sub(1, -6)
      for _, target in ipairs({ base .. ".json", base .. ".vim" }) do
        if util.uv.fs_stat(target) then
          local ok, err = util.uv.fs_unlink(target)
          if not ok then
            return false, err
          end
        end
      end
    end
  end
  return true
end

function M.contains_terminal_entry(key)
  local data = util.read_file(M.paths(key).session)
  return data ~= nil and data:find("term://", 1, true) ~= nil
end

return M
