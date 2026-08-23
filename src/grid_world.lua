-- A patch of spherical-grid voxels that answers the questions the player
-- physics asks: is this point solid, and is there loaded terrain here.
--
-- It is not the streaming world yet. It holds whatever chunks were generated
-- around a position and answers about them, which is enough to stand on the
-- grid terrain and walk about on it rather than only look at it.

local SphericalGrid = require("spherical_grid")
local GridTerrain = require("grid_terrain")
local blocks = require("blocks")
local terrain = require("terrain")

local GridWorld = {}
GridWorld.__index = GridWorld

local CHUNK_SIZE = GridTerrain.CHUNK_SIZE
local floor, sqrt, ceil = math.floor, math.sqrt, math.ceil

function GridWorld.new(planet, seed, options)
  options = options or {}
  return setmetatable({
    planet = planet,
    seed = seed or 1,
    grid = options.grid or SphericalGrid.new({
      radiusMeters = planet.radiusMeters,
      voxelSizeMeters = planet.voxelSizeMeters
    }),
    chunks = {},
    samples = {},
    solidCache = {}
  }, GridWorld)
end

local function chunkKey(face, column, row, layer)
  return face .. ":" .. column .. ":" .. row .. ":" .. layer
end

local function stackKey(face, column, row)
  return face .. ":" .. column .. ":" .. row
end

GridWorld.chunkKey = chunkKey

function GridWorld:columnSamples(face, chunkColumn, chunkRow)
  local key = stackKey(face, chunkColumn, chunkRow)
  local cached = self.samples[key]
  if not cached then
    terrain.setSeed(self.seed)
    cached = GridTerrain.columnSamples(self.grid, face, chunkColumn, chunkRow, self.planet)
    self.samples[key] = cached
  end
  return cached
end

-- Generates the column stack around one tangential cell and returns how many
-- chunks it made.
function GridWorld:ensureStack(face, chunkColumn, chunkRow, padding)
  padding = padding or 1
  local samples = self:columnSamples(face, chunkColumn, chunkRow)
  local grid = self.grid
  local voxel = grid.voxelSizeMeters
  local lowLayer = floor((samples.lowRadius - grid.referenceRadius) / voxel / CHUNK_SIZE)
  local highLayer = floor((samples.highRadius - grid.referenceRadius) / voxel / CHUNK_SIZE)
  local made = 0
  for chunkLayer = lowLayer - padding, highLayer + padding do
    local key = chunkKey(face, chunkColumn, chunkRow, chunkLayer)
    if not self.chunks[key] then
      terrain.setSeed(self.seed)
      local chunk, classification = GridTerrain.fillChunk(
        grid, face, chunkColumn, chunkRow, chunkLayer, self.planet, {samples = samples})
      if classification ~= "empty" then
        self.chunks[key] = {chunk = chunk, classification = classification,
          face = face, chunkColumn = chunkColumn, chunkRow = chunkRow, chunkLayer = chunkLayer}
        made = made + 1
      end
    end
  end
  return made
end

-- Voxel address of a world point: face, column, row and layer.
--
-- Layer k occupies the shell (top(k) - voxel, top(k)], which is why this
-- rounds up: with the top-corner pivot a layer is named by the radius of its
-- upper face, not its centre.
function GridWorld:locatePoint(x, y, z)
  local planet = self.planet
  local rx, ry, rz = x - planet.center[1], y - planet.center[2], z - planet.center[3]
  local radius = sqrt(rx * rx + ry * ry + rz * rz)
  if radius <= 0.0 then return nil end
  local face, column, row = self.grid:locate(rx / radius, ry / radius, rz / radius)
  local layer = ceil((radius - self.grid.referenceRadius) / self.grid.voxelSizeMeters)
  return face, column, row, layer, radius
end

function GridWorld:blockAtVoxel(face, column, row, layer)
  local chunkColumn = floor(column / CHUNK_SIZE)
  local chunkRow = floor(row / CHUNK_SIZE)
  local chunkLayer = floor(layer / CHUNK_SIZE)
  local entry = self.chunks[chunkKey(face, chunkColumn, chunkRow, chunkLayer)]
  if not entry then
    -- Nothing generated here. If the column stack is known, everything below
    -- its lowest surface is rock and everything above its highest is air, so
    -- the answer is still exact without generating anything.
    local samples = self.samples[stackKey(face, chunkColumn, chunkRow)]
    if not samples then return nil end
    if self.grid:layerTopRadius(layer) <= samples.lowRadius then return blocks.stone end
    return 0
  end
  return entry.chunk:getBlock(
    column - chunkColumn * CHUNK_SIZE,
    layer - chunkLayer * CHUNK_SIZE,
    row - chunkRow * CHUNK_SIZE)
end

function GridWorld:blockAtPoint(x, y, z)
  local face, column, row, layer = self:locatePoint(x, y, z)
  if not face then return nil end
  return self:blockAtVoxel(face, column, row, layer)
end

function GridWorld:isSolidAtPoint(x, y, z)
  local id = self:blockAtPoint(x, y, z)
  if not id or id == 0 then return false end
  local cached = self.solidCache[id]
  if cached == nil then
    local definition = blocks.list[id]
    cached = (definition and definition.properties and definition.properties.solid) or false
    self.solidCache[id] = cached
  end
  return cached
end

-- Whether this patch knows about a point at all. Outside it the player physics
-- treats the ground as missing rather than as air, so they do not fall through
-- the edge of the generated region.
function GridWorld:hasCollisionAtPoint(x, y, z)
  local face, column, row = self:locatePoint(x, y, z)
  if not face then return false end
  return self.samples[stackKey(face, floor(column / CHUNK_SIZE), floor(row / CHUNK_SIZE))] ~= nil
end

-- Surface radius for a direction, straight from the generator. Used to place
-- the player on the grid terrain rather than on the Cartesian one.
function GridWorld:surfaceRadius(dx, dy, dz)
  terrain.setSeed(self.seed)
  local sample = terrain.surfaceAtDirection({dx, dy, dz}, self.planet)
  return sample.surfaceRadiusVoxels, sample
end

-- Creates an empty chunk on demand, so a block can be placed in open air where
-- generation never stored anything.
function GridWorld:ensureChunk(face, chunkColumn, chunkRow, chunkLayer)
  local key = chunkKey(face, chunkColumn, chunkRow, chunkLayer)
  local entry = self.chunks[key]
  if entry then return entry end
  if not self.samples[stackKey(face, chunkColumn, chunkRow)] then return nil end
  local Chunk = require("chunk")
  entry = {
    chunk = Chunk.new(blocks.air or 0), classification = "surface",
    face = face, chunkColumn = chunkColumn, chunkRow = chunkRow, chunkLayer = chunkLayer
  }
  self.chunks[key] = entry
  return entry
end

-- Sets a voxel and reports which chunks now need remeshing: its own, plus any
-- neighbour that shares a face with it, since a boundary block changes what the
-- neighbour culls against.
function GridWorld:setBlockAtVoxel(face, column, row, layer, id)
  local chunkColumn = floor(column / CHUNK_SIZE)
  local chunkRow = floor(row / CHUNK_SIZE)
  local chunkLayer = floor(layer / CHUNK_SIZE)
  local entry = self:ensureChunk(face, chunkColumn, chunkRow, chunkLayer)
  if not entry then return nil end

  local localColumn = column - chunkColumn * CHUNK_SIZE
  local localLayer = layer - chunkLayer * CHUNK_SIZE
  local localRow = row - chunkRow * CHUNK_SIZE
  if entry.chunk:getBlock(localColumn, localLayer, localRow) == id then return nil end
  entry.chunk:setBlock(localColumn, localLayer, localRow, id)

  local touched = {[chunkKey(face, chunkColumn, chunkRow, chunkLayer)] = true}
  -- Radial neighbours.
  if localLayer == 0 then
    touched[chunkKey(face, chunkColumn, chunkRow, chunkLayer - 1)] = true
  elseif localLayer == CHUNK_SIZE - 1 then
    touched[chunkKey(face, chunkColumn, chunkRow, chunkLayer + 1)] = true
  end
  -- Tangential neighbours, which may sit on another cube-sphere face.
  for _, step in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
    if (step[1] == 1 and localColumn == CHUNK_SIZE - 1) or (step[1] == -1 and localColumn == 0)
      or (step[2] == 1 and localRow == CHUNK_SIZE - 1) or (step[2] == -1 and localRow == 0) then
      local nf, nc, nr = self.grid:neighbour(face, column, row, step[1], step[2])
      touched[chunkKey(nf, floor(nc / CHUNK_SIZE), floor(nr / CHUNK_SIZE), chunkLayer)] = true
    end
  end
  return touched
end

-- Ray march for block selection.
--
-- A true DDA wants a lattice with straight cell boundaries; this grid curves,
-- so the ray is stepped finely instead and the first solid sample wins. Over a
-- six metre reach at a centimetre a step that is six hundred point samples of
-- pure arithmetic, and it is accurate to a hundredth of a one-metre block --
-- far finer than the player can aim.
function GridWorld:raycast(origin, direction, maxDistance, step)
  maxDistance = maxDistance or 6.0
  step = step or 0.01
  local previousFace, previousColumn, previousRow, previousLayer
  local distance = 0.0
  while distance <= maxDistance do
    local x = origin[1] + direction[1] * distance
    local y = origin[2] + direction[2] * distance
    local z = origin[3] + direction[3] * distance
    local face, column, row, layer = self:locatePoint(x, y, z)
    if face then
      local id = self:blockAtVoxel(face, column, row, layer)
      if id == nil then return nil end
      if id ~= 0 then
        local definition = blocks.list[id]
        local properties = definition and definition.properties
        if properties and (properties.solid or properties.targetable or properties.breakable)
            and not properties.liquid then
          return {
            face = face, column = column, row = row, layer = layer, id = id,
            distance = distance,
            previous = previousFace and {
              face = previousFace, column = previousColumn,
              row = previousRow, layer = previousLayer
            } or nil
          }
        end
      end
      previousFace, previousColumn, previousRow, previousLayer = face, column, row, layer
    end
    distance = distance + step
  end
  return nil
end

-- Drops a column stack and everything in it. Returns the chunk keys removed so
-- their meshes can go with them.
function GridWorld:releaseStack(face, chunkColumn, chunkRow)
  local removed = {}
  for key, entry in pairs(self.chunks) do
    if entry.face == face and entry.chunkColumn == chunkColumn and entry.chunkRow == chunkRow then
      self.chunks[key] = nil
      removed[#removed + 1] = key
    end
  end
  self.samples[stackKey(face, chunkColumn, chunkRow)] = nil
  return removed
end

function GridWorld:chunkCount()
  local count = 0
  for _ in pairs(self.chunks) do count = count + 1 end
  return count
end

GridWorld.CHUNK_SIZE = CHUNK_SIZE

return GridWorld
