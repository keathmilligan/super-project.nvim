local config = require("super-project.config")
local preview = require("super-project.preview")

local M = {}

local function fzf_key(key)
  local control = key and key:match("^<C%-([%w])>$")
  return control and ("ctrl-" .. control:lower()) or key
end

function M.open(projects, options)
  local fzf = require("fzf-lua")
  local lookup = {}
  local entries = {}
  for index, project in ipairs(projects) do
    local line = string.format(
      "%s\t%s",
      vim.fn.fnamemodify(project.root, ":t"),
      project.display or project.root
    )
    entries[index] = line
    lookup[line] = project
  end
  local defaults = {
    prompt = options.prompt .. "> ",
    actions = {
      ["default"] = function(selected)
        local project = selected and lookup[selected[1]]
        if project then
          options.on_select(project)
        end
      end,
    },
    fzf_opts = { ["--delimiter"] = "\t", ["--with-nth"] = "1,2" },
  }
  if config.options.selector.display.project_details then
    defaults.previewer = {
      _ctor = function()
        local builtin = require("fzf-lua.previewer.builtin")
        local ProjectPreviewer = builtin.buffer_or_file:extend()

        function ProjectPreviewer:new(value, picker_options, window)
          ProjectPreviewer.super.new(self, value, picker_options, window)
          self.project_preview_buffer = self:get_tmp_buffer()
          return self
        end

        function ProjectPreviewer:populate_preview_buf(entry)
          local project = lookup[entry]
          if not project then
            return
          end
          local buffer = self.project_preview_buffer
          if buffer and vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_set_lines(buffer, 0, -1, false, preview.generate(project))
            self:set_preview_buf(buffer)
          end
        end

        return ProjectPreviewer
      end,
    }
  end
  for _, key in pairs(config.options.selector.forget_bindings or {}) do
    defaults.actions[fzf_key(key)] = function(selected)
      local project = selected and lookup[selected[1]]
      if project and options.on_forget(project) then
        for index, candidate in ipairs(projects) do
          if candidate.root == project.root then
            table.remove(projects, index)
            break
          end
        end
        vim.schedule(function()
          if #projects > 0 then
            M.open(projects, options)
          end
        end)
      end
    end
  end
  fzf.fzf_exec(
    entries,
    vim.tbl_deep_extend("force", defaults, config.options.selector.backend_options or {})
  )
end

return M
