package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local items = require("items")
local Chunk = require("chunk")
local showcase = require("showcase")
local terrain = require("terrain")
local uiFlow = require("ui_flow")
local uiMenu = require("ui_menu")
local worldInteraction = require("world_interaction")

terrain.setWorldProfile("earth")
local generated = {}
for chunkX = -1, 2 do
  generated[chunkX] = {}
  for chunkZ = -1, 1 do
    local chunk = Chunk.new()
    terrain.fillChunk(chunk, chunkX * 16, chunkZ * 16, 16, 16, 127,
      {generatorType = "showcase"})
    generated[chunkX][chunkZ] = chunk
  end
end

local function generatedBlock(x, y, z)
  local chunkX = math.floor(x / 16)
  local chunkZ = math.floor(z / 16)
  local column = generated[chunkX]
  local chunk = column and column[chunkZ]
  return chunk and chunk:getBlock(x - chunkX * 16, y, z - chunkZ * 16) or blocks.air
end

local seen = {}
for _, sample in ipairs(showcase.blocks()) do
  assert(generatedBlock(sample.x, sample.y, sample.z) == sample.id,
    "each registered block occupies its authored showcase slot")
  seen[sample.id] = true
end
for id, definition in pairs(blocks.list) do
  if type(id) == "number" and id ~= blocks.air then
    assert(seen[id], "showcase omitted block " .. tostring(definition.key))
  end
end

local displayKeys = {}
for _, display in ipairs(showcase.displays()) do displayKeys[display.key] = true end
for _, key in ipairs(items.catalog()) do
  assert(displayKeys[key], "showcase omitted item " .. tostring(key))
end

local bounds = showcase.bounds()
for _, sample in ipairs(showcase.blocks()) do
  assert(generatedBlock(sample.x, sample.y - 1, sample.z) == blocks.air,
    "every block sample floats above one full air block")
  assert(generatedBlock(sample.x, sample.y - 2, sample.z) == blocks.grass,
    "the untouched superflat surface remains below each sample")
  assert(showcase.isProtectedBlock(sample.x, sample.y, sample.z),
    "every generated sample is marked as protected")
end
assert(bounds.minZ < bounds.maxZ and bounds.minX < bounds.maxX,
  "the floating samples form a walkable horizontal grid")
assert(generated[1][0].environment.biome == "showcase",
  "showcase chunks retain their special flat-world environment")

local protected = showcase.blocks()[1]
local fakeWorld = {block = protected.id}
function fakeWorld:blockAt() return self.block end
function fakeWorld:isProtectedBlock(x, y, z)
  return showcase.isProtectedBlock(x, y, z)
end
function fakeWorld:setBlock() error("protected showcase samples must not be changed") end
local changed = worldInteraction.breakBlock(fakeWorld,
  protected.x, protected.y, protected.z)
assert(#changed == 0 and fakeWorld.block == protected.id,
  "world interaction refuses to destroy a showcase sample")

local state = {worldGeneratorType = "default"}
uiFlow.applyAction(state, "toggle_generator")
assert(state.worldGeneratorType == "superflat", "terrain form cycles to superflat")
uiFlow.applyAction(state, "toggle_generator")
assert(state.worldGeneratorType == "showcase", "terrain form cycles to texture showcase")
assert(state.worldGameMode == "creative", "texture showcase defaults to creative flight")
uiFlow.applyAction(state, "start_world")
assert(state.pendingNewWorldConfig.generatorType == "showcase",
  "the selected showcase generator travels into world loading")

local shortcut = {screen = "texture_packs", renderDistance = 8}
assert(uiFlow.applyAction(shortcut, "create_texture_showcase") == "started_world",
  "the resource library can create a preview world directly")
assert(shortcut.pendingNewWorldConfig.generatorType == "showcase" and
    shortcut.pendingNewWorldConfig.gameMode == "creative" and
    shortcut.pendingNewWorldConfig.worldName == "Texture Pack Showcase",
  "the texture-pack shortcut creates an immediately useful showcase")

local hasShortcut = false
for _, button in ipairs(uiMenu.buttons("texture_packs", 640, 360, {})) do
  if button.id == "create_texture_showcase" then hasShortcut = true end
end
assert(hasShortcut, "the resource-library screen exposes the showcase shortcut")

print(string.format("showcase world tests passed: %d blocks, %d items",
  #showcase.blocks(), #showcase.items()))
