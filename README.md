# super-project.nvim

A Neovim project manager with automatic Git discovery, saved workspaces, and
terminal jobs that remain alive while another project is active.

Super Project has capability parity with
[`coffebar/neovim-project`](https://github.com/coffebar/neovim-project), but it
uses its own configuration, commands, events, and storage. It is not a drop-in
API replacement.

## Features

- Registers the current Git worktree automatically on startup and `DirChanged`
- Adds explicit projects from configured paths and glob patterns
- Filters every project source through configurable exclusions
- Recent-project history and source/recent/name/path ordering
- Hot project workspaces that retain tabs, splits, views, modified buffers,
  and terminal buffers
- Terminal processes continue running and producing output in the background
- Command-free cold sessions that reopen terminal leaves with fresh shells
- Optional project- or Git-branch-scoped workspaces
- Builtin, Telescope, fzf-lua, and Snacks selectors
- Optional neo-tree, Super Tree, and barbar state restoration

## Requirements and dependencies

| Dependency | When it is needed |
| --- | --- |
| Neovim 0.10+ | Always |
| Git executable | Automatic Git discovery, Git preview details, and branch-scoped sessions |
| Telescope | Only with `selector.backend = "telescope"` |
| fzf-lua | Only with `selector.backend = "fzf-lua"` |
| Snacks | Only with `selector.backend = "snacks"` |
| neo-tree | Optional explorer-state integration |
| [super-tree.nvim](https://github.com/keathmilligan/super-tree.nvim) | Optional explorer-state and Projects-pane integration |
| barbar.nvim | Optional buffer-order integration |

Plenary and Neovim Session Manager are not used.

Dependencies belong in your plugin-manager specification, not in the
`require("super-project").setup()` table. If an external selector is missing,
Super Project warns once and falls back to `vim.ui.select`.

## Installation

### lazy.nvim with no optional dependencies

```lua
{
  "keathmilligan/super-project.nvim",
  lazy = false,
  priority = 100,
  opts = {
    discovery = {
      roots = {
        "~/projects/*",
        "~/.config/*",
      },
      excludes = {
        "~/projects/archive/*",
      },
    },
  },
}
```

### lazy.nvim with Telescope and Super Tree

```lua
{
  "keathmilligan/super-project.nvim",
  lazy = false,
  priority = 100,
  dependencies = {
    "nvim-telescope/telescope.nvim",
    { "keathmilligan/super-tree.nvim", opts = {} },
  },
  opts = {
    selector = { backend = "telescope" },
    discovery = {
      roots = { "~/projects/*" },
      excludes = {},
      observe_git_cwd = true,
    },
  },
}
```

For another plugin manager, call:

```lua
require("super-project").setup({
  discovery = {
    roots = { "~/projects/*" },
  },
})
```

## Configuration

Defaults:

```lua
{
  discovery = {
    roots = {},
    excludes = {},
    observe_git_cwd = true,
    symlinks = "resolve", -- "resolve", "prefix", or "preserve"
  },
  storage = {
    directory = vim.fn.stdpath("data") .. "/super-project",
  },
  startup = {
    fallback = "last", -- "last" or "empty"
    defer_when_dashboard = false,
  },
  sessions = {
    scope = "project", -- "project" or "branch"
    filetype_delay_ms = 200,
    exclude = {
      directories = { vim.fn.expand("~"), "/tmp" },
      filetypes = {
        "ccc-ui", "dap-repl", "dap-view", "dap-view-term",
        "gitcommit", "gitrebase", "qf", "toggleterm",
      },
      buftypes = {},
    },
  },
  terminals = {
    keep_alive = true,
  },
  integrations = {
    neo_tree = true,
    super_tree = true,
    barbar = true,
  },
  selector = {
    backend = "builtin", -- "builtin", "telescope", "fzf-lua", or "snacks"
    forget_bindings = { insert = "<C-d>", normal = "d" },
    display = {
      project_details = true,
      git_state = true,
      fetch_remote = false,
      hidden_entries = true,
    },
    backend_options = {},
  },
  logging = {
    level = "warn", -- "off", "error", "warn", "info", or "debug"
  },
}
```

Unknown keys are rejected instead of being silently interpreted as options
from another project manager.

### Project discovery

`discovery.roots` accepts directories and Neovim glob patterns. On startup and
after an external working-directory change, `observe_git_cwd` runs
`git rev-parse --show-toplevel` and records the returned worktree root. A CWD
inside a repository therefore registers its root, not the nested directory.
Linked worktrees are independent projects.

`discovery.excludes` applies to configured, Git-observed, persisted, and
directly opened candidates. Canonically equivalent paths are deduplicated.

### Sessions and terminals

Switching A → B captures A's tabs and split trees, protects its buffers with
`bufhidden=hide`, and removes its windows. Returning B → A rebuilds those
windows around the same buffer IDs.

Parked file and terminal buffers remain loaded but become unlisted, so normal
bufferline plugins show only the active project's buffers. Their original
listed state returns with the workspace. Internal layout buffers are unlisted
and discarded, so repeated switches do not accumulate `[No Name]` entries.

For terminal buffers, this means:

- the same job, process, channel, and scrollback remain in memory;
- output continues while the project is parked;
- no command or input is resent when the project returns.

This guarantee lasts only for the current Neovim process. Neovim remains the
parent of terminal jobs and ends them when the editor exits. If a saved terminal
job has exited or its buffer is gone, Super Project opens a fresh default
`:terminal` in that leaf. Cold sessions do the same after restoring terminal
window placement and local directories.

Cold state never stores or reruns the prior command, arguments, environment,
output, process/channel ID, or job ID. Use tmux, zellij, systemd, or another
external process owner when jobs themselves must survive Neovim.

With `sessions.scope = "branch"`, a worktree has a separate workspace for each
branch or detached HEAD. Git is required for this mode.

### Optional integrations

- **neo-tree:** saves whether the filesystem source was open, expanded
  directories, selection, and width.
- **Super Tree:** saves the tree root, open state, expanded directories,
  selection, hidden-entry state, Buffers/Projects pane visibility, and pane
  dimensions. Its Projects pane lists and opens Super Project workspaces.
- **barbar:** saves project buffer order and pin state.

Enabled integrations are feature-detected. Closed or absent explorers are not
loaded during setup. A cold payload that says an explorer was open may load it
on demand to restore that state.

## Commands

| Command | Description |
| --- | --- |
| `:SuperProjectFind [source\|recent\|name\|path]` | Select from every accepted project using the requested order |
| `:SuperProjectRecent` | Select from recent projects |
| `:SuperProjectOpen [directory]` | Register and open a directory, or browse from the current directory when omitted |
| `:SuperProjectPrevious [count]` | Return to an earlier project |
| `:SuperProjectForget [path]` | Remove history and cold sessions without killing live jobs |

The Telescope extension is named `super-project`:

```lua
require("telescope").load_extension("super-project")
require("telescope").extensions["super-project"].find()
require("telescope").extensions["super-project"].recent()
```

## Lua API and events

```lua
local projects = require("super-project")

projects.projects({ order = "recent" })
projects.current()
projects.open("~/projects/example")
projects.browse(vim.fn.getcwd())
projects.previous(1)
projects.forget("~/projects/example", true)
```

The directory browser lists `Open this directory`, `../`, and child
directories. Selecting a child or parent navigates; selecting the first entry
registers and opens the displayed directory. It uses `vim.ui.select`, so any
configured UI-select enhancement applies.

User events:

- `SuperProjectSwitchPre` / `SuperProjectSwitchPost`
- `SuperProjectSavePre` / `SuperProjectSavePost`
- `SuperProjectLoadPre` / `SuperProjectLoadPost`
- `SuperProjectRegistryChanged`

Event data contains source, target, project, result, or error fields as
applicable.

## Storage

By default, state is under `stdpath("data")/super-project`:

```text
registry.json
sessions/<workspace-hash>.vim
sessions/<workspace-hash>.json
super-project.log
```

The `.vim` file is a terminal-command-free native Neovim session containing
inert layout placeholders. The JSON sidecar contains declarative integration
state plus terminal placement/CWD metadata; it never stores prior commands or
runtime window IDs. Writes are atomic.

## Migrating from neovim-project

Super Project does not read old setup keys or state automatically.

| neovim-project | Super Project |
| --- | --- |
| `projects` | `discovery.roots` |
| `ignore_projects` | `discovery.excludes` |
| `datapath` | `storage.directory` |
| `last_session_on_startup` | `startup.fallback` |
| `dashboard_mode` | `startup.defer_when_dashboard` |
| `filetype_autocmd_timeout` | `sessions.filetype_delay_ms` |
| `follow_symlinks` | `discovery.symlinks` |
| `per_branch_sessions` | `sessions.scope` |
| `session_manager_opts.autosave_ignore_*` | `sessions.exclude.*` |
| `forget_project_keys` | `selector.forget_bindings` |
| `picker.type` | `selector.backend` |
| `picker.preview` | `selector.display` |
| `picker.opts` | `selector.backend_options` |
| `debug_logging = true` | `logging.level = "debug"` |

Remove Neovim Session Manager from the dependency list unless it is configured
independently. Existing neovim-project files are left untouched; Super Project
creates fresh state as projects are observed and opened.

## Diagnostics and development

Run `:checkhealth super-project` for the Neovim, Git, selector, and storage
status. Set `logging.level = "debug"` for a transaction log that omits terminal
commands and environment values.

Run tests with:

```sh
make test
```

The real Super Tree contract test uses `../super-tree.nvim` by default. Set
`SUPER_TREE_ROOT=/path/to/super-tree.nvim` when it is checked out elsewhere.
