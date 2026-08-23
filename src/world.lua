local Chunk = require("chunk")
local Planet = require("planet")
local PlanetLod = require("planet_lod")
local blocks = require("blocks")
local lighting = require("lighting")
local terrain = require("terrain")

local World = {}
World.__index = World

local CHUNK_SIZE = 16
-- Below this depth every block is stone, so a chunk entirely under it needs no
-- per-voxel surface evaluation. Must match the deepest band in
-- terrain.fillPlanetChunk that is not plain stone.
local SURFACE_BLOCK_DEPTH_METERS = 9.0
local NEIGHBOURS = {}
for dz = -1, 1 do
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 or dz ~= 0 then NEIGHBOURS[#NEIGHBOURS + 1] = {dx, dy, dz} end
    end
  end
end

function World.new(options)
  options = options or {}
  local self = setmetatable({}, World)
  self.chunks = {}
  -- The loaded region is an ellipsoid aligned to the local up: wide across the
  -- ground, shallow through it. A sphere spends most of its volume on solid
  -- rock underfoot and empty air overhead, and worse, its horizontal reach is
  -- eaten by however much the ground rises or falls -- so on terrain with any
  -- relief the render radius outruns it and you see the far side of the loaded
  -- ball as flat plateaus and floating islands.
  self.chunkRadius = options.chunkRadius3D or math.max(1, options.chunkRadius or 4)
  self.chunkRadiusVertical = math.max(1, math.min(
    options.chunkRadiusVertical or math.ceil(self.chunkRadius * 0.55), self.chunkRadius))
  self.maxHeight = CHUNK_SIZE - 1
  self.generatorType = options.generatorType or "default"
  self.superflatLayers = options.superflatLayers
  self.seed = options.seed or 1
  self.planet = getmetatable(options.planet) == Planet and options.planet or Planet.new(options.planet)
  self.renderOrigin = self.planet:snappedRenderOrigin(options.initialPosition or self.planet:spawnPosition())
  self.renderOriginRevision = 0
  self.visualLod = PlanetLod.new(self, options.planetLod)
  self.lightDirty, self.lightRevision, self.lightingJob = false, 0, nil
  self.lightTouched = {}
  if not options.deferInitialChunks then
    local spawn = self.planet:spawnPosition()
    self:ensureChunksAroundBlock(spawn[1], spawn[2], spawn[3])
  end
  return self
end

function World.chunkCoord(value) return math.floor(value / CHUNK_SIZE) end

function World.chunkKey(chunkX, chunkY, chunkZ)
  assert(chunkY ~= nil and chunkZ ~= nil, "3D chunk keys require x, y and z")
  return chunkX .. "," .. chunkY .. "," .. chunkZ
end

function World:createChunk(chunkX, chunkY, chunkZ, generationOptions)
  local key = World.chunkKey(chunkX, chunkY, chunkZ)
  if self.chunks[key] then return self.chunks[key] end
  local offsetX, offsetY, offsetZ = chunkX * CHUNK_SIZE, chunkY * CHUNK_SIZE, chunkZ * CHUNK_SIZE
  terrain.setSeed(self.seed)
  local classification, minDistance, maxDistance =
    self.planet:classifyChunk(chunkX, chunkY, chunkZ, CHUNK_SIZE)
  local surfaceCorners
  if classification == "surface" then
    -- The planet-wide band is 500 m tall, so it calls nearly everything near
    -- the ground a surface chunk and every one of those pays for a full
    -- 4096-voxel generation. Nine terrain samples say what the ground is doing
    -- over this chunk in particular, and most chunks turn out to be wholly
    -- above it, or deep enough under it that only the caves matter.
    local low, high, corners = terrain.chunkSurfaceBounds(chunkX, chunkY, chunkZ, CHUNK_SIZE, self.planet)
    local voxelSize = self.planet.voxelSizeMeters
    if minDistance > high then
      classification = "outside"
    elseif maxDistance < low - self.planet.generatedInteriorDepthMeters / voxelSize then
      classification = "interior"
    elseif maxDistance < low - SURFACE_BLOCK_DEPTH_METERS / voxelSize then
      classification = "buried"
      -- Copied because chunkSurfaceBounds reuses its corner table.
      surfaceCorners = {corners[1], corners[2], corners[3], corners[4],
        corners[5], corners[6], corners[7], corners[8]}
    end
  end
  local uniform = classification == "interior" and (blocks.stone or 1) or 0
  local chunk = Chunk.new(uniform)
  generationOptions = generationOptions or {}
  if classification == "surface" then
    terrain.fillPlanetChunk(chunk, offsetX, offsetY, offsetZ, self.planet, generationOptions)
  elseif classification == "buried" then
    terrain.fillBuriedChunk(chunk, offsetX, offsetY, offsetZ, self.planet, surfaceCorners, generationOptions)
  end
  local entry = {
    chunk = chunk, chunkX = chunkX, chunkY = chunkY, chunkZ = chunkZ,
    offsetX = offsetX, offsetY = offsetY, offsetZ = offsetZ,
    radialClass = classification, hasTerrain = true, hasCollision = true, serverReady = true,
    hasInitialLight = false, hasInitialLighting = false, hasMesh = false,
    hasGPUBuffer = false, isUploaded = false, renderReady = false,
    lightRevision = nil, meshRevision = 0
  }
  self.chunks[key] = entry
  lighting.lightChunk(self, entry, self.lightTouched, generationOptions.yieldStep)
  entry.hasInitialLight, entry.hasInitialLighting, entry.lightRevision = true, true, self.lightRevision
  for i = 1, #NEIGHBOURS do
    local n = NEIGHBOURS[i]
    local nk = World.chunkKey(chunkX + n[1], chunkY + n[2], chunkZ + n[3])
    local neighbour = self.chunks[nk]
    if neighbour then self.lightTouched[nk] = neighbour end
  end
  return entry
end

function World:createChunkJob(chunkX, chunkY, chunkZ)
  local job = {chunkX = chunkX, chunkY = chunkY, chunkZ = chunkZ, entry = nil}
  job.thread = coroutine.create(function()
    job.entry = self:createChunk(chunkX, chunkY, chunkZ, {yieldStep = function() coroutine.yield(false) end})
    return true
  end)
  return job
end

function World:createChunkSync(chunkX, chunkY, chunkZ) return self:createChunk(chunkX, chunkY, chunkZ) end

-- Squared ellipsoid score for a chunk offset, measured in the local frame: 1.0
-- is the boundary. The offset is split into the component along the local up
-- and the rest, so the region follows the ground rather than the block grid.
function World:chunkRegionScore(dx, dy, dz, up, radius, vertical)
  local radial = dx * up[1] + dy * up[2] + dz * up[3]
  local tx, ty, tz = dx - up[1] * radial, dy - up[2] * radial, dz - up[3] * radial
  local tangentialSquared = tx * tx + ty * ty + tz * tz
  return tangentialSquared / (radius * radius) + radial * radial / (vertical * vertical)
end

function World:chunkWithinLoadRegion(chunkX, chunkY, chunkZ, x, y, z, slack)
  slack = slack or 0
  local cx, cy, cz = World.chunkCoord(x), World.chunkCoord(y), World.chunkCoord(z)
  local up = self.planet:localUp({x, y, z})
  return self:chunkRegionScore(chunkX - cx, chunkY - cy, chunkZ - cz, up,
    self.chunkRadius + slack, self.chunkRadiusVertical + slack) <= 1.0
end

function World:chunkCoordsAroundBlock(x, y, z, radius)
  radius = radius or self.chunkRadius
  local vertical = math.max(1, math.min(self.chunkRadiusVertical or radius, radius))
  local cx, cy, cz = World.chunkCoord(x), World.chunkCoord(y), World.chunkCoord(z)
  local up = self.planet:localUp({x, y, z})
  local coords = {}
  for dz = -radius, radius do
    for dy = -radius, radius do
      for dx = -radius, radius do
        if self:chunkRegionScore(dx, dy, dz, up, radius, vertical) <= 1.0 then
          local distanceSquared = dx * dx + dy * dy + dz * dz
          coords[#coords + 1] = {chunkX = cx + dx, chunkY = cy + dy, chunkZ = cz + dz, distanceSquared = distanceSquared}
        end
      end
    end
  end
  table.sort(coords, function(a, b)
    if a.distanceSquared ~= b.distanceSquared then return a.distanceSquared < b.distanceSquared end
    if a.chunkX ~= b.chunkX then return a.chunkX < b.chunkX end
    if a.chunkY ~= b.chunkY then return a.chunkY < b.chunkY end
    return a.chunkZ < b.chunkZ
  end)
  return coords
end

function World:ensureChunksAroundBlock(x, y, z)
  local added, coords = {}, self:chunkCoordsAroundBlock(x, y, z)
  for i = 1, #coords do
    local c = coords[i]
    local key = World.chunkKey(c.chunkX, c.chunkY, c.chunkZ)
    if not self.chunks[key] then added[#added + 1] = self:createChunk(c.chunkX, c.chunkY, c.chunkZ) end
  end
  return added
end

function World:eachChunk(fn) for _, entry in pairs(self.chunks) do fn(entry.chunk, entry) end end

function World:clearGeneratedChunks()
  self.chunks, self.lightTouched, self.lightingJob = {}, {}, nil
  self.lightDirty, self.lightRevision = false, self.lightRevision + 1
end

function World:markLightDirty() self.lightDirty, self.lightRevision = true, self.lightRevision + 1 end

function World:markLightingReady()
  self:eachChunk(function(_, entry)
    entry.hasInitialLight, entry.hasInitialLighting, entry.lightRevision = true, true, self.lightRevision
  end)
end

function World:rebuildLighting(options)
  lighting.rebuild(self, options)
  self.lightDirty = false
  self:markLightingReady()
end

function World:ensureLighting() if self.lightDirty then self:rebuildLighting() end end
function World:lightingReady() return not self.lightDirty and not self.lightingJob end

function World:startLightingJob()
  if self.lightingJob then return end
  self.lightingJob = coroutine.create(function()
    lighting.rebuild(self, {yieldStep = function() coroutine.yield(false) end})
    return true
  end)
end

function World:stepLightingJob(budget)
  budget = budget or 8
  if self.lightDirty and not self.lightingJob then self:startLightingJob() end
  local steps = 0
  while self.lightingJob and steps < budget do
    local ok, err = coroutine.resume(self.lightingJob)
    if not ok then error(err) end
    steps = steps + 1
    if coroutine.status(self.lightingJob) == "dead" then
      self.lightingJob, self.lightDirty = nil, false
      self:markLightingReady()
    end
  end
  return self:lightingReady()
end

function World:getChunkAtBlock(x, y, z)
  local cx, cy, cz = World.chunkCoord(x), World.chunkCoord(y), World.chunkCoord(z)
  return self.chunks[World.chunkKey(cx, cy, cz)]
end

function World:localBlockCoord(x, y, z)
  local cx, cy, cz = World.chunkCoord(x), World.chunkCoord(y), World.chunkCoord(z)
  return x - cx * CHUNK_SIZE, y - cy * CHUNK_SIZE, z - cz * CHUNK_SIZE, cx, cy, cz
end

function World:containsBlock(x, y, z) return self:getChunkAtBlock(x, y, z) ~= nil end
function World:hasCollisionAtBlock(x, y, z)
  local entry = self:getChunkAtBlock(x, y, z)
  return entry ~= nil and entry.hasCollision == true
end

function World:blockAt(x, y, z)
  local entry = self:getChunkAtBlock(x, y, z)
  if not entry then return nil end
  local lx, ly, lz = self:localBlockCoord(x, y, z)
  return entry.chunk:getBlock(lx, ly, lz)
end

function World:setBlock(x, y, z, id)
  local entry = self:getChunkAtBlock(x, y, z)
  if not entry then return nil end
  local lx, ly, lz = self:localBlockCoord(x, y, z)
  local beforeId = entry.chunk:getBlock(lx, ly, lz)
  if beforeId == id then return entry end
  entry.chunk:setBlock(lx, ly, lz, id)
  entry.meshRevision = (entry.meshRevision or 0) + 1
  lighting.applyBlockChange(self, x, y, z, nil, self.lightTouched, beforeId, id)
  return entry
end

function World:drainLightTouched() local touched = self.lightTouched self.lightTouched = {} return touched end

function World:skyLightAt(x, y, z)
  local entry = self:getChunkAtBlock(x, y, z)
  if not entry then return 15 end
  local lx, ly, lz = self:localBlockCoord(x, y, z)
  return entry.chunk:getSkyLight(lx, ly, lz)
end

local function buildNeighbourSampler(world, chunkX, chunkY, chunkZ, light)
  local neighbours = {}
  for dz = -1, 1 do for dy = -1, 1 do for dx = -1, 1 do
    neighbours[(dz + 1) * 9 + (dy + 1) * 3 + dx + 2] = world.chunks[World.chunkKey(chunkX + dx, chunkY + dy, chunkZ + dz)]
  end end end
  local baseX, baseY, baseZ = chunkX * CHUNK_SIZE, chunkY * CHUNK_SIZE, chunkZ * CHUNK_SIZE
  return function(x, y, z)
    local rx, ry, rz = x - baseX, y - baseY, z - baseZ
    local dx, dy, dz = math.floor(rx / CHUNK_SIZE), math.floor(ry / CHUNK_SIZE), math.floor(rz / CHUNK_SIZE)
    if dx < -1 or dx > 1 or dy < -1 or dy > 1 or dz < -1 or dz > 1 then
      return light and world:skyLightAt(x, y, z) or (world:blockAt(x, y, z) or 0)
    end
    local entry = neighbours[(dz + 1) * 9 + (dy + 1) * 3 + dx + 2]
    if not entry then return light and 15 or 0 end
    local lx, ly, lz = rx - dx * CHUNK_SIZE, ry - dy * CHUNK_SIZE, rz - dz * CHUNK_SIZE
    return light and entry.chunk:getSkyLight(lx, ly, lz) or entry.chunk:getBlock(lx, ly, lz)
  end
end

function World:blockSampler(chunkX, chunkY, chunkZ) return buildNeighbourSampler(self, chunkX, chunkY, chunkZ, false) end
function World:skyLightSampler(chunkX, chunkY, chunkZ) return buildNeighbourSampler(self, chunkX, chunkY, chunkZ, true) end

-- Point-based collision. The camera used to floor a position into integer
-- block coordinates itself, which hard-codes a Cartesian lattice into the
-- physics; asking the world about a *point* lets a different voxel topology
-- answer for itself.
function World:isSolidAtPoint(x, y, z)
  return self:isSolidBlock(math.floor(x), math.floor(y), math.floor(z))
end

function World:hasCollisionAtPoint(x, y, z)
  return self:hasCollisionAtBlock(math.floor(x), math.floor(y), math.floor(z))
end

function World:isSolidBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then return false end
  local def = blocks.list[id]
  return def and def.properties and def.properties.solid or false
end

function World:isRaycastTargetBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then return false end
  local def = blocks.list[id]
  local p = def and def.properties
  return p and (p.solid or p.targetable or p.breakable or p.replaceable) and not p.liquid or false
end

function World:raycast(origin, direction, maxDistance)
  maxDistance = maxDistance or 6.0
  local dx, dy, dz = direction[1], direction[2], direction[3]
  local x, y, z = math.floor(origin[1]), math.floor(origin[2]), math.floor(origin[3])
  local sx, sy, sz = dx >= 0 and 1 or -1, dy >= 0 and 1 or -1, dz >= 0 and 1 or -1
  local huge = math.huge
  local tdx, tdy, tdz = dx == 0 and huge or math.abs(1 / dx), dy == 0 and huge or math.abs(1 / dy), dz == 0 and huge or math.abs(1 / dz)
  local tx = dx == 0 and huge or ((dx >= 0 and x + 1 or x) - origin[1]) / dx
  local ty = dy == 0 and huge or ((dy >= 0 and y + 1 or y) - origin[2]) / dy
  local tz = dz == 0 and huge or ((dz >= 0 and z + 1 or z) - origin[3]) / dz
  local distance, previous = 0.0, nil
  while distance <= maxDistance do
    if self:isRaycastTargetBlock(x, y, z) then
      return {x = x, y = y, z = z, id = self:blockAt(x, y, z), previous = previous, distance = distance}
    end
    previous = {x = x, y = y, z = z}
    if tx <= ty and tx <= tz then distance, x, tx = tx, x + sx, tx + tdx
    elseif ty <= tz then distance, y, ty = ty, y + sy, ty + tdy
    else distance, z, tz = tz, z + sz, tz + tdz end
  end
  return nil
end

function World:updateRenderOrigin(position)
  local nextOrigin = self.planet:snappedRenderOrigin(position)
  if nextOrigin[1] == self.renderOrigin[1] and nextOrigin[2] == self.renderOrigin[2] and nextOrigin[3] == self.renderOrigin[3] then return false end
  self.renderOrigin, self.renderOriginRevision = nextOrigin, self.renderOriginRevision + 1
  return true
end

function World:toRenderPosition(position)
  return {position[1] - self.renderOrigin[1], position[2] - self.renderOrigin[2], position[3] - self.renderOrigin[3]}
end

-- Chunk generation sets the seed itself, so a caller that asked for the surface
-- first got whatever seed was last active. That was invisible while the
-- generator was nearly flat; with real relief it put spawn tens of metres
-- inside the ground.
function World:surfacePosition(direction, eyeHeight)
  terrain.setSeed(self.seed)
  local sample = terrain.surfaceAtDirection(direction, self.planet)
  local radius = sample.surfaceRadiusVoxels + (eyeHeight or 0.0)
  return {self.planet.center[1] + direction[1] * radius, self.planet.center[2] + direction[2] * radius, self.planet.center[3] + direction[3] * radius}, sample
end

return World
