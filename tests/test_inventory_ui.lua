package.path = "src/?.lua;" .. package.path

local hud = require("hud")
local Inventory = require("inventory")

local state = {inventory = Inventory.new("survival")}
local width, height = 800, 600

-- The 176x166 window is rendered at 2x and centered at (224, 134).
-- Crafting interiors are source (98,18), (116,18), (98,36), (116,36).
local craft = hud.inventorySlotAt("inventory", width, height, 436, 186, state)
assert(craft and craft.kind == "craft" and craft.index == 1,
  "the first crafting hitbox should match the unified texture")

local bottomRight = hud.inventorySlotAt("crafting_table", width, height, 360, 244, state)
assert(bottomRight and bottomRight.kind == "craft" and bottomRight.index == 9,
  "the crafting-table route should expose its full 3x3 grid")

local tableResult = hud.inventorySlotAt("crafting_table", width, height, 476, 208, state)
assert(tableResult and tableResult.kind == "result",
  "the crafting-table result should align to the native container texture")

local result = hud.inventorySlotAt("inventory", width, height, 548, 206, state)
assert(result and result.kind == "result",
  "the result hitbox should match source slot (154,28)")

local inventorySlot = hud.inventorySlotAt("inventory", width, height, 256, 318, state)
assert(inventorySlot and inventorySlot.kind == "slot" and inventorySlot.index == 10,
  "inventory hitboxes should remain aligned with the unified window")

local armor = hud.inventorySlotAt("inventory", width, height, 256, 166, state)
assert(armor and armor.kind == "armor" and armor.index == 1,
  "visible armor boxes should participate in hover highlighting")

print("inventory UI alignment tests passed")
