local h = require("tests.helpers")
local root = h.tempdir("adapters")
local project_root = root .. "/project"
vim.fn.mkdir(project_root .. "/src/nested", "p")
h.write(project_root .. "/one.txt", "one")
h.write(root .. "/outside.txt", "outside")
vim.api.nvim_set_current_dir(project_root)

-- barbar adapter: only project buffers and pin state are retained.
local restored_buffers
package.loaded["barbar.state"] = {
  export_buffers = function()
    return {
      { name = project_root .. "/one.txt", pinned = true },
      { name = root .. "/outside.txt" },
    }
  end,
  restore_buffers = function(value)
    restored_buffers = value
  end,
}
vim.cmd("edit " .. vim.fn.fnameescape(project_root .. "/one.txt"))
local barbar = require("super-project.integrations.barbar")
local barbar_state = barbar.capture({ root = project_root })
h.equal(#barbar_state.buffers, 1, "barbar state is scoped to the project")
h.truthy(barbar_state.buffers[1].pinned, "barbar pin state is captured")
barbar.restore({ root = project_root }, barbar_state)
h.equal(
  restored_buffers[1].name,
  project_root .. "/one.txt",
  "barbar ordering restores absolute buffers"
)
package.loaded["barbar.state"] = nil

-- neo-tree adapter: capture public manager state and restore through commands.
local expanded = false
local selected
local refreshes = 0
local neo_state = {
  explicitly_opened_nodes = { [project_root .. "/src"] = true },
  tree = {
    get_node = function(_, id)
      if id then
        return {
          expand = function()
            expanded = true
          end,
        }
      end
      return { id = project_root .. "/one.txt" }
    end,
    set_active_node = function(_, id)
      selected = id
    end,
  },
  commands = {
    refresh = function()
      refreshes = refreshes + 1
    end,
  },
}
package.loaded["neo-tree.sources.manager"] = {
  get_state = function()
    return neo_state
  end,
}
local executed
package.loaded["neo-tree.command"] = {
  execute = function(options)
    executed = options
  end,
}
package.loaded["neo-tree.events"] = {
  AFTER_RENDER = "after_render",
  subscribe = function() end,
}
vim.cmd("rightbelow vsplit")
local neo_win = vim.api.nvim_get_current_win()
local neo_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(neo_win, neo_buf)
vim.bo[neo_buf].filetype = "neo-tree"
vim.api.nvim_create_user_command("Neotree", function(args)
  if args.args == "close" and vim.api.nvim_win_is_valid(neo_win) then
    vim.api.nvim_win_close(neo_win, true)
  end
end, { nargs = "*" })

local neo = require("super-project.integrations.neo_tree")
local neo_payload = neo.capture({ root = project_root })
h.truthy(
  neo_payload.open and neo_payload.expanded[1] == "src",
  "neo-tree expansion is captured relatively"
)
h.equal(neo_payload.selected, "one.txt", "neo-tree selected path is captured")
neo.suspend({ root = project_root }, neo_payload)
h.truthy(not vim.api.nvim_win_is_valid(neo_win), "neo-tree UI is suspended")
neo.restore({ root = project_root }, neo_payload)
vim.wait(100)
h.equal(executed.dir, project_root, "neo-tree restores at the project root")
h.truthy(expanded and refreshes > 0, "neo-tree expanded nodes are restored")
h.equal(selected, project_root .. "/one.txt", "neo-tree selection is restored")

pcall(vim.api.nvim_del_user_command, "Neotree")
vim.api.nvim_create_user_command("Neotree", function(args)
  if args.args == "close" then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buffer = vim.api.nvim_win_get_buf(win)
      if vim.bo[buffer].filetype == "neo-tree" and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end
end, { nargs = "*" })

require("super-project").setup({
  discovery = { roots = { project_root }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  integrations = { neo_tree = true, super_tree = false, barbar = false },
})
vim.o.equalalways = true
vim.cmd("only")
vim.cmd("edit " .. vim.fn.fnameescape(project_root .. "/one.txt"))
vim.cmd("topleft vertical split")
local sidebar = vim.api.nvim_get_current_win()
local sidebar_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(sidebar, sidebar_buffer)
vim.bo[sidebar_buffer].filetype = "neo-tree"
vim.api.nvim_win_set_width(sidebar, 16)
vim.wo[sidebar].winfixwidth = true
vim.cmd("wincmd l")
vim.cmd("rightbelow vsplit")
local right = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(right, 22)
local right_width = vim.api.nvim_win_get_width(right)
h.truthy(right_width < 40, "fixture keeps the right split narrower than half")
require("super-project.integrations").capture_and_suspend({ root = project_root })
local remaining = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_win_get_config(win).relative == "" then
    remaining[#remaining + 1] = vim.api.nvim_win_get_width(win)
  end
end
h.equal(#remaining, 2, "explorer suspend leaves the editor splits")
h.truthy(
  math.abs(remaining[1] - remaining[2]) > 5,
  "closing an explorer does not equalize remaining splits"
)
h.truthy(
  math.min(remaining[1], remaining[2]) <= right_width + 1,
  "the narrow split keeps its width when the explorer closes"
)
pcall(vim.api.nvim_del_user_command, "Neotree")
require("super-project")._reset_for_tests()
package.loaded["neo-tree.sources.manager"] = nil
package.loaded["neo-tree.command"] = nil
package.loaded["neo-tree.events"] = nil
h.cleanup(root)
print("integration_adapters: ok")
