local Chunk = require("chunk")
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

function World:containsBlock(x, z)
  return self:getChunkAtBlock(x, z) ~= nil
end

function World:surfaceYAt(x, z)
  if not self:containsBlock(x, z) then
    return nil
  end

  return terrain.heightAt(x, z, self.maxHeight) + 1.0
end

return World
