# Isolated Neovim test environment

A container with its own Neovim (no host `~/.config/nvim`) and Git.
The plugin is bind-mounted so you test the working tree.

## Commands

From the repository root:

```sh
./tests/env/run.sh          # interactive nvim in /workspace
./tests/env/run.sh nvim alpha/README.md
./tests/env/run.sh test     # headless unit tests
./tests/env/run.sh health   # :checkhealth super-project
./tests/env/run.sh shell    # bash in the container
./tests/env/run.sh build    # rebuild the image
```

`docker` is used when present, otherwise `podman`.

## Workspace projects

On start the container copies `tests/sandbox/` to `/workspace` and
`git init`s the project trees (except `loose/`):

| Path | What to exercise |
| --- | --- |
| `alpha/` | Splits, modified buffers, live `:terminal` |
| `beta/` | Switch target; layout should not leak from alpha |
| `gamma/` | Nested files; picker shows `feature/search` |
| `notes/` | Non-code workspace |
| `loose/` | Configured root with no Git metadata |
| `archive/` | Excluded; must not appear in `:SuperProjectFind` |

Those copies are ephemeral (`docker run --rm`). Edit fixtures in
`tests/sandbox/` on the host to keep changes.

## Suggested session

1. `<leader>pf` (`:SuperProjectFind`) — alpha, beta, gamma, notes, loose;
   not archive
2. Open alpha, split `src/main.lua` and `src/util.lua`, start `:terminal`
3. Switch to beta — the alpha terminal job keeps running
4. `<leader>pp` (`:SuperProjectPrevious`) — same terminal buffer returns
5. `:SuperProjectOpen` to browse; `:SuperProjectForget` to drop history

Debug transactions go to `stdpath("data")/super-project/super-project.log`
inside the throwaway `HOME`.

## Isolation

- `NVIM_APPNAME=super-project-test` and a throwaway `HOME` under `/tmp`
- Host plugins and `packpath` are not loaded
- Neovim comes from the official `v0.12.5` tarball inside the image
- Optional neo-tree, Super Tree, and barbar integrations are disabled
