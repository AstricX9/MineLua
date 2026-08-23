local PlanetLod = {}
PlanetLod.__index = PlanetLod

function PlanetLod.new(world, options)
  options = options or {}
  return setmetatable({
    world = world,
    voxelDistanceMeters = options.voxelDistanceMeters or 480.0,
    terrainDistanceMeters = options.terrainDistanceMeters or 180000.0,
    orbitalDistanceMeters = options.orbitalDistanceMeters or 3000000.0
  }, PlanetLod)
end

function PlanetLod:levelForPosition(position)
  local altitude = self.world.planet:altitudeMeters(position)
  if altitude <= self.voxelDistanceMeters then return "voxel" end
  if altitude <= self.terrainDistanceMeters then return "terrain" end
  if altitude <= self.orbitalDistanceMeters then return "orbital" end
  return "astronomical"
end

-- Every visual representation receives the exact same authoritative inputs.
-- Higher-level renderers can consume this descriptor without duplicating or
-- subtly disagreeing with gameplay world generation.
function PlanetLod:descriptor()
  local planet = self.world.planet
  return {
    center = {planet.center[1], planet.center[2], planet.center[3]},
    radiusMeters = planet.radiusMeters,
    voxelSizeMeters = planet.voxelSizeMeters,
    seaLevelRadiusMeters = planet.seaLevelRadiusVoxels * planet.voxelSizeMeters,
    seed = self.world.seed,
    generatorType = self.world.generatorType
  }
end

return PlanetLod
