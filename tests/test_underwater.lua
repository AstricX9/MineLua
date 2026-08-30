package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local Chunk = require("chunk")
local World = require("world")

local chunk = Chunk.new()
for y = 7, 13 do chunk:setBlock(0, y, 0, blocks.water) end
chunk.waterSurface = {[1] = 12.65}

local world = setmetatable({
  chunks = {[World.chunkKey(0, 0)] = {chunk = chunk}},
  maxHeight = 255
}, World)

assert(world:waterSurfaceAt(0, 0, 10) == 12.65,
  "chunk-owned rivers and lakes expose their local water surface")
assert(world:isPointSubmerged({0.5, 12.50, 0.5}),
  "the underwater post activates below a chunk-local water surface")
assert(not world:isPointSubmerged({0.5, 12.80, 0.5}),
  "a camera above the rendered surface is not underwater")
assert(not world:isPointSubmerged({1.5, 4.0, 0.5}),
  "being below global sea level in a dry column is not underwater")

for y = 2, 5 do chunk:setBlock(1, y, 0, blocks.water) end
assert(world:waterSurfaceAt(1, 0, 3.0) == 4.65,
  "edited water columns derive a surface when generation metadata is absent")
assert(world:isPointSubmerged({1.5, 4.5, 0.5}),
  "edited water also activates underwater post-processing")

if blocks.lava then
  chunk:setBlock(2, 3, 0, blocks.lava)
  assert(not world:isPointSubmerged({2.5, 3.5, 0.5}),
    "lava does not receive the blue underwater grade")
end

print("underwater state tests passed")
