local test = vim.env.SUPER_PROJECT_TEST
if not test or test == "" then
  error("SUPER_PROJECT_TEST is not set")
end

local ok, err = xpcall(function()
  dofile(test)
end, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
