---
feature: configuration
created: 2026-09-18
updated: 2026-09-18
---

# Configuration

| Created | Updated |
| --- | --- |
| 2026-09-18 | 2026-09-18 |

## Purpose

Configuration, dependency, and compatibility boundaries for Super Project.

## Requirements

### Native setup

The plugin SHALL be configured through `require("super-project").setup(opts)`
using the documented `discovery`, `storage`, `startup`, `sessions`,
`terminals`, `integrations`, `selector`, and `logging` groups. Setup SHALL be
idempotent, SHALL validate option types and values, and SHALL reject unknown
keys.

The plugin SHALL require Neovim 0.10 or later. It SHALL NOT require Plenary or
Neovim Session Manager and SHALL NOT expose legacy `neovim-project` setup keys,
commands, events, module aliases, or storage compatibility.

### Feature dependencies

Git SHALL be required when branch-scoped sessions are configured. When Git is
unavailable, project-scoped sessions and configured project roots SHALL remain
usable, while Git-observed discovery SHALL be skipped with a warning.

Telescope, fzf-lua, Snacks, neo-tree, Super Tree, and barbar SHALL remain
optional and SHALL NOT be loaded merely by setup. If a selected external picker
is unavailable, the plugin SHALL warn and use the builtin selector.

### Diagnostics

The plugin SHALL provide health diagnostics and configurable logging. Logs
SHALL omit terminal commands and environment values.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-18 | Initial specification from create-super-project-plugin |
