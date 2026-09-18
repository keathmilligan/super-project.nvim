local h = require("tests.helpers")
local root = h.tempdir("selectors")
local project_record = { root = root, display = root, name = "selectors" }
local selected
local forgotten
local options = {
  prompt = "Projects",
  on_select = function(project)
    selected = project
  end,
  on_forget = function(project)
    forgotten = project
    return true
  end,
}

-- fzf-lua contract.
local fzf_options
local fzf_entries
package.loaded["fzf-lua"] = {
  fzf_exec = function(entries, value)
    fzf_entries = entries
    fzf_options = value
  end,
}
require("super-project.config").setup({ selector = { backend = "fzf-lua" } })
require("super-project.selector.fzf_lua").open({ project_record }, options)
local fzf_line = fzf_entries[1]
h.truthy(fzf_options.previewer ~= nil, "fzf-lua receives a project previewer")
fzf_options.actions.default({ fzf_line })
h.equal(selected, project_record, "fzf-lua selection uses the common action")
fzf_options.actions["ctrl-d"]({ fzf_line })
h.equal(forgotten, project_record, "fzf-lua forget binding uses the common action")
package.loaded["fzf-lua"] = nil

-- Snacks contract.
selected, forgotten = nil, nil
local snacks_options
_G.Snacks = { picker = {
  pick = function(value)
    snacks_options = value
  end,
} }
require("super-project.config").setup({ selector = { backend = "snacks" } })
require("super-project.selector.snacks").open({ project_record }, options)
h.truthy(snacks_options.items[1].dir, "Snacks receives directory items for native previews")
snacks_options.confirm(nil, snacks_options.items[1])
h.equal(selected, project_record, "Snacks selection uses the common action")
snacks_options.actions.forget_project({ find = function() end }, snacks_options.items[1])
h.equal(forgotten, project_record, "Snacks forget action uses the common action")
_G.Snacks = nil

-- Telescope contract.
selected, forgotten = nil, nil
local replacement
local mapped = {}
local picker_spec
package.loaded["telescope.actions"] = {
  select_default = {
    replace = function(_, callback)
      replacement = callback
    end,
  },
  close = function() end,
}
package.loaded["telescope.actions.state"] = {
  get_selected_entry = function()
    return { value = project_record }
  end,
  get_current_picker = function()
    return { refresh = function() end }
  end,
}
package.loaded["telescope.finders"] = {
  new_table = function(value)
    return value
  end,
}
package.loaded["telescope.config"] =
  { values = {
    generic_sorter = function()
      return {}
    end,
  } }
package.loaded["telescope.previewers"] = {
  new_buffer_previewer = function(value)
    return value
  end,
}
package.loaded["telescope.pickers"] = {
  new = function(_, spec)
    picker_spec = spec
    return {
      find = function()
        spec.attach_mappings(1, function(mode, key, callback)
          mapped[mode .. key] = callback
        end)
      end,
    }
  end,
}
require("super-project.config").setup({ selector = { backend = "telescope" } })
require("super-project.selector.telescope").open({ project_record }, options)
h.truthy(picker_spec and replacement, "Telescope picker is constructed")
replacement()
h.equal(selected, project_record, "Telescope selection uses the common action")
mapped["i<C-d>"]()
h.equal(forgotten, project_record, "Telescope forget mapping uses the common action")
for _, module in ipairs({
  "telescope.actions",
  "telescope.actions.state",
  "telescope.finders",
  "telescope.config",
  "telescope.previewers",
  "telescope.pickers",
}) do
  package.loaded[module] = nil
end

h.cleanup(root)
print("selector_adapters: ok")
