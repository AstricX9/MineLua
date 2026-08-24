local json = require("json")
local modApi = require("mod_api")

local registry = {}
local loaded = false
local ENTITY_DATA_ROOT = "data/minecraft/entity/"

local function loadDataFile(name)
  local file = io.open(ENTITY_DATA_ROOT .. name, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return json.decode(content)
end

function registry.load()
  if loaded then
    return
  end

  local entityList = loadDataFile("index.json") or {"player"}

  for _, entityName in ipairs(entityList) do
    local definition = loadDataFile(entityName .. ".json")
    if definition then
      modApi.registerEntity(entityName, definition)
    end
  end

  loaded = true
end

function registry.register(name, definition)
  return modApi.registerEntity(name, definition)
end

function registry.get(name)
  registry.load()
  return modApi.getEntity(name)
end

function registry.list()
  registry.load()
  return modApi.listEntities()
end

return registry
