package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local DroppedItems = require("dropped_items")
local Inventory = require("inventory")

local ground = {}
function ground:blockAt(_, y, _)
  return y <= 0 and blocks.stone or blocks.air
end

local drops = DroppedItems.new()
local item = drops:spawn("oak_log", 1, {0.5, 3.0, 0.5}, {0, 0, 0}, 10.0)
for _ = 1, 180 do drops:update(1 / 60, ground) end
assert(item.grounded, "a dropped item should settle on solid ground")
assert(math.abs(item.position[2] - 1.18) < 0.02, "a dropped item should rest above the block")
local restingPosition = {item.position[1], item.position[2], item.position[3]}
local restingRotation = {item.rotation[1], item.rotation[2], item.rotation[3]}
for _ = 1, 120 do drops:update(1 / 60, ground) end
assert(math.abs(item.position[1] - restingPosition[1]) < 0.002 and
       math.abs(item.position[2] - restingPosition[2]) < 0.002 and
       math.abs(item.position[3] - restingPosition[3]) < 0.002,
       "a grounded item should stay physically at rest")
assert(math.abs(item.rotation[1] - restingRotation[1]) < 0.02 and
       math.abs(item.rotation[3] - restingRotation[3]) < 0.02,
       "a grounded item should stop tumbling instead of spinning forever")

item.pickupDelay = 0
local inventory = Inventory.new("survival")
local pickedUp = drops:update(1 / 60, ground, {0.5, 2.0, 0.5}, inventory)
assert(pickedUp == 1 and #drops.items == 0, "a nearby player should pick up the item")
assert(inventory:find("oak_log"), "picked-up items should enter inventory")

print("dropped item tests passed")
