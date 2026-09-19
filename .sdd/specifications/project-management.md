---
feature: project-management
created: 2026-09-18
updated: 2026-09-18
---

# Project management

| Created | Updated |
| --- | --- |
| 2026-09-18 | 2026-09-18 |

## Purpose

Project discovery, identity, history, selection, and activation behavior.

## Requirements

### Discovery and identity

The system SHALL discover projects from configured paths and glob patterns and,
when enabled, from the Git worktree containing the effective working directory
at startup or after an external directory change. A directory inside a Git
worktree SHALL identify the worktree root, and linked worktrees SHALL be
independent projects.

All configured, observed, persisted, and directly opened candidates SHALL pass
through the same existence, directory, exclusion, canonicalization, and
deduplication rules. Canonically equivalent paths SHALL represent one project
while retaining a user-friendly display path. Asynchronous Git observations
SHALL NOT register stale working directories.

### Manual opening and browsing

`open(directory)` and `:SuperProjectOpen [directory]` SHALL register, persist,
and activate an existing non-excluded directory even when it was not previously
known.

GIVEN `:SuperProjectOpen` has no directory argument
WHEN the command is invoked
THEN a hierarchical browser SHALL allow navigation from the effective working
directory and activation of the displayed directory.

### Registry and selection

Accepted Git observations and manually opened projects SHALL persist in a
registry with recency. The system SHALL support source, recency, name, and path
ordering and SHALL expose equivalent selection and forgetting behavior through
the builtin, Telescope, fzf-lua, and Snacks selectors.

Forgetting a project SHALL remove its persisted history and cold sessions but
SHALL NOT terminate its live jobs. Registry, recency, and active-project
changes SHALL emit the documented Super Project events.

### Public interface

The system SHALL provide the documented `SuperProject` commands, the
`super-project` Telescope extension, and Lua methods for listing projects,
reading the current project, opening a project, browsing directories, returning
to a previous project, and forgetting a project.

## Change history

| Date | Change |
| --- | --- |
| 2026-09-18 | Initial specification from create-super-project-plugin |
