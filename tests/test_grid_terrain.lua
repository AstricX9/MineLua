-- Terrain generation onto the spherical grid.
--
-- The property that justifies the whole rewrite is the last one: on this grid,
-- flat ground is flat. The Cartesian lattice cannot manage that anywhere except
-- near six points on the planet.

package.path = "src/?.lua;" .. package.path

local SphericalGrid = require("spherical_grid")
local GridTerrain = require("grid_terrain")
local Planet = require("planet")
local terrain = require("terrain")
local blocks = require("blocks")

local planet = Planet.new()
local grid = SphericalGrid.new({
  radiusMeters = planet.radiusMeters,
  voxelSizeMeters = planet.voxelSizeMeters
})
terrain.setSeed(1)

local CHUNK = GridTerrain.CHUNK_SIZE
local airId = blocks.air or 0

-- A chunk stack on dry land, away from the seams and the sheared corners. The
-- first place tried was sea floor, where every voxel is solid and the tests
-- below would have passed without ever crossing the surface.
local chunkCount = math.floor(grid.resolution / CHUNK)
local face, chunkColumn, chunkRow, samples
for candidateFace = 1, SphericalGrid.FACE_COUNT do
  for i = 1, 7 do
    for j = 1, 7 do
      if not face then
        local column = math.floor(chunkCount * i / 8)
        local row = math.floor(chunkCount * j / 8)
        local candidate = GridTerrain.columnSamples(grid, candidateFace, column, row, planet)
        -- The whole 16 m footprint has to be above water, so the column stack
        -- really does contain an air/ground boundary. The first site tried was
        -- open ocean, where every voxel is solid and the checks below would
        -- have passed without ever crossing the surface.
        if candidate.lowRadius - planet.radiusVoxels > 4.0 then
          face, chunkColumn, chunkRow, samples = candidateFace, column, row, candidate
        end
      end
    end
  end
end
assert(face, "found dry land to test on")
print(string.format("test site: face %d, chunk column %d, row %d", face, chunkColumn, chunkRow))
assert(samples.n == CHUNK * CHUNK, "one surface sample per column of the chunk")
print(string.format("column band: %.1f m to %.1f m above sea level",
  samples.lowRadius - planet.radiusVoxels, samples.highRadius - planet.radiusVoxels))

-- The chunk layer that straddles the ground.
local groundLayer = math.floor((samples.lowRadius - grid.referenceRadius) / grid.voxelSizeMeters)
local groundChunkLayer = math.floor(groundLayer / CHUNK)

-- 1. Classification is exact, because the samples cover every column.
assert(GridTerrain.classify(grid, groundChunkLayer + 40, planet, samples) == "empty",
  "a chunk well above the ground is empty")
assert(GridTerrain.classify(grid, groundChunkLayer - 40, planet, samples) == "interior",
  "a chunk well below the ground is solid interior")
local nearClass = GridTerrain.classify(grid, groundChunkLayer, planet, samples)
assert(nearClass == "surface" or nearClass == "buried",
  "the chunk at the ground is generated properly, saw " .. nearClass)

-- 2. Generation is deterministic.
local first = GridTerrain.fillChunk(grid, face, chunkColumn, chunkRow, groundChunkLayer, planet)
local second = GridTerrain.fillChunk(grid, face, chunkColumn, chunkRow, groundChunkLayer, planet)
for x = 0, CHUNK - 1 do
  for y = 0, CHUNK - 1 do
    for z = 0, CHUNK - 1 do
      assert(first:getBlock(x, y, z) == second:getBlock(x, y, z),
        "the same chunk generates the same blocks twice")
    end
  end
end

-- 3. Columns are ordered. Going down a column the ground must start once and
--    keep going, apart from caves -- no floating soil, no soil under stone.
local baseLayer = groundChunkLayer * CHUNK
local checkedColumns, solidColumns = 0, 0
for row = 0, CHUNK - 1 do
  for column = 0, CHUNK - 1 do
    local sample = GridTerrain.sampleAt(samples, column, row)
    local surface = sample.surfaceRadiusVoxels
    checkedColumns = checkedColumns + 1
    local sawSolid = false
    for layer = CHUNK - 1, 0, -1 do
      local id = first:getBlock(column, layer, row)
      local radius = grid:layerCenterRadius(baseLayer + layer)
      local depth = surface - radius
      if id ~= airId and id ~= blocks.water and id ~= blocks.water_still then
        sawSolid = true
        solidColumns = solidColumns + 1
        assert(depth >= 0.0,
          string.format("solid blocks only appear at or below the surface (depth %.3f)", depth))
        -- And the block matches the depth rule, unless a cave removed it.
        assert(id == terrain.blockForDepth(sample, depth),
          "a block matches the shared depth-to-block rule")
      elseif sawSolid and id == airId then
        -- Air under solid is allowed only where a cave carved it.
        local dx, dy, dz = grid:columnDirection(
          face, chunkColumn * CHUNK + column, chunkRow * CHUNK + row)
        assert(terrain.caveAt(dx * radius, dy * radius, dz * radius, depth, planet),
          "air below the ground is a cave, not a hole in the generator")
      end
    end
  end
end
print(string.format("checked %d columns, %d solid voxels", checkedColumns, solidColumns))

-- 4. Cost. A column is genuinely a column here, so the expensive surface
--    evaluation happens 256 times per chunk rather than 4096.
local clock = os.clock
local started = clock()
local rounds = 6
for i = 1, rounds do
  GridTerrain.fillChunk(grid, face, chunkColumn + i, chunkRow, groundChunkLayer, planet)
end
local perChunk = (clock() - started) * 1000.0 / rounds
print(string.format("surface chunk: %.1f ms", perChunk))

-- 5. The point of all of it, measured the same way for both topologies.
--
--    A perfectly smooth sphere stands in for terrain, so every wobble is the
--    addressing and not the landscape. On the Cartesian lattice the walkable
--    surface ranges over about a metre away from its three axes; on this grid
--    a layer's radius depends only on its index, so it cannot wobble at all.
local flatRadius = grid.referenceRadius + 50.0
local floor = math.floor

local function cartesianSurface(dx, dy, dz)
  -- Highest voxel centre inside the sphere, along the radial ray -- the same
  -- rule terrain.fillPlanetChunk uses on the Cartesian lattice.
  for offset = 24.0, -24.0, -0.02 do
    local radius = flatRadius + offset
    local cx = floor(dx * radius) + 0.5
    local cy = floor(dy * radius) + 0.5
    local cz = floor(dz * radius) + 0.5
    if math.sqrt(cx * cx + cy * cy + cz * cz) <= flatRadius then return offset end
  end
  return nil
end

local function gridSurface(column, row)
  local layer = floor((flatRadius - grid.referenceRadius) / grid.voxelSizeMeters)
  return grid:layerTopRadius(layer) - flatRadius
end

-- Walk about 120 m from the test site. Sampled at quarter-metre steps in
-- parameter space and starting somewhere generic: walking along a lattice axis
-- and sampling at whole metres lands on the same point inside every voxel,
-- which reports the Cartesian lattice as perfectly smooth when it is not.
local baseColumn = chunkColumn * CHUNK
local baseRow = chunkRow * CHUNK
local startS = grid:columnParameter(baseColumn)
local startT = grid:columnParameter(baseRow)
local parameterPerMetre = 2.0 / (grid.resolution * grid.voxelSizeMeters)

local gridLow, gridHigh = math.huge, -math.huge
local flatLow, flatHigh = math.huge, -math.huge
for i = 0, 480 do
  local metres = i * 0.25
  local dx, dy, dz = SphericalGrid.faceDirection(face, startS + metres * parameterPerMetre, startT)
  local lattice = cartesianSurface(dx, dy, dz)
  if lattice then
    flatLow, flatHigh = math.min(flatLow, lattice), math.max(flatHigh, lattice)
  end

  local column = baseColumn + math.floor(metres)
  local height = gridSurface(column, baseRow)
  gridLow, gridHigh = math.min(gridLow, height), math.max(gridHigh, height)
end

local gridRange, latticeRange = gridHigh - gridLow, flatHigh - flatLow
print(string.format("flat ground over 120 m: spherical grid %.6f m, Cartesian lattice %.3f m",
  gridRange, latticeRange))
assert(gridRange < 1e-9,
  string.format("flat ground is flat on the spherical grid (saw %.6f m)", gridRange))
assert(latticeRange > 0.3,
  string.format("and the comparison is real -- the lattice does wobble (saw %.3f m)", latticeRange))

local ax, ay, az = SphericalGrid.faceDirection(face, startS, startT)
local bx, by, bz = SphericalGrid.faceDirection(face, startS + 120.0 * parameterPerMetre, startT)
local separation = math.acos(math.max(-1.0, math.min(1.0, ax * bx + ay * by + az * bz)))
print(string.format("that walk covered %.1f m of arc", separation * grid.referenceRadius))
assert(separation * grid.referenceRadius > 100.0, "and it really covered ground")

print("grid terrain tests passed")
