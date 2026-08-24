package.path = "src/?.lua;" .. package.path

local crafting = require("crafting")
local Inventory = require("inventory")

local recipes = crafting.load("data")

local rightDrag = Inventory.new("survival", {recipeBook = recipes})
rightDrag.cursor = {item = "stick", count = 4}
assert(rightDrag:placeCraftOne(1) and rightDrag:placeCraftOne(2),
  "right-drag should place one item in each visited crafting slot")
assert(rightDrag.crafting[1].count == 1 and rightDrag.crafting[2].count == 1 and rightDrag.cursor.count == 2,
  "right-drag should remove exactly one cursor item per slot")

local leftDrag = Inventory.new("survival", {recipeBook = recipes})
leftDrag.cursor = {item = "stick", count = 8}
assert(leftDrag:distributeCraft({1, 2}) == 8,
  "left-drag should distribute the held stack across visited crafting slots")
assert(leftDrag.crafting[1].count == 4 and leftDrag.crafting[2].count == 4 and leftDrag.cursor == nil,
  "left-drag across two slots should split the stack in half")

local bulk = Inventory.new("survival", {recipeBook = recipes})
bulk.crafting[1] = {item = "flint", count = 3}
bulk.crafting[2] = {item = "stick", count = 3}
bulk.crafting[3] = {item = "stick", count = 3}
bulk.crafting[4] = {item = "stick", count = 3}
assert(bulk:craftAll() == 3, "shift-click should craft every available recipe batch")
local hatchetSlot = bulk:find("flint_hatchet")
assert(hatchetSlot and bulk.slots[hatchetSlot].count == 3,
  "bulk-crafted results should enter the inventory")
assert(bulk:craftResult() == nil, "bulk crafting should stop when its ingredients run out")

print("crafting shortcut tests passed")
