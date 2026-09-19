---
feature: workspace-sessions
created: 2026-09-18
updated: 2026-09-18
---

# Workspace sessions

| Created | Updated |
| --- | --- |
| 2026-09-18 | 2026-09-18 |

## Purpose

Hot workspace switching, terminal continuity, and safe cold-session behavior.

## Requirements

### Independent workspaces

Each project SHALL retain independent tabs, split layouts, views, current
window, regular buffers, modified buffers, terminal buffers, and supported
integration state. Parked buffers SHALL remain loaded but unlisted and SHALL
regain their prior listed state when restored. Internal transition buffers
SHALL NOT accumulate as listed `[No Name]` buffers.

When `sessions.scope = "branch"`, workspace identity SHALL include the current
branch or detached HEAD and SHALL switch when that identity changes.

### Transactional switching

A switch SHALL validate its target before changing the active workspace, save
and park the source, restore a live or cold target, update the effective working
directory and history, and emit save, load, and switch events in deterministic
order. A failed switch SHALL restore a usable source workspace without deleting
protected buffers or jobs.

### Live terminals

GIVEN a visible project terminal has a running job
WHEN its workspace is parked and later restored in the same Neovim process
THEN the same terminal buffer and job/channel SHALL be restored, output SHALL
continue while parked, and no command or input SHALL be resent.

If a captured terminal buffer or job no longer exists, its leaf SHALL receive a
fresh terminal running Neovim's default shell.

### Cold sessions

Cold sessions SHALL restore non-terminal session state and terminal leaf
placement and local directories. Each restored terminal leaf SHALL run a fresh
default shell.

Persisted state SHALL NOT contain or rerun a terminal's prior command,
arguments, environment, output, process ID, channel ID, or job ID. Terminal
continuity SHALL be guaranteed only while the same Neovim process remains
alive and the terminal buffer has not been explicitly deleted.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-18 | Initial specification from create-super-project-plugin |
