-- Line buffering, so a run that is killed on a timeout still leaves its log.
io.stdout:setvbuf("line")

local debugger = require("debugger")
local game = require("game")

debugger.addIssue("Game started. Initializing...")
debugger.printIssues()

-- Headless smoke-run switches. None of these are reachable from the game UI;
-- they exist so a launch from a script can generate a world, run it, and hand
-- back frames to look at, instead of stopping at the title screen.
--
--   --world [seed]                     skip the menus into a generated world
--   --time <hour>                      hold the sun at that solar hour
--   --teleport <lat,lon,altitude>      start somewhere other than spawn
--   --look sun                         aim the camera at the sun
--   --devmenu                          open the developer navigation panel
--   --screenshot <seconds,...> <path>  write a PPM per listed time, then quit
--
-- Example:
--   lib/luajit.exe src/main.lua --world 1 --time 10 --screenshot 8,20 shots/frame
--
-- Every branch states how many arguments it consumed. An earlier version let
-- one of them fall through without advancing, and the parser span forever
-- before the window was ever created.
local OPTIONS = {
  ["--world"] = function(value)
    game.autoStartWorld = tonumber(value) or true
    return tonumber(value) and 1 or 0
  end,
  ["--devmenu"] = function()
    game.openDevMenu = true
    return 0
  end,
  ["--teleport"] = function(value)
    local latitude, longitude, altitude = tostring(value):match("([^,]+),([^,]+),([^,]+)")
    game.startTeleport = latitude and {tonumber(latitude), tonumber(longitude), tonumber(altitude)}
    return 1
  end,
  ["--time"] = function(value)
    game.forceTimeOfDay = tonumber(value)
    return 1
  end,
  ["--look"] = function(value)
    game.lookAt = value
    return 1
  end,
  ["--screenshot"] = function(times, prefix)
    game.screenshotSchedule = {}
    local order = 0
    for value in tostring(times):gmatch("[^,]+") do
      local at = tonumber(value)
      if at then
        order = order + 1
        game.screenshotSchedule[order] = {
          at = at,
          path = string.format("%s_%02d.ppm", prefix or "frame", order)
        }
      end
    end
    game.exitAfterScreenshots = true
    return 2
  end
}

local index = 1
while index <= #arg do
  local handler = OPTIONS[arg[index]]
  index = index + 1 + (handler and handler(arg[index + 1], arg[index + 2]) or 0)
end

local ok, err = pcall(game.run)
if not ok then
  print("Error: " .. tostring(err))
end

if game.exitAfterScreenshots then
  return
end

print("Press Enter to exit...")
io.read()
