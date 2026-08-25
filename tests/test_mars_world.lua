package.path = "src/?.lua;src/?/init.lua;" .. package.path

local atmosphere = require("atmosphere")
local blocks = require("blocks")
local Chunk = require("chunk")
local Mars = require("worldgen.mars")
local terrain = require("terrain")
local uiFlow = require("ui_flow")
local worldProfiles = require("world_profiles")

local marsProfile = worldProfiles.get("mars")
assert(marsProfile.generator == "mars", "Mars owns a dedicated generator")
assert(math.abs(marsProfile.gravityScale - 3.71 / 9.81) < 0.002,
  "Mars uses its measured surface-gravity ratio")
assert(marsProfile.hasSurfaceWater == false and marsProfile.generation.vegetation == false,
  "Mars disables stable surface water and terrestrial vegetation")

-- The registry is the upgrade seam for future dimension-like worlds.
local future = worldProfiles.register({
  id = "test_future_world",
  name = "Future Test World",
  generator = "pipeline"
})
assert(worldProfiles.get(future.id) == future, "future worlds register without editing the registry API")

local generator = Mars.new({}, 90210)
local low, high = math.huge, -math.huge
local crater, canyon, volcanic = 0.0, 0.0, false
local biomes = {}
for z = -5000, 5000, 96 do
  for x = -5000, 5000, 96 do
    local sample = generator:sampleColumn(x, z, 127)
    assert(not sample.waterLevel and not sample.waterKind, "Mars never generates open surface water")
    assert(sample.rainfall == 0.0, "present-day Mars has no rainfall")
    low, high = math.min(low, sample.height), math.max(high, sample.height)
    crater = math.max(crater, sample.crater)
    canyon = math.max(canyon, sample.canyon)
    volcanic = volcanic or sample.volcanic
    biomes[sample.biome] = true
  end
end
assert(high - low >= 28, "Mars has meaningful basin, highland, crater and volcanic relief")
assert(crater > 0.72, "impact basins and raised rims are active")
assert(canyon > 0.45, "fault-canyon terrain is active")
assert(volcanic, "basaltic shield-volcano terrain is active")
assert(biomes.mars_lowlands and biomes.mars_highlands and biomes.mars_crater,
  "low plains and old cratered highlands are spatial terrain classes")

local first = generator:sampleColumn(317.25, -811.75, 127)
generator:setSeed(12)
generator:setSeed(90210)
local second = generator:sampleColumn(317.25, -811.75, 127)
assert(first.height == second.height and first.biome == second.biome and
  math.abs(first.crater - second.crater) < 1e-12,
  "Mars is deterministic across cache resets")

terrain.setWorldProfile("mars")
terrain.setSeed(90210)
local spawnX, spawnZ, spawnColumn = terrain.findSafeSpawn(16.5, 16.5, 127)
assert(spawnColumn and spawnColumn.biome:match("^mars_"), "safe spawning uses the Mars generator")
assert(not spawnColumn.waterLevel, "Mars spawn is dry")

local chunk = Chunk.new()
local offsetX = math.floor(spawnX / 16) * 16
local offsetZ = math.floor(spawnZ / 16) * 16
terrain.fillChunk(chunk, offsetX, offsetZ, 16, 16, 127)
local forbidden = {
  [blocks.water] = true,
  [blocks.lava] = true,
  [blocks.grass] = true,
  [blocks.tall_grass] = true,
  [blocks.oak_log] = true,
  [blocks.spruce_log] = true
}
for x = 0, 15 do
  for y = 0, 127 do
    for z = 0, 15 do
      assert(not forbidden[chunk:getBlock(x, y, z)],
        "Mars chunks contain no water, lava or terrestrial vegetation")
    end
  end
end
assert(chunk.environment and chunk.environment.world == "mars",
  "generated chunks retain their Mars environment metadata")

local flat = Chunk.new()
terrain.fillChunk(flat, 0, 0, 16, 16, 127, {generatorType = "superflat"})
assert(flat:getBlock(0, 3, 0) == blocks.red_sand and flat.environment.world == "mars",
  "the optional superflat terrain also keeps Mars surface materials")

local noon = atmosphere.forSun({0.0, 1.0, 0.0}, 48.0, 360.0, marsProfile)
assert(noon.fogColor[1] > noon.fogColor[3] * 1.7,
  "airborne dust makes the Martian daytime haze ochre")
assert(noon.lightColor[1] < 0.25, "Mars receives substantially less direct sunlight than Earth")
assert(noon.sunAureole[3] > noon.sunAureole[1] * 2.0,
  "fine dust gives the low-Sun region a blue-grey aureole")

local state = {worldId = "earth"}
uiFlow.applyAction(state, "cycle_world")
assert(state.worldId == "mars", "the create-world UI can select Mars")
uiFlow.applyAction(state, "start_world")
assert(state.pendingNewWorldConfig.worldId == "mars", "the selected world travels into loading")

terrain.setWorldProfile("earth")
print(string.format("Mars world tests passed: relief %d m, crater %.2f, canyon %.2f at spawn %.1f, %.1f",
  high - low, crater, canyon, spawnX, spawnZ))
