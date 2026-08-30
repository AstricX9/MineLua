local Chunk = {}
Chunk.__index = Chunk

local CHUNK_W = 16
local CHUNK_H = 256
local CHUNK_D = 16

function Chunk.new()
  local self = setmetatable({}, Chunk)
  self.blocks = {}
  self.skyLight = {}
  -- RGB block light is packed as three four-bit channels. Unlike skylight it
  -- is emitted by blocks and remains coloured after propagation.
  self.blockLight = {}

  return self
end

function Chunk:setBlock(x, y, z, id)
  local index = x + y * 16 + z * 16 * 256 + 1
  self.blocks[index] = id ~= 0 and id or nil
end

function Chunk:getBlock(x, y, z)
  local index = x + y * 16 + z * 16 * 256 + 1
  return self.blocks[index] or 0
end

function Chunk:clearSkyLight()
  self.skyLight = {}
end

function Chunk:setSkyLight(x, y, z, level)
  local index = x + y * 16 + z * 16 * 256 + 1
  level = math.max(0, math.min(15, math.floor((level or 0) + 0.5)))
  self.skyLight[index] = level > 0 and level or nil
end

function Chunk:getSkyLight(x, y, z)
  local index = x + y * 16 + z * 16 * 256 + 1
  return self.skyLight[index] or 0
end

function Chunk:clearBlockLight()
  self.blockLight = {}
end

function Chunk:setBlockLight(x, y, z, red, green, blue)
  local index = x + y * 16 + z * 16 * 256 + 1
  red = math.max(0, math.min(15, math.floor((red or 0) + 0.5)))
  green = math.max(0, math.min(15, math.floor((green or 0) + 0.5)))
  blue = math.max(0, math.min(15, math.floor((blue or 0) + 0.5)))
  local packed = red + green * 16 + blue * 256
  self.blockLight[index] = packed > 0 and packed or nil
end

function Chunk:getBlockLight(x, y, z)
  local index = x + y * 16 + z * 16 * 256 + 1
  local packed = self.blockLight[index] or 0
  return packed % 16, math.floor(packed / 16) % 16,
    math.floor(packed / 256) % 16
end

return Chunk
