package.path = "src/?.lua;src/?/init.lua;" .. package.path

local blocks = require("blocks")
local Chunk = require("chunk")
local DistantTerrain = require("distant_terrain")

local function ensureRenderData(id)
  local def = assert(blocks.list[id], "test block exists")
  def.color = def.color or {1, 1, 1}
  def.colors = def.colors or {
    top = {1, 1, 1}, bottom = {1, 1, 1}, side = {1, 1, 1}
  }
  def.uvs = def.uvs or {
    top = {u0 = 0, v0 = 0, u1 = 1, v1 = 1},
    bottom = {u0 = 0, v0 = 0, u1 = 1, v1 = 1},
    side = {u0 = 0, v0 = 0, u1 = 1, v1 = 1}
  }
end

ensureRenderData(blocks.grass)
ensureRenderData(blocks.dirt)

local function generatedEntry(chunkX, chunkZ)
  local chunk = Chunk.new()
  for z = 0, 15 do
    for x = 0, 15 do
      local top = x < 8 and 4 or 8
      for y = 0, top - 1 do chunk:setBlock(x, y, z, blocks.dirt) end
      chunk:setBlock(x, top, z, blocks.grass)
      chunk:setSkyLight(x, top + 1, z, 15)
    end
  end
  -- Actual chunk water, not a procedural predicate, owns this LOD surface.
  for z = 0, 3 do
    for x = 0, 3 do
      chunk:setBlock(x, 6, z, blocks.water)
      chunk.waterSurface = chunk.waterSurface or {}
      chunk.waterSurface[x + z * 16 + 1] = 5.65
    end
  end
  return {
    chunk = chunk,
    chunkX = chunkX,
    chunkZ = chunkZ,
    offsetX = chunkX * 16,
    offsetZ = chunkZ * 16,
    dataRevision = 0
  }
end

local ok = pcall(DistantTerrain.capture, nil, 31, blocks.water, blocks.water_still)
assert(not ok, "LOD capture rejects absent chunks")

local entry = generatedEntry(3, -2)
local record = DistantTerrain.capture(entry, 31, blocks.water, blocks.water_still)
assert(record.source == "generated_chunk", "LOD retains generated-chunk provenance")
assert(record.heights[1] == 5 and record.heights[9] == 9, "captured heights come from voxel data")
assert(record.waterSurface[1] == 5.65, "captured water comes from the chunk")

local vertices, waterVertices = DistantTerrain.build(record, 2, {maxHeight = 31})
assert(#vertices > 0 and #vertices % DistantTerrain.TERRAIN_STRIDE == 0,
  "captured columns build a terrain LOD")
assert(#waterVertices > 0 and #waterVertices % DistantTerrain.WATER_STRIDE == 0,
  "captured water builds a far water LOD")
assert(#vertices < 16 * 16 * 6 * 6 * DistantTerrain.TERRAIN_STRIDE,
  "LOD is smaller than a naive full voxel surface")

-- A missing coordinate must complete the ordinary chunk job before any record
-- or mesh can exist. The fake world makes the yield boundary deterministic.
local fakeWorld = {chunks = {}, chunkRadius = 1, jobs = 0}
function fakeWorld:createChunkJob(chunkX, chunkZ)
  self.jobs = self.jobs + 1
  local job = {chunkX = chunkX, chunkZ = chunkZ}
  job.thread = coroutine.create(function()
    coroutine.yield(false)
    job.entry = generatedEntry(chunkX, chunkZ)
    self.chunks[chunkX .. "," .. chunkZ] = job.entry
  end)
  return job
end

local uploads, releases = 0, 0
local manager = DistantTerrain.new({
  radius = 2,
  generationSteps = 1,
  buildBudget = 1,
  frameBudgetMs = 1000,
  maxHeight = 31,
  waterId = blocks.water,
  stillWaterId = blocks.water_still,
  now = function() return 0 end,
  upload = function(captured, solid, water, bounds, step)
    uploads = uploads + 1
    return {count = #solid / 14, waterMesh = #water > 0 and {count = #water / 11} or nil,
      bounds = bounds, chunkX = captured.chunkX, chunkZ = captured.chunkZ, lodStep = step}
  end,
  release = function() releases = releases + 1 end
})

local nearQueue = {}
manager:update(fakeWorld, {}, nearQueue, 0, 0)
assert(fakeWorld.jobs == 1, "missing far terrain enters the normal chunk generator")
assert(next(manager.records) == nil and uploads == 0,
  "no LOD is synthesized while its chunk job is incomplete")

for _ = 1, 4 do manager:update(fakeWorld, {}, nearQueue, 0, 0) end
assert(next(manager.records) ~= nil and uploads > 0,
  "completed generated chunks are compacted and uploaded")
for _, captured in pairs(manager.records) do
  assert(captured.source == "generated_chunk", "every cached LOD has chunk provenance")
end

manager:clear()
assert(releases > 0, "clearing distant terrain releases its GPU representations")

-- A 128 setting represents the exact square radius, but scheduling itself must
-- stay lazy: allocating and sorting all 66,049 coordinates would freeze the
-- frame before generation had even begun.
manager:setRadius(128)
local wideStats = manager:update(fakeWorld, {}, {}, 0, 0)
assert(wideStats.radius == 128 and wideStats.total == 66040,
  "128 selects the full 257x257 square minus the 3x3 full-detail center")
assert(wideStats.scheduledThrough < 128 and #manager.queue < 2048,
  "large square ranges are scheduled progressively by ring")
manager:clear()

print("distant terrain passed: generated-chunk provenance, adaptive LOD, and no fake under-mesh")
