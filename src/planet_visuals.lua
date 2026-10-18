local terrain = require("terrain")

local visuals = {}

local BIOME_COLORS = {
  ocean = {0.025, 0.17, 0.31},
  beach = {0.72, 0.65, 0.39},
  desert = {0.74, 0.59, 0.30},
  savanna = {0.48, 0.52, 0.20},
  shrubland = {0.35, 0.45, 0.24},
  plains = {0.28, 0.50, 0.20},
  forest = {0.075, 0.31, 0.12},
  rainforest = {0.035, 0.25, 0.10},
  taiga = {0.17, 0.34, 0.25},
  tundra = {0.45, 0.52, 0.43},
  mountains = {0.36, 0.36, 0.34},
  frozenShore = {0.72, 0.78, 0.78},
  rockyShore = {0.38, 0.38, 0.36}
}

local function directionAt(latitude, longitude)
  local c = math.cos(latitude)
  return {c * math.cos(longitude), math.sin(latitude), c * math.sin(longitude)}
end

local function append(vertices, position, normal, color, u, v)
  local n = #vertices
  vertices[n + 1], vertices[n + 2], vertices[n + 3] = position[1], position[2], position[3]
  vertices[n + 4], vertices[n + 5], vertices[n + 6] = normal[1], normal[2], normal[3]
  vertices[n + 7], vertices[n + 8], vertices[n + 9] = color[1], color[2], color[3]
  vertices[n + 10], vertices[n + 11] = u, v
end

local function surfaceVertex(world, latitude, longitude, u, v)
  local direction = directionAt(latitude, longitude)
  local sample = terrain.surfaceAtDirection(direction, world.planet)
  local radius = sample.surfaceRadiusVoxels
  local color = BIOME_COLORS[sample.biome] or BIOME_COLORS.plains
  if sample.elevationMeters <= world.planet.seaLevelOffsetMeters then
    radius = world.planet.seaLevelRadiusVoxels
    -- A single sea colour prevents low-frequency bathymetry samples from
    -- revealing the orbital triangle tessellation through interpolation.
    color = {0.026, 0.19, 0.34}
  elseif sample.hasSnow then
    color = {0.82, 0.86, 0.86}
  end
  return {direction[1] * radius, direction[2] * radius, direction[3] * radius}, direction, color, u, v
end

function visuals.buildSurfaceVertices(world, segments, rings)
  segments, rings = segments or 64, rings or 32
  local vertices = {}
  local cache = {}
  local function cachedVertex(row, column)
    local key = row * (segments + 1) + column
    local value = cache[key]
    if value then return value[1], value[2], value[3] end
    local v, u = row / rings, column / segments
    local position, normal, color = surfaceVertex(world, -math.pi * 0.5 + v * math.pi, u * math.pi * 2.0, u, v)
    cache[key] = {position, normal, color}
    return position, normal, color
  end
  for row = 0, rings - 1 do
    local v0, v1 = row / rings, (row + 1) / rings
    local lat0, lat1 = -math.pi * 0.5 + v0 * math.pi, -math.pi * 0.5 + v1 * math.pi
    for column = 0, segments - 1 do
      local u0, u1 = column / segments, (column + 1) / segments
      local lon0, lon1 = u0 * math.pi * 2.0, u1 * math.pi * 2.0
      local p00, n00, c00 = cachedVertex(row, column)
      local p10, n10, c10 = cachedVertex(row, column + 1)
      local p01, n01, c01 = cachedVertex(row + 1, column)
      local p11, n11, c11 = cachedVertex(row + 1, column + 1)
      append(vertices, p00, n00, c00, u0, v0)
      append(vertices, p01, n01, c01, u0, v1)
      append(vertices, p11, n11, c11, u1, v1)
      append(vertices, p11, n11, c11, u1, v1)
      append(vertices, p10, n10, c10, u1, v0)
      append(vertices, p00, n00, c00, u0, v0)
    end
  end
  return vertices
end

function visuals.buildShellVertices(planet, altitudeMeters, segments, rings)
  segments, rings = segments or 64, rings or 32
  local vertices = {}
  local radius = planet.radiusVoxels + altitudeMeters / planet.voxelSizeMeters
  local white = {1.0, 1.0, 1.0}
  for row = 0, rings - 1 do
    local v0, v1 = row / rings, (row + 1) / rings
    local lat0, lat1 = -math.pi * 0.5 + v0 * math.pi, -math.pi * 0.5 + v1 * math.pi
    for column = 0, segments - 1 do
      local u0, u1 = column / segments, (column + 1) / segments
      local lon0, lon1 = u0 * math.pi * 2.0, u1 * math.pi * 2.0
      local n00, n10 = directionAt(lat0, lon0), directionAt(lat0, lon1)
      local n01, n11 = directionAt(lat1, lon0), directionAt(lat1, lon1)
      local function p(n) return {n[1] * radius, n[2] * radius, n[3] * radius} end
      append(vertices, p(n00), n00, white, u0, v0)
      append(vertices, p(n01), n01, white, u0, v1)
      append(vertices, p(n11), n11, white, u1, v1)
      append(vertices, p(n11), n11, white, u1, v1)
      append(vertices, p(n10), n10, white, u1, v0)
      append(vertices, p(n00), n00, white, u0, v0)
    end
  end
  return vertices
end

return visuals
