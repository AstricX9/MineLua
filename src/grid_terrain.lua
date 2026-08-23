-- Terrain generation onto the spherical voxel grid.
--
-- The grid changes the shape of this problem for the better. On the Cartesian
-- lattice a "column" is not a column: the radial direction wanders across a
-- chunk, so the surface had to be evaluated per voxel -- 4096 samples for a
-- 16-cube, each one about forty-five octaves of noise. Here a column really is
-- a column. Every voxel in it shares one direction, so it shares one surface
-- radius, and a whole chunk needs 256 samples instead of 4096.
--
-- Chunk layout inside the 16-cube is (column, layer, row) -> (x, y, z), so y is
-- up. That matches what the mesher and the lighting flood fill already assume
-- about which axis points at the sky.

local terrain = require("terrain")
local blocks = require("blocks")
local Chunk = require("chunk")

local GridTerrain = {}

local CHUNK_SIZE = 16
local SURFACE_BLOCK_DEPTH = 9.0

-- Surface samples for the 256 columns of one chunk column-stack, plus the
-- radial band they span. The band is exact -- these are all the columns the
-- chunk contains, not an estimate from its corners -- so the empty and buried
-- fast paths below never guess.
function GridTerrain.columnSamples(grid, face, chunkColumn, chunkRow, planet, out)
  out = out or {}
  local baseColumn, baseRow = chunkColumn * CHUNK_SIZE, chunkRow * CHUNK_SIZE
  local low, high = math.huge, -math.huge
  local index = 0
  for row = 0, CHUNK_SIZE - 1 do
    for column = 0, CHUNK_SIZE - 1 do
      local dx, dy, dz = grid:columnDirection(face, baseColumn + column, baseRow + row)
      local sample = terrain.surfaceAtDirection({dx, dy, dz}, planet)
      index = index + 1
      out[index] = sample
      local solid = sample.surfaceRadiusVoxels
      -- Water is content too: below sea level, "above the ground" is ocean.
      local wet = sample.waterSurfaceRadiusVoxels or planet.seaLevelRadiusVoxels
      if solid < low then low = solid end
      if solid > high then high = solid end
      if wet > high then high = wet end
    end
  end
  out.n = index
  out.lowRadius, out.highRadius = low, high
  return out
end

local function sampleAt(samples, column, row)
  return samples[row * CHUNK_SIZE + column + 1]
end

GridTerrain.sampleAt = sampleAt

-- Radial band a chunk occupies, in voxels from the planet centre.
function GridTerrain.chunkRadialBounds(grid, chunkLayer)
  local base = chunkLayer * CHUNK_SIZE
  return grid:layerTopRadius(base) - CHUNK_SIZE * grid.voxelSizeMeters,
    grid:layerTopRadius(base + CHUNK_SIZE - 1)
end

-- "empty", "buried", "interior" or "surface". Exact, because the column samples
-- cover every column in the chunk.
function GridTerrain.classify(grid, chunkLayer, planet, samples)
  local lowRadius, highRadius = GridTerrain.chunkRadialBounds(grid, chunkLayer)
  if lowRadius > samples.highRadius then return "empty" end
  local voxel = grid.voxelSizeMeters
  local interiorFloor = samples.lowRadius - planet.generatedInteriorDepthMeters / voxel
  if highRadius < interiorFloor then return "interior" end
  if highRadius < samples.lowRadius - SURFACE_BLOCK_DEPTH / voxel then return "buried" end
  return "surface"
end

-- Ore veins, in the grid's own frame: column and row are tangential, layer is
-- depth. Two things had to change from the Cartesian placer. Its bands are
-- absolute Y on a 0-127 world, which means nothing on a planet, so these are
-- depth below the local surface. And its counts are per 16x128x16 column, which
-- is eight of these chunks -- using them unchanged gave eight times the ore.
local ORE_VEINS = {
  {block = "coal_ore", count = 3, size = 8, minDepth = 4, maxDepth = 80},
  {block = "iron_ore", count = 2, size = 6, minDepth = 8, maxDepth = 64},
  {block = "gold_ore", count = 1, size = 5, minDepth = 24, maxDepth = 96},
  {block = "redstone_ore", count = 1, size = 4, minDepth = 40, maxDepth = 110},
  {block = "lapis_ore", count = 1, size = 4, minDepth = 30, maxDepth = 80},
  {block = "diamond_ore", count = 1, size = 4, minDepth = 50, maxDepth = 110},
  {block = "emerald_ore", count = 1, size = 4, minDepth = 20, maxDepth = 90, biome = "mountains"}
}

local function placeOres(chunk, grid, face, chunkColumn, chunkRow, chunkLayer, planet, samples)
  local stone = blocks.stone
  if not stone then return end
  local baseLayer = chunkLayer * CHUNK_SIZE
  local voxel = grid.voxelSizeMeters

  for veinIndex = 1, #ORE_VEINS do
    local vein = ORE_VEINS[veinIndex]
    local oreId = blocks[vein.block]
    if oreId then
      for attempt = 1, vein.count do
        local salt = 6100 + veinIndex * 31 + attempt
        local seedX = chunkColumn * 16 + attempt
        local seedY = chunkLayer * 16 + veinIndex
        local seedZ = chunkRow * 16 + attempt
        local column = math.floor(terrain.hash3(seedX, seedY, seedZ, salt) * CHUNK_SIZE)
        local row = math.floor(terrain.hash3(seedX, seedY, seedZ, salt + 1) * CHUNK_SIZE)
        local layer = math.floor(terrain.hash3(seedX, seedY, seedZ, salt + 2) * CHUNK_SIZE)
        local sample = sampleAt(samples, column, row)
        local depth = (sample.surfaceRadiusVoxels - grid:layerCenterRadius(baseLayer + layer)) * voxel
        local biomeOk = not vein.biome or sample.biome == vein.biome
        if biomeOk and depth >= vein.minDepth and depth <= vein.maxDepth then
          local radius = 0.9 + terrain.hash3(seedX, seedY, seedZ, salt + 3) * (vein.size * 0.22)
          local reach = math.ceil(radius)
          for dc = -reach, reach do
            for dr = -reach, reach do
              for dl = -reach, reach do
                if dc * dc + dr * dr + dl * dl <= radius * radius then
                  local c, r, l = column + dc, row + dr, layer + dl
                  if c >= 0 and c < CHUNK_SIZE and r >= 0 and r < CHUNK_SIZE
                    and l >= 0 and l < CHUNK_SIZE
                    and chunk:getBlock(c, l, r) == stone then
                    chunk:setBlock(c, l, r, oreId)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- Tall grass and trees.
--
-- Simpler than the Cartesian decorator because a column is a column here: the
-- block above a surface voxel is the next layer up, with no dominant-axis
-- guessing. Trees are only planted where the whole trunk and crown fit inside
-- this chunk, so one never gets sliced in half at a boundary.
local function decorateChunk(chunk, grid, face, chunkColumn, chunkRow, chunkLayer, planet, samples)
  local grassId = blocks.tall_grass
  local logId = blocks.oak_log or blocks.spruce_log
  local leavesId = blocks.oak_leaves or blocks.spruce_leaves
  if not grassId and not (logId and leavesId) then return end
  local airId = blocks.air or 0
  local surfaceIds = {[blocks.grass or -1] = true, [blocks.sand or -2] = true,
    [blocks.gravel or -3] = true}

  local baseColumn = chunkColumn * CHUNK_SIZE
  local baseRow = chunkRow * CHUNK_SIZE
  local baseLayer = chunkLayer * CHUNK_SIZE

  for row = 0, CHUNK_SIZE - 1 do
    for column = 0, CHUNK_SIZE - 1 do
      local sample = sampleAt(samples, column, row)
      local wooded = sample.biome == "forest" or sample.biome == "rainforest"
        or sample.biome == "taiga"
      -- Layers below the top of the chunk, so there is room for what sits above.
      for layer = 0, CHUNK_SIZE - 2 do
        if surfaceIds[chunk:getBlock(column, layer, row)]
          and chunk:getBlock(column, layer + 1, row) == airId then
          local seed = terrain.hash3(baseColumn + column, baseLayer + layer, baseRow + row, 1277)
          -- One in sixty-odd surface columns, not one in four hundred: a tree
          -- also has to fit inside its own chunk, which rejects roughly half
          -- again, and at the original odds a forest had almost no trees.
          if wooded and logId and leavesId and seed > 0.985 then
            local height = 4 + math.floor(terrain.hash3(
              baseColumn + column, baseLayer + layer, baseRow + row, 1283) * 3)
            -- Trunk plus a two-block crown radius has to fit in the chunk.
            if layer + height + 2 < CHUNK_SIZE and column >= 2 and column < CHUNK_SIZE - 2
              and row >= 2 and row < CHUNK_SIZE - 2 then
              for step = 1, height do
                chunk:setBlock(column, layer + step, row, logId)
              end
              local topLayer = layer + height
              for dc = -2, 2 do
                for dr = -2, 2 do
                  for dl = -2, 2 do
                    if dc * dc + dr * dr + dl * dl <= 5
                      and chunk:getBlock(column + dc, topLayer + dl, row + dr) == airId then
                      chunk:setBlock(column + dc, topLayer + dl, row + dr, leavesId)
                    end
                  end
                end
              end
            end
          elseif grassId and chunk:getBlock(column, layer, row) == blocks.grass and seed < 0.075 then
            chunk:setBlock(column, layer + 1, row, grassId)
          end
          break
        end
      end
    end
  end
end

-- Fills one 16-cube. Returns the chunk and the classification it took.
function GridTerrain.fillChunk(grid, face, chunkColumn, chunkRow, chunkLayer, planet, options)
  options = options or {}
  local step = options.yieldStep
  local samples = options.samples or
    GridTerrain.columnSamples(grid, face, chunkColumn, chunkRow, planet)
  local classification = GridTerrain.classify(grid, chunkLayer, planet, samples)

  local airId = blocks.air or 0
  local stoneId = blocks.stone
  local waterId = blocks.water or blocks.water_still

  if classification == "empty" then return Chunk.new(airId), classification, samples end
  if classification == "interior" then return Chunk.new(stoneId), classification, samples end

  local chunk = Chunk.new(airId)
  local baseColumn, baseRow = chunkColumn * CHUNK_SIZE, chunkRow * CHUNK_SIZE
  local baseLayer = chunkLayer * CHUNK_SIZE
  local buried = classification == "buried"
  local processed = 0

  for row = 0, CHUNK_SIZE - 1 do
    for column = 0, CHUNK_SIZE - 1 do
      local sample = sampleAt(samples, column, row)
      local surfaceRadius = sample.surfaceRadiusVoxels
      local waterRadius = sample.waterSurfaceRadiusVoxels or planet.seaLevelRadiusVoxels
      local dx, dy, dz = grid:columnDirection(face, baseColumn + column, baseRow + row)

      for layer = 0, CHUNK_SIZE - 1 do
        local radius = grid:layerCenterRadius(baseLayer + layer)
        local depth = surfaceRadius - radius
        local id = airId
        if depth >= 0.0 then
          -- Caves are sampled at the voxel's real position, so they are the
          -- same tunnels the Cartesian generator carves.
          local wx, wy, wz = dx * radius, dy * radius, dz * radius
          if not terrain.caveAt(wx, wy, wz, depth, planet) then
            id = buried and stoneId or terrain.blockForDepth(sample, depth)
          end
        elseif waterId and radius <= waterRadius then
          id = waterId
        end
        if id ~= airId then chunk:setBlock(column, layer, row, id) end

        processed = processed + 1
        if step and processed % 256 == 0 then step() end
      end
    end
  end

  placeOres(chunk, grid, face, chunkColumn, chunkRow, chunkLayer, planet, samples)
  if not buried then
    decorateChunk(chunk, grid, face, chunkColumn, chunkRow, chunkLayer, planet, samples)
  end
  if step then step() end
  return chunk, classification, samples
end

-- Surface radius directly under a direction, and the layer whose top face is
-- the walkable surface there.
function GridTerrain.surfaceLayer(grid, planet, dx, dy, dz)
  local sample = terrain.surfaceAtDirection({dx, dy, dz}, planet)
  local voxel = grid.voxelSizeMeters
  -- layerTopRadius(k) = reference + k * voxel, and the top face of the highest
  -- solid layer is the ground you stand on.
  local layer = math.floor((sample.surfaceRadiusVoxels - grid.referenceRadius) / voxel)
  return layer, sample
end

GridTerrain.CHUNK_SIZE = CHUNK_SIZE

return GridTerrain
