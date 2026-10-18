package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local Chunk = require("chunk")
local terrain = require("terrain")
local variation = require("foliage_variation")
local voxel = require("voxel")
local voxelTrees = require("voxel_trees")

for _, key in ipairs({
  "ceiba_log_alive", "ceiba_leaves", "jungle_log_alive", "jungle_leaves",
  "palm_log_alive", "palm_leaves", "birch_log_alive", "birch_leaves",
  "acacia_log_alive", "acacia_leaves"
}) do
  assert(blocks[key], key .. " is registered")
end

local function generatorsSeen(biome)
  local seen = {}
  for index = 1, 640 do
    local generator = terrain.treeGeneratorForBiome(biome, index * 19 - 3000, index * -31 + 700)
    seen[generator] = true
  end
  return seen
end

local rainforest = generatorsSeen("rainforest")
assert(rainforest.ceiba and rainforest.jungle and rainforest.fig and rainforest.big,
  "rainforest selection includes emergent ceibas and multiple tropical forms")
local forest = generatorsSeen("forest")
assert(forest.oak and forest.birch and forest.big and forest.forest,
  "temperate forests mix oak, birch, and large trees")
local savanna = generatorsSeen("savanna")
assert(savanna.acacia and savanna.oak,
  "savannas mix flat acacias with sparse oak")
local beach = generatorsSeen("beach")
assert(beach.palm and not next(beach, "palm"), "sandy coasts select palms")

local function coordinateFor(biome, wanted)
  for index = 1, 2000 do
    local x, z = index * 19 - 3000, index * -31 + 700
    if terrain.treeGeneratorForBiome(biome, x, z) == wanted then return x, z end
  end
  error("no deterministic " .. wanted .. " selector found")
end

local function generatedSpecies(biome, wanted, logId, leavesId)
  local worldX, worldZ = coordinateFor(biome, wanted)
  local chunk = Chunk.new()
  terrain.addTree(chunk, worldX - 8, worldZ - 8, worldX, worldZ, 10, biome)
  local logs, leaves = 0, 0
  for _, id in pairs(chunk.blocks) do
    if id == logId then logs = logs + 1 end
    if id == leavesId then leaves = leaves + 1 end
  end
  assert(logs > 3 and leaves > 8,
    wanted .. " generation builds both its authored trunk and crown")
  return logs, leaves
end

local ceibaLogs = generatedSpecies("rainforest", "ceiba", blocks.ceiba_log_alive, blocks.ceiba_leaves)
assert(ceibaLogs > 45, "ceibas have a massive trunk and buttress-root silhouette")
generatedSpecies("rainforest", "fig", blocks.jungle_log_alive, blocks.jungle_leaves)
generatedSpecies("beach", "palm", blocks.palm_log_alive, blocks.palm_leaves)
generatedSpecies("savanna", "acacia", blocks.acacia_log_alive, blocks.acacia_leaves)
generatedSpecies("forest", "birch", blocks.birch_log_alive, blocks.birch_leaves)

local function voxelCount(layer)
  local count = 0
  for _ in pairs(layer) do count = count + 1 end
  return count
end

local function woodIsConnected(layer)
  local first, total
  for voxelKey in pairs(layer) do
    first, total = first or voxelKey, (total or 0) + 1
  end
  local seen, queue, head = {[first] = true}, {first}, 1
  local directions = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
  while head <= #queue do
    local x, y, z = queue[head]:match("([^,]+),([^,]+),([^,]+)")
    head, x, y, z = head + 1, tonumber(x), tonumber(y), tonumber(z)
    for _, direction in ipairs(directions) do
      local neighbour = (x + direction[1]) .. "," .. (y + direction[2]) ..
        "," .. (z + direction[3])
      if layer[neighbour] and not seen[neighbour] then
        seen[neighbour], queue[#queue + 1] = true, neighbour
      end
    end
  end
  return #queue == total
end

for _, species in ipairs(voxelTrees.species) do
  local firstTree = voxelTrees.generate(species, 42)
  local repeatedTree = voxelTrees.generate(species, 42)
  assert(voxelCount(firstTree.wood) > 5 and
      voxelCount(firstTree.leaves) + voxelCount(firstTree.leaves2) > 8,
    species .. " has a woody skeleton and authored canopy")
  assert(voxelCount(firstTree.wood) == voxelCount(repeatedTree.wood) and
      voxelCount(firstTree.leaves) == voxelCount(repeatedTree.leaves) and
      voxelCount(firstTree.leaves2) == voxelCount(repeatedTree.leaves2),
    species .. " generation is deterministic for a fixed seed")
  assert(woodIsConnected(firstTree.wood),
    species .. " branches stay face-connected for whole-tree felling")
end

assert(voxelCount(voxelTrees.generate("willow", 42).leaves2) > 0,
  "willows include hanging leaf curtains")
assert(voxelCount(voxelTrees.generate("ceiba", 42).wood) > 400,
  "ceibas include a massive trunk, branches, and buttress roots")

local first = variation.at(17, 65, -22, 0)
local repeated = variation.at(17, 65, -22, 0)
assert(first.offsetX == repeated.offsetX and first.offsetZ == repeated.offsetZ and
    first.rotation == repeated.rotation and first.widthScale == repeated.widthScale and
    first.heightScale == repeated.heightScale,
  "foliage transforms are deterministic across chunk remeshes")
assert(math.abs(first.offsetX) <= 0.18 and math.abs(first.offsetZ) <= 0.18 and
    first.widthScale >= 0.78 and first.widthScale <= 1.18 and
    first.heightScale >= 0.74 and first.heightScale <= 1.14,
  "grass jitter remains rooted inside its voxel with bounded scale")

local different = variation.at(18, 65, -22, 0)
assert(first.offsetX ~= different.offsetX or first.rotation ~= different.rotation,
  "neighbouring grass clumps do not share one transform")
assert(blocks.list[blocks.tall_grass].properties.randomTransform,
  "tall grass opts into random offset, rotation, and scale")

local grassDefinition = blocks.list[blocks.tall_grass]
grassDefinition.uvs = grassDefinition.uvs or {
  side = {u0 = 0, v0 = 0, u1 = 1, v1 = 1},
  top = {u0 = 0, v0 = 0, u1 = 1, v1 = 1}
}
grassDefinition.color = grassDefinition.color or {1, 1, 1}
grassDefinition.colors = grassDefinition.colors or {side = {1, 1, 1}}
local grassChunk = Chunk.new()
grassChunk:setBlock(2, 1, 2, blocks.tall_grass)
grassChunk:setBlock(3, 1, 2, blocks.tall_grass)
local grassVertices = voxel.meshChunk(grassChunk, 3, 0, 0)
assert(#grassVertices == 24 * voxel.STRIDE_FLOATS,
  "two varied grass clumps remain two complete crossed-plane meshes")
local function bounds(firstVertex)
  local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge,
    math.huge, -math.huge, math.huge, -math.huge
  for vertex = firstVertex, firstVertex + 11 do
    local offset = vertex * voxel.STRIDE_FLOATS
    local x, y, z = grassVertices[offset + 1], grassVertices[offset + 2], grassVertices[offset + 3]
    minX, maxX = math.min(minX, x), math.max(maxX, x)
    minY, maxY = math.min(minY, y), math.max(maxY, y)
    minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
  end
  return {centerX = (minX + maxX) * 0.5, centerZ = (minZ + maxZ) * 0.5,
    height = maxY - minY}
end
local grassA, grassB = bounds(0), bounds(12)
assert(math.abs(grassA.centerX - 2.5) > 0.001 or math.abs(grassA.centerZ - 2.5) > 0.001,
  "grass geometry receives its deterministic horizontal offset")
assert(grassA.height >= 0.74 and grassA.height <= 1.14 and
    math.abs(grassA.height - grassB.height) > 0.001,
  "neighbouring grass geometry receives bounded, independent height scale")

print("vegetation variety tests passed")
