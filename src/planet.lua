local math3d = require("math3d")

local Planet = {}
Planet.__index = Planet

Planet.EARTH_RADIUS_METERS = 6371000.0
Planet.DEFAULT_VOXEL_SIZE_METERS = 1.0

local function copy3(value, fallback)
  value = value or fallback or {0.0, 0.0, 0.0}
  return {tonumber(value[1]) or 0.0, tonumber(value[2]) or 0.0, tonumber(value[3]) or 0.0}
end

function Planet.new(options)
  options = options or {}
  local voxelSize = tonumber(options.voxelSizeMeters) or Planet.DEFAULT_VOXEL_SIZE_METERS
  assert(voxelSize > 0.0, "planet voxel size must be positive")

  local radiusMeters = tonumber(options.radiusMeters) or Planet.EARTH_RADIUS_METERS
  local self = setmetatable({
    center = copy3(options.center),
    radiusMeters = radiusMeters,
    voxelSizeMeters = voxelSize,
    radiusVoxels = radiusMeters / voxelSize,
    diameterMeters = radiusMeters * 2.0,
    diameterVoxels = radiusMeters * 2.0 / voxelSize,
    seaLevelOffsetMeters = tonumber(options.seaLevelOffsetMeters) or 0.0,
    gravityAcceleration = tonumber(options.gravityAcceleration) or 9.81,
    minTerrainElevationMeters = tonumber(options.minTerrainElevationMeters) or -220.0,
    maxTerrainElevationMeters = tonumber(options.maxTerrainElevationMeters) or 300.0,
    generatedInteriorDepthMeters = tonumber(options.generatedInteriorDepthMeters) or 192.0,
    renderOriginGridMeters = tonumber(options.renderOriginGridMeters) or 2048.0
  }, Planet)
  self.seaLevelRadiusVoxels = self.radiusVoxels + self.seaLevelOffsetMeters / voxelSize
  self.minSurfaceRadiusVoxels = self.radiusVoxels + self.minTerrainElevationMeters / voxelSize
  self.maxSurfaceRadiusVoxels = self.radiusVoxels + self.maxTerrainElevationMeters / voxelSize
  return self
end

function Planet:relative(position)
  return {
    position[1] - self.center[1],
    position[2] - self.center[2],
    position[3] - self.center[3]
  }
end

function Planet:distanceVoxels(position)
  local x = position[1] - self.center[1]
  local y = position[2] - self.center[2]
  local z = position[3] - self.center[3]
  return math.sqrt(x * x + y * y + z * z)
end

function Planet:localUp(position)
  return math3d.normalize(self:relative(position))
end

function Planet:localDown(position)
  local up = self:localUp(position)
  return {-up[1], -up[2], -up[3]}
end

function Planet:altitudeMeters(position)
  return (self:distanceVoxels(position) - self.radiusVoxels) * self.voxelSizeMeters
end

function Planet:seaLevelRadius()
  return self.seaLevelRadiusVoxels
end

-- A stable orthonormal frame. Choosing the least-parallel reference axis avoids
-- the pole singularity of a fixed global-up cross product.
function Planet:tangentFrame(position, forwardHint)
  local up = self:localUp(position)
  local reference
  if math.abs(up[2]) < 0.80 then
    reference = {0.0, 1.0, 0.0}
  elseif math.abs(up[1]) < 0.80 then
    reference = {1.0, 0.0, 0.0}
  else
    reference = {0.0, 0.0, 1.0}
  end

  local east = math3d.normalize(math3d.cross(reference, up))
  local north = math3d.normalize(math3d.cross(up, east))
  if forwardHint then
    local dotUp = forwardHint[1] * up[1] + forwardHint[2] * up[2] + forwardHint[3] * up[3]
    local tangent = math3d.normalize({
      forwardHint[1] - up[1] * dotUp,
      forwardHint[2] - up[2] * dotUp,
      forwardHint[3] - up[3] * dotUp
    })
    if tangent[1] ~= 0.0 or tangent[2] ~= 0.0 or tangent[3] ~= 0.0 then
      north = tangent
      east = math3d.normalize(math3d.cross(north, up))
    end
  end
  return east, up, north
end

function Planet:dominantUpStep(position)
  local up = self:localUp(position)
  local ax, ay, az = math.abs(up[1]), math.abs(up[2]), math.abs(up[3])
  if ax >= ay and ax >= az then
    return up[1] >= 0.0 and 1 or -1, 0, 0
  elseif ay >= az then
    return 0, up[2] >= 0.0 and 1 or -1, 0
  end
  return 0, 0, up[3] >= 0.0 and 1 or -1
end

-- Exact minimum/maximum distance from the planet centre to an axis-aligned
-- chunk box. This is the cheap reject used before any noise is evaluated.
function Planet:chunkRadialBounds(chunkX, chunkY, chunkZ, chunkSize)
  local minX, minY, minZ = chunkX * chunkSize, chunkY * chunkSize, chunkZ * chunkSize
  local maxX, maxY, maxZ = minX + chunkSize, minY + chunkSize, minZ + chunkSize
  local cx, cy, cz = self.center[1], self.center[2], self.center[3]

  local function axisDistance(value, low, high)
    if value < low then return low - value end
    if value > high then return value - high end
    return 0.0
  end

  local dx = axisDistance(cx, minX, maxX)
  local dy = axisDistance(cy, minY, maxY)
  local dz = axisDistance(cz, minZ, maxZ)
  local minDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
  local farX = math.max(math.abs(minX - cx), math.abs(maxX - cx))
  local farY = math.max(math.abs(minY - cy), math.abs(maxY - cy))
  local farZ = math.max(math.abs(minZ - cz), math.abs(maxZ - cz))
  local maxDistance = math.sqrt(farX * farX + farY * farY + farZ * farZ)
  return minDistance, maxDistance
end

function Planet:classifyChunk(chunkX, chunkY, chunkZ, chunkSize)
  local minDistance, maxDistance = self:chunkRadialBounds(chunkX, chunkY, chunkZ, chunkSize)
  if minDistance > self.maxSurfaceRadiusVoxels and minDistance > self.seaLevelRadiusVoxels then
    return "outside", minDistance, maxDistance
  end
  local generatedFloor = self.minSurfaceRadiusVoxels - self.generatedInteriorDepthMeters / self.voxelSizeMeters
  if maxDistance < generatedFloor then
    return "interior", minDistance, maxDistance
  end
  return "surface", minDistance, maxDistance
end

function Planet:spawnPosition(eyeHeight)
  return {
    self.center[1] + 0.5,
    self.center[2] + 0.5,
    self.center[3] + self.radiusVoxels + (eyeHeight or 1.62) + self.maxTerrainElevationMeters / self.voxelSizeMeters
  }
end

function Planet:snappedRenderOrigin(position)
  local grid = self.renderOriginGridMeters / self.voxelSizeMeters
  return {
    math.floor(position[1] / grid + 0.5) * grid,
    math.floor(position[2] / grid + 0.5) * grid,
    math.floor(position[3] / grid + 0.5) * grid
  }
end

return Planet
