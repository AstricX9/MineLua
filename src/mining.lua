local blocks = require("blocks")
local blockDrops = require("block_drops")
local items = require("items")

local Mining = {}
local dropRules = blockDrops.load("data")

local profiles = {
  grass={hardness=.6, tool="shovel"}, dirt={hardness=.5, tool="shovel"},
  sand={hardness=.5, tool="shovel"}, red_sand={hardness=.5, tool="shovel"},
  gravel={hardness=.6, tool="shovel"}, clay={hardness=.6, tool="shovel"},
  snow={hardness=.2, tool="shovel"},
  stone={hardness=1.5, tool="pickaxe", requiredTier=1},
  cobblestone={hardness=2.0, tool="pickaxe", requiredTier=1},
  sandstone={hardness=.8, tool="pickaxe", requiredTier=1},
  red_sandstone={hardness=.8, tool="pickaxe", requiredTier=1},
  coal_ore={hardness=3.0, tool="pickaxe", requiredTier=1},
  iron_ore={hardness=3.0, tool="pickaxe", requiredTier=2},
  lapis_ore={hardness=3.0, tool="pickaxe", requiredTier=2},
  gold_ore={hardness=3.0, tool="pickaxe", requiredTier=3},
  redstone_ore={hardness=3.0, tool="pickaxe", requiredTier=3},
  diamond_ore={hardness=3.0, tool="pickaxe", requiredTier=3},
  emerald_ore={hardness=3.0, tool="pickaxe", requiredTier=3},
  oak_log={hardness=2.0, tool="axe", requiredTier=1}, oak_log_x={hardness=2.0, tool="axe", requiredTier=1}, oak_log_z={hardness=2.0, tool="axe", requiredTier=1},
  spruce_log={hardness=2.0, tool="axe", requiredTier=1}, spruce_log_x={hardness=2.0, tool="axe", requiredTier=1}, spruce_log_z={hardness=2.0, tool="axe", requiredTier=1},
  oak_planks={hardness=2.0, tool="axe"}, spruce_planks={hardness=2.0, tool="axe"}, crafting_table={hardness=2.5, tool="axe"},
  furnace={hardness=3.5,tool="pickaxe",requiredTier=1},
  oak_leaves={hardness=.2}, spruce_leaves={hardness=.2},
  glass={hardness=.3}, ice={hardness=.5, tool="pickaxe"}, packed_ice={hardness=.5, tool="pickaxe"},
  tall_grass={hardness=0}, double_grass_lower={hardness=0}, double_grass_upper={hardness=0},
  dandelion={hardness=0}, poppy={hardness=0}, blue_orchid={hardness=0}, allium={hardness=0},
  oxeye_daisy={hardness=0}, red_tulip={hardness=0}, orange_tulip={hardness=0},
  pink_tulip={hardness=0}, white_tulip={hardness=0}
}

local function definition(block)
  if type(block)=="number" then return blocks.list[block] end
  if type(block)=="table" then return block end
  return blocks.mapping[block]
end

function Mining.profile(block)
  local def=definition(block)
  if not def then return {hardness=1} end
  local base=profiles[def.key] or {}
  return {
    hardness=tonumber(def.hardness) or base.hardness or 1,
    tool=def.preferredTool or base.tool,
    requiredTier=tonumber(def.requiredToolTier) or base.requiredTier
  }
end

function Mining.tool(item)
  return item and items.mapping[item] or nil
end

function Mining.canHarvest(block, item)
  local profile=Mining.profile(block)
  if not profile.requiredTier then return true end
  local tool=Mining.tool(item)
  return tool and tool.toolType==profile.tool and (tool.tier or 0)>=profile.requiredTier or false
end

function Mining.drop(block, item)
  local def = definition(block)
  if not def then return nil end
  local properties = def.properties or {}
  return blockDrops.resolve(dropRules, def.key, Mining.tool(item), properties.drop or def.key)
end

function Mining.breakDuration(block, item, gameMode)
  if gameMode=="creative" then return 0 end
  local profile=Mining.profile(block)
  if profile.hardness<=0 then return 0.05 end
  local tool=Mining.tool(item)
  local correct=tool and tool.toolType==profile.tool
  local speed=correct and (tool.speed or 1) or 1
  local base=(correct and Mining.canHarvest(block,item)) and 1.5 or 5.0
  return math.max(.05, profile.hardness*base/speed)
end

return Mining
