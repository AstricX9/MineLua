local Smelting = {}

local COOK_TIME = 10.0
local RECIPES = {
  iron_ore={item="iron_ingot",count=1},
  gold_ore={item="gold_ingot",count=1},
  sand={item="glass",count=1},
  red_sand={item="glass",count=1},
  clay={item="brick",count=1},
  oak_log={item="charcoal",count=1},
  spruce_log={item="charcoal",count=1}
}
local FUELS = {
  coal=80, charcoal=80,
  oak_log=15, spruce_log=15, oak_planks=15, spruce_planks=15,
  stick=5
}

local function consume(stack)
  if not stack then return nil end
  stack.count=stack.count-1
  return stack.count>0 and stack or nil
end

local function canOutput(furnace,recipe)
  local output=furnace.output
  return not output or (output.item==recipe.item and output.count+recipe.count<=64)
end

function Smelting.recipe(item)
  return item and RECIPES[item] or nil
end

function Smelting.fuelTime(item)
  return item and FUELS[item] or nil
end

function Smelting.update(furnace,dt)
  furnace=furnace or {}
  dt=math.max(0,tonumber(dt) or 0)
  local recipe=furnace.input and RECIPES[furnace.input.item]
  local canSmelt=recipe and canOutput(furnace,recipe)
  local stacksChanged=false

  if (furnace.burnTime or 0)<=0 and canSmelt and furnace.fuel then
    local duration=FUELS[furnace.fuel.item]
    if duration then
      furnace.fuel=consume(furnace.fuel)
      furnace.burnTime=duration
      furnace.burnTotal=duration
      stacksChanged=true
    end
  end

  if (furnace.burnTime or 0)>0 then
    furnace.burnTime=math.max(0,furnace.burnTime-dt)
  end

  if canSmelt and (furnace.burnTime or 0)>0 then
    furnace.cookTime=(furnace.cookTime or 0)+dt
    furnace.cookTotal=COOK_TIME
    while furnace.cookTime>=COOK_TIME and furnace.input and canOutput(furnace,recipe) do
      furnace.cookTime=furnace.cookTime-COOK_TIME
      furnace.input=consume(furnace.input)
      if furnace.output then
        furnace.output.count=furnace.output.count+recipe.count
      else
        furnace.output={item=recipe.item,count=recipe.count}
      end
      stacksChanged=true
      recipe=furnace.input and RECIPES[furnace.input.item]
      if not recipe then break end
    end
  elseif not canSmelt then
    furnace.cookTime=0
  end
  return stacksChanged
end

return Smelting
