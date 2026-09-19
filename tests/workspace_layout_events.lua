local h = require("tests.helpers")
local root = h.tempdir("layout")
local plugin_root = vim.fn.getcwd()
local project_a = root .. "/a"
local project_b = root .. "/b"
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
h.write(project_a .. "/one.txt", { "one", "two", "three" })
h.write(project_a .. "/two.txt", "second")

local observed = {}
local group = vim.api.nvim_create_augroup("SuperProjectEventTest", { clear = true })
for _, name in ipairs({
  "SuperProjectSwitchPre",
  "SuperProjectSavePre",
  "SuperProjectSavePost",
  "SuperProjectLoadPre",
  "SuperProjectLoadPost",
  "SuperProjectSwitchPost",
}) do
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = name,
    callback = function()
      observed[#observed + 1] = name
    end,
  })
end

local project = require("super-project").setup({
  discovery = { roots = { project_a, project_b }, observe_git_cwd = false },
  storage = { directory = root .. "/data" },
  startup = { defer_when_dashboard = true },
  sessions = { filetype_delay_ms = 0 },
  integrations = { neo_tree = false, super_tree = false, barbar = false },
})
h.truthy(project.open(project_a))
observed = {}
vim.cmd("edit " .. vim.fn.fnameescape(project_a .. "/one.txt"))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_buf_set_lines(0, 1, 2, false, { "modified" })
local modified_buffer = vim.api.nvim_get_current_buf()
vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(project_a .. "/two.txt"))
local second_buffer = vim.api.nvim_get_current_buf()
vim.cmd("rightbelow split " .. vim.fn.fnameescape(project_a .. "/one.txt"))
local original_layout = vim.fn.winlayout()
local function layout_shape(node)
  if node[1] == "leaf" then
    return "leaf"
  end
  local children = {}
  for _, child in ipairs(node[2]) do
    children[#children + 1] = layout_shape(child)
  end
  return node[1] .. "(" .. table.concat(children, ",") .. ")"
end
local function leaf_sizes(node)
  node = node or vim.fn.winlayout()
  if node[1] == "leaf" then
    local win = node[2]
    return {
      { width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win) },
    }
  end
  local sizes = {}
  for _, child in ipairs(node[2] or {}) do
    for _, size in ipairs(leaf_sizes(child)) do
      sizes[#sizes + 1] = size
    end
  end
  return sizes
end
vim.o.equalalways = true
local left = original_layout[2][1][2]
local right_top = original_layout[2][2][2][1][2]
vim.api.nvim_win_set_width(left, 52)
vim.api.nvim_win_set_height(right_top, 7)
original_layout = vim.fn.winlayout()
local original_sizes = leaf_sizes(original_layout)
h.truthy(
  original_sizes[1].width ~= original_sizes[2].width,
  "fixture starts with an uneven vertical split"
)
h.truthy(
  original_sizes[2].height ~= original_sizes[3].height,
  "fixture starts with an uneven horizontal split"
)
vim.cmd("tabnew " .. vim.fn.fnameescape(project_a .. "/one.txt"))

local save = require("super-project.session").save
require("super-project.session").save = function()
  return false, "forced save failure"
end
local original_notify = vim.notify
vim.notify = function() end
local switched = project.open(project_b)
vim.notify = original_notify
h.truthy(not switched, "failed persistence aborts the switch")
h.equal(
  project.current().root,
  vim.fn.resolve(project_a),
  "failed switch rolls back the active project"
)
h.truthy(
  vim.api.nvim_buf_is_valid(modified_buffer) and vim.bo[modified_buffer].modified,
  "modified buffer survives rollback"
)
h.truthy(vim.bo[modified_buffer].buflisted, "rollback keeps source buffers listed")
require("super-project.session").save = save
observed = {}

h.truthy(project.open(project_b))
h.equal(observed, {
  "SuperProjectSwitchPre",
  "SuperProjectSavePre",
  "SuperProjectSavePost",
  "SuperProjectLoadPre",
  "SuperProjectLoadPost",
  "SuperProjectSwitchPost",
}, "successful switch event order")
h.truthy(vim.api.nvim_buf_is_valid(modified_buffer), "modified buffer remains loaded while parked")
h.truthy(not vim.bo[modified_buffer].buflisted, "parked modified buffer is unlisted")

local cold_child = root .. "/layout-child.lua"
h.write(cold_child, {
  string.format("vim.opt.runtimepath:prepend(%q)", plugin_root),
  string.format(
    "local p = require('super-project').setup({ discovery = { roots = { %q, %q }, observe_git_cwd = false }, storage = { directory = %q }, startup = { defer_when_dashboard = true }, integrations = { neo_tree = false, super_tree = false, barbar = false } })",
    project_a,
    project_b,
    root .. "/data"
  ),
  string.format("assert(p.open(%q))", project_a),
  "assert(#vim.api.nvim_list_tabpages() == 2, 'cold session lost tabs')",
  "local function leaf_sizes(node)",
  "  node = node or vim.fn.winlayout()",
  "  if node[1] == 'leaf' then local win = node[2]; return { { width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win) } } end",
  "  local sizes = {}",
  "  for _, child in ipairs(node[2] or {}) do for _, size in ipairs(leaf_sizes(child)) do sizes[#sizes + 1] = size end end",
  "  return sizes",
  "end",
  string.format(
    "local expected = %s",
    vim.inspect(original_sizes, { newline = " ", indent = " " })
  ),
  "local nested = false",
  "for _, tab in ipairs(vim.api.nvim_list_tabpages()) do",
  "  if #vim.api.nvim_tabpage_list_wins(tab) == 3 then",
  "    nested = true",
  "    vim.api.nvim_set_current_tabpage(tab)",
  "    local actual = leaf_sizes()",
  "    for index, size in ipairs(expected) do",
  "      assert(math.abs(actual[index].width - size.width) <= 1, 'cold session lost vertical split size')",
  "      assert(math.abs(actual[index].height - size.height) <= 1, 'cold session lost horizontal split size')",
  "    end",
  "  end",
  "end",
  "assert(nested, 'cold session lost split layout')",
})
local child = vim
  .system({
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-c",
    "lua dofile(" .. string.format("%q", cold_child) .. ")",
    "-c",
    "qa!",
  }, { cwd = plugin_root, text = true })
  :wait(10000)
h.equal(child.code, 0, "multi-tab cold session restores: " .. (child.stderr or ""))
h.truthy(
  not (child.stderr or ""):find("Error", 1, true),
  "cold session child: " .. (child.stderr or "")
)

h.truthy(project.open(project_a))
h.equal(#vim.api.nvim_list_tabpages(), 2, "all project tabs are restored")
h.truthy(#vim.fn.win_findbuf(second_buffer) > 0, "split buffer is visible after restoration")
h.truthy(vim.bo[modified_buffer].modified, "unsaved state remains modified")
h.truthy(vim.bo[modified_buffer].buflisted, "restored modified buffer is relisted")
h.equal(
  vim.api.nvim_buf_get_lines(modified_buffer, 1, 2, false)[1],
  "modified",
  "unsaved text survives"
)
local restored_layout
for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
  if #vim.api.nvim_tabpage_list_wins(tab) == 3 then
    vim.api.nvim_set_current_tabpage(tab)
    restored_layout = vim.fn.winlayout()
  end
end
h.equal(
  layout_shape(restored_layout),
  layout_shape(original_layout),
  "nested split tree is preserved"
)
local restored_sizes = leaf_sizes(restored_layout)
for index, size in ipairs(original_sizes) do
  h.truthy(
    math.abs(restored_sizes[index].width - size.width) <= 1,
    "hot restore preserves vertical split size"
  )
  h.truthy(
    math.abs(restored_sizes[index].height - size.height) <= 1,
    "hot restore preserves horizontal split size"
  )
end

project._reset_for_tests()
h.cleanup(root)
print("workspace_layout_events: ok")
