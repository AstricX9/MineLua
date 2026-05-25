local ffi = require("ffi")

local function addFace(vertices, x, y, z)
  local i = #vertices
  -- two triangles making a quad
  vertices[i+1] = x     vertices[i+2] = y+1   vertices[i+3] = z
  vertices[i+4] = x+1   vertices[i+5] = y+1   vertices[i+6] = z
  vertices[i+7] = x     vertices[i+8] = y+1   vertices[i+9] = z+1

  vertices[i+10] = x+1  vertices[i+11] = y+1  vertices[i+12] = z
  vertices[i+13] = x+1  vertices[i+14] = y+1  vertices[i+15] = z+1
  vertices[i+16] = x    vertices[i+17] = y+1  vertices[i+18] = z+1
end

local function buildMesh(chunk)
  local vertices = {}

  for x = 0, 15 do
    for y = 0, 255 do
      for z = 0, 15 do
        local id = chunk:getBlock(x, y, z)
        if id ~= 0 then
          addFace(vertices, x, y, z)
        end
      end
    end
  end

  local vertCount = #vertices / 3
  local buffer = ffi.new("float[?]", #vertices, vertices)

  return buffer, vertCount
end

return {
  buildMesh = buildMesh
}
