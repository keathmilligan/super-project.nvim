local M = {}

function M.fail(message)
  error(message, 2)
end

function M.truthy(value, message)
  if not value then
    M.fail(message or ("expected a truthy value, got " .. vim.inspect(value)))
  end
end

function M.equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    M.fail(
      (message and (message .. ": ") or "")
        .. "expected "
        .. vim.inspect(expected)
        .. ", got "
        .. vim.inspect(actual)
    )
  end
end

function M.tempdir(name)
  local directory = vim.fn.tempname() .. "-" .. (name or "super-project")
  vim.fn.mkdir(directory, "p")
  return directory
end

function M.write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(type(lines) == "table" and lines or { lines }, path)
end

function M.cleanup(path)
  if path and path ~= "" then
    vim.fn.delete(path, "rf")
  end
end

function M.termstart(cmd)
  -- jobstart({ term = true }) is Neovim 0.11+; 0.10 still uses termopen().
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.fn.jobstart(cmd, { term = true })
  end
  return vim.fn.termopen(cmd)
end

function M.run(command, cwd)
  local result = vim.system(command, { cwd = cwd, text = true }):wait(5000)
  if result.code ~= 0 then
    M.fail(string.format("command failed (%d): %s", result.code, result.stderr or ""))
  end
  return result.stdout
end

function M.git_repo(path)
  vim.fn.mkdir(path, "p")
  M.run({ "git", "init", "-q" }, path)
  M.run({ "git", "config", "user.email", "tests@example.invalid" }, path)
  M.run({ "git", "config", "user.name", "Super Project Tests" }, path)
  M.write(path .. "/README.md", "fixture")
  M.run({ "git", "add", "README.md" }, path)
  M.run({ "git", "commit", "-qm", "fixture" }, path)
end

return M
