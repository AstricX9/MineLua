package.path = "src/?.lua;src/?/init.lua;" .. package.path

local Chunk = require("chunk")
local storage = require("chunk_storage")
local terrain = require("terrain")

local descriptorPath = arg[1]
if not descriptorPath then os.exit(2) end
local descriptor = io.open(descriptorPath, "rb")
if not descriptor then os.exit(3) end
local savePath = descriptor:read("*l")
local chunkX = tonumber(descriptor:read("*l"))
local chunkZ = tonumber(descriptor:read("*l"))
local maxHeight = tonumber(descriptor:read("*l"))
local generatorType = descriptor:read("*l")
local worldId = descriptor:read("*l")
local seed = tonumber(descriptor:read("*l"))
descriptor:close()
os.remove(descriptorPath)

if not savePath or not chunkX or not chunkZ or not maxHeight or not seed then os.exit(4) end

terrain.setWorldProfile(worldId)
terrain.setSeed(seed)
local chunk = Chunk.new()
terrain.fillChunk(chunk, chunkX * 16, chunkZ * 16, 16, 16, maxHeight, {
  generatorType = generatorType,
  seed = seed,
  worldId = worldId
})

local ok = storage.save(savePath, chunkX, chunkZ, chunk, {
  seed = seed,
  maxHeight = maxHeight,
  generatorType = generatorType,
  worldId = worldId,
  dataRevision = 0
})
os.exit(ok and 0 or 5)
