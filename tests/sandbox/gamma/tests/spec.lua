local app = require("app.init")
local started = app.start()
assert(started.name == "gamma")
