package.path = "src/?.lua;" .. package.path

local hud = require("hud")
local Inventory = require("inventory")
local texture = require("texture")
local uiFlow = require("ui_flow")
local ffi = require("ffi")

local state = {inventory = Inventory.new("survival")}
local width, height = 800, 600

assert(uiFlow.inventoryScreenForGameMode("creative") == "creative_inventory",
  "creative worlds should always open the creative inventory overlay")
assert(uiFlow.inventoryScreenForGameMode("survival") == "inventory",
  "survival worlds should keep their survival inventory")

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

local panel = {w = 176, h = 166, data = ffi.new("uint8_t[?]", 176 * 166 * 4)}
for pixel = 0, 176 * 166 - 1 do panel.data[pixel * 4 + 3] = 255 end
texture.applyGuiCornerTransparency(panel)
local transparent = 0
for pixel = 0, 176 * 166 - 1 do
  if panel.data[pixel * 4 + 3] == 0 then transparent = transparent + 1 end
end
assert(transparent == 18, "container rounding should clear only the canonical corner pixels")
assert(panel.data[((1 * 176 + 1) * 4) + 3] == 255 and
    panel.data[((82 * 176 + 88) * 4) + 3] == 255,
  "container rounding must preserve adjacent and interior alpha")

print("inventory UI alignment tests passed")
