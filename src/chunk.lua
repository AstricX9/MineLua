local Chunk = {}
Chunk.__index = Chunk

local CHUNK_W = 16
local CHUNK_H = 256
local CHUNK_D = 16

function Chunk.new()
  local self = setmetatable({}, Chunk)
  self.blocks = {}
  self.skyLight = {}

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

return Chunk
