package.path = "src/?.lua;" .. package.path

local blocks=require("blocks")
local Mining=require("mining")

assert(Mining.breakDuration(blocks.mapping.stone,nil,"survival") > Mining.breakDuration(blocks.mapping.stone,"wood_pickaxe","survival"),
  "a pickaxe should mine stone faster than a bare hand")
assert(Mining.breakDuration(blocks.mapping.dirt,"wood_shovel","survival") < Mining.breakDuration(blocks.mapping.dirt,"wood_pickaxe","survival"),
  "tool type should matter, not merely holding any tool")
assert(Mining.canHarvest(blocks.mapping.stone,nil)==false,"stone should not drop when punched")
assert(Mining.canHarvest(blocks.mapping.stone,"wood_pickaxe"),"a wooden pickaxe should harvest stone")
assert(not Mining.canHarvest(blocks.mapping.iron_ore,"wood_pickaxe"),"wood is below iron ore's required tier")
assert(Mining.canHarvest(blocks.mapping.iron_ore,"stone_pickaxe"),"stone should harvest iron ore")
assert(Mining.breakDuration(blocks.mapping.stone,"stone_pickaxe","survival") < Mining.breakDuration(blocks.mapping.stone,"wood_pickaxe","survival"),
  "higher tiers should mine faster")
assert(Mining.breakDuration(blocks.mapping.oak_log,"flint_hatchet","survival") < Mining.breakDuration(blocks.mapping.oak_log,nil,"survival"),
  "the flint hatchet should chop logs faster than an empty hand")
assert(not Mining.canHarvest(blocks.mapping.oak_log,nil), "logs should not yield wood when punched")
assert(Mining.canHarvest(blocks.mapping.oak_log,"flint_hatchet"), "the flint hatchet should harvest logs")
assert(blocks.mapping.gravel.properties.drop == "flint", "gravel should supply flint for early progression")
assert(blocks.mapping.oak_leaves.properties.drop == "stick", "oak leaves should supply sticks for early progression")
assert(blocks.mapping.spruce_leaves.properties.drop == "stick", "spruce leaves should supply sticks for early progression")
print("mining/tool tests passed")
