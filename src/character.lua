local Entity = require("entity")
local entityRegistry = require("entity_registry")

local M = {}

M.DEFAULT_SKIN = "assets/textures/entity/steve.png"
M.SLIM_SKIN = "assets/textures/entity/alex.png"

local function copyTable(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copyTable(child) end
  return result
end

local function rotateX(x, y, z, pivotY, angle)
  if not angle or angle == 0 then return x, y, z end
  local c, s = math.cos(angle), math.sin(angle)
  local py = y - pivotY
  return x, pivotY + py * c - z * s, py * s + z * c
end

local function addVertex(vertices, point, normal, uv, pose)
  local x, y, z = rotateX(point[1], point[2], point[3], pose.pivotY, pose.angle)
  local nx, ny, nz = rotateX(normal[1], normal[2], normal[3], 0, pose.angle)
  vertices[#vertices + 1] = x + pose.x
  vertices[#vertices + 1] = y + pose.y
  vertices[#vertices + 1] = z + pose.z
  vertices[#vertices + 1] = nx
  vertices[#vertices + 1] = ny
  vertices[#vertices + 1] = nz
  vertices[#vertices + 1] = 1
  vertices[#vertices + 1] = 1
  vertices[#vertices + 1] = 1
  vertices[#vertices + 1] = uv[1] / 64
  vertices[#vertices + 1] = uv[2] / 64
end

local function addFace(vertices, corners, normal, rect, pose, flip)
  local u, v, w, h = rect[1], rect[2], rect[3], rect[4]
  local uv = flip and {{u+w,v},{u,v},{u,v+h},{u+w,v+h}} or {{u,v},{u+w,v},{u+w,v+h},{u,v+h}}
  for _, index in ipairs({1,2,3,3,4,1}) do addVertex(vertices, corners[index], normal, uv[index], pose) end
end

-- Builds one cuboid from the official unfolded 64x64 Minecraft skin layout.
local function addSkinBox(vertices, center, size, skinSize, skinX, skinY, pose, inflate)
  inflate = inflate or 0
  local sx, sy, sz = size[1], size[2], size[3]
  local ux, uy, uz = skinSize[1], skinSize[2], skinSize[3]
  local x0, x1 = center[1] - sx/2 - inflate, center[1] + sx/2 + inflate
  local y0, y1 = center[2] - sy/2 - inflate, center[2] + sy/2 + inflate
  local z0, z1 = center[3] - sz/2 - inflate, center[3] + sz/2 + inflate
  pose = pose or {x=0,y=0,z=0,pivotY=0,angle=0}
  addFace(vertices, {{x0,y0,z1},{x1,y0,z1},{x1,y1,z1},{x0,y1,z1}}, {0,0,1}, {skinX+uz,skinY+uz,ux,uy}, pose)
  addFace(vertices, {{x1,y0,z0},{x0,y0,z0},{x0,y1,z0},{x1,y1,z0}}, {0,0,-1}, {skinX+uz+ux+uz,skinY+uz,ux,uy}, pose)
  addFace(vertices, {{x0,y0,z0},{x0,y0,z1},{x0,y1,z1},{x0,y1,z0}}, {-1,0,0}, {skinX,skinY+uz,uz,uy}, pose)
  addFace(vertices, {{x1,y0,z1},{x1,y0,z0},{x1,y1,z0},{x1,y1,z1}}, {1,0,0}, {skinX+uz+ux,skinY+uz,uz,uy}, pose)
  addFace(vertices, {{x0,y1,z1},{x1,y1,z1},{x1,y1,z0},{x0,y1,z0}}, {0,1,0}, {skinX+uz,skinY,ux,uz}, pose)
  addFace(vertices, {{x0,y0,z0},{x1,y0,z0},{x1,y0,z1},{x0,y0,z1}}, {0,-1,0}, {skinX+uz+ux,skinY,ux,uz}, pose)
end

local function buildPlayerMesh(position, options)
  options = options or {}
  local unit = options.pixelScale or 1/16
  local armPixels = options.model == "slim" and 3 or 4
  local swing = math.sin(options.walkPhase or 0) * (options.walkAmount or 0)
  local x, y, z = position[1], position[2], position[3]
  local vertices = {}
  local function pose(angle, pivot) return {x=x,y=y,z=z,pivotY=pivot*unit,angle=angle or 0} end
  local function box(cx,cy,cz,sx,sy,sz,ux,uy,p,inflate)
    addSkinBox(vertices,{cx*unit,cy*unit,cz*unit},{sx*unit,sy*unit,sz*unit},{sx,sy,sz},ux,uy,p,(inflate or 0)*unit)
  end

  -- Feet are at the entity origin; shoulder and hip pivots match Java skins.
  box(0,28,0,8,8,8,0,0,pose(options.headPitch or 0,24))
  box(0,28,0,8,8,8,32,0,pose(options.headPitch or 0,24),0.5)
  box(0,18,0,8,12,4,16,16,pose(0,24))
  box(0,18,0,8,12,4,16,32,pose(0,24),0.25)
  box(-(4+armPixels/2),18,0,armPixels,12,4,40,16,pose(swing,24))
  box( (4+armPixels/2),18,0,armPixels,12,4,32,48,pose(-swing,24))
  box(-(4+armPixels/2),18,0,armPixels,12,4,40,32,pose(swing,24),0.25)
  box( (4+armPixels/2),18,0,armPixels,12,4,48,48,pose(-swing,24),0.25)
  box(-2,6,0,4,12,4,0,16,pose(-swing,12))
  box( 2,6,0,4,12,4,16,48,pose(swing,12))
  box(-2,6,0,4,12,4,0,32,pose(-swing,12),0.25)
  box( 2,6,0,4,12,4,0,48,pose(swing,12),0.25)
  return vertices
end

function M.createPlayer(position, options)
  options = options or {}
  local definition = copyTable(entityRegistry.get("player") or {id="player",components={transform={position={8,6,8}}}})
  definition.position = position or (definition.components.transform and definition.components.transform.position) or {8,6,8}
  definition.skinPath = options.skinPath or (options.model == "slim" and M.SLIM_SKIN or M.DEFAULT_SKIN)
  definition.skinModel = options.model or "classic"
  definition.meshFactory = function(entity) return buildPlayerMesh(entity.position, options) end
  local entity = Entity.new(definition)
  entity.skinPath, entity.skinModel = definition.skinPath, definition.skinModel
  return entity
end

function M.createCharacter(options) return M.createPlayer(nil, options):createMesh() end
M.buildPlayerMesh = buildPlayerMesh

return M
