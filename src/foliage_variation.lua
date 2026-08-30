local Variation = {}

local function fract(value)
  return value - math.floor(value)
end

local function hash(x, y, z, salt)
  return fract(math.sin(x * 127.1 + y * 311.7 + z * 74.7 + (salt or 0) * 53.3) * 43758.5453123)
end

-- Stable per-voxel transforms: no mutable RNG means a remesh produces exactly
-- the same clump and neighbouring chunks agree at their shared edge.
function Variation.at(x, y, z, group)
  group = group or 0
  return {
    offsetX = (hash(x, y, z, group + 1) - 0.5) * 0.36,
    offsetZ = (hash(x, y, z, group + 2) - 0.5) * 0.36,
    rotation = hash(x, y, z, group + 3) * math.pi * 2.0,
    widthScale = 0.78 + hash(x, y, z, group + 4) * 0.40,
    heightScale = 0.74 + hash(x, y, z, group + 5) * 0.40
  }
end

return Variation
