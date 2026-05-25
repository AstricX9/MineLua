local Chunk = {}
Chunk.__index = Chunk

local CHUNK_W = 16
local CHUNK_H = 256
local CHUNK_D = 16

function Chunk.new()
  local self = setmetatable({}, Chunk)
  self.blocks = {}

  -- fill with air
  for i = 1, CHUNK_W * CHUNK_H * CHUNK_D do
    self.blocks[i] = 0
  end

  return self
end

function Chunk:setBlock(x, y, z, id)
  local index = x + y * 16 + z * 16 * 256 + 1
  self.blocks[index] = id
end

function Chunk:getBlock(x, y, z)
  local index = x + y * 16 + z * 16 * 256 + 1
  return self.blocks[index]
end

return Chunk
