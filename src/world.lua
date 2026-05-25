local Chunk = require("chunk")
local terrain = require("terrain")

local World = {}
World.__index = World

function World.new()
  local self = setmetatable({}, World)
  self.chunks = {}

  local chunk = Chunk.new()
  terrain.fillChunk(chunk, 16, 16, 32)

  self.chunks["0,0"] = chunk
  return self
end

return World
