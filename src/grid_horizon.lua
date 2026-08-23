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
  else
    -- Snapped to the voxel layer the blocks actually stop at. Sampling the
    -- analytic surface instead leaves the shell up to a voxel out, which is
    -- what made it stick through the ground near the seam.
    local voxel = planet.voxelSizeMeters
    shellRadius = planet.radiusVoxels
      + math.floor((shellRadius - planet.radiusVoxels) / voxel) * voxel
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
  -- Sunk by more than the shell can wander between samples. Rings are chords,
  -- so between two samples the shell cuts across whatever the ground does in
  -- between; at six metre spacing that was up to a metre, and the shell stuck
  -- up through the blocks. Fine inner rings keep that error small and this
  -- absorbs the rest. The cost is a ledge of the same size at the outer seam,
  -- eighty metres away, where it is not visible.
  local sink = options.sink or 0.6
  local renderOrigin = options.renderOrigin or {0.0, 0.0, 0.0}

  local centre = {normalize(
    position[1] - planet.center[1],
    position[2] - planet.center[2],
    position[3] - planet.center[3])}
  local east, _, north = planet:tangentFrame(position)

  -- Ring radii: fine at the inner edge, geometric outward.
  local radii, distance, step = {inner}, inner, options.step or 1.5
  while distance < outer do
    distance = distance + step
    step = step * 1.06
    radii[#radii + 1] = distance
  end

  -- Sample the whole grid first, then derive normals from it. Using the radial
  -- direction as the normal -- which is what the orbital shader was built for --
  -- gives every vertex the same normal at this scale, so nothing catches the
  -- light and kilometres of landscape read as one flat sheet of colour.
  local ringCount = #radii
  local points = {}
  for ringIndex = 1, ringCount do
    local ringRadius = radii[ringIndex]
    local ring = {}
    for segment = 0, segments - 1 do
      local angle = segment / segments * math.pi * 2.0
      ring[segment] = {surfacePoint(planet, centre, east, north,
        cos(angle) * ringRadius, sin(angle) * ringRadius, sink)}
    end
    points[ringIndex] = ring
  end

  local function at(ringIndex, segment)
    local ring = points[math.max(1, math.min(ringCount, ringIndex))]
    return ring[segment % segments]
  end

  -- Normal from the cross product of the two grid tangents through a vertex.
  local function normalAt(ringIndex, segment)
    local outward = at(ringIndex + 1, segment)
    local inward = at(ringIndex - 1, segment)
    local ahead = at(ringIndex, segment + 1)
    local behind = at(ringIndex, segment - 1)
    local ax, ay, az = outward[1] - inward[1], outward[2] - inward[2], outward[3] - inward[3]
    local bx, by, bz = ahead[1] - behind[1], ahead[2] - behind[2], ahead[3] - behind[3]
    local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    if nx * nx + ny * ny + nz * nz < 1e-12 then
      local point = at(ringIndex, segment)
      return point[4], point[5], point[6]
    end
    nx, ny, nz = normalize(nx, ny, nz)
    -- Point it outward, whichever way the cross product came out.
    local point = at(ringIndex, segment)
    if nx * point[4] + ny * point[5] + nz * point[6] < 0.0 then
      return -nx, -ny, -nz
    end
    return nx, ny, nz
  end

  local vertices, n = {}, 0
  local function push(ringIndex, segment)
    local point = at(ringIndex, segment)
    local colour = point[7]
    local nx, ny, nz = normalAt(ringIndex, segment)
    vertices[n + 1] = point[1] - renderOrigin[1] + planet.center[1]
    vertices[n + 2] = point[2] - renderOrigin[2] + planet.center[2]
    vertices[n + 3] = point[3] - renderOrigin[3] + planet.center[3]
    vertices[n + 4], vertices[n + 5], vertices[n + 6] = nx, ny, nz
    vertices[n + 7], vertices[n + 8], vertices[n + 9] = colour[1], colour[2], colour[3]
    vertices[n + 10], vertices[n + 11] = 0.0, 0.0
    n = n + 11
  end

  for ringIndex = 1, ringCount - 1 do
    for segment = 0, segments - 1 do
      push(ringIndex, segment) push(ringIndex + 1, segment) push(ringIndex + 1, segment + 1)
      push(ringIndex + 1, segment + 1) push(ringIndex, segment + 1) push(ringIndex, segment)
    end
  end

  return vertices, #radii, n / 11
end

return GridHorizon
