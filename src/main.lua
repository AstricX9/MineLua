local debugger = require("debugger")
local game = require("game")

debugger.addIssue("Game started. Initializing...")
debugger.printIssues()

local ok, err = pcall(game.run)
if not ok then
  print("Error: " .. tostring(err))
end

print("Press Enter to exit...")
io.read()
