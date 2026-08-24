package.path = "src/?.lua;src/?/init.lua;" .. package.path

local Pipeline = require("worldgen.pipeline")
local terrain = require("terrain")
local Chunk = require("chunk")
local settings = require("graphics_settings").terrainGeneration

-- Drainage edges always point downhill and accumulated flow cannot shrink.
local pipeline = Pipeline.new(settings, 1)
local flows, uphill, accumulationLoss = 0, 0, 0
for cz = -24, 24 do
  for cx = -24, 24 do
    local node = pipeline.hydrology:node(cx, cz)
    if node.downstreamCx then
      flows = flows + 1
      local downstream = pipeline.hydrology:node(node.downstreamCx, node.downstreamCz)
      if downstream.elevation >= node.elevation then uphill = uphill + 1 end
      if pipeline.hydrology:accumulation(downstream.cx, downstream.cz) + 1e-9 <
          pipeline.hydrology:accumulation(cx, cz) then
        accumulationLoss = accumulationLoss + 1
      end
    end
  end
end
assert(flows > 0 and uphill == 0, "drainage graph flows downhill")
assert(accumulationLoss == 0, "flow accumulation grows downstream")

-- Sampling order cannot affect a deterministic procedural world.
local points = {}
for i = 1, 160 do
  points[i] = {math.floor(math.sin(i * 12.3) * 2600), math.floor(math.cos(i * 7.1) * 2600)}
end
terrain.setSeed(1)
local first = {}
for i, point in ipairs(points) do
  local c = terrain.columnAt(point[1], point[2], 127)
  first[i] = {c.height, c.biome, c.waterKind, c.waterLevel, c.river, c.lake}
end
terrain.setSeed(2)
terrain.setSeed(1)
for i = #points, 1, -1 do
  local point, expected = points[i], first[i]
  local c = terrain.columnAt(point[1], point[2], 127)
  assert(c.height == expected[1] and c.biome == expected[2] and
    c.waterKind == expected[3] and c.waterLevel == expected[4] and
    math.abs(c.river - expected[5]) < 1e-12 and math.abs(c.lake - expected[6]) < 1e-12,
    "column result is independent of sampling order")
end

-- Water bodies own valid local levels, with ocean pinned to global sea level.
local riverCount, lakeCount, oceanCount, lowSnow = 0, 0, 0, 0
for z = -2048, 2048, 24 do
  for x = -2048, 2048, 24 do
    local c = terrain.columnAt(x, z, 127)
    if c.waterKind == "ocean" then
      oceanCount = oceanCount + 1
      assert(c.waterLevel == terrain.SEA_LEVEL, "ocean uses global sea level")
    elseif c.waterKind == "river" then
      riverCount = riverCount + 1
      assert(c.height < c.waterLevel, "riverbed is below its local surface")
    elseif c.waterKind == "lake" then
      lakeCount = lakeCount + 1
      assert(c.height < c.waterLevel, "lakebed is below its basin surface")
    end
    if c.hasSnow and c.height <= terrain.SEA_LEVEL + 8 then lowSnow = lowSnow + 1 end
  end
end
assert(oceanCount > 0 and riverCount > 0 and lakeCount > 0, "ocean, river and lake systems are active")
assert(lowSnow == 0, "snowline stays above beaches and water")

-- Chunks persist primary environment metadata for debug and later systems.
local chunk = Chunk.new()
terrain.fillChunk(chunk, 0, 0, 16, 16, 127)
assert(chunk.environment and chunk.environment.biome and chunk.environment.geology and
  chunk.environment.landform, "chunk stores its environment record")

print(string.format(
  "worldgen pipeline passed: %d drainage edges, %d ocean, %d river, %d lake samples",
  flows, oceanCount, riverCount, lakeCount))
