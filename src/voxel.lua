local ffi = require("ffi")
local blocks = require("blocks")

local M = {}

-- Appends a quad (two triangles) for a single face to given verts table
local function append_face(verts, x, y, z, nx, ny, nz, r, g, b, uv)
  local x0, x1 = x, x + 1
  local y0, y1 = y, y + 1
  local z0, z1 = z, z + 1

  local u0, v0 = uv.u0, uv.v0
  local u1, v1 = uv.u1, uv.v1

  if nx == 1 then -- right (+X)
    local f = {
      x1,y0,z1, nx,ny,nz, r,g,b, u0,v1,
      x1,y0,z0, nx,ny,nz, r,g,b, u1,v1,
      x1,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x1,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x1,y1,z1, nx,ny,nz, r,g,b, u0,v0,
      x1,y0,z1, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  elseif nx == -1 then -- left (-X)
    local f = {
      x0,y0,z0, nx,ny,nz, r,g,b, u0,v1,
      x0,y0,z1, nx,ny,nz, r,g,b, u1,v1,
      x0,y1,z1, nx,ny,nz, r,g,b, u1,v0,
      x0,y1,z1, nx,ny,nz, r,g,b, u1,v0,
      x0,y1,z0, nx,ny,nz, r,g,b, u0,v0,
      x0,y0,z0, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  elseif ny == 1 then -- top (+Y)
    local f = {
      x0,y1,z1, nx,ny,nz, r,g,b, u0,v1,
      x1,y1,z1, nx,ny,nz, r,g,b, u1,v1,
      x1,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x1,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x0,y1,z0, nx,ny,nz, r,g,b, u0,v0,
      x0,y1,z1, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  elseif ny == -1 then -- bottom (-Y)
    local f = {
      x0,y0,z0, nx,ny,nz, r,g,b, u0,v1,
      x1,y0,z0, nx,ny,nz, r,g,b, u1,v1,
      x1,y0,z1, nx,ny,nz, r,g,b, u1,v0,
      x1,y0,z1, nx,ny,nz, r,g,b, u1,v0,
      x0,y0,z1, nx,ny,nz, r,g,b, u0,v0,
      x0,y0,z0, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  elseif nz == 1 then -- front (+Z)
    local f = {
      x0,y0,z1, nx,ny,nz, r,g,b, u0,v1,
      x1,y0,z1, nx,ny,nz, r,g,b, u1,v1,
      x1,y1,z1, nx,ny,nz, r,g,b, u1,v0,
      x1,y1,z1, nx,ny,nz, r,g,b, u1,v0,
      x0,y1,z1, nx,ny,nz, r,g,b, u0,v0,
      x0,y0,z1, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  elseif nz == -1 then -- back (-Z)
    local f = {
      x1,y0,z0, nx,ny,nz, r,g,b, u0,v1,
      x0,y0,z0, nx,ny,nz, r,g,b, u1,v1,
      x0,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x0,y1,z0, nx,ny,nz, r,g,b, u1,v0,
      x1,y1,z0, nx,ny,nz, r,g,b, u0,v0,
      x1,y0,z0, nx,ny,nz, r,g,b, u0,v1
    }
    for i=1,#f do verts[#verts+1] = f[i] end
  end
end

function M.meshChunk(chunk, maxh)
  local verts = {}

  local function is_solid(x, y, z)
    if x < 0 or x > 15 or y < 0 or y > 255 or z < 0 or z > 15 then return false end
    local id = chunk:getBlock(x, y, z)
    if id == 0 then return false end
    return blocks.list[id] and blocks.list[id].properties.solid
  end

  for x = 0, 15 do
    for y = 0, maxh - 1 do
      for z = 0, 15 do
        local id = chunk:getBlock(x, y, z)
        if id ~= 0 then
          local def = blocks.list[id]
          local r, g, b = def.color[1], def.color[2], def.color[3]
          
          -- approximate ambient occlusion
          local ao = 1.0 - (y / (maxh + 1)) * 0.35
          r, g, b = r * ao, g * ao, b * ao

          if not is_solid(x+1, y, z) then append_face(verts, x, y, z,  1, 0, 0, r,g,b, def.uvs.side) end
          if not is_solid(x-1, y, z) then append_face(verts, x, y, z, -1, 0, 0, r,g,b, def.uvs.side) end
          if not is_solid(x, y+1, z) then append_face(verts, x, y, z,  0,  1, 0, r,g,b, def.uvs.top) end
          if not is_solid(x, y-1, z) then append_face(verts, x, y, z,  0, -1, 0, r,g,b, def.uvs.bottom) end
          if not is_solid(x, y, z+1) then append_face(verts, x, y, z,  0, 0,  1, r,g,b, def.uvs.side) end
          if not is_solid(x, y, z-1) then append_face(verts, x, y, z,  0, 0, -1, r,g,b, def.uvs.side) end
        end
      end
    end
  end
  return verts
end

return M
