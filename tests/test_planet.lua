package.path = "src/?.lua;" .. package.path

local Planet = require("planet")
local World = require("world")
local terrain = require("terrain")
local blocks = require("blocks")

local function close(actual, expected, tolerance, label)
  assert(math.abs(actual - expected) <= tolerance,
    string.format("%s: expected %.12f, got %.12f", label, expected, actual))
end

local planet = Planet.new()
close(planet.radiusMeters, 6371000.0, 0.0, "Earth mean radius")
close(planet.diameterMeters, 12742000.0, 0.0, "Earth diameter")
close(planet.radiusVoxels, 6371000.0, 0.0, "one-metre voxel radius")

local north = {0.0, planet.radiusVoxels + 10.0, 0.0}
local south = {0.0, -planet.radiusVoxels - 10.0, 0.0}
local northUp, southUp = planet:localUp(north), planet:localUp(south)
close(northUp[2], 1.0, 1e-12, "north up")
close(southUp[2], -1.0, 1e-12, "opposite-side up")
close(planet:localDown(north)[2], -1.0, 1e-12, "north gravity")
close(planet:localDown(south)[2], 1.0, 1e-12, "opposite-side gravity")

-- Directional 3D noise is single-valued at a direction and has no longitude
-- wrap coordinate that could disagree at +/-pi.
local direction = {0.5773502691896258, 0.5773502691896258, 0.5773502691896258}
local a = terrain.surfaceAtDirection(direction, planet)
local b = terrain.surfaceAtDirection(direction, planet)
close(a.elevationMeters, b.elevationMeters, 0.0, "deterministic seamless terrain")

local world = World.new({planet = planet, seed = 424242, chunkRadius3D = 1, deferInitialChunks = true})
local spawn, sample = world:surfacePosition({0.0, 0.0, 1.0}, 2.62)
local cx, cy, cz = World.chunkCoord(spawn[1]), World.chunkCoord(spawn[2]), World.chunkCoord(spawn[3])
for dz = -1, 1 do
  for dy = -1, 1 do
    for dx = -1, 1 do world:createChunk(cx + dx, cy + dy, cz + dz) end
  end
end

assert(world.chunks[World.chunkKey(cx, cy, cz)], "3D chunk key addresses the spawn chunk")
assert(sample.surfaceRadiusVoxels > 6300000.0, "surface uses Earth-scale global coordinates")

local origin = world.planet:snappedRenderOrigin(spawn)
local renderPosition = {spawn[1] - origin[1], spawn[2] - origin[2], spawn[3] - origin[3]}
assert(math.abs(renderPosition[1]) <= 128.0 and math.abs(renderPosition[2]) <= 128.0 and math.abs(renderPosition[3]) <= 128.0,
  "floating origin keeps GPU coordinates local")

-- Earth-scale DDA selection: insert one ordinary Cartesian block and hit it
-- from three metres away. No float conversion is involved in this path.
local targetX, targetY, targetZ = math.floor(spawn[1]), math.floor(spawn[2]), math.floor(spawn[3])
world:setBlock(targetX, targetY, targetZ, blocks.stone)
local hit = world:raycast({targetX + 0.5, targetY + 0.5, targetZ + 3.5}, {0.0, 0.0, -1.0}, 6.0)
assert(hit and hit.x == targetX and hit.y == targetY and hit.z == targetZ, "Earth-scale block raycast remains exact")

local outsideClass = planet:classifyChunk(0, 0, 0, 16)
assert(outsideClass == "interior", "deep planet chunks take the uniform interior fast path")
local farClass = planet:classifyChunk(1000000, 1000000, 1000000, 16)
assert(farClass == "outside", "distant chunks take the empty fast path")

-- Inland lakes own a local concentric water radius instead of borrowing the
-- ocean sphere or a global-Y plane.
terrain.setSeed(1)
local golden = math.pi * (3.0 - math.sqrt(5.0))
local lake
for index = 0, 4095 do
  local y = 1.0 - (index + 0.5) * 2.0 / 4096.0
  local ring = math.sqrt(math.max(0.0, 1.0 - y * y))
  local candidate = terrain.surfaceAtDirection({math.cos(index * golden) * ring, y, math.sin(index * golden) * ring}, planet)
  if candidate.waterKind == "lake" then lake = candidate break end
end
assert(lake and lake.waterSurfaceRadiusVoxels, "spherical generator produces inland lake basins")
close(lake.waterSurfaceRadiusVoxels,
  planet.radiusVoxels + lake.waterLevelMeters / planet.voxelSizeMeters,
  1e-9,
  "lake surface uses its local radial level")

print("planet tests passed")
