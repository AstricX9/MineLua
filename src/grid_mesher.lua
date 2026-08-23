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

-- Ambient occlusion levels by how many of the three blocks around a corner are
-- solid. This is where a voxel world gets its depth: the Cartesian lighting
-- module is a stub that hands out 15 nearly everywhere, so AO was always doing
-- the visual work.
local AO_LEVELS = {1.00, 0.82, 0.67, 0.52}
local AO_BOTH_SIDES = 0.45

-- Sky light falls off with depth below the column's highest solid block, so
-- caves read as caves. Fifteen is open sky.
local SKY_LIGHT_MAX = 15.0
local SKY_LIGHT_FALLOFF = 1.6
-- How far above a chunk to look for the block that shades it.
local SKY_PROBE_HEIGHT = 24

-- Minecraft's light curve: level 15 is full, and each step down is a fixed
-- ratio rather than a linear drop.
local function lightCurve(level)
  local darkness = 1.0 - math.max(0.0, math.min(15.0, level)) / 15.0
  return (1.0 - darkness) / (darkness * 3.0 + 1.0)
end

local CORNER_ORDER = {1, 2, 3, 3, 4, 1}
local CORNER_HIGH_U = {false, true, true, false}
local CORNER_HIGH_V = {true, true, false, false}

local solidLookup, cutoutLookup, leavesLookup, liquidLookup, opaqueLookup, crossLookup
local lookupCount = -1

local function ensureLookups()
  local count = 0
  for _ in pairs(blocks.list) do count = count + 1 end
  if count == lookupCount then return end
  lookupCount = count
  solidLookup, cutoutLookup, leavesLookup, liquidLookup, opaqueLookup, crossLookup =
    {}, {}, {}, {}, {}, {}
  for id, def in pairs(blocks.list) do
    local p = def.properties
    solidLookup[id] = (p and p.solid and not p.cutout) or false
    cutoutLookup[id] = (p and p.cutout) or false
    leavesLookup[id] = (p and p.leaves) or false
    liquidLookup[id] = (p and p.liquid) or false
    crossLookup[id] = (p and p.cross) or false
    -- Only fully opaque blocks occlude: leaves and cutouts must not.
    opaqueLookup[id] = (p and p.solid and not p.cutout and not p.leaves
      and not p.liquid and not p.ice) or false
  end
end

-- Which way a face points, and which two axes span it, given the voxel frame.
-- axis 1 is up (radial), 2 the column axis, 3 the row axis.
-- Steps to a neighbouring voxel in grid coordinates. Tangential steps go
-- through the grid, which carries a cube-sphere face seam correctly; the radial
-- step is a layer.
local function neighbourVoxel(grid, face, column, row, layer, columnStep, rowStep, layerStep)
  if columnStep == 0 and rowStep == 0 then
    return face, column, row, layer + layerStep
  end
  local nf, nc, nr = grid:neighbour(face, column, row, columnStep, rowStep)
  return nf, nc, nr, layer + layerStep
end

-- The two axes that span a face, as grid steps. Axis 1 is radial, 2 the column
-- axis and 3 the row axis, matching FACES.
local FACE_SPAN_STEPS = {
  -- {normal step}, {first span axis step}, {second span axis step}
  {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
  {{0, 0, -1}, {1, 0, 0}, {0, 1, 0}},
  {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
  {{-1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
  {{0, 1, 0}, {1, 0, 0}, {0, 0, 1}},
  {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}}
}

-- Classic voxel ambient occlusion: for each corner of a face, look at the two
-- blocks beside it and the one diagonally across. Two solid sides mean a hard
-- crease, so the corner goes darkest regardless of the diagonal.
local function cornerOcclusion(grid, blockAt, opaque, face, column, row, layer, faceIndex, spanA, spanB)
  local steps = FACE_SPAN_STEPS[faceIndex]
  local normal, axisA, axisB = steps[1], steps[2], steps[3]
  local function sample(a, b)
    local dc = normal[1] + axisA[1] * a + axisB[1] * b
    local dr = normal[2] + axisA[2] * a + axisB[2] * b
    local dl = normal[3] + axisA[3] * a + axisB[3] * b
    local nf, nc, nr, nl = neighbourVoxel(grid, face, column, row, layer, dc, dr, dl)
    return opaque[blockAt(nf, nc, nr, nl)] == true
  end
  local sideA = sample(spanA, 0)
  local sideB = sample(0, spanB)
  if sideA and sideB then return AO_BOTH_SIDES end
  local corner = sample(spanA, spanB)
  local occupied = (sideA and 1 or 0) + (sideB and 1 or 0) + (corner and 1 or 0)
  return AO_LEVELS[occupied + 1]
end

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
  -- Leaves go to their own array: they are alpha-blended in a later pass, so
  -- mixing them into the opaque mesh would sort wrong against everything.
  local leafVertices, leafN = {}, 0
  local half = grid.voxelSizeMeters * 0.5
  local baseColumn = chunkColumn * CHUNK_SIZE
  local baseRow = chunkRow * CHUNK_SIZE
  local baseLayer = chunkLayer * CHUNK_SIZE
  local processed = 0

  for row = 0, CHUNK_SIZE - 1 do
    for column = 0, CHUNK_SIZE - 1 do
      local gridColumn, gridRow = baseColumn + column, baseRow + row
      local ux, uy, uz, rx, ry, rz, fx, fy, fz = grid:voxelFrame(gridFace, gridColumn, gridRow)

      -- Highest opaque block in this column, scanned from well above the chunk.
      -- Anything at or below it is out of direct sky and darkens with depth.
      local skyTopLayer = baseLayer - 1
      for probe = baseLayer + CHUNK_SIZE + SKY_PROBE_HEIGHT, baseLayer, -1 do
        if opaqueLookup[blockAt(gridFace, gridColumn, gridRow, probe)] then
          skyTopLayer = probe
          break
        end
      end

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
          if definition and definition.uvs and crossLookup[id] then
            -- Two quads crossed on the diagonals, standing along the local up.
            local radius = grid:layerCenterRadius(gridLayer)
            local cx = center[1] + ux * radius - renderOrigin[1]
            local cy = center[2] + uy * radius - renderOrigin[2]
            local cz = center[3] + uz * radius - renderOrigin[3]
            local uv = definition.uvs.side or definition.uvs.top
            local colour = (definition.colors and definition.colors.side) or {1, 1, 1}
            local red, green, blue = colour[1], colour[2], colour[3]
            if definition.biomeTint and tintAt then
              local tr, tg, tb = tintAt(gridFace, gridColumn, gridRow)
              red, green, blue = red * tr, green * tg, blue * tb
            end
            local light = lightCurve(SKY_LIGHT_MAX)
            local halfVoxel = half
            for blade = 1, 2 do
              -- The two diagonals of the column/row plane.
              local ax = (blade == 1 and rx + fx or rx - fx) * 0.7071
              local ay = (blade == 1 and ry + fy or ry - fy) * 0.7071
              local az = (blade == 1 and rz + fz or rz - fz) * 0.7071
              local nx = (blade == 1 and rx - fx or rx + fx) * 0.7071
              local ny = (blade == 1 and ry - fy or ry + fy) * 0.7071
              local nz = (blade == 1 and rz - fz or rz + fz) * 0.7071
              for index = 1, 6 do
                local corner = CORNER_ORDER[index]
                local sideways = CORNER_HIGH_U[corner] and 1.0 or -1.0
                local upward = CORNER_HIGH_V[corner] and -1.0 or 1.0
                vertices[n + 1] = cx + ax * sideways * halfVoxel + ux * upward * halfVoxel
                vertices[n + 2] = cy + ay * sideways * halfVoxel + uy * upward * halfVoxel
                vertices[n + 3] = cz + az * sideways * halfVoxel + uz * upward * halfVoxel
                vertices[n + 4], vertices[n + 5], vertices[n + 6] = nx, ny, nz
                vertices[n + 7], vertices[n + 8], vertices[n + 9] = red, green, blue
                vertices[n + 10] = CORNER_HIGH_U[corner] and uv.u1 or uv.u0
                vertices[n + 11] = CORNER_HIGH_V[corner] and uv.v1 or uv.v0
                vertices[n + 12] = MATERIAL_FOLIAGE
                -- Foliage uses this channel for its anchored height, so wind
                -- bends the top of a blade and leaves the root still.
                vertices[n + 13] = CORNER_HIGH_V[corner] and 0.0 or 1.0
                vertices[n + 14] = light
                n = n + 14
              end
            end
          elseif definition and definition.uvs then
            local radius = grid:layerCenterRadius(gridLayer)
            local cx = center[1] + ux * radius - renderOrigin[1]
            local cy = center[2] + uy * radius - renderOrigin[2]
            local cz = center[3] + uz * radius - renderOrigin[3]
            local material = leavesLookup[id] and MATERIAL_LEAVES or MATERIAL_SOLID
            local skyLevel = SKY_LIGHT_MAX
            -- Strictly below: a block is not its own occluder, or every
            -- surface in open sky would come out a third dark.
            if gridLayer < skyTopLayer then
              skyLevel = SKY_LIGHT_MAX - (skyTopLayer - gridLayer + 1) * SKY_LIGHT_FALLOFF
              if skyLevel < 0.0 then skyLevel = 0.0 end
            end
            local light = lightAt and lightAt(gridFace, gridColumn, gridRow, gridLayer)
              or lightCurve(skyLevel)
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
                local target, targetIndex = vertices, n
                if material == MATERIAL_LEAVES then target, targetIndex = leafVertices, leafN end
                -- Face centre is half a voxel out along the face normal.
                local ox, oy, oz = cx + nx * half, cy + ny * half, cz + nz * half

                for index = 1, 6 do
                  local corner = CORNER_ORDER[index]
                  local sa, sb = quad[corner][1], quad[corner][2]
                  local ao = cornerOcclusion(grid, blockAt, opaqueLookup,
                    gridFace, gridColumn, gridRow, gridLayer, face, sa, sb)
                  local vx = ox + ax * sa * half + bx * sb * half
                  local vy = oy + ay * sa * half + by * sb * half
                  local vz = oz + az * sa * half + bz * sb * half
                  target[targetIndex + 1] = vx
                  target[targetIndex + 2] = vy
                  target[targetIndex + 3] = vz
                  target[targetIndex + 4] = nx
                  target[targetIndex + 5] = ny
                  target[targetIndex + 6] = nz
                  target[targetIndex + 7] = red
                  target[targetIndex + 8] = green
                  target[targetIndex + 9] = blue
                  target[targetIndex + 10] = CORNER_HIGH_U[corner] and uv.u1 or uv.u0
                  target[targetIndex + 11] = CORNER_HIGH_V[corner] and uv.v1 or uv.v0
                  target[targetIndex + 12] = material
                  -- Spare channel carries AO so unlit ground keeps its corner
                  -- definition instead of flattening to one ambient value.
                  target[targetIndex + 13] = ao
                  target[targetIndex + 14] = light * ao
                  targetIndex = targetIndex + 14
                end
                if material == MATERIAL_LEAVES then leafN = targetIndex else n = targetIndex end
              end
            end
          end
        end
        processed = processed + 1
        if step and processed % 512 == 0 then step() end
      end
    end
  end

  return vertices, leafVertices
end

GridMesher.CHUNK_SIZE = CHUNK_SIZE
GridMesher.FACES = FACES

return GridMesher
