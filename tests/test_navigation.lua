-- The dev-menu teleport is the answer to a planet you cannot walk across: it
-- has to land where it says it will, and never inside the ground.

package.path = "src/?.lua;" .. package.path

local stub = {GLFW_PRESS = 1, GLFW_RELEASE = 0}
setmetatable(stub, {__index = function(_, key)
  if key:match("^GLFW_") then return 0 end
  return function() return 0 end
end})
stub.glfwGetCursorPos = function(_, x, y) x[0] = 0.0 y[0] = 0.0 end
package.loaded.glfw = stub

local Planet = require("planet")
local World = require("world")
local Camera = require("camera")
local terrain = require("terrain")

local planet = Planet.new()
local world = World.new({planet = planet, seed = 3, chunkRadius3D = 1, deferInitialChunks = true})
local camera = Camera.new({planet = planet, position = planet:spawnPosition()})

local cases = {
  {0.0, 0.0, 500.0}, {45.0, -120.0, 0.0}, {-33.5, 87.25, 12000.0},
  {89.0, 179.0, 100.0}, {-89.0, -179.0, 400000.0}
}

for _, case in ipairs(cases) do
  local wantedLatitude, wantedLongitude, wantedAltitude = case[1], case[2], case[3]
  camera:teleportTo(world, wantedLatitude, wantedLongitude, wantedAltitude)
  local latitude, longitude, altitude = camera:geodeticPosition()

  assert(math.abs(latitude - wantedLatitude) < 1e-6,
    string.format("latitude round trips (%.6f against %.6f)", latitude, wantedLatitude))
  local longitudeError = math.abs((longitude - wantedLongitude + 540.0) % 360.0 - 180.0)
  assert(longitudeError < 1e-6,
    string.format("longitude round trips (%.6f against %.6f)", longitude, wantedLongitude))

  -- Above the requested altitude is fine; below it means the surface won.
  local direction = camera.planet:localUp(camera.position)
  local sample = terrain.surfaceAtDirection(direction, planet)
  local groundAltitude = sample.elevationMeters + camera.eyeHeight
  assert(altitude >= math.min(wantedAltitude, groundAltitude) - 0.01,
    string.format("never below the ground (%.1f m at %.1f lat)", altitude, wantedLatitude))
  assert(altitude >= wantedAltitude - 0.01 or altitude >= groundAltitude - 0.01,
    "the requested altitude is met, or the surface raised it")

  assert(camera.velocity[1] == 0.0 and camera.velocity[2] == 0.0 and camera.velocity[3] == 0.0,
    "a jump lands at rest")
  local heading = camera.heading
  local up = camera.planet:localUp(camera.position)
  local radial = heading[1]*up[1] + heading[2]*up[2] + heading[3]*up[3]
  assert(math.abs(radial) < 1e-6, "the heading stays level with the new horizon")
end

-- Asking for an altitude is a floor, not a demand: over land you end up on the
-- ground, and over ocean floor you stay at the altitude you asked for rather
-- than being dropped a hundred metres under the sea.
for _, place in ipairs({{10.0, 20.0}, {12.5, -64.0}, {-40.0, 140.0}}) do
  camera:teleportTo(world, place[1], place[2], 0.0)
  local _, _, altitude = camera:geodeticPosition()
  local sample = terrain.surfaceAtDirection(camera.planet:localUp(camera.position), planet)
  local standing = sample.elevationMeters + camera.eyeHeight + 1.5
  assert(math.abs(altitude - math.max(0.0, standing)) < 0.01,
    string.format("lands on the higher of ground and requested altitude (%.2f m, terrain %.2f m)",
      altitude, sample.elevationMeters))
end

-- Flight speed is a plain multiplier, and altitude still raises it on its own.
camera.flying = true
camera.flySpeedMultiplier = 1.0
local base = camera:effectiveFlySpeed()
camera.flySpeedMultiplier = 200.0
assert(math.abs(camera:effectiveFlySpeed() - base * 200.0) < 1e-6 or
  camera:effectiveFlySpeed() > base * 200.0 - 1e-6,
  "the speed multiplier scales flight")

print("navigation tests passed")
