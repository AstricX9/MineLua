-- Layered deterministic world-generation pipeline.
--
-- seed -> continuous fields -> geology/landforms -> macro elevation ->
-- erosion -> hydrology -> climate -> biome/coast -> local detail
--
-- This module owns geographic causes and metadata. terrain.lua remains the
-- voxel/material adapter so the existing renderer and chunk format stay intact.
local noise = require("worldgen.noise")
local Fields = require("worldgen.fields")
local Geology = require("worldgen.geology")
local Hydrology = require("worldgen.hydrology")

local Pipeline = {}
Pipeline.__index = Pipeline

local function keyFor(x, z, maxHeight)
  return tostring(x) .. "," .. tostring(z) .. ":" .. tostring(maxHeight or 127)
end

function Pipeline.new(settings, seed)
  local self = setmetatable({}, Pipeline)
  self.settings = settings or {}
  self.seed = tonumber(seed) or 1
  self.seaLevel = self.settings.seaLevel or 63
  self.fields = Fields.new(self.settings, self.seed)
  self.geology = Geology.new(self.settings, self.seed)
  self.baseCache, self.sampleCache, self.sampleCacheCount = {}, {}, 0
  self.hydrology = Hydrology.new(self.settings, self.seed,
    function(x, z) return self:baseElevationAt(x, z) end,
    function(x, z) return self.fields:sample(x, z) end,
    self.seaLevel)
  return self
end

function Pipeline:setSeed(seed)
  seed = tonumber(seed) or 1
  if seed == self.seed then return end
  self.seed = seed
  self.fields:setSeed(seed)
  self.geology:setSeed(seed)
  self.baseCache, self.sampleCache, self.sampleCacheCount = {}, {}, 0
  self.hydrology:reset(self.settings, seed, self.seaLevel)
end

function Pipeline:refresh(settings)
  self.settings = settings or self.settings
  self.seaLevel = self.settings.seaLevel or 63
  self.fields:setSettings(self.settings)
  self.geology:setSettings(self.settings)
  self.baseCache, self.sampleCache, self.sampleCacheCount = {}, {}, 0
  self.hydrology:reset(self.settings, self.seed, self.seaLevel)
end

local function oceanClass(continentalness, landMask)
  if landMask > 0.08 then return nil end
  if continentalness < 0.19 then return "deepOcean" end
  if continentalness < 0.31 then return "ocean" end
  if continentalness < 0.40 then return "shallowOcean" end
  return "coastalWater"
end

-- Height before rivers and lakes. Hydrology samples only this stage, so flow
-- direction cannot be invalidated by terrain that is replaced afterwards.
function Pipeline:baseElevationAt(x, z)
  local key = tostring(x) .. "," .. tostring(z)
  local cached = self.baseCache[key]
  if cached then return cached.height, cached.fields, cached.geology, cached.components end

  local s = self.settings
  local sea = self.seaLevel
  local fields = self.fields:sample(x, z)
  local geology = self.geology:sample(x, z, fields)
  local continentThreshold = s.continentThreshold or 0.455
  local shelfWidth = s.continentalShelfWidth or 0.115
  local landMask = noise.edge(fields.continentalness,
    continentThreshold - shelfWidth * 0.52, continentThreshold + shelfWidth * 0.48)
  fields.landMask = landMask
  fields.rainfallSeed = noise.clamp(fields.humidity * 0.62 + fields.rainfallVariation * 0.38, 0.0, 1.0)

  local verticalScale = s.terrainVerticalScale or 1.0
  local oceanDepth = (s.oceanDepthScale or 42.0) * verticalScale
  local shelf = noise.edge(fields.continentalness, continentThreshold - shelfWidth, continentThreshold)
  local abyss = (fields.baseElevation - 0.5) * 10.0
  local trench = noise.edge(0.22 - fields.continentalness, 0.0, 0.12) *
    noise.edge(fields.tectonicActivity, 0.58, 0.88) * 13.0
  local oceanRidge = fields.mountainChain * noise.edge(0.40 - fields.continentalness, 0.0, 0.22) * 9.0
  local oceanFloor = sea - oceanDepth + fields.continentalness * oceanDepth * 0.62 +
    abyss - trench + oceanRidge
  local shelfFloor = sea - 3.5 + (fields.broadHills - 0.5) * 3.5
  oceanFloor = noise.lerp(oceanFloor, shelfFloor, shelf)

  local inlandness = noise.edge(fields.continentalness, continentThreshold, 0.82)
  local continentalBase = sea + 2.0 + inlandness * 18.0 +
    (fields.baseElevation - 0.5) * 21.0 * verticalScale
  local effectiveErosion = geology.erosion
  local broadRelief = (fields.broadHills - 0.5) * 18.0 * verticalScale * (1.0 - effectiveErosion * 0.52)
  local localRelief = ((fields.localHills - 0.5) * 8.0 +
    (fields.surfaceDetail - 0.5) * 3.4 + (fields.localVariation - 0.5) * 1.2) *
    (s.surfaceDetailStrength or 1.0) * (1.0 - effectiveErosion * 0.68)

  local mountainSharpness = s.mountainSharpness or 1.65
  local mountainHeight = s.mountainHeight or 49.0
  local mountain = (fields.mountainPotential ^ mountainSharpness) *
    (0.48 + (fields.ridge ^ 1.6) * 0.52) * mountainHeight *
    (1.0 - effectiveErosion * 0.42)
  local foothills = noise.edge(fields.mountainPotential, 0.06, 0.38) *
    fields.ridge * (s.foothillHeight or 9.0) * (1.0 - effectiveErosion * 0.28)

  local plateau = geology.plateau * (s.plateauHeight or 18.0)
  if plateau > 0.0 then
    local terraces = math.floor((fields.baseElevation * 4.0) + 0.5) / 4.0
    plateau = plateau * (0.68 + terraces * 0.32)
  end
  local basin = geology.basin * (s.basinDepth or 9.0)
  local volcano = geology.volcanicCone * (s.volcanoHeight or 36.0)
  local caldera = geology.caldera * (s.calderaDepth or 14.0)

  local landHeight = continentalBase + broadRelief + localRelief + mountain + foothills +
    plateau - basin + volcano - caldera
  local height = noise.lerp(oceanFloor, landHeight, landMask)
  local components = {
    oceanFloor = oceanFloor,
    continentalBase = continentalBase,
    broadRelief = broadRelief,
    localRelief = localRelief,
    mountain = mountain,
    foothills = foothills,
    plateau = plateau,
    basin = -basin,
    volcano = volcano,
    caldera = -caldera,
    preHydrology = height
  }
  local result = {height = height, fields = fields, geology = geology, components = components}
  self.baseCache[key] = result
  return height, fields, geology, components
end

local function climateBiome(temperature, rainfall, elevation, sea, landform, geology, hydrology)
  if hydrology.lake > 0.72 then return "swampland", "lake" end
  if hydrology.riverCore > 0.58 then
    -- River remains metadata-first so vegetation/material code can blend with
    -- the surrounding climate instead of making a hard 16-block ribbon.
  end
  -- Keep the wooded climate biome across most slopes. Only the highest caps
  -- switch to sparse alpine terrain, matching Minecraft's forested ranges.
  if elevation > sea + 50 and (landform == "mountainRange" or landform == "volcano") then
    return "mountains", "alpine"
  end
  if temperature < 0.08 then
    return rainfall < 0.22 and "iceDesert" or "tundra", "polar"
  elseif temperature < 0.29 then
    return rainfall < 0.24 and "tundra" or "taiga", "boreal"
  elseif rainfall < 0.16 then
    if temperature > 0.66 then return "desert", geology == "sandstone" and "duneDesert" or "hotDesert" end
    return "shrubland", "coldSteppe"
  elseif rainfall < 0.30 then
    return temperature > 0.68 and "savanna" or "shrubland", "dryGrassland"
  elseif temperature > 0.82 and rainfall > 0.70 then
    return "rainforest", "tropicalRainforest"
  elseif temperature > 0.76 and rainfall > 0.48 then
    return "seasonalForest", "tropicalSeasonalForest"
  elseif rainfall > 0.73 then
    return "forest", "temperateRainforest"
  elseif rainfall > 0.46 then
    return "forest", "temperateForest"
  end
  return "plains", "temperateGrassland"
end

function Pipeline:sampleColumn(x, z, maxHeight)
  maxHeight = maxHeight or 127
  local key = keyFor(x, z, maxHeight)
  local cached = self.sampleCache[key]
  if cached then return cached end
  if self.sampleCacheCount > 180000 then self.sampleCache, self.sampleCacheCount = {}, {}, 0 end

  local s, sea = self.settings, self.seaLevel
  local baseHeight, fields, geology, components = self:baseElevationAt(x, z)
  local hydro = self.hydrology:sample(x, z)
  local height = baseHeight
  local heightExplanation = {}
  for name, value in pairs(components) do heightExplanation[name] = value end
  local waterLevel, waterKind

  if hydro.river > 0.0 and baseHeight > sea - 3.0 then
    local valleyTarget = math.min(baseHeight, (hydro.riverWaterLevel or baseHeight) + 2.0)
    local valleyCarve = hydro.river * (s.riverCarveStrength or 0.90)
    height = noise.lerp(height, valleyTarget, valleyCarve * 0.72)
    if hydro.riverCore > 0.18 then
      local channelDepth = noise.clamp(1.5 + math.sqrt(hydro.riverAccumulation or 0.0) * 0.32, 2.0, 6.0)
      local level = math.min(math.floor(baseHeight - 1.0), hydro.riverWaterLevel or math.floor(baseHeight - 1.0))
      height = noise.lerp(height, level - channelDepth, hydro.riverCore)
      waterLevel, waterKind = level, "river"
    end
  end

  if hydro.lake > 0.0 and hydro.lakeWaterLevel then
    local depth = 2.0 + hydro.lake * 3.0
    height = noise.lerp(height, hydro.lakeWaterLevel - depth, hydro.lake * (s.lakeCarveStrength or 0.90))
    if hydro.lake > 0.35 then waterLevel, waterKind = hydro.lakeWaterLevel, "lake" end
  end

  local landMask = fields.landMask
  local waterClass = oceanClass(fields.continentalness, landMask)
  if height < sea and landMask < 0.52 then waterLevel, waterKind = sea, "ocean" end
  if waterLevel and waterKind ~= "ocean" then
    height = math.min(height, waterLevel - 1.0)
  end
  heightExplanation.hydrology = height - baseHeight
  heightExplanation.waterLevel = waterLevel

  local equator = s.equatorTemperature or 0.96
  local pole = s.poleTemperature or 0.06
  local baseTemperature = noise.lerp(equator, pole, fields.latitude)
  local temperatureNoise = (fields.temperatureVariation - 0.5) * 2.0 * (s.temperatureNoiseStrength or 0.16)
  local continentalTemperature = (fields.continentalness - 0.5) * (s.continentalTemperatureStrength or 0.08)
  local elevation = math.max(0.0, height - sea)
  local temperature = noise.clamp(baseTemperature + temperatureNoise + continentalTemperature +
    (s.globalTemperatureOffset or 0.0) - elevation * (s.altitudeLapseRate or s.elevationCooling or 0.0045), 0.0, 1.0)

  local windAngle = s.prevailingWindAngle or 0.35
  local windDistance = s.rainShadowSampleDistance or 420.0
  local upwind = self.fields:sample(x - math.cos(windAngle) * windDistance, z - math.sin(windAngle) * windDistance)
  local rainShadow = math.max(0.0, upwind.mountainPotential - fields.mountainPotential * 0.36) *
    (s.rainShadowStrength or 0.42)
  local oceanMoisture = (1.0 - noise.edge(fields.continentalness, 0.44, 0.82)) * 0.34
  local waterMoisture = math.max(hydro.river * 0.12, hydro.lake * 0.22)
  local moisture = noise.clamp(fields.humidity * 0.52 + fields.rainfallVariation * 0.30 +
    oceanMoisture + waterMoisture + (s.globalMoistureOffset or 0.0) - rainShadow, 0.0, 1.0)
  local rainfall = noise.clamp(moisture * (0.72 + temperature * 0.28) * (s.rainfallScale or 1.0), 0.0, 1.0)

  local biome, biomeFamily
  local coastType
  if waterKind == "ocean" then
    biome, biomeFamily = "ocean", waterClass or "ocean"
  else
    biome, biomeFamily = climateBiome(temperature, rainfall, height, sea, geology.landform, geology.type, hydro)
  end

  local shorelineWidth = s.shorelineWidth or 7.0
  local nearSea = not waterKind and height <= sea + shorelineWidth and landMask > 0.14 and landMask < 0.99
  if nearSea and hydro.river < 0.38 and hydro.lake < 0.42 then
    local exposure = noise.clamp((1.0 - fields.continentalness) * 0.58 + geology.ruggedness * 0.42, 0.0, 1.0)
    local rocky = geology.ruggedness * 0.62 + geology.hardness * 0.25 + fields.mountainPotential * 0.42
    if rocky > (s.rockyShoreThreshold or 0.46) + 0.28 then
      biome, coastType = "rockyShore", "coastalCliff"
    elseif rocky > (s.rockyShoreThreshold or 0.46) then
      biome, coastType = "rockyShore", "rockyShore"
    else
      biome, coastType = "beach", exposure > 0.62 and "exposedBeach" or "shelteredBeach"
    end
  elseif waterKind == "ocean" then
    coastType = waterClass
  end

  local snowVariation = (noise.fbm(x + 4400.0, z - 7100.0, 733, 2, 0.018, self.seed) - 0.5) * 0.045
  local snowThreshold = (s.snowTemperature or 0.18) + snowVariation
  local snowLine = sea + (s.snowMinElevation or 12.0) + snowVariation * 40.0
  local hasSnow = height >= snowLine and temperature < snowThreshold and (rainfall > 0.10 or temperature < 0.055)
  local freezeWater = temperature < (s.freezeTemperature or 0.08)

  local result = {
    x = x, z = z,
    height = noise.clamp(math.floor(height), 2, math.max(2, maxHeight - 4)),
    baseHeight = baseHeight,
    biome = biome,
    biomeFamily = biomeFamily,
    landform = geology.landform,
    geology = geology.type,
    geologyHardness = geology.hardness,
    soilDepthScale = geology.soilDepth,
    volcanic = geology.volcanic,
    coastType = coastType,
    waterKind = waterKind,
    waterClass = waterClass,
    waterLevel = (s.worldWaterEnabled == false) and nil or waterLevel,
    river = hydro.river,
    riverCore = hydro.riverCore,
    riverAccumulation = hydro.riverAccumulation,
    lake = hydro.lake,
    drainage = math.max(fields.drainage * 0.35, hydro.drainage),
    land = landMask,
    mountain = fields.mountainPotential,
    erosion = geology.erosion,
    ruggedness = geology.ruggedness,
    temperature = temperature,
    moisture = moisture,
    rainfall = rainfall,
    continentalness = fields.continentalness,
    volcanism = fields.volcanism,
    hasSnow = hasSnow,
    freezeWater = freezeWater,
    fields = fields,
    components = heightExplanation
  }
  result.components.final = result.height
  self.sampleCache[key], self.sampleCacheCount = result, self.sampleCacheCount + 1
  return result
end

function Pipeline:heightAt(x, z, maxHeight)
  return self:sampleColumn(x, z, maxHeight).height
end

function Pipeline:macroAt(x, z)
  local sample = self:sampleColumn(x, z, 127)
  local f = sample.fields
  return {
    continent = f.continentalness,
    continentalness = f.continentalness,
    land = sample.land,
    coast = 1.0 - math.abs(sample.land * 2.0 - 1.0),
    regionalElevation = f.baseElevation,
    broadHills = f.broadHills,
    localHills = f.localHills,
    surfaceDetail = f.surfaceDetail,
    micro = f.localVariation,
    mountain = f.mountainPotential,
    mountainPotential = f.mountainPotential,
    ridge = f.ridge,
    river = sample.river,
    riverCore = sample.riverCore,
    lake = sample.lake,
    drainage = sample.drainage,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = sample.rainfall,
    erosion = sample.erosion,
    geologicalAge = f.geologicalAge,
    tectonicActivity = f.tectonicActivity,
    volcanism = f.volcanism,
    geology = sample.geology,
    landform = sample.landform,
    warpX = f.warpX,
    warpZ = f.warpZ
  }
end

function Pipeline:sampleChunkEnvironment(offsetX, offsetZ, width, depth, maxHeight)
  local points = {
    {offsetX + width * 0.5, offsetZ + depth * 0.5},
    {offsetX + 2, offsetZ + 2}, {offsetX + width - 3, offsetZ + 2},
    {offsetX + 2, offsetZ + depth - 3}, {offsetX + width - 3, offsetZ + depth - 3}
  }
  local totalTemperature, totalMoisture, totalRainfall = 0.0, 0.0, 0.0
  local totalElevation, totalErosion, totalRuggedness, totalContinentalness = 0.0, 0.0, 0.0, 0.0
  local river, lake, ocean, coast, volcanic = false, false, false, false, false
  local center = self:sampleColumn(points[1][1], points[1][2], maxHeight)
  for i = 1, #points do
    local sample = self:sampleColumn(points[i][1], points[i][2], maxHeight)
    totalTemperature = totalTemperature + sample.temperature
    totalMoisture = totalMoisture + sample.moisture
    totalRainfall = totalRainfall + sample.rainfall
    totalElevation = totalElevation + sample.height
    totalErosion = totalErosion + sample.erosion
    totalRuggedness = totalRuggedness + sample.ruggedness
    totalContinentalness = totalContinentalness + sample.continentalness
    river = river or sample.riverCore > 0.35
    lake = lake or sample.lake > 0.35
    ocean = ocean or sample.waterKind == "ocean"
    coast = coast or sample.coastType == "rockyShore" or sample.biome == "beach"
    volcanic = volcanic or sample.volcanic
  end
  local count = #points
  return {
    biome = center.biome,
    biomeFamily = center.biomeFamily,
    averageTemperature = totalTemperature / count,
    averageMoisture = totalMoisture / count,
    rainfall = totalRainfall / count,
    continentalness = totalContinentalness / count,
    averageElevation = totalElevation / count,
    erosion = totalErosion / count,
    ruggedness = totalRuggedness / count,
    geology = center.geology,
    landform = center.landform,
    river = river, lake = lake, ocean = ocean, coast = coast, volcanic = volcanic
  }
end

function Pipeline:debugFieldsAt(x, z, maxHeight)
  local sample = self:sampleColumn(x, z, maxHeight or 127)
  return {
    biome = sample.biome,
    biomeFamily = sample.biomeFamily,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = sample.rainfall,
    continentalness = sample.continentalness,
    elevation = sample.height,
    baseElevation = sample.baseHeight,
    mountainPotential = sample.mountain,
    erosion = sample.erosion,
    drainage = sample.drainage,
    riverNetwork = math.max(sample.river, sample.riverCore),
    geology = sample.geology,
    volcanism = sample.volcanism,
    landform = sample.landform,
    waterKind = sample.waterKind,
    coastType = sample.coastType
  }
end

function Pipeline:heightExplanationAt(x, z, maxHeight)
  return self:sampleColumn(x, z, maxHeight or 127).components
end

local GEOLOGY_COLORS = {
  granite = {0.58, 0.58, 0.62}, basalt = {0.18, 0.20, 0.22}, volcanic = {0.34, 0.16, 0.12},
  sedimentary = {0.72, 0.62, 0.45}, sandstone = {0.82, 0.57, 0.31}, limestone = {0.76, 0.76, 0.66},
  metamorphic = {0.43, 0.39, 0.48}
}

function Pipeline:debugColorAt(mode, x, z, maxHeight)
  local fields = self:debugFieldsAt(x, z, maxHeight)
  local value = fields[mode]
  if mode == "geology" then return GEOLOGY_COLORS[value] or {0.5, 0.5, 0.5} end
  if mode == "biome" then
    local hue = noise.hash2(#tostring(value), #tostring(value) * 7, 911, self.seed)
    return {0.25 + hue * 0.65, 0.30 + (1.0 - hue) * 0.55, 0.28 + math.abs(hue - 0.5)}
  end
  if type(value) ~= "number" then return {0.45, 0.45, 0.45} end
  value = noise.clamp(mode == "elevation" and value / (maxHeight or 127) or value, 0.0, 1.0)
  if mode == "temperature" then return {value, 0.25 + value * 0.35, 1.0 - value} end
  if mode == "moisture" or mode == "rainfall" or mode == "drainage" or mode == "riverNetwork" then
    return {0.12, 0.28 + value * 0.62, 0.38 + value * 0.62}
  end
  return {value, value, value}
end

return Pipeline
