local World = require("world")

local spawnLoading = {}

local function sortedCoords(centerChunkX, centerChunkZ, radius)
  local coords = {}
  for dx = -radius, radius do
    for dz = -radius, radius do
      coords[#coords + 1] = {
        chunkX = centerChunkX + dx,
        chunkZ = centerChunkZ + dz,
        dx = dx,
        dz = dz
      }
    end
  end

  table.sort(coords, function(a, b)
    local ar = math.max(math.abs(a.dx), math.abs(a.dz))
    local br = math.max(math.abs(b.dx), math.abs(b.dz))
    if ar ~= br then
      return ar < br
    end

    local ad = a.dx * a.dx + a.dz * a.dz
    local bd = b.dx * b.dx + b.dz * b.dz
    if ad ~= bd then
      return ad < bd
    end

    if a.chunkX == b.chunkX then
      return a.chunkZ < b.chunkZ
    end
    return a.chunkX < b.chunkX
  end)

  return coords
end

local function chunkEntry(world, chunkX, chunkZ)
  return world.chunks[World.chunkKey(chunkX, chunkZ)]
end

local function everyChunkInRadius(plan, world, radius, predicate)
  for dx = -radius, radius do
    for dz = -radius, radius do
      local entry = chunkEntry(world, plan.centerChunkX + dx, plan.centerChunkZ + dz)
      if not predicate(entry) then
        return false
      end
    end
  end

  return true
end

function spawnLoading.createPlan(options)
  options = options or {}
  local requiredRadius = options.requiredRadius or 1
  local haloRadius = math.max(requiredRadius, options.haloRadius or 2)
  local centerChunkX = options.centerChunkX or 0
  local centerChunkZ = options.centerChunkZ or 0

  return {
    centerChunkX = centerChunkX,
    centerChunkZ = centerChunkZ,
    requiredRadius = requiredRadius,
    haloRadius = haloRadius,
    coords = sortedCoords(centerChunkX, centerChunkZ, haloRadius)
  }
end

function spawnLoading.isCenterChunk(plan, chunkX, chunkZ)
  return chunkX == plan.centerChunkX and chunkZ == plan.centerChunkZ
end

function spawnLoading.centerEntry(plan, world)
  return chunkEntry(world, plan.centerChunkX, plan.centerChunkZ)
end

function spawnLoading.hasTerrainHalo(plan, world)
  return everyChunkInRadius(plan, world, plan.haloRadius, function(entry)
    return entry ~= nil and entry.hasTerrain == true
  end)
end

function spawnLoading.hasRequiredCollision(plan, world)
  return everyChunkInRadius(plan, world, plan.requiredRadius, function(entry)
    return entry ~= nil and entry.hasTerrain == true and entry.hasCollision == true
  end)
end

function spawnLoading.isSpawnPlayable(plan, world, terrainMeshes)
  if not spawnLoading.hasTerrainHalo(plan, world) then
    return false
  end
  if not spawnLoading.hasRequiredCollision(plan, world) then
    return false
  end

  local center = spawnLoading.centerEntry(plan, world)
  if not center or not center.hasTerrain or not center.hasCollision then
    return false
  end
  if not center.hasInitialLight and not center.hasInitialLighting then
    return false
  end

  local key = World.chunkKey(plan.centerChunkX, plan.centerChunkZ)
  return center.isUploaded == true and terrainMeshes[key] ~= nil
end

function spawnLoading.streamingMeshQueue(plan, world, terrainMeshes)
  local queue = {}
  for i = 1, #plan.coords do
    local coord = plan.coords[i]
    local key = World.chunkKey(coord.chunkX, coord.chunkZ)
    local entry = world.chunks[key]
    if entry and not terrainMeshes[key] then
      queue[#queue + 1] = {
        chunkX = coord.chunkX,
        chunkZ = coord.chunkZ,
        entry = entry,
        rebuild = true
      }
    end
  end

  return queue
end

function spawnLoading.progress(plan, job)
  local terrainComplete = (job.generatedChunks or 0) / math.max(1, #plan.coords)
  local collisionComplete = spawnLoading.hasRequiredCollision(plan, job.world) and 1.0 or terrainComplete
  local lightingComplete = job.world:lightingReady() and 1.0 or (job.lightingStarted and 0.20 or 0.0)
  local meshComplete = job.spawnMeshComplete and 1.0 or 0.0
  local playerReady = spawnLoading.isSpawnPlayable(plan, job.world, job.terrainMeshes) and 1.0 or 0.0

  local progress =
    terrainComplete * 0.45 +
    collisionComplete * 0.15 +
    lightingComplete * 0.20 +
    meshComplete * 0.15 +
    playerReady * 0.05

  return math.max(0.0, math.min(0.99, progress))
end

function spawnLoading.message(plan, job)
  if (job.generatedChunks or 0) < #plan.coords then
    return "Building spawn terrain"
  end
  if not job.world:lightingReady() then
    return "Lighting spawn"
  end
  if not job.spawnMeshComplete then
    return "Uploading spawn"
  end
  return "Joining world"
end

return spawnLoading
