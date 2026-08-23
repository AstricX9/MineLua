-- Streaming and block editing on the spherical grid: the two things that make
-- it a world you can play in rather than a patch you can look at.

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
local GridRuntime = require("grid_runtime")
local blocks = require("blocks")

local stubUv = {u0 = 0.0, v0 = 0.0, u1 = 0.25, v1 = 0.25}
for _, definition in pairs(blocks.list) do
  definition.uvs = {top = stubUv, bottom = stubUv, side = stubUv}
  definition.colors = definition.colors or {top = {1, 1, 1}, bottom = {1, 1, 1}, side = {1, 1, 1}}
end

local planet = Planet.new()
local world = GridWorld.new(planet, 1)
local grid = world.grid

local uploaded, released = {}, 0
local runtime = GridRuntime.new(world, {
  radius = 3,
  upload = function(key, vertices) uploaded[key] = #vertices end,
  release = function(key) uploaded[key] = nil released = released + 1 end
})

-- Stand on dry land at the spawn meridian.
local up = {0.0, 0.0, 1.0}
local surfaceRadius = world:surfaceRadius(up[1], up[2], up[3])
local position = {up[1] * surfaceRadius, up[2] * surfaceRadius, up[3] * surfaceRadius}

runtime:refocus(position)
local frames = 0
while not runtime:ready() and frames < 400 do
  runtime:update(position)
  frames = frames + 1
end
assert(runtime:ready(), "the ring around the player loads within a sane number of frames")
-- Drain the mesh queue.
for _ = 1, 200 do runtime:update(position) end

local meshCount = 0
for _ in pairs(uploaded) do meshCount = meshCount + 1 end
print(string.format("loaded in %d frames: %d chunks, %d meshes", frames, world:chunkCount(), meshCount))
assert(world:chunkCount() > 0 and meshCount > 0, "the runtime generated and meshed terrain")

-- 1. Budgeting. No single update may do an unbounded amount of work, or
--    walking into new ground would stall the frame instead of costing a slice.
local before = world:chunkCount()
runtime.pendingIndex = 1
local generated, meshed = runtime:update(position)
assert(generated <= runtime.stackBudget, "stack generation respects its budget")
assert(meshed <= runtime.meshBudget, "meshing respects its budget")

-- 2. Raycast finds the ground under the player and reports the block above it.
local eye = {up[1] * (surfaceRadius + 3.0), up[2] * (surfaceRadius + 3.0), up[3] * (surfaceRadius + 3.0)}
local hit = world:raycast(eye, {-up[1], -up[2], -up[3]}, 8.0)
assert(hit, "the ray finds ground below")
assert(hit.previous, "and reports the empty voxel in front of it, for placing")
assert(hit.previous.layer == hit.layer + 1,
  string.format("the placement slot is directly above the hit (%d against %d)",
    hit.previous.layer, hit.layer))
local hitId = world:blockAtVoxel(hit.face, hit.column, hit.row, hit.layer)
assert(hitId ~= 0, "the hit voxel is solid")
assert(world:blockAtVoxel(hit.previous.face, hit.previous.column, hit.previous.row,
  hit.previous.layer) == 0, "the placement slot is empty")

-- 3. Breaking. The voxel goes away, and its chunk is queued for remeshing.
local brokenKey = GridWorld.chunkKey(hit.face,
  math.floor(hit.column / 16), math.floor(hit.row / 16), math.floor(hit.layer / 16))
local sizeBefore = uploaded[brokenKey]
assert(runtime:setBlock(hit.face, hit.column, hit.row, hit.layer, blocks.air or 0),
  "breaking reports a change")
assert(world:blockAtVoxel(hit.face, hit.column, hit.row, hit.layer) == 0, "the block is gone")
assert(runtime.dirty[brokenKey], "and its chunk is queued for remeshing")
for _ = 1, 20 do runtime:update(position) end
assert(uploaded[brokenKey] ~= sizeBefore or sizeBefore == nil,
  "the chunk was remeshed after the edit")

-- 4. Placing puts it back.
assert(runtime:setBlock(hit.face, hit.column, hit.row, hit.layer, blocks.stone),
  "placing reports a change")
assert(world:blockAtVoxel(hit.face, hit.column, hit.row, hit.layer) == blocks.stone,
  "the block is back")
-- Setting the same value again is not a change.
assert(not runtime:setBlock(hit.face, hit.column, hit.row, hit.layer, blocks.stone),
  "setting a voxel to what it already is does nothing")

-- 5. Placing in open air works, even where generation stored no chunk.
local skyLayer = hit.layer + 30
assert(runtime:setBlock(hit.face, hit.column, hit.row, skyLayer, blocks.stone),
  "a block can be placed in open sky")
assert(world:blockAtVoxel(hit.face, hit.column, hit.row, skyLayer) == blocks.stone,
  "and it is there afterwards")

-- 6. Streaming follows the player. Walk far enough to change the centre stack
--    and the far side must be dropped, not accumulated forever.
local chunksBefore = world:chunkCount()
local walked = position
for stepIndex = 1, 12 do
  -- About 16 m a step, tangentially.
  local east = planet:tangentFrame(walked)
  walked = {
    walked[1] + east[1] * 16.0, walked[2] + east[2] * 16.0, walked[3] + east[3] * 16.0
  }
  for _ = 1, 60 do runtime:update(walked) end
end
print(string.format("after walking ~190 m: %d chunks, %d meshes released",
  world:chunkCount(), released))
assert(released > 0, "stacks behind the player are released")
assert(world:chunkCount() < chunksBefore * 4,
  string.format("the loaded set stays bounded (%d against %d at the start)",
    world:chunkCount(), chunksBefore))

print("grid runtime tests passed")
