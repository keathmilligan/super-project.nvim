# Sandbox

Open these trees in the containerized Neovim (`./tests/env/run.sh`).
Each git project is initialized as its own repo at container start.
`loose/` is left without Git.

| Tree | Open | Features |
| --- | --- | --- |
| [alpha](alpha/README.md) | `src/main.lua` | Splits, unsaved buffers, `:terminal` |
| [beta](beta/README.md) | `lib/client.lua` | Second app; switch away from alpha |
| [gamma](gamma/README.md) | `src/app/init.lua` | Nested tree; branch `feature/search` |
| [notes](notes/README.md) | `inbox.md` | Non-code workspace |
| [loose](loose/README.md) | `scratch.txt` | Configured root, no Git |
| [archive](archive/README.md) | — | Excluded; hidden from `:SuperProjectFind` |

Keymaps in the container: `<leader>pf` find, `<leader>pr` recent,
`<leader>pp` previous, `<leader>po` browse, `<leader>px` forget.
