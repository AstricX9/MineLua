local json = require("json")
local filesystem = require("filesystem")

local Items = {
  mapping = {},
  list = {}
}

local ITEM_DATA_ROOT = "data/minecraft/item/"

local definitions = {
  {key="stick", name="Stick", texture="./textures/items/stick.png"},
  {key="flint", name="Flint", texture="./textures/items/flint.png"},
  {key="coal", name="Coal", texture="./textures/items/coal.png"},
  {key="charcoal", name="Charcoal", texture="./textures/items/charcoal.png"},
  {key="iron_ingot", name="Iron Ingot", texture="./textures/items/iron_ingot.png"},
  {key="gold_ingot", name="Gold Ingot", texture="./textures/items/gold_ingot.png"},
  {key="brick", name="Brick", texture="./textures/items/brick.png"},
  {key="flint_hatchet", name="Flint Hatchet", texture="./textures/items/flint_hatchet.png", toolType="axe", tier=1, speed=2.0},
  {key="wood_pickaxe", name="Wooden Pickaxe", texture="./textures/items/wood_pickaxe.png", toolType="pickaxe", tier=1, speed=2.0},
  {key="wood_axe", name="Wooden Axe", texture="./textures/items/wood_axe.png", toolType="axe", tier=1, speed=2.0},
  {key="wood_shovel", name="Wooden Shovel", texture="./textures/items/wood_shovel.png", toolType="shovel", tier=1, speed=2.0},
  {key="stone_pickaxe", name="Stone Pickaxe", texture="./textures/items/stone_pickaxe.png", toolType="pickaxe", tier=2, speed=4.0},
  {key="stone_axe", name="Stone Axe", texture="./textures/items/stone_axe.png", toolType="axe", tier=2, speed=4.0},
  {key="stone_shovel", name="Stone Shovel", texture="./textures/items/stone_shovel.png", toolType="shovel", tier=2, speed=4.0}
}

function Items.register(key, definition)
  if type(key) == "table" then
    definition = key
    key = definition.key
  end
  assert(type(key) == "string" and key ~= "", "Item keys must be non-empty strings")
  assert(not Items.mapping[key], "Item already registered: " .. key)
  definition = definition or {}
  definition.key = key
  definition.id = #Items.list + 1
  definition.itemSprite = true
  definition.color = definition.color or {1.0, 1.0, 1.0}
  definition.name = definition.name or key:gsub("_", " "):gsub("^%l", string.upper)
  Items.mapping[key] = definition
  Items.list[definition.id] = definition
  return definition.id
end

for _, definition in ipairs(definitions) do
  Items.register(definition)
end

-- Like blocks, standalone item definitions are discovered automatically. A
-- future item can be added as data/minecraft/item/<key>.json without touching
-- this module or maintaining a second index list.
for _, entry in ipairs(filesystem.entries(ITEM_DATA_ROOT)) do
  local key = not entry.isDirectory and entry.name:match("^(.*)%.json$") or nil
  if key and key ~= "index" and not Items.mapping[key] then
    local file = io.open(ITEM_DATA_ROOT .. entry.name, "r")
    if file then
      local definition = json.decode(file:read("*a"))
      file:close()
      if type(definition) == "table" then Items.register(key, definition) end
    end
  end
end

function Items.catalog()
  local result = {}
  for _, definition in ipairs(Items.list) do result[#result + 1] = definition.key end
  return result
end

function Items.initTextures(atlas)
  for _, definition in ipairs(Items.list) do
    definition.uv = atlas:addTexture("item_" .. definition.key, definition.texture)
    definition.uvs = {top=definition.uv, bottom=definition.uv, side=definition.uv}
  end
end

return Items
