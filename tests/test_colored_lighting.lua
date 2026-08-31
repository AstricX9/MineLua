package.path = "src/?.lua;" .. package.path

local Chunk = require("chunk")
local blocks = require("blocks")
local lighting = require("lighting")

local chunk = Chunk.new()
local entry = {chunk = chunk, chunkX = 0, chunkZ = 0, offsetX = 0, offsetZ = 0}
local world = {maxHeight = 15}

function world:getChunkAtBlock(x, z)
  if x >= 0 and x < 16 and z >= 0 and z < 16 then return entry end
end
function world:localBlockCoord(x, z) return x, z end
function world:blockAt(x, y, z)
  if y < 0 or y > self.maxHeight then return nil end
  local found = self:getChunkAtBlock(x, z)
  return found and found.chunk:getBlock(x, y, z) or nil
end
function world:eachChunk(callback) callback(chunk, entry) end

chunk:setBlock(8, 8, 8, blocks.lava)
lighting.rebuild(world)

local sourceRed, sourceGreen, sourceBlue = chunk:getBlockLight(8, 8, 8)
assert(sourceRed == 15 and sourceGreen == 7 and sourceBlue == 2,
  "lava seeds its authored RGB emission")
local red, green, blue = chunk:getBlockLight(9, 8, 8)
assert(red == 14 and green == 6 and blue == 1,
  "coloured light attenuates independently by channel")
red, green, blue = chunk:getBlockLight(10, 8, 8)
assert(red == 13 and green == 5 and blue == 0,
  "the shortest wavelength channel can expire before red")

local before = lighting.directSkyColumn(world, 8, 8)
local oldRed, oldGreen, oldBlue = chunk:getBlockLight(8, 8, 8)
chunk:setBlock(8, 8, 8, blocks.air)
lighting.applyBlockChange(world, 8, 8, 8, before, {}, blocks.lava,
  oldRed, oldGreen, oldBlue)
red, green, blue = chunk:getBlockLight(9, 8, 8)
assert(red == 0 and green == 0 and blue == 0,
  "removing the only emitter removes its propagated light")

-- Closing a room one block at a time used to leave a plateau of stale sky
-- light behind. Equal-strength propagated neighbours were mistaken for fresh
-- sources and refilled the cavity after its final opening was sealed.
local function placeOpaque(x, y, z)
  local beforeColumn = lighting.directSkyColumn(world, x, z)
  local oldId = chunk:getBlock(x, y, z)
  local oldR, oldG, oldB = chunk:getBlockLight(x, y, z)
  chunk:setBlock(x, y, z, blocks.dirt)
  lighting.applyBlockChange(world, x, y, z, beforeColumn, {}, oldId,
    oldR, oldG, oldB)
end

lighting.rebuild(world)
for x = 4, 11 do
  for z = 4, 11 do
    if x == 4 or x == 11 or z == 4 or z == 11 then
      for y = 2, 7 do placeOpaque(x, y, z) end
    end
    placeOpaque(x, 2, z)
    placeOpaque(x, 7, z)
  end
end

for x = 5, 10 do
  for y = 3, 6 do
    for z = 5, 10 do
      assert(chunk:getSkyLight(x, y, z) == 0,
        "a fully sealed room must not retain propagated skylight")
    end
  end
end

local function removeBlock(x, y, z)
  local beforeColumn = lighting.directSkyColumn(world, x, z)
  local oldId = chunk:getBlock(x, y, z)
  local oldR, oldG, oldB = chunk:getBlockLight(x, y, z)
  chunk:setBlock(x, y, z, blocks.air)
  lighting.applyBlockChange(world, x, y, z, beforeColumn, {}, oldId,
    oldR, oldG, oldB)
end

removeBlock(8, 7, 8)
assert(chunk:getSkyLight(8, 6, 8) == 15 and chunk:getSkyLight(8, 5, 8) == 15,
  "reopening the roof restores direct skylight")
placeOpaque(8, 7, 8)
assert(chunk:getSkyLight(8, 6, 8) == 0 and chunk:getSkyLight(8, 5, 8) == 0,
  "closing a reopened roof removes skylight again")

print("colored lighting tests passed")
