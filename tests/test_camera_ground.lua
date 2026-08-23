-- The player standing still must stay still.
--
-- Ground contact is a downward ray from the eye that used to be reported at the
-- resolution of its 0.04 m scan step. Gravity then pulled the eye down a few
-- millimetres per frame while the snap could only push it back in whole steps,
-- so a motionless player rose 4 cm, sank for about thirteen frames and rose
-- again. This drives the real camera against a real generated chunk and asserts
-- the residual motion is sub-millimetre.

package.path = "src/?.lua;" .. package.path

-- glfw is only reached for input polling here, and there is no window in a
-- headless run. The stub reports every control released.
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

local planet = Planet.new()
local world = World.new({planet = planet, seed = 7, chunkRadius3D = 1, deferInitialChunks = true})

local spawn = world:surfacePosition({0.0, 0.0, 1.0}, 3.0)
local cx, cy, cz = World.chunkCoord(spawn[1]), World.chunkCoord(spawn[2]), World.chunkCoord(spawn[3])
for dz = -2, 1 do
  for dy = -1, 1 do
    for dx = -1, 1 do world:createChunk(cx + dx, cy + dy, cz + dz) end
  end
end

local camera = Camera.new({planet = planet, position = spawn})
camera.heading = select(3, planet:tangentFrame(camera.position))

local dt = 1.0 / 60.0
-- Let the fall settle before measuring.
for _ = 1, 240 do camera:updateMovement(dt, nil, world) end

local function altitude()
  return planet:distanceVoxels(camera.position)
end

assert(camera.grounded, "camera settles onto generated ground")

local settled = altitude()
local lowest, highest = settled, settled
for _ = 1, 600 do
  camera:updateMovement(dt, nil, world)
  local a = altitude()
  if a < lowest then lowest = a end
  if a > highest then highest = a end
end

local excursion = highest - lowest
print(string.format("standing excursion over 600 frames: %.6f m", excursion))
assert(excursion < 0.001,
  string.format("a motionless player must not oscillate (saw %.4f m)", excursion))

-- The refined contact must still agree with the block boundary it came from,
-- and must not drift below the surface.
local distance = camera:groundDistance(world)
assert(distance, "ground is found under a settled camera")
assert(math.abs(distance - camera.eyeHeight) < 0.05,
  string.format("eye sits at eye height above contact (saw %.4f)", distance))

print("camera ground tests passed")
