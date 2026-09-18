local M = {}

function M.open(projects, options)
  vim.ui.select(projects, {
    prompt = options.prompt,
    format_item = function(project)
      return string.format(
        "%s  %s",
        vim.fn.fnamemodify(project.root, ":t"),
        project.display or project.root
      )
    end,
  }, function(project)
    if project then
      options.on_select(project)
    end
  end)
end

return M
