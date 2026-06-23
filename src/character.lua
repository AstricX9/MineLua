local Entity = require("entity")
local entityRegistry = require("entity_registry")

local M = {}

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for key, child in pairs(value) do
    result[key] = copyTable(child)
  end
  return result
end

local function cube_vertices(x, y, z, size, r, g, b)
  local sx = size[1] or size
  local sy = size[2] or sx
  local sz = size[3] or sx
  local x0, x1 = x - sx/2, x + sx/2
  local y0, y1 = y - sy/2, y + sy/2
  local z0, z1 = z - sz/2, z + sz/2
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

function M.createPlayer(position)
  local definition = copyTable(entityRegistry.get("player") or {
    id = "player",
    components = {
      transform = {position = {8, 6, 8}},
      render = {
        size = {0.8, 0.8, 0.8},
        color = {0.8, 0.5, 0.3}
      }
    }
  })

  local render = definition.components and definition.components.render or {}
  local size = render.size or {0.8, 0.8, 0.8}
  local color = render.color or {0.8, 0.5, 0.3}

  definition.position = position or (definition.components.transform and definition.components.transform.position) or {8, 6, 8}
  definition.meshFactory = function(entity)
    local x = entity.position[1]
    local y = entity.position[2]
    local z = entity.position[3]
    return cube_vertices(x, y, z, size, color[1], color[2], color[3])
  end

  return Entity.new(definition)
end

function M.createCharacter()
  return M.createPlayer():createMesh()
end

return M
