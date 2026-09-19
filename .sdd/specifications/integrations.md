---
feature: integrations
created: 2026-09-18
updated: 2026-09-18
---

# Integrations

| Created | Updated |
| --- | --- |
| 2026-09-18 | 2026-09-18 |

## Purpose

Optional selector, explorer, tree, and bufferline interoperability.

## Requirements

### Integration lifecycle

Enabled integrations SHALL be feature-detected and SHALL remain no-ops when
absent. Closed or absent integrations SHALL NOT be loaded during setup. A cold
workspace whose saved state says an enabled explorer was open MAY load that
explorer to restore it. An integration failure SHALL NOT invalidate the project
switch.

### Explorer state

The neo-tree integration SHALL preserve filesystem visibility, expanded
directories, selection, and width per workspace.

The Super Tree integration SHALL preserve tree root, open state, expanded
directories, selection, hidden-entry state, Buffers and Projects pane
visibility, pane selections, sidebar width, and pane heights per workspace.

### Super Tree project provider

When both plugins are available, Super Project SHALL register a native provider
through Super Tree's public API. The Projects pane SHALL list and identify Super
Project workspaces, switch them through the public `open` operation, and refresh
after registry or switch events without requiring a `neovim-project` module
alias.

### Barbar

When barbar is loaded, its project-visible buffer order and pin state SHALL be
preserved across workspace restoration. The integration SHALL NOT own or delete
those buffers.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-18 | Initial specification from create-super-project-plugin |
