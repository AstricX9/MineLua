local Items = {
  mapping = {},
  list = {}
}

local definitions = {
  {key="stick", name="Stick", texture="./textures/items/stick.png"},
  {key="flint", name="Flint", texture="./textures/items/flint.png"},
  {key="flint_hatchet", name="Flint Hatchet", texture="./textures/items/flint_hatchet.png", toolType="axe", tier=1, speed=2.0},
  {key="wood_pickaxe", name="Wooden Pickaxe", texture="./textures/items/wood_pickaxe.png", toolType="pickaxe", tier=1, speed=2.0},
  {key="wood_axe", name="Wooden Axe", texture="./textures/items/wood_axe.png", toolType="axe", tier=1, speed=2.0},
  {key="wood_shovel", name="Wooden Shovel", texture="./textures/items/wood_shovel.png", toolType="shovel", tier=1, speed=2.0},
  {key="stone_pickaxe", name="Stone Pickaxe", texture="./textures/items/stone_pickaxe.png", toolType="pickaxe", tier=2, speed=4.0},
  {key="stone_axe", name="Stone Axe", texture="./textures/items/stone_axe.png", toolType="axe", tier=2, speed=4.0},
  {key="stone_shovel", name="Stone Shovel", texture="./textures/items/stone_shovel.png", toolType="shovel", tier=2, speed=4.0}
}

for index, definition in ipairs(definitions) do
  definition.id = index
  definition.itemSprite = true
  definition.color = {1.0, 1.0, 1.0}
  Items.mapping[definition.key] = definition
  Items.list[index] = definition
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
