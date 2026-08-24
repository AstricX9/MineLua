package.path = "src/?.lua;" .. package.path

local crafting = require("crafting")
local Inventory = require("inventory")

local recipes = crafting.load("data")
assert(#recipes.recipes >= 10, "every standalone recipe JSON should be indexed automatically")
local recipeIds = {}
for _, recipe in ipairs(recipes.recipes) do recipeIds[recipe.id] = true end
assert(recipeIds["minecraft:oak_planks"] and recipeIds["minecraft:crafting_table"] and recipeIds["minecraft:stick"],
  "recipe IDs should be derived automatically from namespace and filename")
assert(recipes.tags["minecraft:oak_logs"].oak_log,
  "the #minecraft:oak_logs item tag should contain oak logs")
assert(recipes.tags["minecraft:spruce_logs"].spruce_log,
  "one valid spruce recipe must not prevent every other recipe from loading")

local result = crafting.matchGrid(recipes, {
  {"", "", ""},
  {"", "oak_log", ""},
  {"", "", ""}
})
assert(result and result.item == "oak_planks", "one oak log should match wooden planks")
assert(result.count == 4, "one oak log should produce four wooden planks")

local taggedLogResult = crafting.matchGrid(recipes, {{"oak_log_x"}})
assert(taggedLogResult and taggedLogResult.item == "oak_planks",
  "every item in #minecraft:oak_logs should satisfy the recipe")

local spruceResult = crafting.matchGrid(recipes, {{"spruce_log_z"}})
assert(spruceResult and spruceResult.item == "spruce_planks" and spruceResult.count == 4,
  "spruce logs should craft after their item tag is loaded")

local pickaxeResult = crafting.matchGrid(recipes, {
  {"oak_planks", "oak_planks", "oak_planks"},
  {"", "stick", ""},
  {"", "stick", ""}
})
assert(pickaxeResult and pickaxeResult.item == "wood_pickaxe",
  "survival tool recipes should be part of the live recipe book")

local hatchetResult = crafting.matchGrid(recipes, {
  {"flint", "stick"},
  {"stick", "stick"}
})
assert(hatchetResult and hatchetResult.item == "flint_hatchet" and hatchetResult.count == 1,
  "flint and three sticks should craft a flint hatchet in the player's 2x2 grid")

local primitiveInventory = Inventory.new("survival", {recipeBook = recipes})
primitiveInventory.crafting[1] = {item = "flint", count = 1}
primitiveInventory.crafting[2] = {item = "stick", count = 1}
primitiveInventory.crafting[3] = {item = "stick", count = 1}
primitiveInventory.crafting[4] = {item = "stick", count = 1}
local primitiveResult = primitiveInventory:takeCraftResult()
assert(primitiveResult and primitiveResult.item == "flint_hatchet",
  "the default player inventory should craft the hatchet without a crafting table")

local tableResult = crafting.matchGrid(recipes, {
  {"", "", ""},
  {"", "oak_planks", "oak_planks"},
  {"", "oak_planks", "oak_planks"}
})
assert(tableResult and tableResult.item == "crafting_table" and tableResult.count == 1,
  "a shaped recipe should match when its JSON pattern is offset in the 3x3 grid")

local misplacedResult = crafting.matchGrid(recipes, {
  {"oak_planks", "oak_planks", ""},
  {"oak_planks", "", ""},
  {"", "oak_planks", ""}
})
assert(misplacedResult == nil, "a shaped recipe must respect its JSON placement")

local inventory = Inventory.new("survival", {recipeBook = recipes})
inventory:setCraftingGridSize(3)
inventory.crafting[5] = {item = "oak_log", count = 2}

local crafted = inventory:takeCraftResult()
assert(crafted and crafted.item == "oak_planks" and crafted.count == 4,
  "taking the crafting-table result should create four wooden planks")
assert(inventory.crafting[5] and inventory.crafting[5].count == 1,
  "crafting should consume exactly one log")
local plankSlot = inventory:find("oak_planks")
assert(plankSlot and inventory.slots[plankSlot].count == 4,
  "crafted wooden planks should enter the inventory")

print("crafting JSON tests passed")
