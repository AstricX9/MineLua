local Chunk = require("chunk")
local blocks = require("blocks")
local terrain = require("terrain")

local World = {}
World.__index = World

local CHUNK_SIZE = 16

function World.new(options)
  options = options or {}

  local self = setmetatable({}, World)
  self.chunks = {}
  self.chunkRadius = options.chunkRadius or 4
  self.maxHeight = options.maxHeight or 24

  self:ensureChunksAroundBlock(0, 0)

  return self
end

function World.chunkCoord(value)
  return math.floor(value / CHUNK_SIZE)
end

function World.chunkKey(chunkX, chunkZ)
  return chunkX .. "," .. chunkZ
end

function World:createChunk(chunkX, chunkZ)
  local offsetX = chunkX * CHUNK_SIZE
  local offsetZ = chunkZ * CHUNK_SIZE
  local chunk = Chunk.new()

  terrain.fillChunk(chunk, offsetX, offsetZ, CHUNK_SIZE, CHUNK_SIZE, self.maxHeight)

  local entry = {
    chunk = chunk,
    chunkX = chunkX,
    chunkZ = chunkZ,
    offsetX = offsetX,
    offsetZ = offsetZ
  }

  self.chunks[World.chunkKey(chunkX, chunkZ)] = entry
  return entry
end

function World:ensureChunksAroundBlock(x, z)
  local centerChunkX = World.chunkCoord(x)
  local centerChunkZ = World.chunkCoord(z)
  local added = {}

  for chunkX = centerChunkX - self.chunkRadius, centerChunkX + self.chunkRadius do
    for chunkZ = centerChunkZ - self.chunkRadius, centerChunkZ + self.chunkRadius do
      local key = World.chunkKey(chunkX, chunkZ)
      if not self.chunks[key] then
        added[#added + 1] = self:createChunk(chunkX, chunkZ)
      end
    end
  end

  return added
end

function World:eachChunk(fn)
  for _, entry in pairs(self.chunks) do
    fn(entry.chunk, entry)
  end
end

function World:getChunkAtBlock(x, z)
  local chunkX = World.chunkCoord(x)
  local chunkZ = World.chunkCoord(z)

  return self.chunks[World.chunkKey(chunkX, chunkZ)]
end

function World:localBlockCoord(x, z)
  local chunkX = World.chunkCoord(x)
  local chunkZ = World.chunkCoord(z)

  return x - chunkX * CHUNK_SIZE, z - chunkZ * CHUNK_SIZE, chunkX, chunkZ
end

function World:containsBlock(x, z)
  return self:getChunkAtBlock(x, z) ~= nil
end

function World:blockAt(x, y, z)
  if y < 0 or y > 255 then
    return nil
  end

  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  return entry.chunk:getBlock(localX, y, localZ)
end

function World:setBlock(x, y, z, id)
  if y < 0 or y > 255 then
    return nil
  end

  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  entry.chunk:setBlock(localX, y, localZ, id)
  return entry
end

function World:isSolidBlock(x, y, z)
  local id = self:blockAt(x, y, z)
  if not id or id == 0 then
    return false
  end

  local def = blocks.list[id]
  return def and def.properties and def.properties.solid
end

function World:raycast(origin, direction, maxDistance, step)
  step = step or 0.08
  maxDistance = maxDistance or 6.0

  local previous = nil
  local distance = 0.0
  while distance <= maxDistance do
    local x = origin[1] + direction[1] * distance
    local y = origin[2] + direction[2] * distance
    local z = origin[3] + direction[3] * distance
    local blockX = math.floor(x)
    local blockY = math.floor(y)
    local blockZ = math.floor(z)

    if self:isSolidBlock(blockX, blockY, blockZ) then
      return {
        x = blockX,
        y = blockY,
        z = blockZ,
        id = self:blockAt(blockX, blockY, blockZ),
        previous = previous,
        distance = distance
      }
    end

    previous = {x = blockX, y = blockY, z = blockZ}
    distance = distance + step
  end

  return nil
end

function World:surfaceYAt(x, z)
  local entry = self:getChunkAtBlock(x, z)
  if not entry then
    return nil
  end

  local localX, localZ = self:localBlockCoord(x, z)
  for y = self.maxHeight, 0, -1 do
    local id = entry.chunk:getBlock(localX, y, localZ)
    if id and id ~= 0 then
      local def = blocks.list[id]
      if def and def.properties and def.properties.solid then
        return y + 1.0
      end
    end
  end

  return nil
end

return World
