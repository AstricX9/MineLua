local Chunk = {}
Chunk.__index = Chunk

local CHUNK_SIZE = 16

function Chunk.new(uniformBlock)
  local self = setmetatable({}, Chunk)
  self.blocks = {}
  self.skyLight = {}
  self.uniformBlock = uniformBlock or 0

  return self
end

function Chunk:setBlock(x, y, z, id)
  if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
    return false
  end
  if self.uniformBlock ~= nil then
    local uniform = self.uniformBlock
    self.uniformBlock = nil
    if uniform ~= 0 then
      for index = 1, CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE do
        self.blocks[index] = uniform
      end
    end
  end
  local index = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE + 1
  self.blocks[index] = id ~= 0 and id or nil
  return true
end

function Chunk:getBlock(x, y, z)
  if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
    return 0
  end
  if self.uniformBlock ~= nil then
    return self.uniformBlock
  end
  local index = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE + 1
  return self.blocks[index] or 0
end

function Chunk:isUniform()
  return self.uniformBlock ~= nil, self.uniformBlock
end

function Chunk:clearSkyLight()
  self.skyLight = {}
end

function Chunk:setSkyLight(x, y, z, level)
  if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
    return
  end
  local index = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE + 1
  level = math.max(0, math.min(15, math.floor((level or 0) + 0.5)))
  self.skyLight[index] = level > 0 and level or nil
end

function Chunk:getSkyLight(x, y, z)
  if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE then
    return 15
  end
  local index = x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE + 1
  return self.skyLight[index] or 0
end

return Chunk
