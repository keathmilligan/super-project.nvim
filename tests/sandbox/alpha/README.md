# Alpha

Small Lua app. Open splits, edit without saving, and start a terminal
before switching to beta.

- [src/main.lua](src/main.lua)
- [src/util.lua](src/util.lua)

```vim
:edit src/main.lua
:rightbelow vsplit src/util.lua
:terminal
```

Then `:SuperProjectFind` and open beta. The terminal job should keep
producing output until you return with `:SuperProjectPrevious`.
