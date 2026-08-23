-- Standing on the spherical grid.
--
-- Physics only ever asks the world about points now, so this checks that a
-- grid-backed world answers those questions correctly, and then drives the real
-- camera against it: a player dropped above the ground must land on it, stay
-- put, and walk without sinking or bouncing.

package.path = "src/?.lua;" .. package.path

local stub = {GLFW_PRESS = 1, GLFW_RELEASE = 0}
setmetatable(stub, {__index = function(_, key)
  if key:match("^GLFW_") then return 0 end
  return function() return 0 end
end})
stub.glfwGetCursorPos = function(_, x, y) x[0] = 0.0 y[0] = 0.0 end
package.loaded.glfw = stub

local Planet = require("planet")
local GridWorld = require("grid_world")
local Camera = require("camera")
local blocks = require("blocks")

local planet = Planet.new()
local world = GridWorld.new(planet, 1)
local grid = world.grid
local CHUNK = GridWorld.CHUNK_SIZE

-- Somewhere on dry land, away from the seams and the sheared corners.
local chunkCount = math.floor(grid.resolution / CHUNK)
local face, chunkColumn, chunkRow
for candidateFace = 1, 6 do
  for i = 1, 7 do
    for j = 1, 7 do
      if not face then
        local column = math.floor(chunkCount * i / 8)
        local row = math.floor(chunkCount * j / 8)
        local samples = world:columnSamples(candidateFace, column, row)
        if samples.lowRadius - planet.radiusVoxels > 8.0 then
          face, chunkColumn, chunkRow = candidateFace, column, row
        end
      end
    end
  end
end
assert(face, "found dry land to stand on")

-- Generate a patch around it.
local made = 0
for dr = -2, 2 do
  for dc = -2, 2 do
    made = made + world:ensureStack(face, chunkColumn + dc, chunkRow + dr)
  end
end
print(string.format("patch: %d chunks over 5x5 column stacks", made))
assert(made > 0, "the patch generated something")

-- 1. Address round trip: the centre of a voxel must resolve back to it.
local column = chunkColumn * CHUNK + 8
local row = chunkRow * CHUNK + 8
for _, layer in ipairs({-40, -1, 0, 12, 97}) do
  local x, y, z = grid:voxelCenter(face, column, row, layer, planet.center)
  local backFace, backColumn, backRow, backLayer = world:locatePoint(x, y, z)
  assert(backFace == face and backColumn == column and backRow == row and backLayer == layer,
    string.format("voxel (%d,%d,%d,%d) round trips, got (%s,%s,%s,%s)",
      face, column, row, layer, tostring(backFace), tostring(backColumn),
      tostring(backRow), tostring(backLayer)))
end

-- 2. Solidity agrees with the generator: above the surface is air, below is not.
local samples = world:columnSamples(face, chunkColumn, chunkRow)
local sample = require("grid_terrain").sampleAt(samples, 8, 8)
local surfaceRadius = sample.surfaceRadiusVoxels
local dx, dy, dz = grid:columnDirection(face, column, row)
local function pointAt(radius)
  return planet.center[1] + dx * radius, planet.center[2] + dy * radius, planet.center[3] + dz * radius
end
assert(not world:isSolidAtPoint(pointAt(surfaceRadius + 3.0)), "three metres up is air")
assert(world:isSolidAtPoint(pointAt(surfaceRadius - 0.5)), "half a metre down is ground")
assert(world:hasCollisionAtPoint(pointAt(surfaceRadius)), "the patch reports itself loaded")

-- 3. Drop the real camera onto it. This is the physics path, unchanged: it
--    only sees the grid through isSolidAtPoint and hasCollisionAtPoint.
local spawnRadius = surfaceRadius + 6.0
local spawnX, spawnY, spawnZ = pointAt(spawnRadius)
local camera = Camera.new({planet = planet, position = {spawnX, spawnY, spawnZ}})
camera.heading = select(3, planet:tangentFrame(camera.position))

local dt = 1.0 / 60.0
for _ = 1, 300 do camera:updateMovement(dt, nil, world) end
assert(camera.grounded, "the player lands on grid terrain and stays on it")

local landedRadius = planet:distanceVoxels(camera.position)
local standingHeight = landedRadius - surfaceRadius
print(string.format("landed %.3f m above the surface (eye height %.2f m)", standingHeight, camera.eyeHeight))
assert(standingHeight > camera.eyeHeight - 0.6 and standingHeight < camera.eyeHeight + 0.6,
  string.format("standing at about eye height above the ground, saw %.3f m", standingHeight))

-- 4. And having landed, they stay still.
local low, high = landedRadius, landedRadius
for _ = 1, 400 do
  camera:updateMovement(dt, nil, world)
  local radius = planet:distanceVoxels(camera.position)
  low, high = math.min(low, radius), math.max(high, radius)
end
local excursion = high - low
print(string.format("standing excursion on the grid: %.6f m", excursion))
assert(excursion < 0.001,
  string.format("a motionless player does not bob on the grid either (saw %.4f m)", excursion))

-- 5. Outside the generated patch the ground reads as missing, not as air, so a
--    walker stops at the edge instead of falling through it.
local farColumn = (chunkColumn + 40) * CHUNK
local fx, fy, fz = grid:voxelCenter(face, farColumn, row, 0, planet.center)
assert(not world:hasCollisionAtPoint(fx, fy, fz), "beyond the patch is unloaded, not empty")

print("grid world tests passed")
