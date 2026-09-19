local config = require("app.config")

local function start()
  return { name = config.name, env = config.env }
end

return {
  start = start,
}
