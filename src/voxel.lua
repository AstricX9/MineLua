local ffi = require("ffi")
local blocks = require("blocks")
local terrain = require("terrain")

local M = {}

M.STRIDE_FLOATS = 14

local MATERIAL_SOLID = 0.0
local MATERIAL_LEAVES = 1.0
local MATERIAL_FOLIAGE = 2.0
local MATERIAL_ICE = 3.0
local MATERIAL_GLASS = 4.0

local WHITE = {1.0, 1.0, 1.0}
-- Hoisted: this used to be built fresh on every vertexAO call, which meant one
-- table allocation per vertex of every face in the chunk.
local AO_LEVELS = {1.00, 0.82, 0.67, 0.52}

-- y-rows meshed between yields. Smaller keeps the frame budget tight at the cost
-- of a little more coroutine overhead.
local MESH_YIELD_ROWS = 32

-- Flat id -> boolean lookups, so the hot paths stop walking
-- blocks.list[id].properties.<field> several times per vertex.
local aoSolid, faceSolid, faceLeaves, faceCutout, faceDielectric
local lookupCount = -1

local function ensureLookups()
  local n = 0
  for _ in pairs(blocks.list) do n = n + 1 end
  if n == lookupCount then
    return
  end

  lookupCount = n
  aoSolid, faceSolid, faceLeaves, faceCutout, faceDielectric = {}, {}, {}, {}, {}
  for id, def in pairs(blocks.list) do
    local p = def.properties
    local dielectric = p and (p.ice or p.glass) or false
    aoSolid[id] = (p and p.solid and not p.cutout and not dielectric) or false
    -- Keep the opaque contact face behind a transparent dielectric block. It
    -- becomes the transmitted scene sampled by the dedicated material pass.
    faceSolid[id] = (p and p.solid and not dielectric) or false
    faceLeaves[id] = (p and p.leaves) or false
    faceCutout[id] = (p and p.cutout) or false
    faceDielectric[id] = dielectric
  end
end

-- The four quad corners for each face direction, as (sx, sy, sz) selectors. The
-- same triple gives the vertex position (x+sx, y+sy, z+sz) and the corner that
-- ambient occlusion and smooth lighting sample around.
local FACE_CORNERS = {
  {{1,0,1}, {1,0,0}, {1,1,0}, {1,1,1}}, -- 1: +X
  {{0,0,0}, {0,0,1}, {0,1,1}, {0,1,0}}, -- 2: -X
  {{0,1,1}, {1,1,1}, {1,1,0}, {0,1,0}}, -- 3: +Y
  {{0,0,0}, {1,0,0}, {1,0,1}, {0,0,1}}, -- 4: -Y
  {{0,0,1}, {1,0,1}, {1,1,1}, {0,1,1}}, -- 5: +Z
  {{1,0,0}, {0,0,0}, {0,1,0}, {1,1,0}}  -- 6: -Z
}

-- Two triangles from four corners: A B C, C D A.
local CORNER_ORDER = {1, 2, 3, 3, 4, 1}
-- Corner n always carries the same UV: A=(u0,v1) B=(u1,v1) C=(u1,v0) D=(u0,v0).
local CORNER_HIGH_U = {false, true, true, false}
local CORNER_HIGH_V = {true, true, false, false}

-- Reused across faces so the per-corner results cost no allocation.
local cornerLight = {0.0, 0.0, 0.0, 0.0}
local cornerHeight = {0.0, 0.0, 0.0, 0.0}

local function lightCurve(level)
  local darkness = 1.0 - math.max(0.0, math.min(15.0, level)) / 15.0
  return (1.0 - darkness) / (darkness * 3.0 + 1.0)
end

local function isSolidForAO(id)
  if id == 0 then
    return false
  end
  return aoSolid[id] == true
end

local function cornerBasis(nx, ny, nz, cx, cy, cz)
  local sx = cx > 0.5 and 1 or -1
  local sy = cy > 0.5 and 1 or -1
  local sz = cz > 0.5 and 1 or -1
  local ax, ay, az, bx, by, bz, ox, oy, oz

  if nx ~= 0 then
    ox, oy, oz = nx, 0, 0
    ax, ay, az = 0, sy, 0
    bx, by, bz = 0, 0, sz
  elseif ny ~= 0 then
    ox, oy, oz = 0, ny, 0
    ax, ay, az = sx, 0, 0
    bx, by, bz = 0, 0, sz
  else
    ox, oy, oz = 0, 0, nz
    ax, ay, az = sx, 0, 0
    bx, by, bz = 0, sy, 0
  end

  return ox, oy, oz, ax, ay, az, bx, by, bz
end

local function smoothSkyLight(skyAt, x, y, z, nx, ny, nz, cx, cy, cz)
  local ox, oy, oz, ax, ay, az, bx, by, bz = cornerBasis(nx, ny, nz, cx, cy, cz)
  local baseX, baseY, baseZ = x + ox, y + oy, z + oz
  return (
    skyAt(baseX, baseY, baseZ) +
    skyAt(baseX + ax, baseY + ay, baseZ + az) +
    skyAt(baseX + bx, baseY + by, baseZ + bz) +
    skyAt(baseX + ax + bx, baseY + ay + by, baseZ + az + bz)
  ) * 0.25
end

local function vertexAO(sampleBlock, x, y, z, nx, ny, nz, cx, cy, cz)
  local ox, oy, oz, ax, ay, az, bx, by, bz = cornerBasis(nx, ny, nz, cx, cy, cz)

  local sideA = isSolidForAO(sampleBlock(x + ox + ax, y + oy + ay, z + oz + az))
  local sideB = isSolidForAO(sampleBlock(x + ox + bx, y + oy + by, z + oz + bz))
  local corner = isSolidForAO(sampleBlock(x + ox + ax + bx, y + oy + ay + by, z + oz + az + bz))

  if sideA and sideB then
    return 0.45
  end

  local occupied = (sideA and 1 or 0) + (sideB and 1 or 0) + (corner and 1 or 0)
  return AO_LEVELS[occupied + 1]
end

local function materialFor(def)
  local props = def and def.properties
  if props and props.cross then
    return MATERIAL_FOLIAGE
  end
  if props and props.glass then
    return MATERIAL_GLASS
  end
  if props and props.ice then
    return MATERIAL_ICE
  end
  if props and props.leaves then
    return MATERIAL_LEAVES
  end
  return MATERIAL_SOLID
end

local function push_vertex(verts, n, vx, vy, vz, nx, ny, nz, r, g, b, u, v, material, heightFactor, vertexLight)
  verts[n + 1] = vx; verts[n + 2] = vy; verts[n + 3] = vz
  verts[n + 4] = nx; verts[n + 5] = ny; verts[n + 6] = nz
  verts[n + 7] = r; verts[n + 8] = g; verts[n + 9] = b
  verts[n + 10] = u; verts[n + 11] = v
  verts[n + 12] = material
  verts[n + 13] = heightFactor
  verts[n + 14] = vertexLight
  return n + 14
end

-- Appends a quad (two triangles) for a single face. The quad has six vertices
-- but only four distinct corners, so lighting and AO are evaluated four times.
local function append_face(verts, n, sampleBlock, lx, ly, lz, x, y, z, dir, nx, ny, nz, r, g, b, uv, def, skyAt, auxiliary)
  local corners = FACE_CORNERS[dir]
  local material = materialFor(def)
  local isLeaves = material == MATERIAL_LEAVES
  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1

  for i = 1, 4 do
    local c = corners[i]
    local cx, cy, cz = c[1], c[2], c[3]
    local sky = smoothSkyLight(skyAt, lx, ly, lz, nx, ny, nz, cx, cy, cz)
    local ao = vertexAO(sampleBlock, lx, ly, lz, nx, ny, nz, cx, cy, cz)
    if isLeaves and ao < 0.78 then
      ao = 0.78
    end
    cornerLight[i] = lightCurve(sky) * ao
    cornerHeight[i] = isLeaves and cy or
      ((material == MATERIAL_ICE or material == MATERIAL_GLASS) and (auxiliary or 1.0) or 0.0)
  end

  for i = 1, 6 do
    local ci = CORNER_ORDER[i]
    local c = corners[ci]
    n = push_vertex(verts, n,
      x + c[1], y + c[2], z + c[3],
      nx, ny, nz, r, g, b,
      CORNER_HIGH_U[ci] and u1 or u0,
      CORNER_HIGH_V[ci] and v1 or v0,
      material, cornerHeight[ci], cornerLight[ci])
  end

  return n
end

local function append_cross(verts, n, lx, ly, lz, x, y, z, r, g, b, uv, skyAt)
  local inset = 0.0625
  local x0, x1 = x + inset, x + 1.0 - inset
  local y0, y1 = y, y + 1.0
  local z0, z1 = z + inset, z + 1.0 - inset
  local d = 0.70710678
  local sky = math.max(skyAt(lx, ly, lz), skyAt(lx, ly + 1, lz))
  local light = lightCurve(sky)
  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1

  -- first blade, p0 p1 p2 / p2 p3 p0
  n = push_vertex(verts, n, x0,y0,z0, -d,0,d, r,g,b, u0,v1, MATERIAL_FOLIAGE, 0.0, light)
  n = push_vertex(verts, n, x1,y0,z1, -d,0,d, r,g,b, u1,v1, MATERIAL_FOLIAGE, 0.0, light)
  n = push_vertex(verts, n, x1,y1,z1, -d,0,d, r,g,b, u1,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x1,y1,z1, -d,0,d, r,g,b, u1,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x0,y1,z0, -d,0,d, r,g,b, u0,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x0,y0,z0, -d,0,d, r,g,b, u0,v1, MATERIAL_FOLIAGE, 0.0, light)

  -- second blade
  n = push_vertex(verts, n, x1,y0,z0, d,0,d, r,g,b, u0,v1, MATERIAL_FOLIAGE, 0.0, light)
  n = push_vertex(verts, n, x0,y0,z1, d,0,d, r,g,b, u1,v1, MATERIAL_FOLIAGE, 0.0, light)
  n = push_vertex(verts, n, x0,y1,z1, d,0,d, r,g,b, u1,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x0,y1,z1, d,0,d, r,g,b, u1,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x1,y1,z0, d,0,d, r,g,b, u0,v0, MATERIAL_FOLIAGE, 1.0, light)
  n = push_vertex(verts, n, x1,y0,z0, d,0,d, r,g,b, u0,v1, MATERIAL_FOLIAGE, 0.0, light)

  return n
end

-- Resolves one face colour without building a closure or a fresh colour table.
local function faceRGB(def, face, biomeTint, tintAllFaces, ao)
  local colors = def.colors
  local color = (colors and colors[face]) or def.color or WHITE
  local r, g, b = color[1], color[2], color[3]

  if biomeTint and (face == "top" or tintAllFaces) then
    r = r * biomeTint[1]
    g = g * biomeTint[2]
    b = b * biomeTint[3]
  end

  return r * ao, g * ao, b * ao
end

function M.meshChunk(chunk, maxh, offsetX, offsetZ, options)
  options = options or {}
  ensureLookups()

  local step = options.yieldStep
  offsetX = offsetX or 0
  offsetZ = offsetZ or 0
  local verts = {}
  local dielectricVerts = {}
  local n = 0
  local dielectricN = 0
  local skyLightAtWorld = options.skyLightAt
  local blockAtWorld = options.blockAt
  -- Yielding once per x-slice made a single step up to 9 ms, which the frame
  -- budget can only overshoot. Yield every MESH_YIELD_ROWS y-rows instead.
  local sinceYield = 0

  -- Local (lx, y, lz) -> block id. With a world sampler the mesher sees into
  -- neighbouring chunks, so boundary faces get culled and AO is correct there.
  -- Without one it falls back to this chunk alone, treating outside as air.
  local sampleBlock
  if blockAtWorld then
    sampleBlock = function(lx, y, lz)
      return blockAtWorld(lx + offsetX, y, lz + offsetZ)
    end
  else
    sampleBlock = function(lx, y, lz)
      if lx < 0 or lx > 15 or y < 0 or y > 255 or lz < 0 or lz > 15 then
        return 0
      end
      return chunk:getBlock(lx, y, lz)
    end
  end

  local function skyAt(lx, y, lz)
    if skyLightAtWorld then
      return skyLightAtWorld(lx + offsetX, y, lz + offsetZ)
    end
    if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y > maxh then
      return 15
    end
    if y < 0 then
      return 0
    end
    return chunk:getSkyLight(lx, y, lz)
  end

  local function occludes_face(x, y, z, currentId, currentIsLeaves, currentIsDielectric)
    local id = sampleBlock(x, y, z)
    if id == 0 then return false end
    if id == currentId then return true end
    if currentIsDielectric and faceDielectric[id] then return false end
    if currentIsLeaves and faceLeaves[id] then return true end
    if faceCutout[id] then return false end
    return faceSolid[id] == true
  end

  local function dielectricThickness(x, y, z, dx, dy, dz, currentId)
    local thickness = 1
    for distance = 1, 11 do
      local id = sampleBlock(x + dx * distance, y + dy * distance, z + dz * distance)
      if id ~= currentId then break end
      thickness = thickness + 1
    end
    return thickness
  end

  for x = 0, 15 do
    for y = 0, maxh do
      for z = 0, 15 do
        local id = chunk:getBlock(x, y, z)
        if id ~= 0 then
          local def = blocks.list[id]
          if not def then
            goto continue_block
          end
          local props = def.properties
          if props and props.liquid then
            goto continue_block
          end

          -- Keep block colors crisp; directional lighting and fog handle depth.
          local ao = 0.98
          local wx = x + offsetX
          local wz = z + offsetZ
          local biomeTint = nil
          if def.biomeTint then
            biomeTint = terrain.grassColorAt(wx, wz)
          end
          -- Leaves use grayscale mask textures just like cross-plane plants.
          -- Tinting only their top face leaves the four visible sides white,
          -- which made temperate spruce crowns look permanently snow-covered.
          local tintAllFaces = (props and (props.plant or props.leaves)) and true or false

          if props and props.cross then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            n = append_cross(verts, n, x, y, z, wx, y, wz, r, g, b, def.uvs.side or def.uvs.top, skyAt)
            goto continue_block
          end

          local currentIsLeaves = faceLeaves[id] == true
          local currentIsDielectric = faceDielectric[id] == true
          local targetVerts = currentIsDielectric and dielectricVerts or verts
          local targetN = currentIsDielectric and dielectricN or n
          local uvs = def.uvs

          if not occludes_face(x + 1, y, z, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, -1, 0, 0, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 1, 1, 0, 0, r, g, b, uvs.side, def, skyAt, thickness)
          end
          if not occludes_face(x - 1, y, z, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, 1, 0, 0, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 2, -1, 0, 0, r, g, b, uvs.side, def, skyAt, thickness)
          end
          if not occludes_face(x, y + 1, z, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "top", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, 0, -1, 0, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 3, 0, 1, 0, r, g, b, uvs.top, def, skyAt, thickness)
          end
          if not occludes_face(x, y - 1, z, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "bottom", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, 0, 1, 0, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 4, 0, -1, 0, r, g, b, uvs.bottom, def, skyAt, thickness)
          end
          if not occludes_face(x, y, z + 1, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, 0, 0, -1, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 5, 0, 0, 1, r, g, b, uvs.side, def, skyAt, thickness)
          end
          if not occludes_face(x, y, z - 1, id, currentIsLeaves, currentIsDielectric) then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            local thickness = currentIsDielectric and dielectricThickness(x, y, z, 0, 0, 1, id) or nil
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, wx, y, wz, 6, 0, 0, -1, r, g, b, uvs.side, def, skyAt, thickness)
          end

          if currentIsDielectric then
            dielectricN = targetN
          else
            n = targetN
          end
        end
        ::continue_block::
      end

      sinceYield = sinceYield + 1
      if step and sinceYield >= MESH_YIELD_ROWS then
        sinceYield = 0
        step()
      end
    end
  end

  return verts, dielectricVerts
end

return M
