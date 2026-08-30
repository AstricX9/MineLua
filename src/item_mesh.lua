local texture = require("texture")

local ItemMesh = {}
ItemMesh.STRIDE_FLOATS = 18
local ORDER = {1,2,3,3,4,1}
local ATLAS_HALF_TEXEL = 0.5 / 256

local function vertex(vertices, x,y,z, nx,ny,nz, color, u,v)
  local values = {
    x,y,z,nx,ny,nz,color[1],color[2],color[3],u,v,
    0,0,1,       -- material, shape height, skylight
    0,0,0,       -- RGB block light
    1            -- legacy scalar skylight tail
  }
  for i=1,#values do vertices[#vertices+1]=values[i] end
end

local function quad(vertices, points, normal, color, uvs)
  for _, index in ipairs(ORDER) do
    local point, uv = points[index], uvs[index]
    vertex(vertices, point[1],point[2],point[3], normal[1],normal[2],normal[3], color, uv[1],uv[2])
  end
end

local function sourceTexture(definition)
  local value = definition.texture
  if type(value) == "string" then return value end
  if type(value) == "table" then
    value = value.top or value.side
    if type(value) == "table" then return value[1] end
    return value
  end
end

local function isFoliage(definition)
  local properties = definition.properties or {}
  return definition.itemSprite or properties.leaves or properties.cross or properties.plant
end

function ItemMesh.isSprite(definition)
  return definition and isFoliage(definition) or false
end

function ItemMesh.vertices(definition, radius)
  if not definition or not definition.uvs then return {} end
  radius = radius or 0.18
  if not isFoliage(definition) then return nil end

  local uv = definition.uv or definition.uvs.top or definition.uvs.side
  if not uv then return {} end
  local color = definition.color or {1,1,1}
  local depth = radius * 0.16
  local du=math.min(ATLAS_HALF_TEXEL,(uv.u1-uv.u0)*0.25)
  local dv=math.min(ATLAS_HALF_TEXEL,(uv.v1-uv.v0)*0.25)
  local atlasU0,atlasV0,atlasU1,atlasV1=uv.u0+du,uv.v0+dv,uv.u1-du,uv.v1-dv
  local pointsFront={{-radius,-radius,depth},{radius,-radius,depth},{radius,radius,depth},{-radius,radius,depth}}
  local pointsBack={{radius,-radius,-depth},{-radius,-radius,-depth},{-radius,radius,-depth},{radius,radius,-depth}}
  local faceUvs={{atlasU0,atlasV1},{atlasU1,atlasV1},{atlasU1,atlasV0},{atlasU0,atlasV0}}
  local backUvs={{atlasU1,atlasV1},{atlasU0,atlasV1},{atlasU0,atlasV0},{atlasU1,atlasV0}}
  local vertices={}
  quad(vertices,pointsFront,{0,0,1},color,faceUvs)
  quad(vertices,pointsBack,{0,0,-1},color,backUvs)

  -- Pixel-accurate perimeter quads give sprites Minecraft-style thickness.
  local image = texture.loadPng(sourceTexture(definition))
  if not image then return vertices end
  local function opaque(x,y)
    if x<0 or y<0 or x>=image.w or y>=image.h then return false end
    return image.data[(y*image.w+x)*4+3] >= 128
  end
  local function edge(x0,y0,x1,y1, normal, euv)
    local function px(x) return -radius + 2*radius*x/image.w end
    local function py(y) return radius - 2*radius*y/image.h end
    local points={{px(x0),py(y0),-depth},{px(x1),py(y1),-depth},{px(x1),py(y1),depth},{px(x0),py(y0),depth}}
    quad(vertices,points,normal,color,euv)
  end
  for y=0,image.h-1 do for x=0,image.w-1 do if opaque(x,y) then
    local u0=uv.u0+(uv.u1-uv.u0)*x/image.w
    local u1=uv.u0+(uv.u1-uv.u0)*(x+1)/image.w
    local v0=uv.v0+(uv.v1-uv.v0)*y/image.h
    local v1=uv.v0+(uv.v1-uv.v0)*(y+1)/image.h
    -- Side walls sample the centre of their opaque source pixel. Sampling the
    -- perimeter itself can cross into a transparent pixel or another atlas tile.
    local uc,vc=(u0+u1)*0.5,(v0+v1)*0.5
    local sideUv={{uc,vc},{uc,vc},{uc,vc},{uc,vc}}
    if not opaque(x-1,y) then edge(x,y,x,y+1,{-1,0,0},sideUv) end
    if not opaque(x+1,y) then edge(x+1,y+1,x+1,y,{1,0,0},sideUv) end
    if not opaque(x,y-1) then edge(x+1,y,x,y,{0,1,0},sideUv) end
    if not opaque(x,y+1) then edge(x,y+1,x+1,y+1,{0,-1,0},sideUv) end
  end end end
  return vertices
end

return ItemMesh
