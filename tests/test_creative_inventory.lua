package.path = "src/?.lua;" .. package.path

local Inventory = require("inventory")
local blocks = require("blocks")
local items = require("items")
local hud = require("hud")

local all = Inventory.catalog("search")
local expected = 0
for id, definition in pairs(blocks.list) do
  local properties = definition.properties or {}
  if type(id) == "number" and id ~= (blocks.air or 0) and
      not properties.hidden and not (properties.doublePlant and properties.half == "upper") and
      definition.key ~= "water" and definition.key ~= "lava" then
    expected = expected + 1
  end
end
expected = expected + #items.catalog()
assert(#all == expected, "the search catalogue should index every visible registered block and item")

local firstPageLast = Inventory.creativeItemAt(all, 0, 45)
local secondPageFirst = Inventory.creativeItemAt(all, 1, 1)
assert(firstPageLast == all[45] and secondPageFirst == all[10],
  "creative row scrolling should expose entries beyond the first 45 slots")
assert(Inventory.clampCreativeScroll(999, #all) == Inventory.maxCreativeScroll(#all),
  "creative scrolling should clamp to the final complete row")

local state = {
  creativeTab = "search",
  creativeFiltered = all,
  creativeScroll = 1,
  inventory = Inventory.new("creative")
}
local target = hud.inventorySlotAt("creative_inventory", 800, 600, 224, 201, state)
assert(target and target.item == all[10],
  "creative slot hit-testing should use the same scrolled catalogue index as rendering")

local emptyCreative = Inventory.new("creative")
for index = 1, Inventory.SLOT_COUNT do
  assert(emptyCreative.slots[index] == nil,
    "creative mode should not pre-fill the player's inventory")
end

local inventoryTab = hud.inventorySlotAt("creative_inventory", 800, 600, 545, 440, state)
assert(inventoryTab and inventoryTab.kind == "creative_tab" and inventoryTab.tab == "inventory",
  "creative inventory exposes the Minecraft-style player inventory tab at the bottom")
state.creativeTab = "inventory"
local backpackSlot = hud.inventorySlotAt("creative_inventory", 800, 600, 224, 209, state)
local hotbarSlot = hud.inventorySlotAt("creative_inventory", 800, 600, 224, 341, state)
assert(backpackSlot and backpackSlot.kind == "slot" and backpackSlot.index == 10,
  "the bottom creative tab exposes the player's backpack")
assert(hotbarSlot and hotbarSlot.kind == "slot" and hotbarSlot.index == 1,
  "the bottom creative tab exposes the player's hotbar")

local materials = Inventory.catalog("materials")
assert(#materials == #items.catalog(), "the materials tab should automatically contain every item")
for _, key in ipairs(materials) do
  assert(items.mapping[key], "materials entries should come from the item registry")
end

print("creative inventory indexing tests passed")
