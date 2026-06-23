local modApi = {
  blocks = {
    byName = {},
    byId = {},
    order = {},
    nextId = 0
  },
  entities = {
    byName = {},
    order = {}
  }
}

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

local function normalizeName(name)
  assert(type(name) == "string" and name ~= "", "Registry names must be non-empty strings")
  return name:lower()
end

function modApi.registerBlock(name, definition)
  name = normalizeName(name)
  definition = copyTable(definition or {})

  assert(not modApi.blocks.byName[name], "Block already registered: " .. name)

  local id = definition.id
  if id == nil then
    id = modApi.blocks.nextId
  end

  while modApi.blocks.byId[id] do
    id = id + 1
  end

  definition.id = id
  definition.key = name
  definition.name = definition.name or name
  definition.properties = definition.properties or {}
  if definition.properties.solid == nil then
    definition.properties.solid = true
  end

  modApi.blocks.byName[name] = definition
  modApi.blocks.byId[id] = definition
  modApi.blocks.order[#modApi.blocks.order + 1] = name
  modApi.blocks.nextId = math.max(modApi.blocks.nextId, id + 1)

  return id
end

function modApi.getBlock(nameOrId)
  if type(nameOrId) == "number" then
    return modApi.blocks.byId[nameOrId]
  end

  return modApi.blocks.byName[normalizeName(nameOrId)]
end

function modApi.listBlocks()
  return modApi.blocks.byId
end

function modApi.registerEntity(name, definition)
  name = normalizeName(name)
  definition = copyTable(definition or {})

  assert(not modApi.entities.byName[name], "Entity already registered: " .. name)

  definition.key = name
  definition.name = definition.name or name
  definition.components = definition.components or {}

  modApi.entities.byName[name] = definition
  modApi.entities.order[#modApi.entities.order + 1] = name

  return definition
end

function modApi.getEntity(name)
  return modApi.entities.byName[normalizeName(name)]
end

function modApi.listEntities()
  return modApi.entities.byName
end

return modApi
