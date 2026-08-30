package.path = "src/?.lua;" .. package.path

local Inventory = require("inventory")

local inventory = Inventory.new("survival")
inventory.cursor = {item = "stone", count = 12}
inventory.slots[1] = {item = "stone", count = 20}
inventory.slots[2] = {item = "dirt", count = 30}
inventory.slots[3] = {item = "stone", count = 40}

assert(inventory:collectToCursor() == 52, "double-click collection should fill the held stack")
assert(inventory.cursor.item == "stone" and inventory.cursor.count == 64,
  "collected items should be added to the cursor stack up to its limit")
assert(inventory.slots[1] == nil and inventory.slots[3].count == 8,
  "matching inventory stacks should be consumed in slot order")
assert(inventory.slots[2].item == "dirt" and inventory.slots[2].count == 30,
  "unrelated item stacks should not be changed")
assert(inventory:collectToCursor() == 0 and inventory.slots[3].count == 8,
  "a full cursor stack should not consume additional items")

local everyContainer = Inventory.new("survival")
everyContainer.cursor = {item = "oak_planks", count = 8}
everyContainer.slots[18] = {item = "oak_planks", count = 7}
everyContainer.crafting[1] = {item = "oak_planks", count = 6}
everyContainer.furnace.input = {item = "oak_planks", count = 5}
everyContainer.furnace.fuel = {item = "coal", count = 3}
assert(everyContainer:collectToCursor() == 18,
  "double-click collection should include inventory, crafting, and furnace stacks")
assert(everyContainer.cursor.count == 26 and everyContainer.slots[18] == nil and
    everyContainer.crafting[1] == nil and everyContainer.furnace.input == nil,
  "matching stacks from every visible container should move to the cursor")
assert(everyContainer.furnace.fuel.item == "coal",
  "double-click collection should leave non-matching container stacks alone")

local drag = Inventory.new("survival")
drag.cursor = {item = "oak_log", count = 16}
assert(drag:distributeSlots({1, 2}) == 16,
  "left-dragging across two inventory slots should distribute the held stack")
assert(drag.slots[1].count == 8 and drag.slots[2].count == 8 and drag.cursor == nil,
  "left-dragging across two slots should split the stack in half")

local uneven = Inventory.new("survival")
uneven.cursor = {item = "stone", count = 9}
assert(uneven:distributeSlots({1, 2}) == 8 and uneven.cursor.count == 1,
  "an indivisible remainder should stay attached to the cursor")

print("inventory double-click tests passed")
