local ffi = require("ffi")
local blocks = require("blocks")
local terrain = require("terrain")

local M = {}

M.STRIDE_FLOATS = 14

local MATERIAL_SOLID = 0.0
local MATERIAL_LEAVES = 1.0
local MATERIAL_FOLIAGE = 2.0

local function blockAtLocal(chunk, x, y, z)
  if x < 0 or x > 15 or y < 0 or y > 255 or z < 0 or z > 15 then
    return 0
  end
  return chunk:getBlock(x, y, z)
end

local function lightCurve(level)
  local darkness = 1.0 - math.max(0.0, math.min(15.0, level)) / 15.0
  return (1.0 - darkness) / (darkness * 3.0 + 1.0)
end

local function isSolidForAO(id)
  if not id or id == 0 then
    return false
  end
  local def = blocks.list[id]
  return def and def.properties and def.properties.solid and not def.properties.cutout
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

local function vertexAO(chunk, x, y, z, nx, ny, nz, cx, cy, cz)
  local ox, oy, oz, ax, ay, az, bx, by, bz = cornerBasis(nx, ny, nz, cx, cy, cz)

  local sideA = isSolidForAO(blockAtLocal(chunk, x + ox + ax, y + oy + ay, z + oz + az))
  local sideB = isSolidForAO(blockAtLocal(chunk, x + ox + bx, y + oy + by, z + oz + bz))
  local corner = isSolidForAO(blockAtLocal(chunk, x + ox + ax + bx, y + oy + ay + by, z + oz + az + bz))

  if sideA and sideB then
    return 0.45
  end

  local occupied = (sideA and 1 or 0) + (sideB and 1 or 0) + (corner and 1 or 0)
  return ({1.00, 0.82, 0.67, 0.52})[occupied + 1]
end

local function materialFor(def)
  local props = def and def.properties
  if props and props.cross then
    return MATERIAL_FOLIAGE
  end
  if props and props.leaves then
    return MATERIAL_LEAVES
  end
  return MATERIAL_SOLID
end

local function push_vertex(verts, vx, vy, vz, nx, ny, nz, r, g, b, u, v, material, heightFactor, vertexLight)
  verts[#verts+1] = vx; verts[#verts+1] = vy; verts[#verts+1] = vz
  verts[#verts+1] = nx; verts[#verts+1] = ny; verts[#verts+1] = nz
  verts[#verts+1] = r; verts[#verts+1] = g; verts[#verts+1] = b
  verts[#verts+1] = u; verts[#verts+1] = v
  verts[#verts+1] = material or MATERIAL_SOLID
  verts[#verts+1] = heightFactor or 0.0
  verts[#verts+1] = vertexLight or 1.0
end

-- Appends a quad (two triangles) for a single face to given verts table
local function append_face(verts, chunk, lx, ly, lz, x, y, z, nx, ny, nz, r, g, b, uv, def, skyAt)
  local x0, x1 = x, x + 1
  local y0, y1 = y, y + 1
  local z0, z1 = z, z + 1

  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1
  local material = materialFor(def)
  local function info(vx, vy, vz, cx, cy, cz)
    local sky = smoothSkyLight(skyAt, lx, ly, lz, nx, ny, nz, cx, cy, cz)
    local ao = vertexAO(chunk, lx, ly, lz, nx, ny, nz, cx, cy, cz)
    if material == MATERIAL_LEAVES then
      ao = math.max(0.78, ao)
    end
    return material, material == MATERIAL_LEAVES and cy or 0.0, lightCurve(sky) * ao
  end

  if nx == 1 then -- right (+X)
    local m,h,l = info(x1,y0,z1,1,0,1); push_vertex(verts,x1,y0,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x1,y0,z0,1,0,0); push_vertex(verts,x1,y0,z0,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x1,y1,z0,1,1,0); push_vertex(verts,x1,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y1,z0,1,1,0); push_vertex(verts,x1,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y1,z1,1,1,1); push_vertex(verts,x1,y1,z1,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x1,y0,z1,1,0,1); push_vertex(verts,x1,y0,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  elseif nx == -1 then -- left (-X)
    local m,h,l = info(x0,y0,z0,0,0,0); push_vertex(verts,x0,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x0,y0,z1,0,0,1); push_vertex(verts,x0,y0,z1,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x0,y1,z1,0,1,1); push_vertex(verts,x0,y1,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y1,z1,0,1,1); push_vertex(verts,x0,y1,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y1,z0,0,1,0); push_vertex(verts,x0,y1,z0,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x0,y0,z0,0,0,0); push_vertex(verts,x0,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  elseif ny == 1 then -- top (+Y)
    local m,h,l = info(x0,y1,z1,0,1,1); push_vertex(verts,x0,y1,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x1,y1,z1,1,1,1); push_vertex(verts,x1,y1,z1,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x1,y1,z0,1,1,0); push_vertex(verts,x1,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y1,z0,1,1,0); push_vertex(verts,x1,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y1,z0,0,1,0); push_vertex(verts,x0,y1,z0,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x0,y1,z1,0,1,1); push_vertex(verts,x0,y1,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  elseif ny == -1 then -- bottom (-Y)
    local m,h,l = info(x0,y0,z0,0,0,0); push_vertex(verts,x0,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x1,y0,z0,1,0,0); push_vertex(verts,x1,y0,z0,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x1,y0,z1,1,0,1); push_vertex(verts,x1,y0,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y0,z1,1,0,1); push_vertex(verts,x1,y0,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y0,z1,0,0,1); push_vertex(verts,x0,y0,z1,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x0,y0,z0,0,0,0); push_vertex(verts,x0,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  elseif nz == 1 then -- front (+Z)
    local m,h,l = info(x0,y0,z1,0,0,1); push_vertex(verts,x0,y0,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x1,y0,z1,1,0,1); push_vertex(verts,x1,y0,z1,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x1,y1,z1,1,1,1); push_vertex(verts,x1,y1,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y1,z1,1,1,1); push_vertex(verts,x1,y1,z1,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y1,z1,0,1,1); push_vertex(verts,x0,y1,z1,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x0,y0,z1,0,0,1); push_vertex(verts,x0,y0,z1,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  elseif nz == -1 then -- back (-Z)
    local m,h,l = info(x1,y0,z0,1,0,0); push_vertex(verts,x1,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
    m,h,l = info(x0,y0,z0,0,0,0); push_vertex(verts,x0,y0,z0,nx,ny,nz,r,g,b,u1,v1,m,h,l)
    m,h,l = info(x0,y1,z0,0,1,0); push_vertex(verts,x0,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x0,y1,z0,0,1,0); push_vertex(verts,x0,y1,z0,nx,ny,nz,r,g,b,u1,v0,m,h,l)
    m,h,l = info(x1,y1,z0,1,1,0); push_vertex(verts,x1,y1,z0,nx,ny,nz,r,g,b,u0,v0,m,h,l)
    m,h,l = info(x1,y0,z0,1,0,0); push_vertex(verts,x1,y0,z0,nx,ny,nz,r,g,b,u0,v1,m,h,l)
  end
end

local function append_cross_quad(verts, p0, p1, p2, p3, nx, nz, r, g, b, uv, baseY, vertexLight)
  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1
  push_vertex(verts, p0[1],p0[2],p0[3], nx,0,nz, r,g,b, u0,v1, MATERIAL_FOLIAGE, p0[2] - baseY, vertexLight)
  push_vertex(verts, p1[1],p1[2],p1[3], nx,0,nz, r,g,b, u1,v1, MATERIAL_FOLIAGE, p1[2] - baseY, vertexLight)
  push_vertex(verts, p2[1],p2[2],p2[3], nx,0,nz, r,g,b, u1,v0, MATERIAL_FOLIAGE, p2[2] - baseY, vertexLight)
  push_vertex(verts, p2[1],p2[2],p2[3], nx,0,nz, r,g,b, u1,v0, MATERIAL_FOLIAGE, p2[2] - baseY, vertexLight)
  push_vertex(verts, p3[1],p3[2],p3[3], nx,0,nz, r,g,b, u0,v0, MATERIAL_FOLIAGE, p3[2] - baseY, vertexLight)
  push_vertex(verts, p0[1],p0[2],p0[3], nx,0,nz, r,g,b, u0,v1, MATERIAL_FOLIAGE, p0[2] - baseY, vertexLight)
end

local function append_cross(verts, chunk, lx, ly, lz, x, y, z, r, g, b, uv, skyAt)
  local inset = 0.0625
  local x0, x1 = x + inset, x + 1.0 - inset
  local y0, y1 = y, y + 1.0
  local z0, z1 = z + inset, z + 1.0 - inset
  local n = 0.70710678
  local sky = math.max(skyAt(lx, ly, lz), skyAt(lx, ly + 1, lz))
  local vertexLight = lightCurve(sky)

  append_cross_quad(verts, {x0,y0,z0}, {x1,y0,z1}, {x1,y1,z1}, {x0,y1,z0}, -n, n, r, g, b, uv, y, vertexLight)
  append_cross_quad(verts, {x1,y0,z0}, {x0,y0,z1}, {x0,y1,z1}, {x1,y1,z0}, n, n, r, g, b, uv, y, vertexLight)
end

function M.meshChunk(chunk, maxh, offsetX, offsetZ, options)
  options = options or {}
  local step = options.yieldStep
  offsetX = offsetX or 0
  offsetZ = offsetZ or 0
  local verts = {}
  local skyLightAtWorld = options.skyLightAt

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

  local function occludes_face(x, y, z, currentId)
    if x < 0 or x > 15 or y < 0 or y > 255 or z < 0 or z > 15 then return false end
    local id = chunk:getBlock(x, y, z)
    if id == 0 then return false end
    if id == currentId then
      return true
    end
    local def = blocks.list[id]
    local currentDef = blocks.list[currentId]
    if def and currentDef and def.properties and currentDef.properties and def.properties.leaves and currentDef.properties.leaves then
      return true
    end
    if def and def.properties and def.properties.cutout then
      return false
    end
    return def and def.properties and def.properties.solid
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
          if def.properties and def.properties.liquid then
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

          local function faceColor(face)
            local color = (def.colors and def.colors[face]) or def.color or {1.0, 1.0, 1.0}
            if biomeTint and (face == "top" or (def.properties and def.properties.plant)) then
              color = {
                color[1] * biomeTint[1],
                color[2] * biomeTint[2],
                color[3] * biomeTint[3]
              }
            end
            return color[1] * ao, color[2] * ao, color[3] * ao
          end

          if def.properties and def.properties.cross then
            local r,g,b = faceColor("side")
            append_cross(verts, chunk, x, y, z, wx, y, wz, r, g, b, def.uvs.side or def.uvs.top, skyAt)
            goto continue_block
          end

          if not occludes_face(x+1, y, z, id) then local r,g,b = faceColor("side"); append_face(verts, chunk, x, y, z, wx, y, wz,  1, 0, 0, r,g,b, def.uvs.side, def, skyAt) end
          if not occludes_face(x-1, y, z, id) then local r,g,b = faceColor("side"); append_face(verts, chunk, x, y, z, wx, y, wz, -1, 0, 0, r,g,b, def.uvs.side, def, skyAt) end
          if not occludes_face(x, y+1, z, id) then local r,g,b = faceColor("top"); append_face(verts, chunk, x, y, z, wx, y, wz,  0,  1, 0, r,g,b, def.uvs.top, def, skyAt) end
          if not occludes_face(x, y-1, z, id) then local r,g,b = faceColor("bottom"); append_face(verts, chunk, x, y, z, wx, y, wz,  0, -1, 0, r,g,b, def.uvs.bottom, def, skyAt) end
          if not occludes_face(x, y, z+1, id) then local r,g,b = faceColor("side"); append_face(verts, chunk, x, y, z, wx, y, wz,  0, 0,  1, r,g,b, def.uvs.side, def, skyAt) end
          if not occludes_face(x, y, z-1, id) then local r,g,b = faceColor("side"); append_face(verts, chunk, x, y, z, wx, y, wz,  0, 0, -1, r,g,b, def.uvs.side, def, skyAt) end
        end
        ::continue_block::
      end
    end
    if step then step() end
  end
  return verts
end

return M
