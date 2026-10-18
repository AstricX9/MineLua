package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")
local Chunk = require("chunk")
local storage = require("chunk_storage")
local Workers = require("chunk_workers")
local World = require("world")

if ffi.os == "Windows" then
  ffi.cdef[[int _mkdir(const char *dirname);]]
  ffi.C._mkdir("world_cache")
  ffi.C._mkdir("world_cache\\chunk persistence test")
else
  ffi.cdef[[int mkdir(const char *path, unsigned int mode);]]
  ffi.C.mkdir("world_cache", tonumber("755", 8))
  ffi.C.mkdir("world_cache/chunk persistence test", tonumber("755", 8))
end

local root = "world_cache/chunk persistence test"
local options = {
  seed = 987654,
  maxHeight = 24,
  generatorType = "superflat",
  worldId = "earth",
  dataRevision = 17
}

local original = Chunk.new()
original:setBlock(0, 0, 0, 1)
original:setBlock(15, 255, 15, 42)
original:setBlock(7, 12, 9, 300)
original.waterSurface = {[1] = 62.65, [256] = 12.25}
original.environment = {
  biome = "persistence_test",
  averageElevation = 12.5,
  ocean = false,
  coast = true
}

assert(storage.save(root, -12, 34, original, options))
local restored, loadError, revision = storage.load(root, -12, 34, options)
assert(restored, loadError)
assert(restored:getBlock(0, 0, 0) == 1 and restored:getBlock(15, 255, 15) == 42 and
  restored:getBlock(7, 12, 9) == 300, "all voxel coordinates round trip")
assert(restored.waterSurface[1] == 62.65 and restored.waterSurface[256] == 12.25,
  "water surface data round trips")
assert(restored.environment.biome == "persistence_test" and
  restored.environment.averageElevation == 12.5 and restored.environment.coast == true and
  restored.environment.ocean == false, "chunk environment round trips")
assert(revision == 17, "chunk edit revision round trips")

-- World integration: a generated chunk is cached, an edit is autosave-ready,
-- and a later World instance can load it without calling terrain generation.
local firstWorld = World.new({
  savePath = root, seed = 13579, maxHeight = 24, generatorType = "superflat",
  worldId = "earth", chunkWorkerCount = 1, deferInitialChunks = true
})
firstWorld:createChunkSync(7, -3)
firstWorld:setBlock(7 * 16 + 5, 20, -3 * 16 + 6, 42)
assert(firstWorld:saveDirtyChunks() == 1, "edited world chunk is flushed")
firstWorld:close()

local terrain = require("terrain")
local originalFillChunk = terrain.fillChunk
terrain.fillChunk = function() error("cached chunk unexpectedly regenerated") end
local secondWorld = World.new({
  savePath = root, seed = 13579, maxHeight = 24, generatorType = "superflat",
  worldId = "earth", chunkWorkerCount = 1, deferInitialChunks = true
})
local cachedEntry = secondWorld:createChunkSync(7, -3)
terrain.fillChunk = originalFillChunk
assert(cachedEntry.chunk:getBlock(5, 20, 6) == 42 and cachedEntry.dataRevision >= 1,
  "joining a world reuses the edited persistent chunk")
secondWorld:close()

-- Far LOD jobs load real voxels without spending main-thread time on lighting.
-- Promotion reuses the same entry and completes lighting incrementally before
-- the normal streamer can mesh it.
local promotionWorld = World.new({
  savePath = root, seed = 13579, maxHeight = 24, generatorType = "superflat",
  worldId = "earth", chunkWorkerCount = 1, deferInitialChunks = true
})
local farJob = promotionWorld:createChunkJob(7, -3, {deferLighting = true})
assert(coroutine.resume(farJob.thread))
assert(coroutine.status(farJob.thread) == "dead" and farJob.entry and
  farJob.entry.hasInitialLight == false, "far chunk handoff defers flood lighting")
local promoted = promotionWorld:requireChunkLighting(farJob)
local promotionSteps = 0
while coroutine.status(promoted.thread) ~= "dead" do
  assert(coroutine.resume(promoted.thread))
  promotionSteps = promotionSteps + 1
end
assert(promoted.entry and promoted.entry.hasInitialLight == true and promotionSteps > 1,
  "near promotion incrementally lights the existing far chunk")
promotionWorld:close()

-- This exercises the real Windows worker/process path. Both jobs are submitted
-- before either is polled, proving the pool can have generation in flight at once.
local workers = Workers.new(root, {workerCount = 2})
if workers:count() > 0 then
  local generatedOptions = {
    seed = 2468,
    maxHeight = 24,
    generatorType = "default",
    worldId = "earth"
  }
  local jobs = {
    workers:submit(40, 50, generatedOptions),
    workers:submit(41, 50, generatedOptions)
  }
  assert(jobs[1] and jobs[2], "parallel chunk jobs submit")
  local deadline = os.time() + 20
  local complete = 0
  local seen = {}
  while complete < #jobs and os.time() <= deadline do
    for i = 1, #jobs do
      if not seen[i] then
        local done, failed = workers:poll(jobs[i])
        if done then
          assert(not failed, "chunk worker exits successfully")
          seen[i], complete = true, complete + 1
        end
      end
    end
  end
  assert(complete == #jobs, "parallel chunk workers finish before timeout")
  assert(storage.load(root, 40, 50, generatedOptions), "first worker chunk is persisted")
  assert(storage.load(root, 41, 50, generatedOptions), "second worker chunk is persisted")
  workers:close()
end

print("chunk persistence and worker tests passed")
