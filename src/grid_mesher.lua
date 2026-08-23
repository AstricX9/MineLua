-- Meshes a spherical-grid chunk as individually rotated cubes.
--
-- Every voxel is a perfect cube: its eight corners are its centre plus or minus
-- half a voxel along three orthonormal axes. Nothing is stretched, tapered or
-- curved. What changes from voxel to voxel is only where the cube sits and
-- which way it is turned -- its local up is the direction out from the planet
-- centre, so a cube on the far side of the world is upside down relative to one
-- here, and both are still cubes.
--
-- The rotation is baked into the vertex positions and normals, so this needs no
-- shader of its own: the output is the same fourteen-float layout the Cartesian
-- mesher produces and goes through the existing terrain program unchanged.

local blocks = require("blocks")

local GridMesher = {}

local CHUNK_SIZE = 16
GridMesher.STRIDE_FLOATS = 14

local MATERIAL_SOLID = 0.0
local MATERIAL_LEAVES = 1.0
local MATERIAL_FOLIAGE = 2.0

-- The six cube faces, as a sign and which frame axis they face along.
-- 1 = local up (radial), 2 = column axis, 3 = row axis.
local FACES = {
  {axis = 1, sign = 1, kind = "top"},
  {axis = 1, sign = -1, kind = "bottom"},
  {axis = 2, sign = 1, kind = "side"},
  {axis = 2, sign = -1, kind = "side"},
  {axis = 3, sign = 1, kind = "side"},
  {axis = 3, sign = -1, kind = "side"}
}

-- Corner offsets for a face, in (along, across, up-of-texture) order so the
-- winding stays counter-clockwise seen from outside and the texture's own up
-- runs along the local up on side faces. That is the same fix the Cartesian
-- mesher needed: a grass fringe has to lie along the top edge, not up a
-- vertical one.
local FACE_QUADS = {
  -- top: across = column, up-of-texture = row
  {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}},
  -- bottom: wound the other way
  {{-1, 1}, {1, 1}, {1, -1}, {-1, -1}},
  {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}},
  {{1, -1}, {-1, -1}, {-1, 1}, {1, 1}},
  {{1, -1}, {-1, -1}, {-1, 1}, {1, 1}},
  {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
}

local CORNER_ORDER = {1, 2, 3, 3, 4, 1}
local CORNER_HIGH_U = {false, true, true, false}
local CORNER_HIGH_V = {true, true, false, false}

local solidLookup, cutoutLookup, leavesLookup, liquidLookup
local lookupCount = -1

local function ensureLookups()
  local count = 0
  for _ in pairs(blocks.list) do count = count + 1 end
  if count == lookupCount then return end
  lookupCount = count
  solidLookup, cutoutLookup, leavesLookup, liquidLookup = {}, {}, {}, {}
  for id, def in pairs(blocks.list) do
    local p = def.properties
    solidLookup[id] = (p and p.solid and not p.cutout) or false
    cutoutLookup[id] = (p and p.cutout) or false
    leavesLookup[id] = (p and p.leaves) or false
    liquidLookup[id] = (p and p.liquid) or false
  end
end

-- Which way a face points, and which two axes span it, given the voxel frame.
-- axis 1 is up (radial), 2 the column axis, 3 the row axis.
local function faceBasis(face, ux, uy, uz, rx, ry, rz, fx, fy, fz)
  local definition = FACES[face]
  local sign = definition.sign
  if definition.axis == 1 then
    return ux * sign, uy * sign, uz * sign, rx, ry, rz, fx, fy, fz
  elseif definition.axis == 2 then
    -- Side face along the column axis: the texture's up must follow local up.
    return rx * sign, ry * sign, rz * sign, fx, fy, fz, ux, uy, uz
  end
  return fx * sign, fy * sign, fz * sign, rx, ry, rz, ux, uy, uz
end

-- Builds the vertex array for one chunk.
--
-- `blockAt(face, column, row, layer)` must answer for the chunk and one voxel
-- beyond it in every direction, so boundary faces get culled against real
-- neighbours instead of against nothing.
function GridMesher.meshChunk(grid, gridFace, chunkColumn, chunkRow, chunkLayer, options)
  options = options or {}
  ensureLookups()
  local blockAt = assert(options.blockAt, "the mesher needs a block sampler")
  local lightAt = options.lightAt
  -- Per-column biome tint. Grass, leaves and foliage ship greyscale textures
  -- that are meaningless until this is applied.
  local tintAt = options.tintAt
  local renderOrigin = options.renderOrigin or {0.0, 0.0, 0.0}
  local center = options.center or {0.0, 0.0, 0.0}
  local step = options.yieldStep

  local vertices, n = {}, 0
  local half = grid.voxelSizeMeters * 0.5
  local baseColumn = chunkColumn * CHUNK_SIZE
  local baseRow = chunkRow * CHUNK_SIZE
  local baseLayer = chunkLayer * CHUNK_SIZE
  local processed = 0

  for row = 0, CHUNK_SIZE - 1 do
    for column = 0, CHUNK_SIZE - 1 do
      local gridColumn, gridRow = baseColumn + column, baseRow + row
      local ux, uy, uz, rx, ry, rz, fx, fy, fz = grid:voxelFrame(gridFace, gridColumn, gridRow)

      for layer = 0, CHUNK_SIZE - 1 do
        local gridLayer = baseLayer + layer
        local id = blockAt(gridFace, gridColumn, gridRow, gridLayer)
        -- Liquids are never meshed as blocks. An ocean column runs from sea
        -- level down to the sea floor, so meshing it as cubes builds a wall of
        -- water hundreds of metres tall and shows you its cut faces wherever
        -- the loaded region ends. The Cartesian mesher skips them for the same
        -- reason and leaves them to the water pass.
        if id and id ~= 0 and not liquidLookup[id] then
          local definition = blocks.list[id]
          if definition and definition.uvs then
            local radius = grid:layerCenterRadius(gridLayer)
            local cx = center[1] + ux * radius - renderOrigin[1]
            local cy = center[2] + uy * radius - renderOrigin[2]
            local cz = center[3] + uz * radius - renderOrigin[3]
            local material = leavesLookup[id] and MATERIAL_LEAVES or MATERIAL_SOLID
            local light = lightAt and lightAt(gridFace, gridColumn, gridRow, gridLayer) or 1.0
            local tintRed, tintGreen, tintBlue
            if definition.biomeTint and tintAt then
              tintRed, tintGreen, tintBlue = tintAt(gridFace, gridColumn, gridRow)
            end
            -- Leaves and plants are tinted on every face; grass only on top,
            -- because its side texture already has the fringe painted in.
            local tintEverySide = (definition.properties and
              (definition.properties.plant or definition.properties.leaves)) or false

            for face = 1, 6 do
              -- The neighbour across this face. Radial steps are a layer up or
              -- down; tangential ones go through the grid, which is what
              -- carries a face seam across correctly.
              local nf, nc, nr, nl
              if FACES[face].axis == 1 then
                nf, nc, nr, nl = gridFace, gridColumn, gridRow, gridLayer + FACES[face].sign
              else
                local stepColumn = FACES[face].axis == 2 and FACES[face].sign or 0
                local stepRow = FACES[face].axis == 3 and FACES[face].sign or 0
                nf, nc, nr = grid:neighbour(gridFace, gridColumn, gridRow, stepColumn, stepRow)
                nl = gridLayer
              end
              local neighbourId = blockAt(nf, nc, nr, nl)
              local hidden = neighbourId and neighbourId ~= 0 and
                (neighbourId == id or (solidLookup[neighbourId] and not cutoutLookup[neighbourId]))
              if not hidden then
                local nx, ny, nz, ax, ay, az, bx, by, bz =
                  faceBasis(face, ux, uy, uz, rx, ry, rz, fx, fy, fz)
                local kind = FACES[face].kind
                local uv = definition.uvs[kind] or definition.uvs.side or definition.uvs.top
                local colour = (definition.colors and definition.colors[kind]) or {1, 1, 1}
                local shade = kind == "top" and 1.0 or (kind == "bottom" and 0.58 or 0.82)
                local red, green, blue = colour[1] * shade, colour[2] * shade, colour[3] * shade
                if tintRed and (kind == "top" or tintEverySide) then
                  red, green, blue = red * tintRed, green * tintGreen, blue * tintBlue
                end
                local quad = FACE_QUADS[face]
                -- Face centre is half a voxel out along the face normal.
                local ox, oy, oz = cx + nx * half, cy + ny * half, cz + nz * half

                for index = 1, 6 do
                  local corner = CORNER_ORDER[index]
                  local sa, sb = quad[corner][1], quad[corner][2]
                  local vx = ox + ax * sa * half + bx * sb * half
                  local vy = oy + ay * sa * half + by * sb * half
                  local vz = oz + az * sa * half + bz * sb * half
                  vertices[n + 1], vertices[n + 2], vertices[n + 3] = vx, vy, vz
                  vertices[n + 4], vertices[n + 5], vertices[n + 6] = nx, ny, nz
                  vertices[n + 7], vertices[n + 8], vertices[n + 9] = red, green, blue
                  vertices[n + 10] = CORNER_HIGH_U[corner] and uv.u1 or uv.u0
                  vertices[n + 11] = CORNER_HIGH_V[corner] and uv.v1 or uv.v0
                  vertices[n + 12] = material
                  vertices[n + 13] = 1.0
                  vertices[n + 14] = light
                  n = n + 14
                end
              end
            end
          end
        end
        processed = processed + 1
        if step and processed % 512 == 0 then step() end
      end
    end
  end

  return vertices
end

GridMesher.CHUNK_SIZE = CHUNK_SIZE
GridMesher.FACES = FACES

return GridMesher
