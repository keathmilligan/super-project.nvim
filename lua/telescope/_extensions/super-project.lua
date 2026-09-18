local telescope = require("telescope")

return telescope.register_extension({
  exports = {
    find = function(options)
      require("super-project").find((options or {}).order or "source", options)
    end,
    recent = function(options)
      require("super-project").recent(options)
    end,
  },
})
