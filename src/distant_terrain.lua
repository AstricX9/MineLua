local blocks = require("blocks")
local terrain = require("terrain")

local DistantTerrain = {}
DistantTerrain.__index = DistantTerrain

local CHUNK_SIZE = 16
local TERRAIN_STRIDE = 18
local WATER_STRIDE = 11
local QUAD_ORDER = {1, 2, 3, 3, 4, 1}
local WHITE = {1.0, 1.0, 1.0}

local function chunkKey(chunkX, chunkZ)
  return chunkX .. "," .. chunkZ
end

local function pendingCoords(item)
  if item.entry then
    return item.entry.chunkX, item.entry.chunkZ
  end
  return item.chunkX, item.chunkZ
end

local function lightCurve(level)
  local darkness = 1.0 - math.max(0.0, math.min(15.0, level or 15.0)) / 15.0
  return (1.0 - darkness) / (darkness * 3.0 + 1.0)
end

local function faceColor(def, face, worldX, worldZ)
  local colors = def.colors
  local color = (colors and colors[face]) or def.color or WHITE
  local r, g, b = color[1], color[2], color[3]
  if def.biomeTint and (face == "top" or def.tintAllFaces) then
    local tint = terrain.grassColorAt(worldX, worldZ)
    r, g, b = r * tint[1], g * tint[2], b * tint[3]
  end
  return r, g, b
end

local function pushTerrainVertex(vertices, p, normal, color, u, v, light)
  local n = #vertices
  vertices[n + 1] = p[1]; vertices[n + 2] = p[2]; vertices[n + 3] = p[3]
  vertices[n + 4] = normal[1]; vertices[n + 5] = normal[2]; vertices[n + 6] = normal[3]
  vertices[n + 7] = color[1]; vertices[n + 8] = color[2]; vertices[n + 9] = color[3]
  vertices[n + 10] = u; vertices[n + 11] = v
  -- Distant terrain is an opaque representation. Ice and glass keep their
  -- physical near-field pass, but are deliberately folded into the LOD color
  -- surface instead of multiplying expensive refraction buffers far away.
  vertices[n + 12] = 0.0
  vertices[n + 13] = 0.0
  vertices[n + 14] = light
  vertices[n + 15] = 0.0
  vertices[n + 16] = 0.0
  vertices[n + 17] = 0.0
  vertices[n + 18] = light
end

local function appendTerrainQuad(vertices, corners, normal, def, face, worldX, worldZ, light)
  local uv = def.uvs and (def.uvs[face] or def.uvs.side or def.uvs.top)
  if not uv then return end
  local r, g, b = faceColor(def, face, worldX, worldZ)
  local color = {r, g, b}
  local cornerU = {uv.u0, uv.u1, uv.u1, uv.u0}
  local cornerV = {uv.v1, uv.v1, uv.v0, uv.v0}
  for i = 1, 6 do
    local corner = QUAD_ORDER[i]
    pushTerrainVertex(vertices, corners[corner], normal, color, cornerU[corner], cornerV[corner], light)
  end
end

local function pushWaterVertex(vertices, x, y, z, exposure, shore)
  local n = #vertices
  vertices[n + 1] = x; vertices[n + 2] = y; vertices[n + 3] = z
  vertices[n + 4] = 0.0; vertices[n + 5] = 1.0; vertices[n + 6] = 0.0
  vertices[n + 7] = 1.0; vertices[n + 8] = 1.0; vertices[n + 9] = 1.0
  vertices[n + 10] = exposure or 1.0
  vertices[n + 11] = shore or 1.0
end

local function appendWaterQuad(vertices, x0, z0, x1, z1, y, waveDataAt)
  local function wave(x, z)
    if waveDataAt then return waveDataAt(x, z) end
    return 1.0, 1.0
  end
  local e01, s01 = wave(x0, z1)
  local e11, s11 = wave(x1, z1)
  local e10, s10 = wave(x1, z0)
  local e00, s00 = wave(x0, z0)
  pushWaterVertex(vertices, x0, y, z1, e01, s01)
  pushWaterVertex(vertices, x1, y, z1, e11, s11)
  pushWaterVertex(vertices, x1, y, z0, e10, s10)
  pushWaterVertex(vertices, x1, y, z0, e10, s10)
  pushWaterVertex(vertices, x0, y, z0, e00, s00)
  pushWaterVertex(vertices, x0, y, z1, e01, s01)
end

-- Capture is the hard provenance boundary: LOD data can only be made from a
-- completed voxel chunk. Nothing in this module samples procedural height or
-- water geometry for a chunk that does not exist.
function DistantTerrain.capture(entry, maxHeight, waterId, stillWaterId)
  assert(entry and entry.chunk, "distant LOD capture requires a generated chunk")
  local record = {
    chunkX = entry.chunkX,
    chunkZ = entry.chunkZ,
    offsetX = entry.offsetX,
    offsetZ = entry.offsetZ,
    revision = entry.dataRevision or 0,
    heights = {},
    blockIds = {},
    skyLight = {},
    waterSurface = {},
    source = "generated_chunk"
  }
  local chunk = entry.chunk
  local rawBlocks = chunk.blocks
  local rawSkyLight = chunk.skyLight

  local function isWater(id)
    return id == waterId or (stillWaterId and id == stillWaterId)
  end

  for z = 0, CHUNK_SIZE - 1 do
    local zOffset = z * CHUNK_SIZE * 256
    for x = 0, CHUNK_SIZE - 1 do
      local index = x + z * CHUNK_SIZE + 1
      local topY, topId
      local waterY = chunk.waterSurface and chunk.waterSurface[index] or nil
      local blockIndex = x + maxHeight * CHUNK_SIZE + zOffset + 1
      for y = maxHeight, 0, -1 do
        -- Capture runs for every generated far chunk. Reading the chunk's flat
        -- arrays directly avoids tens of thousands of Lua method calls here.
        local id = rawBlocks[blockIndex] or 0
        if id ~= 0 then
          local def = blocks.list[id]
          local props = def and def.properties
          if not waterY and isWater(id) then
            waterY = y - 0.35
          end
          -- A distant chunk is a terrain height field, not a coarse voxel
          -- remesh. Folding a leaf or living log into it stretches one tree
          -- across an entire 2/4/8-block LOD cell.
          if props and props.solid and not props.cross and not props.leaves and
              not props.aliveTree then
            topY, topId = y, id
            -- Any visible water was encountered above this surface while
            -- scanning downward. Continuing through the whole stone column
            -- cannot change the result and dominated LOD capture time.
            break
          end
        end
        blockIndex = blockIndex - CHUNK_SIZE
      end
      if topY then
        record.heights[index] = topY + 1.0
        record.blockIds[index] = topId
        local lightY = math.min(maxHeight, topY + 1)
        local lightIndex = x + lightY * CHUNK_SIZE + zOffset + 1
        record.skyLight[index] = entry.hasInitialLight == false and 15 or
          (rawSkyLight[lightIndex] or 0)
      end
      if waterY then record.waterSurface[index] = waterY end
    end
  end

  return record
end

local function aggregate(record, originX, originZ, step)
  local heightSum, lightSum, count = 0.0, 0.0, 0
  local idCounts = {}
  local waterSum, waterCount = 0.0, 0
  for z = originZ, originZ + step - 1 do
    for x = originX, originX + step - 1 do
      local index = x + z * CHUNK_SIZE + 1
      local height = record.heights[index]
      if height then
        count = count + 1
        heightSum = heightSum + height
        lightSum = lightSum + (record.skyLight[index] or 15)
        local id = record.blockIds[index]
        idCounts[id] = (idCounts[id] or 0) + 1
      end
      local water = record.waterSurface[index]
      if water then
        waterCount = waterCount + 1
        waterSum = waterSum + water
      end
    end
  end

  local bestId, bestCount = nil, -1
  for id, idCount in pairs(idCounts) do
    if idCount > bestCount or (idCount == bestCount and (not bestId or id < bestId)) then
      bestId, bestCount = id, idCount
    end
  end

  return {
    height = count > 0 and math.floor(heightSum / count + 0.5) or nil,
    blockId = bestId,
    light = count > 0 and lightCurve(lightSum / count) or 1.0,
    -- A quarter-cell threshold keeps thin generated rivers visible without
    -- turning a single isolated water block into a whole coarse lake tile.
    water = waterCount >= math.max(1, math.floor(step * step * 0.25 + 0.5)) and
      (waterSum / waterCount) or nil
  }
end

local function aggregateGrid(record, step)
  record.aggregateCache = record.aggregateCache or {}
  local cached = record.aggregateCache[step]
  if cached then return cached end

  local gridSize = CHUNK_SIZE / step
  local cells = {}
  for gz = 0, gridSize - 1 do
    for gx = 0, gridSize - 1 do
      cells[gx + gz * gridSize + 1] = aggregate(record, gx * step, gz * step, step)
    end
  end
  record.aggregateCache[step] = cells
  return cells
end

function DistantTerrain.build(record, step, options)
  assert(record and record.source == "generated_chunk", "LOD mesh requires captured chunk data")
  step = math.max(1, math.min(CHUNK_SIZE, math.floor(step or 4)))
  while CHUNK_SIZE % step ~= 0 do step = step - 1 end
  options = options or {}

  local gridSize = CHUNK_SIZE / step
  local cells = aggregateGrid(record, step)

  local function cellAt(gx, gz)
    if gx < 0 or gx >= gridSize or gz < 0 or gz >= gridSize then
      if not options.recordAt then return nil end
      local chunkDx, chunkDz = 0, 0
      if gx < 0 then chunkDx, gx = -1, gx + gridSize end
      if gx >= gridSize then chunkDx, gx = 1, gx - gridSize end
      if gz < 0 then chunkDz, gz = -1, gz + gridSize end
      if gz >= gridSize then chunkDz, gz = 1, gz - gridSize end
      local neighbourRecord = options.recordAt(chunkDx, chunkDz)
      if not neighbourRecord then return nil end
      return aggregateGrid(neighbourRecord, step)[gx + gz * gridSize + 1]
    end
    return cells[gx + gz * gridSize + 1]
  end

  local terrainVertices, waterVertices = {}, {}
  for gz = 0, gridSize - 1 do
    for gx = 0, gridSize - 1 do
      local cell = cellAt(gx, gz)
      local x0 = record.offsetX + gx * step
      local z0 = record.offsetZ + gz * step
      local x1, z1 = x0 + step, z0 + step
      if cell.height and cell.blockId then
        local def = blocks.list[cell.blockId]
        if def then
          local y = cell.height
          appendTerrainQuad(terrainVertices,
            {{x0,y,z1}, {x1,y,z1}, {x1,y,z0}, {x0,y,z0}},
            {0,1,0}, def, "top", (x0+x1)*0.5, (z0+z1)*0.5, cell.light)

          local neighbour = cellAt(gx + 1, gz)
          if neighbour and neighbour.height and neighbour.height < y then
            appendTerrainQuad(terrainVertices,
              {{x1,neighbour.height,z1},{x1,neighbour.height,z0},{x1,y,z0},{x1,y,z1}},
              {1,0,0}, def, "side", (x0+x1)*0.5, (z0+z1)*0.5, cell.light)
          elseif neighbour and neighbour.height and neighbour.height > y and
              gx == gridSize - 1 and options.transitionAt and options.transitionAt(1, 0) then
            local neighbourDef = blocks.list[neighbour.blockId] or def
            appendTerrainQuad(terrainVertices,
              {{x1,y,z0},{x1,y,z1},{x1,neighbour.height,z1},{x1,neighbour.height,z0}},
              {-1,0,0}, neighbourDef, "side", (x0+x1)*0.5, (z0+z1)*0.5, neighbour.light)
          end
          neighbour = cellAt(gx - 1, gz)
          if neighbour and neighbour.height and neighbour.height < y then
            appendTerrainQuad(terrainVertices,
              {{x0,neighbour.height,z0},{x0,neighbour.height,z1},{x0,y,z1},{x0,y,z0}},
              {-1,0,0}, def, "side", (x0+x1)*0.5, (z0+z1)*0.5, cell.light)
          elseif neighbour and neighbour.height and neighbour.height > y and gx == 0 and
              options.transitionAt and options.transitionAt(-1, 0) then
            local neighbourDef = blocks.list[neighbour.blockId] or def
            appendTerrainQuad(terrainVertices,
              {{x0,y,z1},{x0,y,z0},{x0,neighbour.height,z0},{x0,neighbour.height,z1}},
              {1,0,0}, neighbourDef, "side", (x0+x1)*0.5, (z0+z1)*0.5, neighbour.light)
          end
          neighbour = cellAt(gx, gz + 1)
          if neighbour and neighbour.height and neighbour.height < y then
            appendTerrainQuad(terrainVertices,
              {{x0,neighbour.height,z1},{x1,neighbour.height,z1},{x1,y,z1},{x0,y,z1}},
              {0,0,1}, def, "front", (x0+x1)*0.5, (z0+z1)*0.5, cell.light)
          elseif neighbour and neighbour.height and neighbour.height > y and
              gz == gridSize - 1 and options.transitionAt and options.transitionAt(0, 1) then
            local neighbourDef = blocks.list[neighbour.blockId] or def
            appendTerrainQuad(terrainVertices,
              {{x1,y,z1},{x0,y,z1},{x0,neighbour.height,z1},{x1,neighbour.height,z1}},
              {0,0,-1}, neighbourDef, "back", (x0+x1)*0.5, (z0+z1)*0.5, neighbour.light)
          end
          neighbour = cellAt(gx, gz - 1)
          if neighbour and neighbour.height and neighbour.height < y then
            appendTerrainQuad(terrainVertices,
              {{x1,neighbour.height,z0},{x0,neighbour.height,z0},{x0,y,z0},{x1,y,z0}},
              {0,0,-1}, def, "back", (x0+x1)*0.5, (z0+z1)*0.5, cell.light)
          elseif neighbour and neighbour.height and neighbour.height > y and gz == 0 and
              options.transitionAt and options.transitionAt(0, -1) then
            local neighbourDef = blocks.list[neighbour.blockId] or def
            appendTerrainQuad(terrainVertices,
              {{x0,y,z0},{x1,y,z0},{x1,neighbour.height,z0},{x0,neighbour.height,z0}},
              {0,0,1}, neighbourDef, "front", (x0+x1)*0.5, (z0+z1)*0.5, neighbour.light)
          end
          -- Missing neighbouring records are left open. Filling that void with
          -- a skirt or floor would reintroduce the fake under-mesh this renderer
          -- is specifically designed to avoid.
        end
      end
      if cell.water then
        appendWaterQuad(waterVertices, x0, z0, x1, z1, cell.water, options.waveDataAt)
      end
    end
  end

  return terrainVertices, waterVertices, {
    minX = record.offsetX,
    minY = 0,
    minZ = record.offsetZ,
    maxX = record.offsetX + CHUNK_SIZE,
    maxY = options.maxHeight or 256,
    maxZ = record.offsetZ + CHUNK_SIZE
  }
end

function DistantTerrain.new(options)
  options = options or {}
  local self = setmetatable({}, DistantTerrain)
  self.radius = math.max(1, math.floor(options.radius or 24))
  self.generationSteps = math.max(1, math.floor(options.generationSteps or 8))
  self.buildBudget = math.max(1, math.floor(options.buildBudget or 2))
  self.frameBudget = (options.frameBudgetMs or 3.0) / 1000.0
  self.queueTarget = math.max(64, math.floor(options.queueTarget or 512))
  self.ringBudget = math.max(1, math.floor(options.ringBudget or 4))
  self.maxHeight = options.maxHeight or 127
  self.waterId = options.waterId
  self.stillWaterId = options.stillWaterId
  self.upload = assert(options.upload, "distant terrain requires an upload callback")
  self.release = assert(options.release, "distant terrain requires a release callback")
  self.now = options.now or os.clock
  self.waveDataAt = options.waveDataAt
  self.records = {}
  self.queue = {}
  self.queueHead = 1
  self.queued = {}
  self.active = {}
  self.activeIndex = 1
  return self
end

function DistantTerrain:clear()
  for _, record in pairs(self.records) do
    if record.mesh then self.release(record.mesh) end
  end
  self.records, self.queue, self.queued = {}, {}, {}
  self.queueHead = 1
  self.active = {}
  self.activeIndex = 1
  self.radiusDirty = false
  self.centerChunkX, self.centerChunkZ, self.innerRadius = nil, nil, nil
end

function DistantTerrain:setRadius(radius)
  local replacement = math.max(1, math.floor(tonumber(radius) or self.radius))
  if replacement == self.radius then return false end
  self.radius = replacement
  self.radiusDirty = true
  return true
end

function DistantTerrain:isPending(chunkX, chunkZ)
  return self.queued[chunkKey(chunkX, chunkZ)] == true
end

local function lodStep(distance, innerRadius)
  if distance <= innerRadius + 4 then return 2 end
  if distance <= innerRadius + 10 then return 4 end
  return 8
end

function DistantTerrain:_replaceMesh(record, step, world)
  if record.mesh and record.meshStep == step and not record.meshDirty then return false end
  local vertices, waterVertices, bounds = DistantTerrain.build(record, step, {
    maxHeight = self.maxHeight,
    waveDataAt = self.waveDataAt,
    recordAt = function(dx, dz)
      local key = chunkKey(record.chunkX + dx, record.chunkZ + dz)
      local neighbour = self.records[key]
      if neighbour or not world then return neighbour end

      -- The inner LOD boundary touches a real chunk which is intentionally not
      -- rendered by this manager. Capture its exact generated columns on
      -- demand so the far side wall meets the real surface instead of being
      -- left open. The compact record is reusable if that chunk later moves
      -- into the far ring.
      local entry = world.chunks and world.chunks[key]
      if entry and entry.chunk then neighbour = self:_capture(entry) end
      return neighbour
    end,
    transitionAt = function(dx, dz)
      if not world or not world.chunks then return false end
      local chunkX, chunkZ = record.chunkX + dx, record.chunkZ + dz
      local entry = world.chunks[chunkKey(chunkX, chunkZ)]
      if not entry then return false end
      if self.centerChunkX and self.centerChunkZ and self.innerRadius then
        return math.max(math.abs(chunkX - self.centerChunkX),
          math.abs(chunkZ - self.centerChunkZ)) <= self.innerRadius
      end
      return entry.hasMesh == true
    end
  })
  local replacement = self.upload(record, vertices, waterVertices, bounds, step)
  if record.mesh then self.release(record.mesh) end
  record.mesh, record.meshStep, record.meshDirty = replacement, step, false
  return true
end

function DistantTerrain:_capture(entry)
  local key = chunkKey(entry.chunkX, entry.chunkZ)
  local previous = self.records[key]
  if previous and previous.revision == (entry.dataRevision or 0) then return previous, false end
  local record = DistantTerrain.capture(entry, self.maxHeight, self.waterId, self.stillWaterId)
  if previous and previous.mesh then
    record.mesh = previous.mesh
    record.meshStep = previous.meshStep
    record.meshDirty = true
  end
  self.records[key] = record
  -- Boundary faces depend on the adjacent chunk-derived column records. Mark
  -- both sides dirty as real neighbours arrive; absent neighbours stay open
  -- instead of being hidden with a synthetic skirt.
  local sides = {{-1,0}, {1,0}, {0,-1}, {0,1}}
  for i = 1, #sides do
    local side = sides[i]
    local neighbour = self.records[chunkKey(entry.chunkX + side[1], entry.chunkZ + side[2])]
    if neighbour then neighbour.meshDirty = true end
  end
  return record, true
end

function DistantTerrain:_refreshQueue(centerChunkX, centerChunkZ, innerRadius)
  self.queue, self.queued = {}, {}
  self.queueHead = 1
  for i = 1, #self.active do
    local item = self.active[i]
    self.queued[chunkKey(item.chunkX, item.chunkZ)] = true
  end
  self.nextRing = innerRadius + 1
  self.centerChunkX, self.centerChunkZ, self.innerRadius = centerChunkX, centerChunkZ, innerRadius
  self.queuedRadius = self.radius
end

local function nearPendingKeys(nearEntries)
  local nearPending = {}
  for i = 1, #nearEntries do
    local x, z = pendingCoords(nearEntries[i])
    if x and z then nearPending[chunkKey(x, z)] = true end
  end
  return nearPending
end

function DistantTerrain:_fillQueue(nearEntries)
  local pendingCount = math.max(0, #self.queue - self.queueHead + 1)
  if pendingCount >= self.queueTarget or self.nextRing > self.radius then return end

  -- Compact consumed slots before appending another ring. table.remove(queue, 1)
  -- shifts the entire list and becomes prohibitively expensive at a 128-chunk
  -- range; a head index keeps each dequeue O(1).
  if self.queueHead > 1 then
    local remaining = {}
    for i = self.queueHead, #self.queue do remaining[#remaining + 1] = self.queue[i] end
    self.queue, self.queueHead = remaining, 1
    pendingCount = #remaining
  end

  local nearPending = nearPendingKeys(nearEntries)
  local function enqueue(dx, dz, ring)
    local chunkX, chunkZ = self.centerChunkX + dx, self.centerChunkZ + dz
    local key = chunkKey(chunkX, chunkZ)
    -- Queue every missing record, including coordinates whose full chunk is
    -- currently resident. update() compacts resident chunks directly; if the
    -- near renderer prunes one first, this item falls through to generation.
    if not self.records[key] and not nearPending[key] and not self.queued[key] then
      self.queue[#self.queue + 1] = {
        chunkX = chunkX,
        chunkZ = chunkZ,
        ring = ring
      }
      self.queued[key] = true
    end
  end

  -- Chebyshev-distance rings are square perimeters. Completing r=1, then r=2,
  -- and so on makes the selected render distance a progressively filled square
  -- range around the player without allocating/sorting all 66,049 coordinates
  -- when the slider is 128.
  local ringsScheduled = 0
  while pendingCount < self.queueTarget and self.nextRing <= self.radius and
      ringsScheduled < self.ringBudget do
    local ring = self.nextRing
    for dx = -ring, ring do
      enqueue(dx, -ring, ring)
      enqueue(dx, ring, ring)
    end
    for dz = -ring + 1, ring - 1 do
      enqueue(-ring, dz, ring)
      enqueue(ring, dz, ring)
    end
    self.nextRing = ring + 1
    ringsScheduled = ringsScheduled + 1
    pendingCount = math.max(0, #self.queue - self.queueHead + 1)
  end
end

function DistantTerrain:_prune(centerChunkX, centerChunkZ, innerRadius, exactHorizon)
  local outerRadius = math.max(self.radius, innerRadius) + (exactHorizon and 0 or 2)
  for i = #self.active, 1, -1 do
    local item = self.active[i]
    if math.abs(item.chunkX - centerChunkX) > outerRadius or
        math.abs(item.chunkZ - centerChunkZ) > outerRadius then
      self.queued[chunkKey(item.chunkX, item.chunkZ)] = nil
      -- A not-yet-completed chunk job has not installed an entry in the world;
      -- abandoning its coroutine is therefore safe when it leaves the horizon.
      table.remove(self.active, i)
    end
  end
  if self.activeIndex > #self.active then self.activeIndex = 1 end
  for key, record in pairs(self.records) do
    if math.abs(record.chunkX - centerChunkX) > outerRadius or
        math.abs(record.chunkZ - centerChunkZ) > outerRadius then
      if record.mesh then self.release(record.mesh) end
      self.records[key] = nil
    end
  end
end

function DistantTerrain:update(world, terrainMeshes, nearEntries, x, z)
  local centerChunkX = math.floor(x / CHUNK_SIZE)
  local centerChunkZ = math.floor(z / CHUNK_SIZE)
  local innerRadius = world.chunkRadius
  local changedCenter = centerChunkX ~= self.centerChunkX or centerChunkZ ~= self.centerChunkZ or
    innerRadius ~= self.innerRadius or self.queuedRadius ~= self.radius
  if changedCenter then
    self:_prune(centerChunkX, centerChunkZ, innerRadius, self.radiusDirty)
    self:_refreshQueue(centerChunkX, centerChunkZ, innerRadius)
    self.radiusDirty = false
  end
  self:_fillQueue(nearEntries)

  local deadline = self.now() + self.frameBudget
  local built = 0

  -- First capture real chunks leaving the full-detail ring. This happens before
  -- game.lua prunes them, so their actual voxel data is never replaced by a
  -- procedural approximation.
  for key, entry in pairs(world.chunks) do
    local distance = math.max(math.abs(entry.chunkX - centerChunkX), math.abs(entry.chunkZ - centerChunkZ))
    if distance > innerRadius and distance <= math.max(self.radius, innerRadius) then
      local record, captured = self:_capture(entry)
      if captured then record.meshDirty = true end
      if built < self.buildBudget and (not record.mesh or record.meshDirty or
          record.meshStep ~= lodStep(distance, innerRadius)) then
        if self:_replaceMesh(record, lodStep(distance, innerRadius), world) then built = built + 1 end
      end
      if built >= self.buildBudget or self.now() >= deadline then break end
    end
  end

  -- Re-select coarser geometry as records move farther from the player. The
  -- compact record is sufficient; the full chunk does not need to stay loaded.
  if built < self.buildBudget then
    for _, record in pairs(self.records) do
      local distance = math.max(math.abs(record.chunkX - centerChunkX), math.abs(record.chunkZ - centerChunkZ))
      if distance > innerRadius and distance <= math.max(self.radius, innerRadius) then
        local step = lodStep(distance, innerRadius)
        if (not record.mesh or record.meshStep ~= step or record.meshDirty) and
            self:_replaceMesh(record, step, world) then
          built = built + 1
          if built >= self.buildBudget or self.now() >= deadline then break end
        end
      end
    end
  end

  -- If a far-generation job becomes a near chunk while the player moves, hand
  -- that exact job to the normal streamer. It will finish as a full chunk and
  -- cannot race a duplicate generation request.
  for i = #self.active, 1, -1 do
    local item = self.active[i]
    local distance = math.max(math.abs(item.chunkX - centerChunkX), math.abs(item.chunkZ - centerChunkZ))
    if distance <= innerRadius then
      if world.requireChunkLighting then item = world:requireChunkLighting(item) end
      nearEntries[#nearEntries + 1] = item
      self.queued[chunkKey(item.chunkX, item.chunkZ)] = nil
      table.remove(self.active, i)
    end
  end
  if self.activeIndex > #self.active then self.activeIndex = 1 end

  local steps = 0
  local generationWidth = 1
  if world.chunkWorkerCount then
    local workers = math.max(1, world:chunkWorkerCount())
    -- Leave a process slot available for a newly requested collision chunk;
    -- active far jobs cannot be pre-empted once Windows has launched them.
    generationWidth = math.max(1, workers - 1)
  end

  -- Far terrain used to keep only one generation job alive, leaving every
  -- other worker idle. Fill the same pool that near chunks use, then poll it
  -- round-robin under the existing frame/step budget.
  local function fillActive()
    while #self.active < generationWidth do
      local coord = self.queue[self.queueHead]
      if coord then self.queue[self.queueHead] = false; self.queueHead = self.queueHead + 1 end
      while coord and self.records[chunkKey(coord.chunkX, coord.chunkZ)] do
        self.queued[chunkKey(coord.chunkX, coord.chunkZ)] = nil
        coord = self.queue[self.queueHead]
        if coord then self.queue[self.queueHead] = false; self.queueHead = self.queueHead + 1 end
      end
      if not coord then break end
      local key = chunkKey(coord.chunkX, coord.chunkZ)
      local existing = world.chunks[key]
      local item = existing or world:createChunkJob(coord.chunkX, coord.chunkZ, {
        deferLighting = true
      })
      item.chunkX, item.chunkZ = coord.chunkX, coord.chunkZ
      self.active[#self.active + 1] = item
    end
  end

  fillActive()
  while steps < self.generationSteps and self.now() < deadline do
    if #self.active == 0 then break end
    if self.activeIndex > #self.active then self.activeIndex = 1 end
    local index = self.activeIndex
    local item = self.active[index]
    if item.thread and not item.entry then
      local ok, err = coroutine.resume(item.thread)
      if not ok then error(err) end
      steps = steps + 1
      if coroutine.status(item.thread) == "dead" and not item.entry then
        self.queued[chunkKey(item.chunkX, item.chunkZ)] = nil
        table.remove(self.active, index)
      else
        self.activeIndex = index + 1
      end
    else
      local entry = item.entry or item
      local distance = math.max(math.abs(entry.chunkX - centerChunkX), math.abs(entry.chunkZ - centerChunkZ))
      local key = chunkKey(entry.chunkX, entry.chunkZ)
      if distance <= innerRadius then
        nearEntries[#nearEntries + 1] = item.entry and item or entry
      else
        local record = self:_capture(entry)
        if built < self.buildBudget then
          self:_replaceMesh(record, lodStep(distance, innerRadius), world)
          built = built + 1
        end
        -- The compact LOD record is now authoritative for far rendering. Keep
        -- full chunks only when the normal renderer already owns a mesh.
        if not terrainMeshes[key] then
          world.chunks[key] = nil
          -- Do not let the lighting touch-set retain the heavy voxel entry we
          -- just compacted. Any loaded neighbour touched by its boundary light
          -- remains queued under that neighbour's own key.
          if world.lightTouched then world.lightTouched[key] = nil end
        end
      end
      self.queued[key] = nil
      table.remove(self.active, index)
      steps = steps + 1
    end
    if self.activeIndex > #self.active then self.activeIndex = 1 end
    fillActive()
  end

  local queued = math.max(0, #self.queue - self.queueHead + 1) + #self.active
  local total = math.max(0, (self.radius * 2 + 1) ^ 2 - (innerRadius * 2 + 1) ^ 2)
  return {
    built = built,
    generationSteps = steps,
    queued = queued,
    active = #self.active,
    total = total,
    scheduledThrough = math.min(self.radius, (self.nextRing or innerRadius + 1) - 1),
    radius = self.radius
  }
end

function DistantTerrain:visible(frustum, aabbInFrustum, centerChunkX, centerChunkZ, innerRadius)
  local visible = {}
  local outerRadius = math.max(self.radius, innerRadius)
  for _, record in pairs(self.records) do
    local mesh = record.mesh
    local distance = math.max(math.abs(record.chunkX - centerChunkX), math.abs(record.chunkZ - centerChunkZ))
    if mesh and distance > innerRadius and distance <= outerRadius and
        (not mesh.bounds or aabbInFrustum(frustum, mesh.bounds)) then
      visible[#visible + 1] = mesh
    end
  end
  return visible
end

DistantTerrain.TERRAIN_STRIDE = TERRAIN_STRIDE
DistantTerrain.WATER_STRIDE = WATER_STRIDE
DistantTerrain.lodStep = lodStep

return DistantTerrain
