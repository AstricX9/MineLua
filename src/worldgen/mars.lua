-- Scientifically grounded procedural Mars surface.
--
-- This is deliberately a generator module, not a branch in terrain.lua. It
-- models the terrain classes visible in global Mars data (northern lowlands,
-- ancient cratered southern highlands, impact ejecta, basaltic volcanic rises,
-- long fault canyons, wind-worked dust and polar ice) at gameplay scale. It is
-- deterministic and implements the same semantic interface as pipeline.lua.
local noise = require("worldgen.noise")

local Mars = {}
Mars.__index = Mars

local function cacheKey(x, z, maxHeight)
  return tostring(x) .. "," .. tostring(z) .. ":" .. tostring(maxHeight or 127)
end

local function craterLayer(x, z, cellSize, salt, seed, density, depthScale)
  local cellX, cellZ = math.floor(x / cellSize), math.floor(z / cellSize)
  local relief, strength, rimStrength, ejectaStrength = 0.0, 0.0, 0.0, 0.0

  for dz = -1, 1 do
    for dx = -1, 1 do
      local cx, cz = cellX + dx, cellZ + dz
      if noise.hash2(cx, cz, salt, seed) < density then
        local centerX = (cx + 0.18 + noise.hash2(cx, cz, salt + 3, seed) * 0.64) * cellSize
        local centerZ = (cz + 0.18 + noise.hash2(cx, cz, salt + 7, seed) * 0.64) * cellSize
        local radius = cellSize * (0.17 + noise.hash2(cx, cz, salt + 11, seed) * 0.22)
        local q = math.sqrt((x - centerX) ^ 2 + (z - centerZ) ^ 2) / radius
        if q < 1.55 then
          local age = 0.48 + noise.hash2(cx, cz, salt + 13, seed) * 0.52
          local depth = radius * depthScale * age
          local bowl = q < 1.0 and -depth * (1.0 - q * q) ^ 2 or 0.0
          local rim = depth * 0.36 * math.exp(-((q - 1.0) / 0.105) ^ 2)
          local ejecta = q > 1.0 and depth * 0.10 * math.exp(-(q - 1.0) * 4.2) or 0.0
          local rayNoise = noise.ridged(noise.fbm(x, z, salt + 19, 2, 0.022, seed))
          ejecta = ejecta * (0.55 + rayNoise * 0.75)
          relief = relief + bowl + rim + ejecta
          strength = math.max(strength, q < 1.0 and 1.0 - q or 0.0)
          rimStrength = math.max(rimStrength, math.exp(-((q - 1.0) / 0.12) ^ 2))
          ejectaStrength = math.max(ejectaStrength,
            q >= 1.0 and q < 1.55 and (1.55 - q) / 0.55 or 0.0)
        end
      end
    end
  end

  return relief, strength, rimStrength, ejectaStrength
end

local function volcanicRelief(x, z, seed)
  local cellSize = 3200.0
  local cellX, cellZ = math.floor(x / cellSize), math.floor(z / cellSize)
  local relief, strength = 0.0, 0.0
  for dz = -1, 1 do
    for dx = -1, 1 do
      local cx, cz = cellX + dx, cellZ + dz
      if noise.hash2(cx, cz, 401, seed) < 0.17 then
        local centerX = (cx + 0.2 + noise.hash2(cx, cz, 409, seed) * 0.6) * cellSize
        local centerZ = (cz + 0.2 + noise.hash2(cx, cz, 419, seed) * 0.6) * cellSize
        local radius = 620.0 + noise.hash2(cx, cz, 421, seed) * 720.0
        local q = math.sqrt((x - centerX) ^ 2 + (z - centerZ) ^ 2) / radius
        if q < 1.0 then
          local shield = (1.0 - q) ^ 2 * (24.0 + radius * 0.012)
          local caldera = q < 0.16 and (1.0 - q / 0.16) ^ 2 * shield * 0.52 or 0.0
          relief = relief + shield - caldera
          strength = math.max(strength, 1.0 - q)
        end
      end
    end
  end
  return relief, strength
end

function Mars.new(settings, seed)
  return setmetatable({
    settings = settings or {},
    seed = tonumber(seed) or 1,
    sampleCache = {},
    sampleCacheCount = 0
  }, Mars)
end

function Mars:setSeed(seed)
  self.seed = tonumber(seed) or 1
  self.sampleCache, self.sampleCacheCount = {}, 0
end

function Mars:refresh(settings)
  self.settings = settings or self.settings
  self.sampleCache, self.sampleCacheCount = {}, 0
end

function Mars:sampleColumn(x, z, maxHeight)
  maxHeight = maxHeight or 127
  local key = cacheKey(x, z, maxHeight)
  local cached = self.sampleCache[key]
  if cached then return cached end
  if self.sampleCacheCount > 180000 then
    self.sampleCache, self.sampleCacheCount = {}, 0
  end

  local seed = self.seed
  local wx, wz = noise.warp2(x, z, 0.00048, 210.0, 307, seed)
  local highlands = 1.0 - noise.edge(z, -620.0, 620.0)
  local regional = (noise.fbm(wx, wz, 311, 5, 0.00072, seed) - 0.5) * 18.0
  local rolling = (noise.fbm(wx, wz, 317, 4, 0.0031, seed) - 0.5) * 9.0
  local highlandRoughness = (noise.fbm(x, z, 331, 4, 0.0105, seed) - 0.5) * (5.0 + highlands * 5.5)

  local largeCrater, craterStrength, largeRim, largeEjecta =
    craterLayer(x, z, 720.0, 347, seed, 0.62 + highlands * 0.22, 0.075)
  local smallCrater, smallStrength, smallRim, smallEjecta =
    craterLayer(x, z, 176.0, 359, seed, 0.48 + highlands * 0.28, 0.070)
  local craterRelief = largeCrater + smallCrater
  craterStrength = math.max(craterStrength, smallStrength)
  local rimStrength = math.max(largeRim, smallRim)
  local ejectaStrength = math.max(largeEjecta, smallEjecta)

  local volcano, volcanic = volcanicRelief(x, z, seed)

  -- Long, fault-controlled troughs stand in for the Valles Marineris class of
  -- terrain. The low-frequency gate makes them regional rather than a web over
  -- every square kilometre; anisotropic coordinates make them canyon-like.
  local canyonX, canyonZ = noise.rotated(wx, wz, -0.09)
  local canyonLine = noise.ridged(noise.fbm(canyonX, canyonZ * 0.16, 373, 4, 0.00145, seed))
  local canyonRegion = noise.edge(noise.fbm(wx, wz, 379, 3, 0.00031, seed), 0.53, 0.72)
  local canyon = noise.edge(canyonLine, 0.90, 0.985) * canyonRegion
  local canyonDepth = canyon * (11.0 + noise.fbm(x, z, 383, 3, 0.006, seed) * 12.0)

  local duneRegion = noise.edge(noise.fbm(wx, wz, 389, 3, 0.0011, seed), 0.54, 0.76)
  local duneX, duneZ = noise.rotated(x, z, 0.42)
  local dunes = (noise.ridged(noise.fbm(duneX, duneZ * 0.24, 397, 3, 0.031, seed)) - 0.5) *
    2.4 * duneRegion

  -- MOLA's hemispheric dichotomy is represented at compressed gameplay scale:
  -- old southern highlands sit above smoother northern plains.
  local components = {
    datum = 69.0,
    dichotomy = highlands * 10.0 - (1.0 - highlands) * 5.0,
    regional = regional,
    rolling = rolling,
    roughness = highlandRoughness,
    craters = craterRelief,
    volcano = volcano,
    canyon = -canyonDepth,
    dunes = dunes
  }
  local height = 0.0
  for _, value in pairs(components) do height = height + value end
  height = noise.clamp(math.floor(height + 0.5), 6, math.max(6, maxHeight - 4))

  local latitude = noise.clamp(math.abs(z) / 24000.0, 0.0, 1.0)
  local polar = noise.edge(latitude, 0.82, 0.94)
  local dust = noise.clamp(noise.fbm(x, z, 433, 4, 0.0042, seed) * 0.72 + duneRegion * 0.28, 0.0, 1.0)
  local exposedBasalt = volcanic > 0.28 or dust < 0.29 or canyon > 0.72

  local biome, landform, topBlock, fillerBlock
  if polar > 0.58 then
    biome, landform, topBlock, fillerBlock = "mars_polar", "polar_cap", "packed_ice", "packed_ice"
  elseif volcanic > 0.32 then
    biome, landform, topBlock, fillerBlock = "mars_volcanic", "shield_volcano", "stone", "stone"
  elseif canyon > 0.44 then
    biome, landform, topBlock, fillerBlock = "mars_canyon", "fault_canyon", "stone", "red_sandstone"
  elseif craterStrength > 0.28 or rimStrength > 0.52 then
    biome, landform = "mars_crater", rimStrength > 0.58 and "impact_rim" or "impact_basin"
    topBlock = (rimStrength > 0.64 or exposedBasalt) and "gravel" or "red_sand"
    fillerBlock = "red_sandstone"
  elseif highlands > 0.5 then
    biome, landform = "mars_highlands", "cratered_highlands"
    topBlock, fillerBlock = exposedBasalt and "stone" or "red_sand", "red_sandstone"
  else
    biome, landform = "mars_lowlands", duneRegion > 0.58 and "dune_field" or "northern_plain"
    topBlock, fillerBlock = exposedBasalt and "stone" or "red_sand", "red_sandstone"
  end

  local ruggedness = noise.clamp(highlands * 0.42 + rimStrength * 0.38 + canyon * 0.52 + volcanic * 0.25, 0.0, 1.0)
  local result = {
    x = x, z = z,
    height = height,
    baseHeight = components.datum + components.dichotomy + regional,
    biome = biome,
    biomeFamily = highlands > 0.5 and "noachian_highlands" or "northern_lowlands",
    landform = landform,
    geology = exposedBasalt and "exposed_basalt" or "dust_mantled_basalt",
    geologyHardness = exposedBasalt and 0.88 or 0.63,
    soilDepthScale = exposedBasalt and 0.38 or (0.72 + dust * 0.72),
    volcanic = volcanic > 0.28,
    coastType = nil,
    waterKind = nil,
    waterClass = nil,
    waterLevel = nil,
    river = 0.0,
    riverCore = 0.0,
    riverAccumulation = 0.0,
    lake = 0.0,
    drainage = 0.0,
    land = 1.0,
    mountain = volcanic,
    erosion = noise.clamp(0.18 + dust * 0.26, 0.0, 1.0),
    ruggedness = ruggedness,
    temperature = noise.clamp(0.34 - latitude * 0.23 - math.max(0, height - 69) * 0.0024, 0.02, 0.36),
    moisture = polar * 0.08,
    rainfall = 0.0,
    continentalness = highlands,
    volcanism = volcanic,
    hasSnow = false,
    freezeWater = false,
    topBlock = topBlock,
    fillerBlock = fillerBlock,
    crater = math.max(craterStrength, rimStrength, ejectaStrength),
    craterFloor = craterStrength,
    craterRim = rimStrength,
    ejecta = ejectaStrength,
    canyon = canyon,
    dust = dust,
    polarIce = polar,
    components = components,
    fields = {
      latitude = latitude,
      dichotomy = highlands,
      crater = math.max(craterStrength, rimStrength),
      canyon = canyon,
      dust = dust,
      volcanism = volcanic,
      surfaceDetail = noise.clamp(math.abs(dunes) / 2.4 + ruggedness, 0.0, 1.0)
    }
  }
  result.components.final = height
  self.sampleCache[key], self.sampleCacheCount = result, self.sampleCacheCount + 1
  return result
end

function Mars:heightAt(x, z, maxHeight)
  return self:sampleColumn(x, z, maxHeight).height
end

function Mars:macroAt(x, z)
  local sample = self:sampleColumn(x, z, 127)
  return {
    continent = sample.continentalness,
    continentalness = sample.continentalness,
    land = 1.0,
    coast = 0.0,
    regionalElevation = sample.baseHeight / 127.0,
    broadHills = sample.ruggedness,
    localHills = sample.fields.surfaceDetail,
    surfaceDetail = sample.fields.surfaceDetail,
    micro = sample.dust,
    mountain = sample.mountain,
    mountainPotential = sample.mountain,
    ridge = sample.craterRim,
    river = 0.0,
    riverCore = 0.0,
    lake = 0.0,
    drainage = 0.0,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = 0.0,
    erosion = sample.erosion,
    geologicalAge = sample.continentalness,
    tectonicActivity = sample.canyon,
    volcanism = sample.volcanism,
    geology = sample.geology,
    landform = sample.landform,
    crater = sample.crater,
    canyon = sample.canyon,
    dust = sample.dust,
    polarIce = sample.polarIce,
    warpX = 0.0,
    warpZ = 0.0
  }
end

function Mars:sampleChunkEnvironment(offsetX, offsetZ, width, depth, maxHeight)
  local points = {
    {offsetX + width * 0.5, offsetZ + depth * 0.5},
    {offsetX + 2, offsetZ + 2}, {offsetX + width - 3, offsetZ + 2},
    {offsetX + 2, offsetZ + depth - 3}, {offsetX + width - 3, offsetZ + depth - 3}
  }
  local center = self:sampleColumn(points[1][1], points[1][2], maxHeight)
  local elevation, temperature, ruggedness, crater, dust = 0.0, 0.0, 0.0, 0.0, 0.0
  for index = 1, #points do
    local sample = self:sampleColumn(points[index][1], points[index][2], maxHeight)
    elevation = elevation + sample.height
    temperature = temperature + sample.temperature
    ruggedness = ruggedness + sample.ruggedness
    crater = math.max(crater, sample.crater)
    dust = dust + sample.dust
  end
  return {
    world = "mars",
    biome = center.biome,
    biomeFamily = center.biomeFamily,
    averageTemperature = temperature / #points,
    averageMoisture = 0.0,
    rainfall = 0.0,
    continentalness = center.continentalness,
    averageElevation = elevation / #points,
    erosion = center.erosion,
    ruggedness = ruggedness / #points,
    geology = center.geology,
    landform = center.landform,
    river = false, lake = false, ocean = false, coast = false,
    volcanic = center.volcanic,
    crater = crater,
    dust = dust / #points
  }
end

function Mars:debugFieldsAt(x, z, maxHeight)
  local sample = self:sampleColumn(x, z, maxHeight or 127)
  return {
    biome = sample.biome,
    biomeFamily = sample.biomeFamily,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = 0.0,
    continentalness = sample.continentalness,
    elevation = sample.height,
    baseElevation = sample.baseHeight,
    mountainPotential = sample.mountain,
    erosion = sample.erosion,
    drainage = 0.0,
    riverNetwork = 0.0,
    geology = sample.geology,
    volcanism = sample.volcanism,
    landform = sample.landform,
    waterKind = nil,
    coastType = nil,
    crater = sample.crater,
    canyon = sample.canyon,
    dust = sample.dust,
    polarIce = sample.polarIce
  }
end

function Mars:heightExplanationAt(x, z, maxHeight)
  return self:sampleColumn(x, z, maxHeight or 127).components
end

local BIOME_COLORS = {
  mars_lowlands = {0.64, 0.30, 0.16},
  mars_highlands = {0.72, 0.38, 0.22},
  mars_crater = {0.43, 0.24, 0.18},
  mars_volcanic = {0.18, 0.16, 0.16},
  mars_canyon = {0.34, 0.17, 0.12},
  mars_polar = {0.82, 0.88, 0.90}
}

function Mars:debugColorAt(mode, x, z, maxHeight)
  local fields = self:debugFieldsAt(x, z, maxHeight or 127)
  if mode == "biome" then return BIOME_COLORS[fields.biome] or {0.65, 0.32, 0.18} end
  if mode == "geology" then
    return fields.geology == "exposed_basalt" and {0.17, 0.16, 0.17} or {0.67, 0.33, 0.19}
  end
  local value = fields[mode]
  if type(value) ~= "number" then return {0.45, 0.30, 0.24} end
  value = noise.clamp(mode == "elevation" and value / (maxHeight or 127) or value, 0.0, 1.0)
  if mode == "temperature" then return {0.35 + value * 0.65, 0.18 + value * 0.25, 0.28 - value * 0.18} end
  return {value, value * 0.55, value * 0.32}
end

return Mars
