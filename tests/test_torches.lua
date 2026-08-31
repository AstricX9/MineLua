package.path = "src/?.lua;" .. package.path

local Chunk = require("chunk")
local blocks = require("blocks")
local crafting = require("crafting")
local Inventory = require("inventory")
local lighting = require("lighting")
local heldItem = require("held_item")
local texture = require("texture")
local voxel = require("voxel")

local torch = blocks.mapping.torch
assert(torch and blocks.torch == torch.id, "the torch block should be registered")
assert(torch.itemSprite and not torch.properties.cross and not torch.properties.solid,
  "torches should be rigid item sprites, not crossed foliage")
assert(torch.properties.targetable and torch.properties.breakable,
  "placed torches should be targetable and breakable")
assert(torch.properties.extrudedSprite,
  "torches should use generated 3D sprite geometry rather than foliage planes")

local creative = Inventory.catalog("building")
local foundTorch = false
for _, item in ipairs(creative) do
  if item == "torch" then foundTorch = true end
end
assert(foundTorch, "torches should appear in the creative building catalogue")

local recipes = crafting.load("data")
local coalResult = crafting.matchGrid(recipes, {{"coal"}, {"stick"}})
assert(coalResult and coalResult.item == "torch" and coalResult.count == 4,
  "coal over a stick should craft four torches")
local charcoalResult = crafting.matchGrid(recipes, {{"charcoal"}, {"stick"}})
assert(charcoalResult and charcoalResult.item == "torch" and charcoalResult.count == 4,
  "charcoal should also craft four torches")

local chunk = Chunk.new()
local entry = {chunk = chunk, chunkX = 0, chunkZ = 0, offsetX = 0, offsetZ = 0}
local world = {maxHeight = 15}

function world:getChunkAtBlock(x, z)
  if x >= 0 and x < 16 and z >= 0 and z < 16 then return entry end
end
function world:localBlockCoord(x, z) return x, z end
function world:blockAt(x, y, z)
  if y < 0 or y > self.maxHeight then return nil end
  local found = self:getChunkAtBlock(x, z)
  return found and found.chunk:getBlock(x, y, z) or nil
end
function world:eachChunk(callback) callback(chunk, entry) end

chunk:setBlock(8, 8, 8, blocks.torch)
lighting.rebuild(world)

local red, green, blue = chunk:getBlockLight(8, 8, 8)
assert(red == 14 and green == 11 and blue == 7,
  "a torch should seed its authored warm block light")
red, green, blue = chunk:getBlockLight(9, 8, 8)
assert(red == 13 and green == 10 and blue == 6,
  "torch light should propagate into neighbouring air")

red, green, blue = lighting.heldEmission({item = "torch"})
assert(red == 14 and green == 11 and blue == 7,
  "a carried torch should expose the same warm emission as a placed torch")

local atlas = texture.createAtlas()
blocks.initTextures(atlas)
local placedVertices = voxel.meshChunk(chunk, world.maxHeight, 0, 0, {
  skyLightAt = function(x, y, z)
    local found = world:getChunkAtBlock(x, z)
    return found and found.chunk:getSkyLight(x, y, z) or 0
  end,
  blockLightAt = function(x, y, z)
    local found = world:getChunkAtBlock(x, z)
    if found then return found.chunk:getBlockLight(x, y, z) end
    return 0, 0, 0
  end,
  blockAt = function(x, y, z) return world:blockAt(x, y, z) or 0 end
})
local handModel = heldItem.model(torch)
assert(#placedVertices / voxel.STRIDE_FLOATS == #handModel.vertices / heldItem.STRIDE_FLOATS,
  "placed and held torches should share the same opaque-texel 3D model")
for index = 1, #placedVertices, voxel.STRIDE_FLOATS do
  assert(placedVertices[index + 11] == 0.0,
    "torch vertices must use the rigid material and never receive foliage wind sway")
end

local before = lighting.directSkyColumn(world, 8, 8)
local oldRed, oldGreen, oldBlue = chunk:getBlockLight(8, 8, 8)
chunk:setBlock(8, 8, 8, blocks.air)
lighting.applyBlockChange(world, 8, 8, 8, before, {}, blocks.torch,
  oldRed, oldGreen, oldBlue)
red, green, blue = chunk:getBlockLight(9, 8, 8)
assert(red == 0 and green == 0 and blue == 0,
  "breaking the only torch should remove its propagated light")

print("torch tests passed")
