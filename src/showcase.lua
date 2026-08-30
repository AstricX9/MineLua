local blocks = require("blocks")
local items = require("items")

-- Shared layout for the texture-pack showcase. Samples sit one empty block
-- above the superflat surface in a simple walkable grid.
local showcase = {
  SAMPLE_Y = 5,
  START_X = 5,
  START_Z = 8,
  COLUMNS = 12,
  SPACING = 2
}

local blockSamples
local itemDisplays
local protectedSamples

local function orderedBlocks()
  local definitions = {}
  for id, definition in pairs(blocks.list) do
    if type(id) == "number" and id ~= (blocks.air or 0) and definition then
      definitions[#definitions + 1] = definition
    end
  end
  table.sort(definitions, function(a, b) return a.id < b.id end)
  return definitions
end

local function slot(index, startZ)
  local zero = index - 1
  return showcase.START_X + (zero % showcase.COLUMNS) * showcase.SPACING,
    startZ - math.floor(zero / showcase.COLUMNS) * showcase.SPACING
end

function showcase.blocks()
  if blockSamples then return blockSamples end
  blockSamples = {}
  for index, definition in ipairs(orderedBlocks()) do
    local x, z = slot(index, showcase.START_Z)
    blockSamples[index] = {
      key = definition.key,
      id = definition.id,
      x = x,
      y = showcase.SAMPLE_Y,
      z = z,
      liquid = definition.properties and definition.properties.liquid == true
    }
  end
  return blockSamples
end

function showcase.items()
  if itemDisplays then return itemDisplays end
  local samples = showcase.blocks()
  local blockRows = math.ceil(#samples / showcase.COLUMNS)
  local startZ = showcase.START_Z - blockRows * showcase.SPACING
  itemDisplays = {}
  for index, key in ipairs(items.catalog()) do
    local x, z = slot(index, startZ)
    itemDisplays[index] = {
      key = key,
      x = x + 0.5,
      y = showcase.SAMPLE_Y + 0.5,
      z = z + 0.5,
      scale = 2.15
    }
  end
  return itemDisplays
end

function showcase.bounds()
  local samples = showcase.blocks()
  local displays = showcase.items()
  local lastBlockZ = samples[#samples] and samples[#samples].z or showcase.START_Z
  local lastItemZ = displays[#displays] and math.floor(displays[#displays].z) or lastBlockZ
  return {
    minX = showcase.START_X,
    maxX = showcase.START_X + (showcase.COLUMNS - 1) * showcase.SPACING,
    minZ = math.min(lastBlockZ, lastItemZ),
    maxZ = showcase.START_Z
  }
end

function showcase.isProtectedBlock(x, y, z)
  if y ~= showcase.SAMPLE_Y then return false end
  if not protectedSamples then
    protectedSamples = {}
    for _, sample in ipairs(showcase.blocks()) do
      protectedSamples[sample.x .. ":" .. sample.y .. ":" .. sample.z] = true
    end
  end
  return protectedSamples[x .. ":" .. y .. ":" .. z] == true
end

-- Liquids have a dedicated horizontal surface renderer and therefore need a
-- static cube model to make their side texture visible in the floating grid.
-- Standalone items use the same permanent display mechanism.
function showcase.displays()
  local result = {}
  for _, sample in ipairs(showcase.blocks()) do
    if sample.liquid then
      result[#result + 1] = {
        key = sample.key,
        x = sample.x + 0.5,
        y = sample.y + 0.5,
        z = sample.z + 0.5,
        scale = 2.5
      }
    end
  end
  for _, display in ipairs(showcase.items()) do
    result[#result + 1] = display
  end
  return result
end

local function setWorldBlock(chunk, offsetX, offsetZ, width, depth, maxHeight,
    worldX, y, worldZ, id)
  local x, z = worldX - offsetX, worldZ - offsetZ
  if x >= 0 and x < width and z >= 0 and z < depth and y >= 0 and y <= maxHeight then
    chunk:setBlock(x, y, z, id)
  end
end

function showcase.decorateChunk(chunk, offsetX, offsetZ, width, depth, maxHeight)
  local bounds = showcase.bounds()
  local chunkMaxX, chunkMaxZ = offsetX + width - 1, offsetZ + depth - 1
  if chunkMaxX < bounds.minX or offsetX > bounds.maxX or
      chunkMaxZ < bounds.minZ or offsetZ > bounds.maxZ then
    return
  end

  for _, sample in ipairs(showcase.blocks()) do
    setWorldBlock(chunk, offsetX, offsetZ, width, depth, maxHeight,
      sample.x, sample.y, sample.z, sample.id)
  end
end

return showcase
