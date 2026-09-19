local M = {}

M.uv = vim.uv or vim.loop

function M.is_list(value)
  if vim.islist then
    return vim.islist(value)
  end
  return vim.tbl_islist(value)
end

function M.trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.tbl_copy(value)
  return vim.deepcopy(value)
end

function M.list_contains(values, needle)
  for _, value in ipairs(values or {}) do
    if value == needle then
      return true
    end
  end
  return false
end

function M.ensure_dir(path)
  if path == nil or path == "" then
    return false, "directory is empty"
  end
  if vim.fn.isdirectory(path) == 1 then
    return true
  end
  local ok = vim.fn.mkdir(path, "p", "0700")
  if ok == 0 and vim.fn.isdirectory(path) ~= 1 then
    return false, "could not create directory: " .. path
  end
  return true
end

function M.read_file(path)
  local fd, open_err = M.uv.fs_open(path, "r", 384)
  if not fd then
    return nil, open_err
  end
  local stat, stat_err = M.uv.fs_fstat(fd)
  if not stat then
    M.uv.fs_close(fd)
    return nil, stat_err
  end
  local data, read_err = M.uv.fs_read(fd, stat.size, 0)
  M.uv.fs_close(fd)
  if not data then
    return nil, read_err
  end
  return data
end

function M.atomic_write(path, data)
  local parent = vim.fn.fnamemodify(path, ":h")
  local ok, mkdir_err = M.ensure_dir(parent)
  if not ok then
    return false, mkdir_err
  end

  local suffix = string.format(".%d.%s.tmp", vim.fn.getpid(), tostring(M.uv.hrtime()))
  local temporary = path .. suffix
  local fd, open_err = M.uv.fs_open(temporary, "w", 384)
  if not fd then
    return false, open_err
  end

  local wrote, write_err = M.uv.fs_write(fd, data, 0)
  if not wrote then
    M.uv.fs_close(fd)
    M.uv.fs_unlink(temporary)
    return false, write_err
  end
  pcall(M.uv.fs_fsync, fd)
  M.uv.fs_close(fd)

  local renamed, rename_err = M.uv.fs_rename(temporary, path)
  if not renamed then
    M.uv.fs_unlink(temporary)
    return false, rename_err
  end
  return true
end

function M.json_decode(data)
  if data == nil or data == "" then
    return nil, "empty JSON"
  end
  local ok, decoded = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if not ok then
    return nil, decoded
  end
  return decoded
end

function M.json_encode(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return nil, encoded
  end
  return encoded
end

function M.safe_autocmd(pattern, data)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = pattern,
    modeline = false,
    data = data,
  })
  return ok, err
end

function M.valid_buf(buffer)
  return type(buffer) == "number" and vim.api.nvim_buf_is_valid(buffer)
end

function M.valid_win(window)
  return type(window) == "number" and vim.api.nvim_win_is_valid(window)
end

function M.valid_tab(tab)
  return type(tab) == "number" and vim.api.nvim_tabpage_is_valid(tab)
end

function M.schedule_once(callback)
  local scheduled = false
  return function(...)
    local args = { ... }
    if scheduled then
      return
    end
    scheduled = true
    vim.schedule(function()
      scheduled = false
      callback(unpack(args))
    end)
  end
end

local function snapshot_leaf_sizes()
  local result = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if M.valid_win(win) and vim.api.nvim_win_get_config(win).relative == "" then
        result[#result + 1] = {
          win = win,
          width = vim.api.nvim_win_get_width(win),
          height = vim.api.nvim_win_get_height(win),
          winfixwidth = vim.wo[win].winfixwidth,
          winfixheight = vim.wo[win].winfixheight,
        }
      end
    end
  end
  return result
end

local function restore_leaf_sizes(entries)
  for _, item in ipairs(entries or {}) do
    if M.valid_win(item.win) then
      vim.wo[item.win].winfixwidth = item.winfixwidth
      vim.wo[item.win].winfixheight = item.winfixheight
      pcall(vim.api.nvim_win_set_width, item.win, item.width)
      pcall(vim.api.nvim_win_set_height, item.win, item.height)
    end
  end
end

-- Closing or opening a sidebar with the default 'equalalways' equalizes every
-- remaining split, so cold sessions would persist 50/50 sizes. Restoring the
-- option also equalizes. Lock the leaf sizes during that assignment: merely
-- reapplying them afterwards lets temporary shrinks destroy terminal cells.
function M.without_equalalways(callback)
  local original = vim.o.equalalways
  vim.o.equalalways = false
  local ok, result, extra = xpcall(callback, debug.traceback)
  local sizes = snapshot_leaf_sizes()
  for _, item in ipairs(sizes) do
    vim.wo[item.win].winfixwidth = true
    vim.wo[item.win].winfixheight = true
  end
  vim.o.equalalways = original
  restore_leaf_sizes(sizes)
  if not ok then
    error(result, 0)
  end
  return result, extra
end

return M
