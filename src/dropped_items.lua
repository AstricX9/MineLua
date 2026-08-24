local blocks = require("blocks")
local items = require("items")
local itemMesh = require("item_mesh")

local DroppedItems = {}
DroppedItems.__index = DroppedItems

local ITEM_RADIUS = 0.18
local GRAVITY = 20.0
local MAX_AGE = 300.0
local PICKUP_RANGE_SQUARED = 2.25 * 2.25
local QUARTER_TURN = math.pi * 0.5

local function solidAt(world, x, y, z)
  if not world then return false end
  local id = world:blockAt(math.floor(x), math.floor(y), math.floor(z))
  local definition = id and blocks.list[id]
  return definition and definition.properties and definition.properties.solid == true or false
end

function DroppedItems.new()
  return setmetatable({items = {}, nextId = 1}, DroppedItems)
end

function DroppedItems:spawn(item, count, position, velocity, pickupDelay)
  if not item or (count or 0) <= 0 then return nil end
  local entityId = self.nextId
  local initialVelocity = velocity or {0.0, 0.0, 0.0}
  local entity = {
    id = entityId,
    item = tostring(item):gsub("^minecraft:", ""),
    count = math.floor(count or 1),
    position = {position[1], position[2], position[3]},
    velocity = {
      initialVelocity[1] or 0.0,
      initialVelocity[2] or 0.0,
      initialVelocity[3] or 0.0
    },
    rotation = {
      (entityId * 0.31) % QUARTER_TURN,
      (entityId * 0.79) % (math.pi * 2.0),
      (entityId * 0.17) % QUARTER_TURN
    },
    angularVelocity = {
      (initialVelocity[3] or 0.0) * 1.4 + 1.1,
      1.7 + (entityId % 4) * 0.35,
      -(initialVelocity[1] or 0.0) * 1.4 - 0.8
    },
    pickupDelay = pickupDelay or 0.35,
    age = 0.0,
    grounded = false
  }
  self.nextId = self.nextId + 1
  self.items[#self.items + 1] = entity
  return entity
end

local function integrate(entity, dt, world)
  entity.velocity[2] = entity.velocity[2] - GRAVITY * dt
  local nextX = entity.position[1] + entity.velocity[1] * dt
  local nextY = entity.position[2] + entity.velocity[2] * dt
  local nextZ = entity.position[3] + entity.velocity[3] * dt

  if entity.velocity[2] <= 0 and solidAt(world, nextX, nextY - ITEM_RADIUS, nextZ) then
    local blockY = math.floor(nextY - ITEM_RADIUS)
    nextY = blockY + 1.0 + ITEM_RADIUS
    if math.abs(entity.velocity[2]) > 1.0 then
      entity.velocity[2] = -entity.velocity[2] * 0.18
    else
      entity.velocity[2] = 0.0
    end
    entity.velocity[1] = entity.velocity[1] * 0.72
    entity.velocity[3] = entity.velocity[3] * 0.72
    entity.grounded = entity.velocity[2] == 0.0
  else
    entity.grounded = false
  end

  local drag = entity.grounded and math.exp(-8.0 * dt) or math.exp(-0.7 * dt)
  entity.velocity[1] = entity.velocity[1] * drag
  entity.velocity[3] = entity.velocity[3] * drag
  entity.position[1], entity.position[2], entity.position[3] = nextX, nextY, nextZ

  local rotation = entity.rotation
  local angularVelocity = entity.angularVelocity
  if entity.grounded then
    local settle = 1.0 - math.exp(-18.0 * dt)
    local targetX = math.floor(rotation[1] / QUARTER_TURN + 0.5) * QUARTER_TURN
    local targetZ = math.floor(rotation[3] / QUARTER_TURN + 0.5) * QUARTER_TURN
    rotation[1] = rotation[1] + (targetX - rotation[1]) * settle
    rotation[3] = rotation[3] + (targetZ - rotation[3]) * settle
    local angularDrag = math.exp(-16.0 * dt)
    for axis = 1, 3 do
      angularVelocity[axis] = angularVelocity[axis] * angularDrag
      if math.abs(angularVelocity[axis]) < 0.015 then angularVelocity[axis] = 0.0 end
    end
  else
    for axis = 1, 3 do
      rotation[axis] = rotation[axis] + angularVelocity[axis] * dt
      angularVelocity[axis] = angularVelocity[axis] * math.exp(-0.45 * dt)
    end
  end
end

local function closeEnough(entity, playerPosition)
  if not playerPosition or entity.pickupDelay > 0 then return false end
  local dx = entity.position[1] - playerPosition[1]
  local dy = entity.position[2] - playerPosition[2]
  local dz = entity.position[3] - playerPosition[3]
  return dx * dx + dy * dy + dz * dz <= PICKUP_RANGE_SQUARED
end

function DroppedItems:update(dt, world, playerPosition, inventory)
  dt = math.max(0.0, math.min(dt or 0.0, 0.1))
  local pickedUp = 0
  local index = 1
  while index <= #self.items do
    local entity = self.items[index]
    entity.age = entity.age + dt
    entity.pickupDelay = math.max(0.0, entity.pickupDelay - dt)

    local remaining = dt
    while remaining > 0 do
      local step = math.min(remaining, 0.025)
      integrate(entity, step, world)
      remaining = remaining - step
    end

    local remove = entity.age >= MAX_AGE
    if not remove and inventory and closeEnough(entity, playerPosition) then
      local leftover = inventory:add(entity.item, entity.count)
      pickedUp = pickedUp + entity.count - leftover
      entity.count = leftover
      remove = leftover == 0
    end

    if remove then
      table.remove(self.items, index)
    else
      index = index + 1
    end
  end
  return pickedUp
end

function DroppedItems:clear()
  self.items = {}
end

local FACE_DATA = {
  {normal={ 1, 0, 0}, corners={{ 1,-1, 1},{ 1,-1,-1},{ 1, 1,-1},{ 1, 1, 1}}, texture="side"},
  {normal={-1, 0, 0}, corners={{-1,-1,-1},{-1,-1, 1},{-1, 1, 1},{-1, 1,-1}}, texture="side"},
  {normal={ 0, 1, 0}, corners={{-1, 1, 1},{ 1, 1, 1},{ 1, 1,-1},{-1, 1,-1}}, texture="top"},
  {normal={ 0,-1, 0}, corners={{-1,-1,-1},{ 1,-1,-1},{ 1,-1, 1},{-1,-1, 1}}, texture="bottom"},
  {normal={ 0, 0, 1}, corners={{-1,-1, 1},{ 1,-1, 1},{ 1, 1, 1},{-1, 1, 1}}, texture="side"},
  {normal={ 0, 0,-1}, corners={{ 1,-1,-1},{-1,-1,-1},{-1, 1,-1},{ 1, 1,-1}}, texture="side"}
}
local ORDER = {1,2,3,3,4,1}
local UV_CORNERS = {{0,1},{1,1},{1,0},{0,0}}

function DroppedItems.meshVertices(item)
  local definition = blocks.mapping[item] or items.mapping[item]
  local fallback = blocks.mapping.oak_planks
  definition = definition or fallback
  if not definition or not definition.uvs then return {} end

  local spriteVertices = itemMesh.vertices(definition, ITEM_RADIUS)
  if spriteVertices then return spriteVertices end

  local vertices = {}
  local colors = definition.colors or {}
  for _, face in ipairs(FACE_DATA) do
    local uv = definition.uvs[face.texture] or definition.uvs.side or definition.uvs.top
    if uv then
      local color = definition.biomeTint and definition.color or colors[face.texture] or definition.color or {1,1,1}
      for _, cornerIndex in ipairs(ORDER) do
        local corner = face.corners[cornerIndex]
        local tex = UV_CORNERS[cornerIndex]
        vertices[#vertices+1] = corner[1] * ITEM_RADIUS
        vertices[#vertices+1] = corner[2] * ITEM_RADIUS
        vertices[#vertices+1] = corner[3] * ITEM_RADIUS
        vertices[#vertices+1] = face.normal[1]
        vertices[#vertices+1] = face.normal[2]
        vertices[#vertices+1] = face.normal[3]
        vertices[#vertices+1] = color[1]
        vertices[#vertices+1] = color[2]
        vertices[#vertices+1] = color[3]
        vertices[#vertices+1] = tex[1] == 0 and uv.u0 or uv.u1
        vertices[#vertices+1] = tex[2] == 0 and uv.v0 or uv.v1
        vertices[#vertices+1] = 0.0
        vertices[#vertices+1] = 0.0
        vertices[#vertices+1] = 1.0
      end
    end
  end
  return vertices
end

return DroppedItems
