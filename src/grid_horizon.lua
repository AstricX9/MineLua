-- Distant terrain, drawn as a smooth shell rather than voxels.
--
-- Voxel chunks cost about 2.3 ms each and their count grows with the square of
-- the radius, so a kilometre of visible ground would be tens of thousands of
-- chunks and most of a minute. But the landscape is a function -- terrain
-- surfaceAtDirection -- and sampling it directly costs about 0.02 ms a point.
-- A few thousand points cover kilometres.
--
-- Rings grow geometrically outward, so the near edge matches the voxel
-- resolution it hides behind and the far edge is coarse enough to be free.

local terrain = require("terrain")

local GridHorizon = {}

local BIOME_COLORS = {
  ocean = {0.025, 0.17, 0.31},
  beach = {0.72, 0.65, 0.39},
  desert = {0.74, 0.59, 0.30},
  savanna = {0.48, 0.52, 0.20},
  shrubland = {0.35, 0.45, 0.24},
  plains = {0.34, 0.53, 0.24},
  forest = {0.18, 0.38, 0.16},
  rainforest = {0.10, 0.30, 0.12},
  taiga = {0.20, 0.36, 0.26},
  tundra = {0.45, 0.52, 0.43},
  mountains = {0.40, 0.40, 0.38},
  frozenShore = {0.72, 0.78, 0.78},
  rockyShore = {0.38, 0.38, 0.36}
}

local sqrt, cos, sin = math.sqrt, math.cos, math.sin

local function normalize(x, y, z)
  local length = sqrt(x * x + y * y + z * z)
  return x / length, y / length, z / length
end

-- Where the shell sits for one tangential offset from the centre.
local function surfacePoint(planet, centre, east, north, offsetEast, offsetNorth, sink)
  local radius = planet.radiusMeters
  local dx, dy, dz = normalize(
    centre[1] + east[1] * offsetEast / radius + north[1] * offsetNorth / radius,
    centre[2] + east[2] * offsetEast / radius + north[2] * offsetNorth / radius,
    centre[3] + east[3] * offsetEast / radius + north[3] * offsetNorth / radius)
  local sample = terrain.surfaceAtDirection({dx, dy, dz}, planet)
  -- Sea shows as a flat sheet rather than the sea floor, which would otherwise
  -- read as a canyon wherever there is ocean.
  local shellRadius = sample.surfaceRadiusVoxels
  local colour = BIOME_COLORS[sample.biome] or BIOME_COLORS.plains
  if sample.elevationMeters <= planet.seaLevelOffsetMeters then
    shellRadius = planet.seaLevelRadiusVoxels
    colour = BIOME_COLORS.ocean
  elseif sample.hasSnow then
    colour = {0.82, 0.86, 0.86}
  end
  shellRadius = shellRadius - sink
  return dx * shellRadius, dy * shellRadius, dz * shellRadius, dx, dy, dz, colour
end

-- Builds the shell around a position. `inner` is where the voxel world stops,
-- `outer` how far to draw, both in metres.
function GridHorizon.build(planet, position, options)
  options = options or {}
  local inner = options.inner or 96.0
  local outer = options.outer or 4000.0
  local segments = options.segments or 96
  -- Dropped slightly so voxel terrain always wins where the two overlap,
  -- instead of the shell poking through the blocks it hides behind.
  local sink = options.sink or 2.0
  local renderOrigin = options.renderOrigin or {0.0, 0.0, 0.0}

  local centre = {normalize(
    position[1] - planet.center[1],
    position[2] - planet.center[2],
    position[3] - planet.center[3])}
  local east, _, north = planet:tangentFrame(position)

  -- Ring radii: fine at the inner edge, geometric outward.
  local radii, distance, step = {inner}, inner, options.step or 6.0
  while distance < outer do
    distance = distance + step
    step = step * 1.06
    radii[#radii + 1] = distance
  end

  local vertices, n = {}, 0
  local cache = {}
  local function corner(ringIndex, segment)
    local key = ringIndex * (segments + 1) + segment
    local hit = cache[key]
    if hit then return hit end
    local angle = segment / segments * math.pi * 2.0
    local ringRadius = radii[ringIndex]
    local value = {surfacePoint(planet, centre, east, north,
      cos(angle) * ringRadius, sin(angle) * ringRadius, sink)}
    cache[key] = value
    return value
  end

  local function push(value)
    local colour = value[7]
    vertices[n + 1] = value[1] - renderOrigin[1] + planet.center[1]
    vertices[n + 2] = value[2] - renderOrigin[2] + planet.center[2]
    vertices[n + 3] = value[3] - renderOrigin[3] + planet.center[3]
    vertices[n + 4], vertices[n + 5], vertices[n + 6] = value[4], value[5], value[6]
    vertices[n + 7], vertices[n + 8], vertices[n + 9] = colour[1], colour[2], colour[3]
    vertices[n + 10], vertices[n + 11] = 0.0, 0.0
    n = n + 11
  end

  for ringIndex = 1, #radii - 1 do
    for segment = 0, segments - 1 do
      local a = corner(ringIndex, segment)
      local b = corner(ringIndex, segment + 1)
      local c = corner(ringIndex + 1, segment + 1)
      local d = corner(ringIndex + 1, segment)
      push(a) push(d) push(c)
      push(c) push(b) push(a)
    end
  end

  return vertices, #radii, n / 11
end

return GridHorizon
