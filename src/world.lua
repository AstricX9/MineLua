local Chunk = require("chunk")
local ChunkStorage = require("chunk_storage")
local ChunkWorkers = require("chunk_workers")
local blocks = require("blocks")
local lighting = require("lighting")
local terrain = require("terrain")
local worldProfiles = require("world_profiles")
local showcase = require("showcase")

local World = {}
World.__index = World

local CHUNK_SIZE = 16
local SIDE_NEIGHBOURS = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

function World.new(options)
  options = options or {}

  local self = setmetatable({}, World)
  self.chunks = {}
  self.chunkRadius = options.chunkRadius or 4
  self.maxHeight = options.maxHeight or 24
  self.generatorType = options.generatorType or "default"
  self.worldId = worldProfiles.id(options.worldId)
  self.worldProfile = worldProfiles.get(self.worldId)
  self.superflatLayers = options.superflatLayers
  self.seed = options.seed or 1
  self.savePath = options.savePath
  self.semiBlockingChunks = options.semiBlockingChunks ~= false
  self.dirtyChunks = {}
  self.chunkWorkers = ChunkWorkers.new(self.savePath, {
    workerCount = options.chunkWorkerCount
  })
  self.lightDirty = false
  self.lightRevision = 0
  self.lightingJob = nil
  self.lightingJobRevision = nil
  -- Chunks whose sky light changed since the renderer last drained this set.
  self.lightTouched = {}

  if not options.deferInitialChunks then
    self:ensureChunksAroundBlock(0, 0)
  end

  return self
end

function World.chunkCoord(value)
  return math.floor(value / CHUNK_SIZE)
end

function World.chunkKey(chunkX, chunkZ)
  return chunkX .. "," .. chunkZ
end

function World:storageOptions(extra)
  return ChunkStorage.options(self, extra)
end

function World:finishInitialLighting(entry, step)
  lighting.lightChunk(self, entry, self.lightTouched, step)
  entry.hasInitialLight = true
  entry.hasInitialLighting = true
  entry.lightRevision = self.lightRevision

  -- A newly playable chunk changes its neighbours' boundary faces and ambient
  -- occlusion, which the mesher reads across the border.
  for i = 1, #SIDE_NEIGHBOURS do
    local side = SIDE_NEIGHBOURS[i]
    local key = World.chunkKey(entry.chunkX + side[1], entry.chunkZ + side[2])
    local neighbour = self.chunks[key]
    if neighbour then self.lightTouched[key] = neighbour end
  end
  return entry
end

function World:finishChunk(chunk, chunkX, chunkZ, generationOptions, dataRevision)
  local offsetX = chunkX * CHUNK_SIZE
  local offsetZ = chunkZ * CHUNK_SIZE
  generationOptions = generationOptions or {}

  local entry = {
    chunk = chunk,
    environment = chunk.environment,
    chunkX = chunkX,
    chunkZ = chunkZ,
    offsetX = offsetX,
    offsetZ = offsetZ,
    hasTerrain = true,
    hasCollision = true,
    serverReady = true,
    hasInitialLight = false,
    hasInitialLighting = false,
    hasMesh = false,
    hasGPUBuffer = false,
    isUploaded = false,
    renderReady = false,
    lightRevision = nil,
    -- Incremented by voxel edits so a compact distant-terrain record can prove
    -- whether it still represents this exact generated chunk.
    dataRevision = dataRevision or 0
  }

  self.chunks[World.chunkKey(chunkX, chunkZ)] = entry

  -- Far-only chunks are compacted into an LOD record immediately. Flood-lighting
  -- those voxels on the render thread is wasted work; promotion to the playable
  -- ring calls requireChunkLighting before a mesh can be built.
  if not generationOptions.deferLighting then
    self:finishInitialLighting(entry, generationOptions.yieldStep)
  end

  return entry
end

function World:createChunk(chunkX, chunkZ, generationOptions)
  local offsetX = chunkX * CHUNK_SIZE
  local offsetZ = chunkZ * CHUNK_SIZE
  local options = self:storageOptions()
  local chunk, loadError, dataRevision = ChunkStorage.load(
    self.savePath, chunkX, chunkZ, options)

  if loadError then
    io.stderr:write(string.format("Unable to load chunk %d,%d: %s; regenerating it\n",
      chunkX, chunkZ, tostring(loadError)))
  end
  if not chunk then
    chunk = Chunk.new()
    generationOptions = generationOptions or {}
    generationOptions.generatorType = self.generatorType
    generationOptions.superflatLayers = self.superflatLayers
    generationOptions.seed = self.seed
    generationOptions.worldId = self.worldId
    terrain.setWorldProfile(self.worldId)
    terrain.setSeed(self.seed)
    terrain.fillChunk(chunk, offsetX, offsetZ, CHUNK_SIZE, CHUNK_SIZE, self.maxHeight, generationOptions)

    if self.savePath then
      local saved, saveError = ChunkStorage.save(self.savePath, chunkX, chunkZ, chunk, options)
      if not saved then
        io.stderr:write(string.format("Unable to save generated chunk %d,%d: %s\n",
          chunkX, chunkZ, tostring(saveError)))
      end
    end
  end

  -- Environment metadata is reproducible and is much smaller to recompute than
  -- the full density/material pass. Voxel and water data come from the cache.
  if not chunk.environment then
    terrain.setWorldProfile(self.worldId)
    terrain.setSeed(self.seed)
    chunk.environment = terrain.chunkEnvironmentAt(offsetX, offsetZ, CHUNK_SIZE, CHUNK_SIZE, self.maxHeight)
  end
  return self:finishChunk(chunk, chunkX, chunkZ, generationOptions, dataRevision)
end

function World:createChunkJob(chunkX, chunkZ, jobOptions)
  jobOptions = jobOptions or {}
  local job = {
    chunkX = chunkX,
    chunkZ = chunkZ,
    entry = nil,
    deferLighting = jobOptions.deferLighting == true
  }

  local options = self:storageOptions()
  if self.savePath and not ChunkStorage.exists(self.savePath, chunkX, chunkZ, options) then
    job.workerJob = self.chunkWorkers:submit(chunkX, chunkZ, options)
  end

  job.thread = coroutine.create(function()
    if job.workerJob then
      while true do
        local done = self.chunkWorkers:poll(job.workerJob)
        if done then break end
        coroutine.yield(false)
      end
      -- A failed worker falls through to createChunk's synchronous fallback.
    end
    job.entry = self:createChunk(chunkX, chunkZ, {
      -- Read this at completion time: a far job can be promoted while its
      -- worker is still running.
      deferLighting = job.deferLighting,
      yieldStep = function()
        coroutine.yield(false)
      end
    })
    return true
  end)

  return job
end

function World:requireChunkLighting(item)
  if not item then return item end
  -- An unfinished far job can simply change course before createChunk installs
  -- its entry. Its existing coroutine remains the single owner of generation.
  if item.thread and not item.entry then
    item.deferLighting = false
    return item
  end

  local entry = item.entry or item
  if entry.hasInitialLight then return item end
  local job = item.entry and item or {
    chunkX = entry.chunkX,
    chunkZ = entry.chunkZ
  }
  job.entry = nil
  job.deferLighting = false
  job.thread = coroutine.create(function()
    self:finishInitialLighting(entry, function() coroutine.yield(false) end)
    job.entry = entry
    return true
  end)
  return job
end

function World:createChunkSync(chunkX, chunkZ)
  return self:createChunk(chunkX, chunkZ, {
    generatorType = self.generatorType,
    superflatLayers = self.superflatLayers
  })
end

function World:chunkWorkerCount()
  return self.chunkWorkers and self.chunkWorkers:count() or 0
end

function World:prioritizeChunkJob(job)
  return self.chunkWorkers and job and self.chunkWorkers:prioritize(job.workerJob) or false
end

function World:saveChunk(entry)
  if not self.savePath or not entry or not entry.chunk then return false end
  local saved, err = ChunkStorage.save(self.savePath, entry.chunkX, entry.chunkZ,
    entry.chunk, self:storageOptions({dataRevision = entry.dataRevision or 0}))
  if saved then
    self.dirtyChunks[World.chunkKey(entry.chunkX, entry.chunkZ)] = nil
  else
    io.stderr:write(string.format("Unable to save chunk %d,%d: %s\n",
      entry.chunkX, entry.chunkZ, tostring(err)))
  end
  return saved
end

function World:saveDirtyChunks()
  local saved = 0
  local pending = {}
  for key, entry in pairs(self.dirtyChunks) do pending[#pending + 1] = {key, entry} end
  for i = 1, #pending do
    if self:saveChunk(pending[i][2]) then saved = saved + 1 end
  end
  return saved
end

function World:close()
  self:saveDirtyChunks()
  if self.chunkWorkers then self.chunkWorkers:close() end
end

function World:ensureChunksAroundBlock(x, z)
  local centerChunkX = World.chunkCoord(x)
  local centerChunkZ = World.chunkCoord(z)
  local added = {}

  for chunkX = centerChunkX - self.chunkRadius, centerChunkX + self.chunkRadius do
    for chunkZ = centerChunkZ - self.chunkRadius, centerChunkZ + self.chunkRadius do
      local key = World.chunkKey(chunkX, chunkZ)
      if not self.chunks[key] then
        added[#added + 1] = self:createChunk(chunkX, chunkZ)
      end
    end
  end

  return added
end

function World:eachChunk(fn)
  for _, entry in pairs(self.chunks) do
    fn(entry.chunk, entry)
  end
end

-- Developer world-generation preview reset. GPU meshes and queued jobs are
-- owned by game.lua; this clears only the generated voxel/light state so the
-- same World instance can be repopulated around the current camera.
function World:clearGeneratedChunks()
  self:saveDirtyChunks()
  self.chunks = {}
  self.lightDirty = false
  self.lightRevision = self.lightRevision + 1
  self.lightingJob = nil
  self.lightingJobRevision = nil
  self.lightTouched = {}
end

function World:markLightDirty()
  self.lightDirty = true
  self.lightRevision = self.lightRevision + 1
end

function World:markLightingReady()
  self:eachChunk(function(chunk, entry)
    entry.hasInitialLight = true
    entry.hasInitialLighting = true
    entry.lightRevision = self.lightRevision
  end)
end

function World:rebuildLighting(options)
  local revision = self.lightRevision
  lighting.rebuild(self, options)
  if self.lightRevision == revision then
    self.lightDirty = false
    self:markLightingReady()
  end
end

function World:ensureLighting()
  if self.lightDirty then
    self:rebuildLighting()
  end
end

function World:lightingReady()
  return not self.lightDirty and not self.lightingJob
end

function World:startLightingJob()
  if self.lightingJob then
    return
  end

  self.lightingJobRevision = self.lightRevision
  self.lightingJob = coroutine.create(function()
    lighting.rebuild(self, {
      yieldStep = function()
        coroutine.yield(false)
      end
    })
    return true
  end)
end

function World:stepLightingJob(budget)
  budget = budget or 8
  if self.lightDirty and not self.lightingJob then
    self:startLightingJob()
  end

  if not self.lightingJob then
    return true
  end

  local steps = 0
  while self.lightingJob and steps < budget do
    local ok, err = coroutine.resume(self.lightingJob)
    if not ok then
      error(err)
    end

    steps = steps + 1
    if coroutine.status(self.lightingJob) == "dead" then
      if self.lightRevision == self.lightingJobRevision then
        self.lightDirty = false
        self:markLightingReady()
      else
        self.lightDirty = true
      end
      self.lightingJob = nil
      self.lightingJobRevision = nil
      break
    end
  end

  return self:lightingReady()
end

function World:getChunkAtBlock(x, z)
  local chunkX = World.chunkCoord(x)
  local chunkZ = World.chunkCoord(z)

  return self.chunks[World.chunkKey(chunkX, chunkZ)]
end

function World:localBlockCoord(x, z)
  local chunkX = World.chunkCoord(x)
  local chunkZ = World.chunkCoord(z)

  return x - chunkX * CHUNK_SIZE, z - chunkZ * CHUNK_SIZE, chunkX, chunkZ
end

function World:containsBlock(x, z)
  return self:getChunkAtBlock(x, z) ~= nil
end

function World:hasCollisionAtBlock(x, z)
  local entry = self:getChunkAtBlock(x, z)
  return entry ~= nil and entry.hasCollision == true
end

function World:blockAt(x, y, z)
  if y < 0 or y > 255 then
    return nil
  end

  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  return entry.chunk:getBlock(localX, y, localZ)
end

function World:setBlock(x, y, z, id)
  if y < 0 or y > 255 then
    return nil
  end

  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  -- Capture the sky column before the write so the update can tell which cells
  -- actually gained or lost direct sky.
  local beforeColumn = lighting.directSkyColumn(self, x, z)
  local oldBlockId = entry.chunk:getBlock(localX, y, localZ)
  local oldRed, oldGreen, oldBlue = entry.chunk:getBlockLight(localX, y, localZ)
  entry.chunk:setBlock(localX, y, localZ, id)
  entry.dataRevision = (entry.dataRevision or 0) + 1
  self.dirtyChunks[World.chunkKey(entry.chunkX, entry.chunkZ)] = entry
  lighting.applyBlockChange(self, x, y, z, beforeColumn, self.lightTouched,
    oldBlockId, oldRed, oldGreen, oldBlue)

  return entry
end

-- Returns the chunks whose light changed since the last call, and clears the set.
function World:drainLightTouched()
  local touched = self.lightTouched
  self.lightTouched = {}
  return touched
end

function World:skyLightAt(x, y, z)
  if y > self.maxHeight then
    return 15
  end
  if y < 0 then
    return 0
  end

  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return 15
  end

  local localX, localZ = self:localBlockCoord(x, z)
  return entry.chunk:getSkyLight(localX, y, localZ)
end

function World:blockLightAt(x, y, z)
  if y < 0 or y > self.maxHeight then return 0, 0, 0 end
  local entry = self:getChunkAtBlock(x, z)
  if not entry then return 0, 0, 0 end
  local localX, localZ = self:localBlockCoord(x, z)
  return entry.chunk:getBlockLight(localX, y, localZ)
end

-- Block sampler bound to the 3x3 chunk neighbourhood, in world coordinates.
-- The mesher must see across chunk borders: without it every chunk treats its
-- neighbours as empty air, which emits the whole boundary wall as hidden
-- geometry and computes ambient occlusion as if a void sat next to it.
-- Missing neighbours still read as air, so an edge chunk meshes as it does now
-- and is remeshed once the neighbour arrives.
function World:blockSampler(chunkX, chunkZ)
  local neighbours = {}
  for dz = -1, 1 do
    for dx = -1, 1 do
      neighbours[dz * 3 + dx] = self.chunks[World.chunkKey(chunkX + dx, chunkZ + dz)]
    end
  end

  local baseX = chunkX * CHUNK_SIZE
  local baseZ = chunkZ * CHUNK_SIZE
  local floor = math.floor

  return function(x, y, z)
    if y < 0 or y > 255 then
      return 0
    end

    local lx = x - baseX
    local lz = z - baseZ
    local cx = floor(lx / CHUNK_SIZE)
    local cz = floor(lz / CHUNK_SIZE)

    if cx < -1 or cx > 1 or cz < -1 or cz > 1 then
      return self:blockAt(x, y, z) or 0
    end

    local entry = neighbours[cz * 3 + cx]
    if not entry then
      return 0
    end

    return entry.chunk:getBlock(lx - cx * CHUNK_SIZE, y, lz - cz * CHUNK_SIZE)
  end
end

-- Returns a sky-light sampler bound to the 3x3 chunk neighbourhood around
-- (chunkX, chunkZ). The mesher takes about 24 light samples per face, and going
-- through skyLightAt for each one rebuilds a "x,z" string key every time; this
-- resolves the chunks once and indexes them arithmetically.
function World:skyLightSampler(chunkX, chunkZ)
  local neighbours = {}
  for dz = -1, 1 do
    for dx = -1, 1 do
      neighbours[dz * 3 + dx] = self.chunks[World.chunkKey(chunkX + dx, chunkZ + dz)]
    end
  end

  local baseX = chunkX * CHUNK_SIZE
  local baseZ = chunkZ * CHUNK_SIZE
  local maxHeight = self.maxHeight
  local floor = math.floor

  return function(x, y, z)
    if y > maxHeight then
      return 15
    end
    if y < 0 then
      return 0
    end

    local lx = x - baseX
    local lz = z - baseZ
    local cx = floor(lx / CHUNK_SIZE)
    local cz = floor(lz / CHUNK_SIZE)

    if cx < -1 or cx > 1 or cz < -1 or cz > 1 then
      -- The mesher never samples this far out, but stay correct if it ever does.
      return self:skyLightAt(x, y, z)
    end

    local entry = neighbours[cz * 3 + cx]
    if not entry then
      return 15
    end

    return entry.chunk:getSkyLight(lx - cx * CHUNK_SIZE, y, lz - cz * CHUNK_SIZE)
  end
end

-- RGB block-light counterpart to skyLightSampler. The bound neighbourhood
-- keeps smooth corner samples cheap at chunk boundaries.
function World:blockLightSampler(chunkX, chunkZ)
  local neighbours = {}
  for dz = -1, 1 do
    for dx = -1, 1 do
      neighbours[dz * 3 + dx] = self.chunks[World.chunkKey(chunkX + dx, chunkZ + dz)]
    end
  end

  local baseX, baseZ = chunkX * CHUNK_SIZE, chunkZ * CHUNK_SIZE
  local maxHeight, floor = self.maxHeight, math.floor
  return function(x, y, z)
    if y < 0 or y > maxHeight then return 0, 0, 0 end
    local lx, lz = x - baseX, z - baseZ
    local cx, cz = floor(lx / CHUNK_SIZE), floor(lz / CHUNK_SIZE)
    if cx < -1 or cx > 1 or cz < -1 or cz > 1 then
      return self:blockLightAt(x, y, z)
    end
    local entry = neighbours[cz * 3 + cx]
    if not entry then return 0, 0, 0 end
    return entry.chunk:getBlockLight(lx - cx * CHUNK_SIZE, y, lz - cz * CHUNK_SIZE)
  end
end

function World:isSolidBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then
    return false
  end

  local def = blocks.list[id]
  return def and def.properties and def.properties.solid
end

function World:isProtectedBlock(x, y, z)
  return self.generatorType == "showcase" and showcase.isProtectedBlock(x, y, z)
end

function World:collisionHeightAt(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then return 0.0 end
  local def = blocks.list[id]
  local properties = def and def.properties
  if not properties or not properties.solid then return 0.0 end
  return math.max(0.0,math.min(1.0,tonumber(properties.collisionHeight) or 1.0))
end

function World:isLiquidBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then return false end
  local def = blocks.list[id]
  return def and def.properties and def.properties.liquid == true
end

function World:isWaterBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  return id == blocks.water or (blocks.water_still and id == blocks.water_still)
end

-- Returns the rendered surface of the liquid column containing `aroundY`.
-- Generated rivers, lakes, and oceans record their exact local surface on the
-- chunk. Edited/placed liquid falls back to the same top-column convention the
-- water mesher uses.
function World:waterSurfaceAt(x, z, aroundY)
  local entry = self:getChunkAtBlock(x, z)
  if not entry then return nil end
  local localX, localZ = self:localBlockCoord(x, z)
  local columnIndex = localX + localZ * CHUNK_SIZE + 1
  local stored = entry.chunk.waterSurface and entry.chunk.waterSurface[columnIndex]
  if stored then return stored end

  local probeY = math.floor(aroundY or self.maxHeight or 255)
  if not self:isWaterBlock(x, probeY, z) then return nil end
  local top = probeY
  local maxHeight = self.maxHeight or 255
  while top < maxHeight and self:isWaterBlock(x, top + 1, z) do top = top + 1 end
  return top - 0.35
end

function World:isPointSubmerged(position)
  if not position then return false end
  local x, y, z = position[1], position[2], position[3]
  local blockX, blockY, blockZ = math.floor(x), math.floor(y), math.floor(z)
  if not self:isWaterBlock(blockX, blockY, blockZ) then return false end
  local surface = self:waterSurfaceAt(blockX, blockZ, y)
  return surface ~= nil and y < surface
end

function World:isRaycastTargetBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then
    return false
  end

  local def = blocks.list[id]
  local properties = def and def.properties
  return properties and (properties.solid or properties.targetable or properties.breakable or properties.replaceable) and not properties.liquid
end

function World:raycast(origin, direction, maxDistance, step)
  step = step or 0.08
  maxDistance = maxDistance or 6.0

  local previous = nil
  local distance = 0.0
  while distance <= maxDistance do
    local x = origin[1] + direction[1] * distance
    local y = origin[2] + direction[2] * distance
    local z = origin[3] + direction[3] * distance
    local blockX = math.floor(x)
    local blockY = math.floor(y)
    local blockZ = math.floor(z)

    local targetId=self:blockAt(blockX,blockY,blockZ)
    local targetDefinition=targetId and blocks.list[targetId]
    local targetProperties=targetDefinition and targetDefinition.properties
    local targetHeight=math.max(0.0,math.min(1.0,
      tonumber(targetProperties and (targetProperties.collisionHeight or targetProperties.renderHeight)) or 1.0))
    if self:isRaycastTargetBlock(blockX, blockY, blockZ) and
        (targetHeight >= 1.0 or y <= blockY + targetHeight) then
      return {
        x = blockX,
        y = blockY,
        z = blockZ,
        id = self:blockAt(blockX, blockY, blockZ),
        previous = previous,
        distance = distance
      }
    end

    previous = {x = blockX, y = blockY, z = blockZ}
    distance = distance + step
  end

  return nil
end

function World:surfaceYAt(x, z)
  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  for y = self.maxHeight, 0, -1 do
    local id = entry.chunk:getBlock(localX, y, localZ)
    if id and id ~= 0 then
      local def = blocks.list[id]
      if def and def.properties and def.properties.solid then
        return y + math.max(0.0,math.min(1.0,
          tonumber(def.properties.collisionHeight) or 1.0))
      end
    end
  end

  return nil
end

return World
