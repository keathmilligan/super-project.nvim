local config = require("super-project.config")
local preview = require("super-project.preview")

local M = {}

function M.open(projects, options)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local telescope_config = require("telescope.config").values
  local previewers = require("telescope.previewers")

  local function finder()
    return finders.new_table({
      results = projects,
      entry_maker = function(project)
        local name = vim.fn.fnamemodify(project.root, ":t")
        return {
          value = project,
          display = string.format("%-28s %s", name, project.display or project.root),
          ordinal = name .. " " .. (project.display or project.root),
        }
      end,
    })
  end

  local picker_options = vim.tbl_deep_extend(
    "force",
    config.options.selector.backend_options or {},
    options.picker_options or {}
  )
  local project_previewer
  if config.options.selector.display.project_details then
    project_previewer = previewers.new_buffer_previewer({
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview.generate(entry.value))
      end,
    })
  end

  pickers
    .new(picker_options, {
      prompt_title = options.prompt,
      finder = finder(),
      sorter = telescope_config.generic_sorter(picker_options),
      previewer = project_previewer,
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            options.on_select(entry.value)
          end
        end)
        for mode, key in pairs(config.options.selector.forget_bindings or {}) do
          local telescope_mode = mode == "insert" and "i" or mode == "normal" and "n" or mode
          map(telescope_mode, key, function()
            local entry = action_state.get_selected_entry()
            if entry and options.on_forget(entry.value) then
              for index, project in ipairs(projects) do
                if project.root == entry.value.root then
                  table.remove(projects, index)
                  break
                end
              end
              action_state
                .get_current_picker(prompt_bufnr)
                :refresh(finder(), { reset_prompt = true })
            end
          end)
        end
        return true
      end,
    })
    :find()
end

return M
