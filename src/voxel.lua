local ffi = require("ffi")
local blocks = require("blocks")
local terrain = require("terrain")

local M = {}

M.STRIDE_FLOATS = 14

local MATERIAL_SOLID = 0.0
local MATERIAL_LEAVES = 1.0
local MATERIAL_FOLIAGE = 2.0
local MATERIAL_ICE = 3.0

local WHITE = {1.0, 1.0, 1.0}
-- Hoisted: this used to be built fresh on every vertexAO call, which meant one
-- table allocation per vertex of every face in the chunk.
local AO_LEVELS = {1.00, 0.82, 0.67, 0.52}

-- y-rows meshed between yields. Smaller keeps the frame budget tight at the cost
-- of a little more coroutine overhead.
local MESH_YIELD_ROWS = 32

-- Flat id -> boolean lookups, so the hot paths stop walking
-- blocks.list[id].properties.<field> several times per vertex.
local aoSolid, faceSolid, faceLeaves, faceCutout, faceIce
local lookupCount = -1

local function ensureLookups()
  local n = 0
  for _ in pairs(blocks.list) do n = n + 1 end
  if n == lookupCount then
    return
  end

  lookupCount = n
  aoSolid, faceSolid, faceLeaves, faceCutout, faceIce = {}, {}, {}, {}, {}
  for id, def in pairs(blocks.list) do
    local p = def.properties
    aoSolid[id] = (p and p.solid and not p.cutout and not p.ice) or false
    -- Opaque blocks next to ice keep their contact face so it can be seen
    -- through the transmissive ice pass.
    faceSolid[id] = (p and p.solid and not p.ice) or false
    faceLeaves[id] = (p and p.leaves) or false
    faceCutout[id] = (p and p.cutout) or false
    faceIce[id] = (p and p.ice) or false
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
-- So corners 3 and 4 are the pair along the top edge of the texture.
local CORNER_HIGH_U = {false, true, true, false}
local CORNER_HIGH_V = {true, true, false, false}

-- These corner lists were written for a world whose up is always +Y. On a
-- planet the local up is the radial direction, so at the default spawn it is
-- roughly +Z and every side texture came out rotated a quarter turn: the grass
-- fringe on a dirt block ran up a vertical edge instead of along the top.
--
-- Rotating the UV assignment around the quad by r fixes it. Only the pairing
-- changes, never the vertex order, so the winding is untouched. Ties keep r=0,
-- which is the original Y-up behaviour.
--
-- FACE_EDGE_DIRECTIONS[dir][i] is the outward direction of the edge shared by
-- corners i and i+1, precomputed so the per-face lookup is four dot products
-- and no allocation. Corner offsets are 0 or 1, so a+b-1 is the sum of the two
-- corners measured from the block centre.
local FACE_EDGE_DIRECTIONS = {}
for dir = 1, 6 do
  local corners = FACE_CORNERS[dir]
  local edges = {}
  for i = 1, 4 do
    local a, b = corners[i], corners[i % 4 + 1]
    edges[i] = {a[1] + b[1] - 1.0, a[2] + b[2] - 1.0, a[3] + b[3] - 1.0}
  end
  FACE_EDGE_DIRECTIONS[dir] = edges
end

local function faceUvRotation(dir, up)
  if not up then return 0 end
  local edges = FACE_EDGE_DIRECTIONS[dir]
  local upX, upY, upZ = up[1], up[2], up[3]
  local reference = edges[3]
  local bestIndex = 3
  local bestScore = reference[1] * upX + reference[2] * upY + reference[3] * upZ
  for i = 1, 4 do
    local e = edges[i]
    local score = e[1] * upX + e[2] * upY + e[3] * upZ
    if score > bestScore + 1e-9 then bestIndex, bestScore = i, score end
  end
  return (3 - bestIndex) % 4
end

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
  if props and props.ice then
    return MATERIAL_ICE
  end
  if props and props.leaves then
    return MATERIAL_LEAVES
  end
  return MATERIAL_SOLID
end

local FACE_NORMALS={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}

local function faceKindFor(properties, direction, localUp)
  local axis = properties and properties.logAxis
  if axis == "x" then
    return direction <= 2 and "top" or "side"
  elseif axis == "z" then
    return direction >= 5 and "top" or "side"
  end
  if localUp then
    local normal=FACE_NORMALS[direction]
    local alignment=normal[1]*localUp[1]+normal[2]*localUp[2]+normal[3]*localUp[3]
    if alignment>0.5 then return "top" end
    if alignment< -0.5 then return "bottom" end
    return "side"
  end
  if direction == 3 then return "top" end
  if direction == 4 then return "bottom" end
  return "side"
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
local function append_face(verts, n, sampleBlock, lx, ly, lz, x, y, z, dir, nx, ny, nz, r, g, b, uv, def, skyAt, auxiliary, uvRotation)
  local corners = FACE_CORNERS[dir]
  uvRotation = uvRotation or 0
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
    -- Foliage needs its anchored height for wind. Solid vertices use this spare
    -- channel for AO so completely unlit caves still retain corner definition
    -- instead of collapsing to one flat ambient-floor value.
    cornerHeight[i] = isLeaves and cy or (material == MATERIAL_ICE and (auxiliary or 1.0) or ao)
  end

  for i = 1, 6 do
    local ci = CORNER_ORDER[i]
    local c = corners[ci]
    local ui = (ci - 1 + uvRotation) % 4 + 1
    n = push_vertex(verts, n,
      x + c[1], y + c[2], z + c[3],
      nx, ny, nz, r, g, b,
      CORNER_HIGH_U[ui] and u1 or u0,
      CORNER_HIGH_V[ui] and v1 or v0,
      material, cornerHeight[ci], cornerLight[ci])
  end

  return n
end

local function append_cross(verts, n, lx, ly, lz, x, y, z, r, g, b, uv, skyAt, localUp)
  local up = localUp or {0.0, 1.0, 0.0}
  local reference = math.abs(up[2]) < 0.85 and {0.0,1.0,0.0} or {1.0,0.0,0.0}
  local tx = reference[2]*up[3]-reference[3]*up[2]
  local ty = reference[3]*up[1]-reference[1]*up[3]
  local tz = reference[1]*up[2]-reference[2]*up[1]
  local tl = math.sqrt(tx*tx+ty*ty+tz*tz)
  tx,ty,tz=tx/tl,ty/tl,tz/tl
  local bx=up[2]*tz-up[3]*ty
  local by=up[3]*tx-up[1]*tz
  local bz=up[1]*ty-up[2]*tx
  local cx,cy,cz=x+0.5,y+0.5,z+0.5
  local rootX,rootY,rootZ=cx-up[1]*0.5,cy-up[2]*0.5,cz-up[3]*0.5
  local topX,topY,topZ=rootX+up[1],rootY+up[2],rootZ+up[3]
  local half=0.44
  local sky = math.max(skyAt(lx, ly, lz), skyAt(lx, ly + 1, lz))
  local light = lightCurve(sky)
  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1

  local function blade(ax,ay,az,nx,ny,nz)
    local r0={rootX-ax*half,rootY-ay*half,rootZ-az*half}
    local r1={rootX+ax*half,rootY+ay*half,rootZ+az*half}
    local t0={topX-ax*half,topY-ay*half,topZ-az*half}
    local t1={topX+ax*half,topY+ay*half,topZ+az*half}
    n=push_vertex(verts,n,r0[1],r0[2],r0[3],nx,ny,nz,r,g,b,u0,v1,MATERIAL_FOLIAGE,0.0,light)
    n=push_vertex(verts,n,r1[1],r1[2],r1[3],nx,ny,nz,r,g,b,u1,v1,MATERIAL_FOLIAGE,0.0,light)
    n=push_vertex(verts,n,t1[1],t1[2],t1[3],nx,ny,nz,r,g,b,u1,v0,MATERIAL_FOLIAGE,1.0,light)
    n=push_vertex(verts,n,t1[1],t1[2],t1[3],nx,ny,nz,r,g,b,u1,v0,MATERIAL_FOLIAGE,1.0,light)
    n=push_vertex(verts,n,t0[1],t0[2],t0[3],nx,ny,nz,r,g,b,u0,v0,MATERIAL_FOLIAGE,1.0,light)
    n=push_vertex(verts,n,r0[1],r0[2],r0[3],nx,ny,nz,r,g,b,u0,v1,MATERIAL_FOLIAGE,0.0,light)
  end
  blade(tx,ty,tz,bx,by,bz)
  blade(bx,by,bz,-tx,-ty,-tz)

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

function M.meshChunk(chunk, maxh, offsetX, offsetY, offsetZ, options)
  options = options or {}
  ensureLookups()

  local step = options.yieldStep
  offsetX = offsetX or 0
  offsetY = offsetY or 0
  offsetZ = offsetZ or 0
  local renderOrigin = options.renderOrigin or {0.0, 0.0, 0.0}
  local verts = {}
  local iceVerts = {}
  local leafVerts = {}
  local n = 0
  local iceN = 0
  local leafN = 0
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
      return blockAtWorld(lx + offsetX, y + offsetY, lz + offsetZ)
    end
  else
    sampleBlock = function(lx, y, lz)
      if lx < 0 or lx > 15 or y < 0 or y > 15 or lz < 0 or lz > 15 then
        return 0
      end
      return chunk:getBlock(lx, y, lz)
    end
  end

  local function skyAt(lx, y, lz)
    if skyLightAtWorld then
      return skyLightAtWorld(lx + offsetX, y + offsetY, lz + offsetZ)
    end
    if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y > maxh then
      return 15
    end
    if y < 0 then
      return 0
    end
    return chunk:getSkyLight(lx, y, lz)
  end

  local function occludes_face(x, y, z, currentId, currentIsLeaves, currentIsIce)
    local id = sampleBlock(x, y, z)
    if id == 0 then return false end
    if id == currentId then return true end
    if currentIsIce and faceIce[id] then return true end
    if currentIsLeaves and faceLeaves[id] then return true end
    if faceCutout[id] then return false end
    return faceSolid[id] == true
  end

  local function iceThickness(x, y, z, dx, dy, dz)
    local thickness = 1
    for distance = 1, 11 do
      if not faceIce[sampleBlock(x + dx * distance, y + dy * distance, z + dz * distance)] then
        break
      end
      thickness = thickness + 1
    end
    return thickness
  end

  for x = 0, 15 do
    for y = 0, 15 do
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
          local wy = y + offsetY
          local wz = z + offsetZ
          local rx = wx - renderOrigin[1]
          local ry = wy - renderOrigin[2]
          local rz = wz - renderOrigin[3]
          local blockUp=options.planet and options.planet:localUp({wx+0.5,wy+0.5,wz+0.5}) or nil
          local biomeTint = nil
          if def.biomeTint then
            biomeTint = options.planet and terrain.grassColorAtPosition(wx + 0.5, wy + 0.5, wz + 0.5, options.planet) or terrain.grassColorAt(wx, wz)
          end
          -- Leaves use grayscale mask textures just like cross-plane plants.
          -- Tinting only their top face leaves the four visible sides white,
          -- which made temperate spruce crowns look permanently snow-covered.
          local tintAllFaces = (props and (props.plant or props.leaves)) and true or false

          if props and props.cross then
            local r, g, b = faceRGB(def, "side", biomeTint, tintAllFaces, ao)
            local localUp = options.planet and options.planet:localUp({wx + 0.5, wy + 0.5, wz + 0.5}) or {0,1,0}
            n = append_cross(verts, n, x, y, z, rx, ry, rz, r, g, b, def.uvs.side or def.uvs.top, skyAt, localUp)
            goto continue_block
          end

          local currentIsLeaves = faceLeaves[id] == true
          local currentIsIce = faceIce[id] == true
          local targetVerts = currentIsIce and iceVerts or (currentIsLeaves and leafVerts or verts)
          local targetN = currentIsIce and iceN or (currentIsLeaves and leafN or n)
          local uvs = def.uvs

          if not occludes_face(x + 1, y, z, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,1,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z, rx, ry,rz, 1, 1, 0, 0, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, -1, 0, 0) or nil, faceUvRotation(1, blockUp))
          end
          if not occludes_face(x - 1, y, z, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,2,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z,rx,ry,rz, 2, -1, 0, 0, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, 1, 0, 0) or nil, faceUvRotation(2, blockUp))
          end
          if not occludes_face(x, y + 1, z, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,3,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z,rx,ry,rz, 3, 0, 1, 0, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, 0, -1, 0) or nil, faceUvRotation(3, blockUp))
          end
          if not occludes_face(x, y - 1, z, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,4,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z,rx,ry,rz, 4, 0, -1, 0, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, 0, 1, 0) or nil, faceUvRotation(4, blockUp))
          end
          if not occludes_face(x, y, z + 1, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,5,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z,rx,ry,rz, 5, 0, 0, 1, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, 0, 0, -1) or nil, faceUvRotation(5, blockUp))
          end
          if not occludes_face(x, y, z - 1, id, currentIsLeaves, currentIsIce) then
            local kind = faceKindFor(props,6,blockUp)
            local r, g, b = faceRGB(def, kind, biomeTint, tintAllFaces, ao)
            targetN = append_face(targetVerts, targetN, sampleBlock, x, y, z,rx,ry,rz, 6, 0, 0, -1, r, g, b, uvs[kind], def, skyAt,
              currentIsIce and iceThickness(x, y, z, 0, 0, 1) or nil, faceUvRotation(6, blockUp))
          end

          if currentIsIce then
            iceN = targetN
          elseif currentIsLeaves then
            leafN = targetN
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

  return verts, iceVerts, leafVerts
end

return M
