local util = require("util")

local function greet(name)
  return util.format("alpha says hello to %s", name or "world")
end

return {
  greet = greet,
}
