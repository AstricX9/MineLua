local noise = require("worldgen.noise")

local Hydrology = {}
Hydrology.__index = Hydrology

local NEIGHBOURS = {
  {-1, -1}, {0, -1}, {1, -1},
  {-1, 0},             {1, 0},
  {-1, 1},  {0, 1},   {1, 1}
}

function Hydrology.new(settings, seed, baseElevationAt, fieldsAt, seaLevel)
  return setmetatable({
    settings = settings or {}, seed = seed or 1,
    baseElevationAt = baseElevationAt, fieldsAt = fieldsAt,
    seaLevel = seaLevel or 63, nodeCache = {}, accumulationCache = {}
  }, Hydrology)
end

function Hydrology:reset(settings, seed, seaLevel)
  self.settings = settings or self.settings
  self.seed = tonumber(seed) or self.seed
  self.seaLevel = seaLevel or self.seaLevel
  self.nodeCache, self.accumulationCache = {}, {}
end

local function nodeKey(cx, cz) return tostring(cx) .. "," .. tostring(cz) end

local function nodePosition(self, cx, cz)
  local grid = self.settings.riverGridSize or 56.0
  local jitter = grid * 0.22
  return
    (cx + 0.5) * grid + (noise.hash2(cx, cz, 401, self.seed) - 0.5) * jitter,
    (cz + 0.5) * grid + (noise.hash2(cx, cz, 409, self.seed) - 0.5) * jitter
end

function Hydrology:node(cx, cz)
  local key = nodeKey(cx, cz)
  local cached = self.nodeCache[key]
  if cached then return cached end

  local x, z = nodePosition(self, cx, cz)
  local elevation, fields = self.baseElevationAt(x, z)
  fields = fields or self.fieldsAt(x, z)
  local node = {
    cx = cx, cz = cz, x = x, z = z, elevation = elevation,
    rainfall = fields.rainfallSeed or fields.humidity or 0.5,
    land = fields.landMask or noise.edge(fields.continentalness, 0.40, 0.56)
  }
  -- Insert before finding neighbours so mutually requested nodes cannot recurse.
  self.nodeCache[key] = node

  local lowestElevation = elevation
  local lowestCx, lowestCz
  for i = 1, #NEIGHBOURS do
    local dx, dz = NEIGHBOURS[i][1], NEIGHBOURS[i][2]
    local nx, nz = nodePosition(self, cx + dx, cz + dz)
    local neighbourElevation = self.baseElevationAt(nx, nz)
    -- Stable tie-break prevents flat regions from producing order-dependent flow.
    local candidate = neighbourElevation + noise.hash2(cx + dx, cz + dz, 419, self.seed) * 0.015
    if candidate < lowestElevation - 0.04 then
      lowestElevation, lowestCx, lowestCz = candidate, cx + dx, cz + dz
    end
  end
  node.downstreamCx, node.downstreamCz = lowestCx, lowestCz
  return node
end

function Hydrology:accumulation(cx, cz, visiting, depth)
  local key = nodeKey(cx, cz)
  local cached = self.accumulationCache[key]
  if cached then return cached end
  visiting, depth = visiting or {}, depth or 0
  local node = self:node(cx, cz)
  local runoff = 0.25 + node.rainfall * 1.15
  if visiting[key] or depth >= (self.settings.riverAccumulationDepth or 56) then return runoff end
  visiting[key] = true
  local total = runoff
  for i = 1, #NEIGHBOURS do
    local nx, nz = cx + NEIGHBOURS[i][1], cz + NEIGHBOURS[i][2]
    local upstream = self:node(nx, nz)
    if upstream.downstreamCx == cx and upstream.downstreamCz == cz then
      total = total + self:accumulation(nx, nz, visiting, depth + 1)
      if total >= 512.0 then total = 512.0 break end
    end
  end
  visiting[key] = nil
  self.accumulationCache[key] = total
  return total
end

local function segmentDistance(x, z, from, to, seed)
  local mx, mz = (from.x + to.x) * 0.5, (from.z + to.z) * 0.5
  local dx, dz = to.x - from.x, to.z - from.z
  local length = math.max(1.0, math.sqrt(dx * dx + dz * dz))
  local meander = (noise.hash2(from.cx, from.cz, 433, seed) - 0.5) * length * 0.24
  mx, mz = mx - dz / length * meander, mz + dx / length * meander
  local da, ta = noise.distanceToSegment(x, z, from.x, from.z, mx, mz)
  local db, tb = noise.distanceToSegment(x, z, mx, mz, to.x, to.z)
  if da <= db then return da, ta * 0.5 end
  return db, 0.5 + tb * 0.5
end

function Hydrology:sample(x, z)
  local s = self.settings
  local grid = s.riverGridSize or 56.0
  local cellX, cellZ = math.floor(x / grid), math.floor(z / grid)
  local minimumAccumulation = s.riverMinimumAccumulation or 5.5
  local density = math.max(0.15, (s.riverDensity or 1.0) * (s.riverFrequency or 1.0))
  local bestRiver, bestDistance, bestWidth, bestLevel, bestAccumulation = 0.0, math.huge, 0.0, nil, 0.0

  for dz = -1, 1 do
    for dx = -1, 1 do
      local node = self:node(cellX + dx, cellZ + dz)
      if node.downstreamCx and node.land > 0.20 then
        local accumulation = self:accumulation(node.cx, node.cz)
        local threshold = minimumAccumulation / density
        if accumulation >= threshold then
          local downstream = self:node(node.downstreamCx, node.downstreamCz)
          local distance, t = segmentDistance(x, z, node, downstream, self.seed)
          local width = noise.clamp(1.2 + math.sqrt(accumulation - threshold + 1.0) *
            (s.riverWidthScale or 0.72), 1.4, 12.0)
          local valleyWidth = width * 3.6 + 4.0
          local strength = 1.0 - noise.smoothstep(distance / valleyWidth)
          if strength > bestRiver then
            bestRiver, bestDistance, bestWidth = strength, distance, width
            bestLevel = math.floor(noise.lerp(node.elevation, downstream.elevation, t) - 0.35)
            bestAccumulation = accumulation
          end
        end
      end
    end
  end

  local lake, lakeLevel, lakeRadius = 0.0, nil, 0.0
  if (s.lakeFrequency or 0.20) > 0.0 then
    for dz = -1, 1 do
      for dx = -1, 1 do
        local basin = self:node(cellX + dx, cellZ + dz)
        if not basin.downstreamCx and basin.land > 0.58 and basin.elevation > self.seaLevel + 3 then
          local accumulation = self:accumulation(basin.cx, basin.cz)
          local chance = noise.hash2(basin.cx, basin.cz, 457, self.seed)
          local terminalRiver = accumulation >= (s.riverMinimumAccumulation or 5.5) * 1.65
          if accumulation >= (s.lakeMinimumAccumulation or 4.0) and
              (terminalRiver or chance < (s.lakeFrequency or 0.20)) then
            local radius = noise.clamp(13.0 + math.sqrt(accumulation) * 4.2, 16.0, 58.0)
            local dxp, dzp = x - basin.x, z - basin.z
            local distance = math.sqrt(dxp * dxp + dzp * dzp)
            local strength = 1.0 - noise.smoothstep(distance / radius)
            if strength > lake then
              lake, lakeRadius = strength, radius
              lakeLevel = math.floor(basin.elevation - 1.0)
            end
          end
        end
      end
    end
  end

  local riverCore = bestDistance <= bestWidth and noise.edge(bestWidth - bestDistance, 0.0, math.max(0.8, bestWidth * 0.72)) or 0.0
  return {
    river = bestRiver,
    riverCore = riverCore,
    riverDistance = bestDistance,
    riverWidth = bestWidth,
    riverAccumulation = bestAccumulation,
    riverWaterLevel = bestLevel,
    lake = lake,
    lakeWaterLevel = lakeLevel,
    lakeRadius = lakeRadius,
    drainage = noise.clamp(bestAccumulation / 64.0, 0.0, 1.0)
  }
end

return Hydrology
