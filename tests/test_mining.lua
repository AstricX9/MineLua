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

-- Chopping: wood under an axe costs whole swings, and a better head means fewer
-- of them rather than a faster swing.
assert(Mining.chopsRequired("oak_log","wood_axe","survival")>=3,"a wooden axe should need at least three blows on a log")
assert(Mining.chopsRequired("oak_log","stone_axe","survival")<Mining.chopsRequired("oak_log","wood_axe","survival"),
  "a better tier should fell a log in fewer blows")
assert(Mining.chopsRequired("crafting_table","wood_axe","survival")>Mining.chopsRequired("oak_log","wood_axe","survival"),
  "a harder wooden block should cost more blows")
assert(Mining.chopsRequired("oak_log",nil,"survival")==nil,"bare hands do not chop")
assert(Mining.chopsRequired("oak_log","stone_pickaxe","survival")==nil,"a pickaxe does not chop")
assert(Mining.chopsRequired("stone","wood_axe","survival")==nil,"an axe on stone still mines normally")
assert(Mining.chopsRequired("oak_log","wood_axe","creative")==nil,"creative breaks instantly, as before")
assert(Mining.chopsRequired("oak_log","titanium_axe","survival")==nil,"unknown items are not axes")
-- A top-tier head is the one that fells a log outright.
assert(math.ceil(Mining.profile("oak_log").hardness/Mining.chopPower({toolType="axe",tier=4}))==1,
  "the highest tier should take a log down in a single swing")

-- End to end: hold attack on a log and count what it actually costs. The swing
-- decides when a blow lands, so this exercises the animation and the break
-- bookkeeping together rather than each in isolation.
local heldItem = require("held_item")
local function fell(item)
  local target = {breakProgress = 0}
  local arm = {handSwing = 0, handSwinging = false}
  local step, elapsed, blows, stages = 1/60, 0, 0, {}
  while elapsed < 60 do
    local landed = heldItem.updateSwing(arm, step, true, heldItem.isHeavy(Mining.tool(item)))
    if landed then blows = blows + 1 end
    local broke = Mining.advanceBreak(target, "oak_log", item, "survival", step, landed)
    stages[#stages+1] = math.floor(math.min(.999, target.breakProgress/target.breakDuration)*10)
    elapsed = elapsed + step
    if broke then return elapsed, blows, stages end
  end
  error("the log never gave way")
end

local seconds, blows, stages = fell("wood_axe")
assert(blows == 3, "a wooden axe should fell a log in three blows, took " .. blows)
local expectedThreeBlows = heldItem.CHOP_SECONDS * (1.0 + heldItem.CHOP_IMPACT_A)
assert(math.abs(seconds - expectedThreeBlows) < 2 / 60,
  "three blows follow the faster chop cadence, got " .. seconds .. "s")
-- The crack overlay must step, not creep: a chopped log only ever shows the
-- stages its blows have earned.
local seen = {}
for _, stage in ipairs(stages) do
  if seen[#seen] ~= stage then seen[#seen + 1] = stage end
end
assert(#seen == 4, "an untouched log plus one stage per blow, saw " .. #seen)
assert(seen[1] == 0 and seen[2] == 3 and seen[3] == 6 and seen[4] == 9,
  "the crack overlay should jump a third of the way per blow")

local stoneSeconds, stoneBlows = fell("stone_axe")
assert(stoneBlows == 2 and stoneSeconds < seconds, "a better axe should fell the same log sooner")

-- Anything that is not an axe on wood keeps the continuous break it always had.
local bare = {breakProgress = 0}
assert(not Mining.advanceBreak(bare, "stone", "stone_pickaxe", "survival", 0.1, false),
  "stone should not break on the first frame")
assert(bare.breakProgress > 0, "mining without a landed blow still makes progress")

print("mining/tool tests passed")
