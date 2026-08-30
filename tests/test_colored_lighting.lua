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

print("colored lighting tests passed")
