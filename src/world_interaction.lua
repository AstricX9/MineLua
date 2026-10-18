local blocks = require("blocks")

local interaction = {}

local function air()
  return blocks.air or 0
end

function interaction.breakBlock(world, x, y, z)
  local id = world:blockAt(x, y, z)
  local def = id and blocks.list[id]
  local changed = {}

  if not id or id == 0 then
    return changed
  end
  if world.isProtectedBlock and world:isProtectedBlock(x, y, z) then
    return changed
  end

  world:setBlock(x, y, z, air())
  changed[#changed + 1] = {x = x, y = y, z = z}

  local properties = def and def.properties
  if properties and properties.doublePlant then
    local linkedY = properties.half == "lower" and y + 1 or y - 1
    local linkedId = world:blockAt(x, linkedY, z)
    local linkedDef = linkedId and blocks.list[linkedId]
    local linkedProps = linkedDef and linkedDef.properties
    local expectedHalf = properties.half == "lower" and "upper" or "lower"

    if linkedProps and linkedProps.doublePlant and linkedProps.half == expectedHalf then
      world:setBlock(x, linkedY, z, air())
      changed[#changed + 1] = {x = x, y = linkedY, z = z}
    end
  end

  return changed
end

function interaction.placeFromHit(world, hit, blockId)
  if not hit or not blockId then
    return nil
  end

  local hitDef = blocks.list[hit.id]
  local hitProps = hitDef and hitDef.properties
  local target = hitProps and hitProps.replaceable and hit or hit.previous
  if not target or world:isSolidBlock(target.x, target.y, target.z) then
    return nil
  end
  if world.isProtectedBlock and world:isProtectedBlock(target.x, target.y, target.z) then
    return nil
  end

  world:setBlock(target.x, target.y, target.z, blockId)
  return {x = target.x, y = target.y, z = target.z}
end

return interaction
