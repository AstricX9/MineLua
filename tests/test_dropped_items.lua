package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local DroppedItems = require("dropped_items")
local Inventory = require("inventory")

blocks.mapping.oak_leaves.uvs = blocks.mapping.oak_leaves.uvs or {
  top = {u0 = 0, v0 = 0, u1 = 1, v1 = 1},
  side = {u0 = 0, v0 = 0, u1 = 1, v1 = 1}
}
local leafVertices = DroppedItems.meshVertices("oak_leaves")
assert(#leafVertices > 0 and #leafVertices % DroppedItems.STRIDE_FLOATS == 0,
  "dropped leaf meshes use the terrain shader's full RGB-lighting stride")
for index = 1, #leafVertices, DroppedItems.STRIDE_FLOATS do
  assert(math.abs(leafVertices[index]) <= 0.181 and
      math.abs(leafVertices[index + 1]) <= 0.181 and
      math.abs(leafVertices[index + 2]) <= 0.181,
    "leaf item vertices stay inside the dropped-item model bounds")
end

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

local stumpGround={}
function stumpGround:blockAt(_,y,_)
  if y<=0 then return blocks.stone end
  return y==1 and blocks.oak_stump or blocks.air
end
function stumpGround:collisionHeightAt(_,y,_)
  if y<=0 then return 1.0 end
  return y==1 and 0.32 or 0.0
end
local stumpDrops=DroppedItems.new()
local stumpItem=stumpDrops:spawn("oak_log",1,{0.5,3.0,0.5},{0,0,0},10.0)
for _=1,180 do stumpDrops:update(1/60,stumpGround) end
assert(math.abs(stumpItem.position[2]-1.50)<0.02,
  "dropped items should rest on the visible top of a partial-height stump")

local displays = DroppedItems.new()
local display = displays:spawnDisplay("stick", {4.5, 8.5, 2.1}, 2.15)
local nearby = Inventory.new("creative")
for _=1,360 do displays:update(1/60, ground, {4.5,8.5,2.1}, nearby) end
assert(#displays.items == 1 and display.position[2] == 8.5,
  "showcase displays neither fall, expire nor enter a nearby inventory")
assert(display.scale == 2.15 and display.rotation[1] == 0,
  "showcase displays retain their authored presentation transform")

print("dropped item tests passed")
