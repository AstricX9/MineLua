local ffi = require("ffi")

local M = {}

local function cube_vertices(x, y, z, size, r, g, b)
  local s = size
  local x0, x1 = x - s/2, x + s/2
  local y0, y1 = y - s/2, y + s/2
  local z0, z1 = z - s/2, z + s/2
  local verts = {
    -- front face (+Z) normal (0,0,1)
    x0,y0,z1, 0,0,1, r,g,b, 0,0,
    x1,y0,z1, 0,0,1, r,g,b, 1,0,
    x1,y1,z1, 0,0,1, r,g,b, 1,1,
    x1,y1,z1, 0,0,1, r,g,b, 1,1,
    x0,y1,z1, 0,0,1, r,g,b, 0,1,
    x0,y0,z1, 0,0,1, r,g,b, 0,0,
    -- back face (-Z) normal (0,0,-1)
    x1,y0,z0, 0,0,-1, r,g,b, 0,0,
    x0,y0,z0, 0,0,-1, r,g,b, 1,0,
    x0,y1,z0, 0,0,-1, r,g,b, 1,1,
    x0,y1,z0, 0,0,-1, r,g,b, 1,1,
    x1,y1,z0, 0,0,-1, r,g,b, 0,1,
    x1,y0,z0, 0,0,-1, r,g,b, 0,0,
    -- left face (-X) normal (-1,0,0)
    x0,y0,z0, -1,0,0, r,g,b, 0,0,
    x0,y0,z1, -1,0,0, r,g,b, 1,0,
    x0,y1,z1, -1,0,0, r,g,b, 1,1,
    x0,y1,z1, -1,0,0, r,g,b, 1,1,
    x0,y1,z0, -1,0,0, r,g,b, 0,1,
    x0,y0,z0, -1,0,0, r,g,b, 0,0,
    -- right face (+X) normal (1,0,0)
    x1,y0,z1, 1,0,0, r,g,b, 0,0,
    x1,y0,z0, 1,0,0, r,g,b, 1,0,
    x1,y1,z0, 1,0,0, r,g,b, 1,1,
    x1,y1,z0, 1,0,0, r,g,b, 1,1,
    x1,y1,z1, 1,0,0, r,g,b, 0,1,
    x1,y0,z1, 1,0,0, r,g,b, 0,0,
    -- top face (+Y) normal (0,1,0)
    x0,y1,z1, 0,1,0, r,g,b, 0,0,
    x1,y1,z1, 0,1,0, r,g,b, 1,0,
    x1,y1,z0, 0,1,0, r,g,b, 1,1,
    x1,y1,z0, 0,1,0, r,g,b, 1,1,
    x0,y1,z0, 0,1,0, r,g,b, 0,1,
    x0,y1,z1, 0,1,0, r,g,b, 0,0,
    -- bottom face (-Y) normal (0,-1,0)
    x0,y0,z0, 0,-1,0, r,g,b, 0,0,
    x1,y0,z0, 0,-1,0, r,g,b, 1,0,
    x1,y0,z1, 0,-1,0, r,g,b, 1,1,
    x1,y0,z1, 0,-1,0, r,g,b, 1,1,
    x0,y0,z1, 0,-1,0, r,g,b, 0,1,
    x0,y0,z0, 0,-1,0, r,g,b, 0,0,
  }
  return verts
end

function M.createCharacter()
  -- center at (8, 6, 8)
  local verts = cube_vertices(8, 6, 8, 0.8, 0.8, 0.5, 0.3)
  return verts
end

return M
