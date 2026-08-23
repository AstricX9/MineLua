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
