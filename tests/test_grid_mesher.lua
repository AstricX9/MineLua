-- Meshing the spherical grid as individually rotated cubes.
--
-- The claims that matter are geometric, so they are measured off the emitted
-- vertices rather than inferred from a screenshot: every quad is a square of
-- exactly one voxel, every cube is orthonormal, and the seam between
-- neighbouring cubes at the reference radius is the sub-micron one the top
-- corner pivot promises.

package.path = "src/?.lua;" .. package.path

local SphericalGrid = require("spherical_grid")
local GridMesher = require("grid_mesher")
local blocks = require("blocks")

-- Textures are assigned by the atlas at run time, which needs a GL context.
-- A headless run only needs the UV rectangles to exist.
local stubUv = {u0 = 0.0, v0 = 0.0, u1 = 0.25, v1 = 0.25}
for _, definition in pairs(blocks.list) do
  definition.uvs = {top = stubUv, bottom = stubUv, side = stubUv}
  definition.colors = definition.colors or {top = {1, 1, 1}, bottom = {1, 1, 1}, side = {1, 1, 1}}
end

local grid = SphericalGrid.new({radiusMeters = 6371000.0, voxelSizeMeters = 1.0})
local STRIDE = GridMesher.STRIDE_FLOATS
local CHUNK = GridMesher.CHUNK_SIZE
local stone = blocks.stone

local face = 1
local chunkColumn = math.floor(grid.resolution / CHUNK / 2)
local chunkRow = chunkColumn
local chunkLayer = 0

-- Vertices come out at roughly 6.4e6 m from the planet centre, which a 32-bit
-- float resolves to about half a metre. The floating origin is not an
-- optimisation on this grid, it is the only way the geometry survives being
-- put in a vertex buffer at all -- so the tests below run through it, exactly
-- as the renderer will.
local originX, originY, originZ = grid:voxelCenter(face,
  chunkColumn * CHUNK + 8, chunkRow * CHUNK + 8, chunkLayer * CHUNK + 8)
local renderOrigin = {originX, originY, originZ}
local TOLERANCE = 1e-9

local function vertexAt(vertices, index)
  local base = (index - 1) * STRIDE
  return vertices[base + 1], vertices[base + 2], vertices[base + 3],
    vertices[base + 4], vertices[base + 5], vertices[base + 6]
end

local function length(x, y, z) return math.sqrt(x * x + y * y + z * z) end

-- 1. One lone voxel gives six faces and nothing else.
local soloColumn = chunkColumn * CHUNK + 8
local soloRow = chunkRow * CHUNK + 8
local soloLayer = chunkLayer * CHUNK + 8
local solo = GridMesher.meshChunk(grid, face, chunkColumn, chunkRow, chunkLayer, {
  renderOrigin = renderOrigin,
  blockAt = function(f, c, r, l)
    if f == face and c == soloColumn and r == soloRow and l == soloLayer then return stone end
    return 0
  end
})
local soloVertices = #solo / STRIDE
assert(soloVertices == 36,
  string.format("a lone cube emits six quads, saw %d vertices", soloVertices))

-- 2. Those quads describe a perfect cube: every edge exactly one voxel, every
--    face square, every normal unit length and perpendicular to its face.
local voxel = grid.voxelSizeMeters
for quad = 0, 5 do
  local base = quad * 6
  local ax, ay, az, nx, ny, nz = vertexAt(solo, base + 1)
  local bx, by, bz = vertexAt(solo, base + 2)
  local cx, cy, cz = vertexAt(solo, base + 3)
  local edge1 = length(bx - ax, by - ay, bz - az)
  local edge2 = length(cx - bx, cy - by, cz - bz)
  assert(math.abs(edge1 - voxel) < TOLERANCE,
    string.format("quad %d edge is one voxel, saw %.12f", quad, edge1))
  assert(math.abs(edge2 - voxel) < TOLERANCE,
    string.format("quad %d edge is one voxel, saw %.12f", quad, edge2))
  -- Square, not a rhombus: the two edges meet at a right angle.
  local dot = ((bx - ax) * (cx - bx) + (by - ay) * (cy - by) + (bz - az) * (cz - bz)) / (edge1 * edge2)
  assert(math.abs(dot) < TOLERANCE, string.format("quad %d is square, saw cos %.3e", quad, dot))
  assert(math.abs(length(nx, ny, nz) - 1.0) < TOLERANCE, "normals are unit length")
  local alongFace = ((bx - ax) * nx + (by - ay) * ny + (bz - az) * nz) / edge1
  assert(math.abs(alongFace) < TOLERANCE, "the normal is perpendicular to its own face")
end

-- 3. Every corner is exactly half a voxel diagonal from the cube centre, which
--    is the definition of an undeformed cube.
local centreX, centreY, centreZ = grid:voxelCenter(face, soloColumn, soloRow, soloLayer)
centreX, centreY, centreZ = centreX - originX, centreY - originY, centreZ - originZ
local expected = voxel * math.sqrt(3.0) * 0.5
for index = 1, soloVertices do
  local x, y, z = vertexAt(solo, index)
  local distance = length(x - centreX, y - centreY, z - centreZ)
  assert(math.abs(distance - expected) < TOLERANCE,
    string.format("corner sits on the cube's circumsphere, saw %.12f against %.12f", distance, expected))
end

-- 4. The top face points along local up, and the bottom against it.
local ux, uy, uz = grid:columnDirection(face, soloColumn, soloRow)
local _, _, _, topNx, topNy, topNz = vertexAt(solo, 1)
assert(topNx * ux + topNy * uy + topNz * uz > 0.999999, "the first quad is the top, facing local up")
local _, _, _, bottomNx, bottomNy, bottomNz = vertexAt(solo, 7)
assert(bottomNx * ux + bottomNy * uy + bottomNz * uz < -0.999999, "the second is the bottom")

-- 5. Interior voxels emit nothing: a solid chunk is hollow from outside.
local solid = GridMesher.meshChunk(grid, face, chunkColumn, chunkRow, chunkLayer, {
  renderOrigin = renderOrigin,
  blockAt = function() return stone end
})
assert(#solid == 0, "a chunk with solid neighbours all round emits no faces at all")

-- 6. The seam. Two neighbouring surface cubes, both with their top face at the
--    reference radius: how far apart are the corners that are meant to touch?
--    This is the number the top-corner pivot exists to make small.
local function topFaceCorners(column, row, layer)
  local mesh = GridMesher.meshChunk(grid, face,
    math.floor(column / CHUNK), math.floor(row / CHUNK), math.floor(layer / CHUNK), {
      renderOrigin = renderOrigin,
      blockAt = function(f, c, r, l)
        if f == face and c == column and r == row and l == layer then return stone end
        return 0
      end
    })
  local corners = {}
  for index = 1, 6 do
    local x, y, z = vertexAt(mesh, index)
    corners[#corners + 1] = {x, y, z}
  end
  return corners
end

local layerAtReference = -1 -- top face of layer -1 is the reference radius
local left = topFaceCorners(soloColumn, soloRow, layerAtReference)
local right = topFaceCorners(soloColumn + 1, soloRow, layerAtReference)
local closest = math.huge
for _, a in ipairs(left) do
  for _, b in ipairs(right) do
    closest = math.min(closest, length(a[1] - b[1], a[2] - b[2], a[3] - b[3]))
  end
end
print(string.format("neighbouring surface cubes: nearest top corners %.3f um apart", closest * 1e6))
assert(closest < 1e-3,
  string.format("the surface seam is sub-millimetre (saw %.6f m)", closest))

-- 6b. Liquids are never meshed as blocks. An ocean column is hundreds of metres
--     deep, so meshing it as cubes builds a wall of water and shows its cut
--     faces wherever the loaded region ends.
local water = blocks.water or blocks.water_still
if water then
  local flooded = GridMesher.meshChunk(grid, face, chunkColumn, chunkRow, chunkLayer, {
    renderOrigin = renderOrigin,
    blockAt = function(f, c, r, l)
      if f == face and c == soloColumn and r == soloRow and l == soloLayer then return water end
      return 0
    end
  })
  assert(#flooded == 0,
    string.format("a lone water voxel emits nothing, saw %d vertices", #flooded / STRIDE))

  -- And a solid block next to water still shows the face they share, because
  -- water is transparent and must not cull it.
  local beside = GridMesher.meshChunk(grid, face, chunkColumn, chunkRow, chunkLayer, {
    renderOrigin = renderOrigin,
    blockAt = function(f, c, r, l)
      if f ~= face or c ~= soloColumn or r ~= soloRow then return 0 end
      if l == soloLayer then return stone end
      if l == soloLayer + 1 then return water end
      return 0
    end
  })
  assert(#beside / STRIDE == 36,
    string.format("the stone under water keeps all six faces, saw %d", #beside / STRIDE))
end

-- 6c. Ambient occlusion. A corner tucked against neighbouring blocks must come
--     out darker than one in the open. This is where the world gets its depth:
--     the lighting module is a stub that hands out full sky light nearly
--     everywhere, so AO does the visual work.
local function topFaceLight(neighbours)
  local mesh = GridMesher.meshChunk(grid, face, chunkColumn, chunkRow, chunkLayer, {
    renderOrigin = renderOrigin,
    blockAt = function(f, c, r, l)
      if f ~= face then return 0 end
      if c == soloColumn and r == soloRow and l == soloLayer then return stone end
      for _, n in ipairs(neighbours) do
        if c == soloColumn + n[1] and r == soloRow + n[2] and l == soloLayer + n[3] then
          return stone
        end
      end
      return 0
    end
  })
  -- Light lives in the last float of each vertex; the top face is emitted
  -- first. Report the darkest and brightest of its four corners.
  local low, high = math.huge, -math.huge
  for index = 1, 6 do
    local value = mesh[(index - 1) * STRIDE + STRIDE]
    low, high = math.min(low, value), math.max(high, value)
  end
  return low, high
end

local openLow, openHigh = topFaceLight({})
assert(math.abs(openHigh - openLow) < 1e-9, "an isolated block has no occlusion anywhere on its top")

-- One block beside and above, shading two of the top corners.
local shadedLow, shadedHigh = topFaceLight({{1, 0, 1}})
assert(shadedLow < openLow - 0.01,
  string.format("a shaded corner is darker (%.4f against %.4f)", shadedLow, openLow))
assert(shadedHigh > shadedLow,
  "and the far corners of the same face stay brighter, so it is a gradient not a flat dim")

-- Blocks on both sides of a corner give the hardest crease.
local creaseLow = topFaceLight({{1, 0, 1}, {0, 1, 1}})
assert(creaseLow < shadedLow,
  string.format("two occluders darken a corner further (%.4f against %.4f)", creaseLow, shadedLow))
print(string.format("AO: open %.3f, one occluder %.3f, corner crease %.3f",
  openLow, shadedLow, creaseLow))

-- 7. Cost, on a chunk that is all surface.
local clock = os.clock
local started = clock()
local rounds = 4
local total = 0
for i = 1, rounds do
  local mesh = GridMesher.meshChunk(grid, face, chunkColumn + i, chunkRow, chunkLayer, {
    renderOrigin = renderOrigin,
    blockAt = function(f, c, r, l)
      -- A flat slab: solid up to the middle layer, air above.
      return l <= chunkLayer * CHUNK + 7 and stone or 0
    end
  })
  total = total + #mesh / STRIDE
end
print(string.format("slab chunk: %.1f ms, %d vertices", (clock() - started) * 1000.0 / rounds, total / rounds))

print("grid mesher tests passed")
