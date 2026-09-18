---
id: create-super-project-plugin
status: review
features: [project-management, workspace-sessions, configuration, integrations]
created: 2026-09-17
updated: 2026-09-18
---

# Create the Super Project Neovim plugin

| Created | Updated |
| --- | --- |
| 2026-09-17 | 2026-09-18 |

## What

### Why

`coffebar/neovim-project` provides project history, configured project
discovery, pickers, and disk-backed Neovim sessions. Its session switching
deletes the current buffers before loading another session. For terminal
buffers, that ends the attached jobs; restoring a session starts replacement
terminal processes rather than preserving the originals.

Super Project will provide equivalent project-management capabilities through
its own interface while adding automatic Git project registration and
terminal-aware, in-process workspaces. A program running in a project terminal
can continue running while another project is active and reappear in the same
terminal buffer when the user returns.

### Requirements

#### Capability parity and native interface

- Super Project SHALL provide functional counterparts for the reference
  plugin's configured discovery, ignore filtering, recent history, project
  selection, ordering, forgetting, startup restoration, disk sessions,
  per-branch sessions, previews, and debug logging.
- Users SHALL configure the plugin through
  `require("super-project").setup(opts)` and a Super Project-specific nested
  schema. The `neovim-project` setup module and its configuration keys SHALL
  NOT be aliases.
- Project commands and Telescope exports SHALL use the `SuperProject` and
  `super-project` namespaces. Legacy command and extension aliases SHALL NOT
  be provided.
- Telescope, fzf-lua, Snacks, and `vim.ui.select` SHALL be supported picker
  choices with equivalent project-selection capabilities.
- Super Project SHALL use its own events and storage layout. Existing
  `neovim-project` configuration and state SHALL NOT be consumed implicitly.
- The reference plugin's advertised neo-tree expanded-directory and barbar
  buffer-order restoration capabilities SHALL have native counterparts.
- When `super-tree.nvim` is available, Super Project SHALL preserve its
  project-specific tree root, visibility, expanded directories, selected path,
  hidden-file state, auxiliary pane visibility, and user-adjusted pane
  dimensions.
- The Super Tree Projects pane SHALL be able to list, identify, and switch
  Super Project workspaces through a native provider API, without
  `neovim-project` module aliases.
- Documentation SHALL provide a clear capability and configuration migration
  map for users moving from `coffebar/neovim-project`.

#### Dependencies and integrations

- Neovim 0.10 or later SHALL be the only hard runtime dependency. The plugin
  SHALL NOT require Plenary or Neovim Session Manager.
- Git SHALL be an external feature dependency when
  `discovery.observe_git_cwd` is enabled or `sessions.scope = "branch"`.
- Telescope, fzf-lua, and Snacks SHALL be optional dependencies installed only
  when selected as the project's selector backend. The builtin selector SHALL
  require no picker plugin.
- neo-tree, Super Tree, and barbar SHALL remain optional, feature-detected
  integrations and SHALL NOT be installed solely for workspace payload
  support.
- Dependencies SHALL be documented in plugin-manager installation examples,
  not declared inside `require("super-project").setup(opts)`. Setup validation
  SHALL report unavailable required features, while a missing optional picker
  SHALL warn and fall back to the builtin selector.

#### Project registration and discovery

- Paths and glob patterns in `discovery.roots` SHALL add explicit project
  candidates.
- `:SuperProjectOpen [directory]` and `open(directory)` SHALL accept an
  existing, non-excluded directory even when it is not already registered,
  persist it as a manual project, and activate it.
- Invoking `:SuperProjectOpen` without a directory SHALL show a hierarchical
  directory browser rooted at the effective CWD.
- On startup and after an effective working-directory change, the plugin SHALL
  determine whether the current directory is inside a Git worktree. If so, it
  SHALL register the worktree root as a project.
- Git worktrees SHALL be treated as independent project roots. A subdirectory
  inside a worktree SHALL resolve to the worktree root rather than becoming a
  separate project.
- `discovery.excludes` SHALL be evaluated before any configured, Git-observed,
  or historical candidate is exposed or activated. Excluded paths SHALL not
  be added to history by automatic discovery.
- Canonically equivalent paths SHALL be deduplicated while preserving a
  user-friendly display path, including configured symlink spelling where
  applicable.
- Git-observed projects SHALL persist in project history, participate in
  discovery and sorting, and be available in later Neovim processes.
- Git checks caused by directory changes SHALL not block the editor, and stale
  asynchronous results SHALL not register a directory that is no longer
  current.

#### Project and session switching

- Each project SHALL have an independent workspace containing its tabs,
  regular windows, buffers, views, and current-window selection.
- Switching away from a project SHALL keep its buffers loaded in the current
  Neovim process, including modified buffers, rather than deleting them.
- Buffers owned by a parked project SHALL become unlisted so bufferline UIs
  show only the active workspace, then regain their prior listed state when
  that workspace returns.
- Internal transition and layout-construction buffers SHALL never remain as
  listed `[No Name]` buffers after a switch.
- Switching back to a live workspace SHALL restore its prior tab and split
  layout using the same surviving buffer instances.
- Non-terminal session state and command-free terminal leaf placement SHALL be
  saved when leaving a project and restored on a cold load or later start.
- When `sessions.scope = "branch"`, the workspace and cold session key SHALL
  include the Git branch or detached HEAD identity and switch automatically
  when that identity changes.
- A failed switch SHALL leave the current project usable or roll it back from
  the captured live workspace. Switching SHALL reject missing and ignored
  targets without disturbing the current workspace.
- Project switches SHALL update history and emit documented Super Project
  events in deterministic order.

#### Live terminal preservation

- A terminal buffer with a running job that belongs to the active project
  SHALL be hidden, not unloaded, wiped, or recreated, when that project is
  parked.
- The job SHALL continue to run and produce output while its project is in the
  background.
- Returning to the project SHALL place the same terminal buffer back into its
  former window position. Its terminal job/channel identity SHALL be unchanged
  and the plugin SHALL NOT resend its command or input.
- If a captured terminal leaf no longer has a running job when restored, the
  plugin SHALL replace it with a fresh terminal running Neovim's default shell
  rather than presenting the exited process as restored.
- Cold sessions SHALL retain the tab/split placement and local directory of
  visible terminal leaves, then open a fresh default terminal in each leaf.
- Disk state SHALL NOT contain the prior terminal command, arguments,
  environment, output, process ID, channel ID, or job ID. A cold load SHALL NOT
  pretend that a process survived a Neovim exit or rerun its prior command.
- Terminal continuity is guaranteed only for the lifetime of one Neovim
  process and for terminal buffers that have not been explicitly deleted by
  the user or another plugin.

#### Quality and documentation

- Automated tests SHALL cover the capability matrix, native configuration,
  path and exclusion rules, Git discovery, history, hot and cold switching,
  rollback, per-branch keys, optional explorer state, and real terminal-job
  continuity.
- Terminal integration tests SHALL verify that the same running job remains
  alive across an A → B → A switch, that a missing job produces a fresh default
  terminal, and that cold loading restores terminal leaves without rerunning a
  prior command.
- User documentation SHALL explain installation, the native configuration,
  commands, picker integrations, migration from the reference plugin, and the
  boundary between project switching and a full Neovim exit.

### Scope

- **In:** a production-ready Lua plugin, configured and Git-observed projects,
  recent history, project pickers, disk-backed command-free sessions with
  fresh terminal leaves, per-branch workspaces, same-process terminal
  preservation, a native setup
  schema and command namespace, neo-tree/Super Tree/barbar adapters, the small
  public state and provider hooks required in `../super-tree.nvim`, migration
  documentation, tests, README, and Vim help.
- **Out:** keeping jobs alive after Neovim itself exits, tmux/zellij or remote
  process integration, cloning or creating repositories, recursively scanning
  arbitrary disks for repositories, deleting project directories, and a
  guarantee for floating or plugin-managed terminal UIs that explicitly wipe
  their own buffers. Drop-in API, command, configuration, event, and on-disk
  compatibility with `neovim-project` are also out of scope.

### Open questions

- None. Approval confirms that terminal continuity is scoped to project
  switches within one Neovim process; cross-process continuity requires an
  external process manager and is outside this change.

## How

### Approach

Build a clean Lua implementation with a native configuration and command
surface, a canonical project registry, asynchronous Git observation, a
transactional switch coordinator, an in-memory workspace store, and
command-free cold sessions. A lazy-safe integration layer will capture and
restore plugin-owned UI state outside the generic window serializer.
The switch coordinator will temporarily protect workspace buffers with
`bufhidden=hide`, capture and remove the visible project layout, and later
rebuild that layout around the same buffer IDs. Native sessions will persist
only cold-restorable state and will never serialize prior terminal commands.

See [the design narrative](../design/create-super-project-plugin.md) for the
capability baseline, native configuration, component boundaries, switch
sequence, storage model, and failure handling.

### Impacted specifications

- `project-management` (new)
- `workspace-sessions` (new)
- `configuration` (new)
- `integrations` (new)
- `window` (existing in `../super-tree.nvim`)

### Plan

#### 1. Plugin foundation and configuration

- [x] 1.1 Create the Lua plugin, test, documentation, and formatting
  structure with a Neovim 0.10 minimum-version guard.
- [x] 1.2 Implement and validate the native nested schema for discovery,
  storage, startup, sessions, terminals, selection, integrations, and logging.
- [x] 1.3 Add an idempotent `require("super-project").setup(opts)` entrypoint
  without legacy setup or option aliases.
- [x] 1.4 Add native debug logging and diagnostics without taking control of a
  separately configured Session Manager installation.
- [x] 1.5 Add dependency and feature detection, actionable validation errors,
  and builtin-selector fallback for an unavailable optional picker.

#### 2. Project registry and Git discovery

- [x] 2.1 Implement path expansion, canonical identity, display paths,
  symlink policy, glob expansion, and exact deduplication.
- [x] 2.2 Implement `discovery.excludes` matching as a common gate for every
  project source and activation path.
- [x] 2.3 Implement the native project-history store with atomic writes,
  external-change reloads, pruning, sorting, and forget operations.
- [x] 2.4 Implement non-shell Git root and branch queries, including worktrees,
  detached HEAD, unavailable Git, and malformed repositories.
- [x] 2.5 Observe startup and `DirChanged` with debouncing and generation guards,
  then persist accepted Git roots without recursively reacting to plugin
  directory changes.

#### 3. Workspace and cold-session engines

- [x] 3.1 Define runtime workspace, tab, split-tree, window, buffer, and terminal
  reference models.
- [x] 3.2 Capture all managed tab layouts, window views, local directories,
  current selections, and live buffer IDs without changing user state.
- [x] 3.3 Park a workspace through a transition window while temporarily
  protecting buffers from unload/wipe, and track terminal ownership through
  `TermOpen` and `TermClose`.
- [x] 3.4 Reconstruct tabs and split trees from a live snapshot, restore views
  and buffer-local hide policy, and tolerate buffers that ended or were
  explicitly deleted while parked.
- [x] 3.5 Save command-free native cold sessions with inert visible-terminal
  placeholders, without capturing hidden buffers from other projects, and
  restore all temporary editor options even when saving fails.
- [x] 3.6 Load native cold sessions without invoking a buffer-deleting session
  engine or executing serialized terminal entries.
- [x] 3.7 Implement branch-aware session keys and a debounced Git HEAD watcher
  compatible with regular repositories and worktrees.
- [x] 3.8 Preserve each workspace buffer's listed state, unlist it while
  parked, and dispose internal layout placeholders after restoration.
- [x] 3.9 Persist inert terminal-leaf placeholders and local directories, then
  replace them with fresh default terminals on cold or missing-job restoration.

#### 4. Transactional switching and startup

- [x] 4.1 Implement guarded A → B switching with target validation, save and
  capture, park, hot/cold target restore, CWD update, event emission, and
  history commit.
- [x] 4.2 Add rollback for capture, save, layout reconstruction, and session
  load failures without deleting protected buffers or terminal jobs.
- [x] 4.3 Implement startup rules for arguments, dashboards, current Git or
  configured projects, and optional last-session loading.
- [x] 4.4 Emit documented `SuperProjectSavePre/Post`,
  `SuperProjectLoadPre/Post`, and `SuperProjectSwitchPre/Post` events and
  implement configured delayed `FileType` behavior.

#### 5. Optional integrations

- [x] 5.1 Define a lazy-safe integration adapter lifecycle for capture,
  suspension, hot restoration, cold payload serialization, and cleanup.
- [x] 5.2 Implement neo-tree visibility and expanded-directory restoration
  without requiring neo-tree to be installed or eagerly loaded.
- [x] 5.3 Add stable `capture_state`, `restore_state`, and project-provider
  hooks to `../super-tree.nvim` while preserving its existing standalone and
  `neovim-project` behavior.
- [x] 5.4 Implement the Super Tree adapter and provider so its UI state is
  restored per workspace and its Projects pane uses the Super Project registry
  and switch coordinator.
- [x] 5.5 Implement barbar buffer-order capture and restoration when barbar is
  loaded.
- [x] 5.6 Keep existing terminal windows from triggering Super Tree's
  editor-recovery split while retaining their exclusion as file-open targets.

#### 6. Commands, pickers, and capability parity

- [x] 6.1 Implement the native `SuperProject` commands, argument completion,
  recent navigation, validation, sorting, and project forgetting.
- [x] 6.2 Implement the builtin, Telescope, fzf-lua, and Snacks picker adapters
  with configurable forget mappings and equivalent selection behavior.
- [x] 6.3 Implement the `super-project` Telescope extension and project
  previews, including configured hidden-file and Git-status behavior.
- [x] 6.4 Verify every reference capability has a native counterpart using a
  feature matrix, without adding legacy API or configuration aliases.
- [x] 6.5 Let `SuperProjectOpen` register an arbitrary directory and provide a
  builtin directory browser when no argument is supplied.

#### 7. Verification and documentation

- [x] 7.1 Add unit tests for configuration, canonical paths, exclusions,
  registry union, sorting and persistence, Git results, and session keys.
- [x] 7.2 Add headless Neovim integration tests for layouts, modified buffers,
  hot/cold switches, startup, event order, failure rollback, and branch changes.
- [x] 7.3 Add explorer integration tests for neo-tree and Super Tree hot/cold
  state restoration, lazy loading, missing plugins, and Super Tree project
  selection.
- [x] 7.4 Add a real terminal heartbeat test that proves buffer, channel, and
  process identity survive A → B → A, plus fresh-terminal and sentinel tests
  proving missing/cold jobs restore leaves without rerunning prior commands.
- [x] 7.5 Add CI across the minimum and current stable Neovim versions, Lua
  formatting/static checks, and deterministic test cleanup.
- [x] 7.6 Write `README.md` and Vim help covering installation, configuration,
  hard and optional dependencies, commands, migration, troubleshooting, and
  terminal lifetime semantics.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-17 | Initial proposal |
| 2026-09-17 | Reframed drop-in compatibility as capability parity with a native configuration and API |
| 2026-09-17 | Clarified hard, feature, and optional dependencies and where users declare them |
| 2026-09-17 | Added native Super Tree state restoration and project-provider integration alongside neo-tree |
| 2026-09-17 | Proposal approved; implementation started |
| 2026-09-17 | Implementation completed; moved to review |
| 2026-09-17 | Fixed review defect where native-session scratch cleanup could abort loading with E517 |
| 2026-09-17 | Fixed review defect where Super Tree created an editor split despite existing terminal windows |
| 2026-09-18 | Isolated parked buffers from bufferline UIs and stopped hot restores from accumulating listed placeholders |
| 2026-09-18 | Extended SuperProjectOpen with manual directory registration and a no-argument directory browser |
| 2026-09-18 | Restored missing and cold terminal leaves with fresh default shells while keeping prior commands out of persisted state |
