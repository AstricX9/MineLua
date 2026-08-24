local noise = require("worldgen.noise")

local Fields = {}
Fields.__index = Fields

function Fields.new(settings, seed)
  return setmetatable({settings = settings or {}, seed = seed or 1, cache = {}, cacheCount = 0}, Fields)
end

function Fields:setSeed(seed)
  self.seed = tonumber(seed) or 1
  self.cache, self.cacheCount = {}, 0
end

function Fields:setSettings(settings)
  self.settings = settings or self.settings
  self.cache, self.cacheCount = {}, 0
end

local function cacheKey(x, z)
  return tostring(x) .. "," .. tostring(z)
end

-- These are independent, low-frequency world fields. Later stages are free to
-- combine them, but none is inferred from a named biome or surface material.
function Fields:sample(x, z)
  local key = cacheKey(x, z)
  local cached = self.cache[key]
  if cached then return cached end
  if self.cacheCount > 180000 then self.cache, self.cacheCount = {}, 0 end

  local s = self.settings
  local seed = self.seed
  local continentScale = (s.continentScale or 0.00036) / math.max(0.1, s.continentSize or 1.0)
  local climateScale = s.biomeScale or 0.00092
  local regionScale = s.regionScale or 0.00125
  local mountainScale = (s.mountainScale or 0.00078) * (s.mountainFrequency or 1.0)
  local warpScale = s.macroWarpScale or 0.00062
  local warpAmount = s.macroWarpAmount or 360.0
  local wx, wz, warpX, warpZ = noise.warp2(x, z, warpScale, warpAmount, 53, seed)

  local continentCore = noise.fbm(wx, wz, 11, 6, continentScale, seed)
  local continentBreakup = noise.fbm(wx + 6200.0, wz - 5800.0, 13, 4, continentScale * 2.15, seed)
  local fragmentation = noise.clamp(s.continentFragmentation or 0.28, 0.0, 1.0)
  local continentalness = noise.clamp(
    continentCore * (0.90 - fragmentation * 0.35) +
    continentBreakup * (0.10 + fragmentation * 0.35), 0.0, 1.0)

  local baseElevation = noise.fbm(wx - 14000.0, wz + 9300.0, 17, 4, regionScale, seed)
  local tectonicActivity = noise.fbm(wx + 18700.0, wz - 12300.0, 91, 4, regionScale * 0.52, seed)
  local geologicalAge = noise.fbm(wx - 22400.0, wz - 16700.0, 109, 4, regionScale * 0.38, seed)
  local erosionPotential = noise.clamp(
    noise.fbm(wx + 7200.0, wz + 19300.0, 127, 4, regionScale * 0.72, seed) * 0.58 +
    geologicalAge * 0.42, 0.0, 1.0)

  local chainA = noise.ridgeChain(wx + 300.0, wz - 450.0, 97, mountainScale, 0.58, 0.34, seed)
  local chainB = noise.ridgeChain(wx - 12000.0, wz + 9400.0, 101, mountainScale * 0.72, -0.82, 0.28, seed)
  local chainC = noise.ridgeChain(wx + 19000.0, wz + 2100.0, 103, mountainScale * 1.18, 1.36, 0.42, seed)
  local chain = math.max(chainA, chainB * 0.92, chainC * 0.76)
  local mountainPotential = noise.edge(chain, 0.47, 0.84) *
    noise.edge(tectonicActivity, 0.34, 0.78) * noise.edge(continentalness, 0.40, 0.62)
  local ridge = noise.ridged(noise.fbm(wx + 1700.0, wz - 2200.0, 37, 5, mountainScale * 6.15, seed))

  local latitudeScale = s.climateLatitudeScale or 0.000075
  local latitudeWarp = (noise.fbm(wx + 31000.0, wz - 27000.0, 139, 3, latitudeScale * 3.0, seed) - 0.5) * 0.85
  local latitude = math.abs(math.sin(wz * latitudeScale + seed * 0.173 + latitudeWarp))
  local temperatureVariation = noise.fbm(wx + 1200.0, wz - 800.0, 71, 4, climateScale, seed)
  local humidity = noise.fbm(wx - 500.0, wz + 900.0, 83, 4, climateScale * 0.82, seed)
  local rainfallVariation = noise.fbm(wx + 8300.0, wz - 11900.0, 151, 4, climateScale * 1.18, seed)
  local drainage = noise.ridged(noise.fbm(wx - 3900.0, wz + 6100.0, 163, 4, regionScale * 1.25, seed))

  local volcanism = noise.clamp(
    noise.fbm(wx + 44000.0, wz + 32000.0, 181, 4, regionScale * 0.44, seed) * 0.55 +
    tectonicActivity * 0.45, 0.0, 1.0)
  local geologyRegion = noise.fbm(wx - 51000.0, wz + 47000.0, 193, 3, regionScale * 0.32, seed)
  local plateauPotential = noise.fbm(wx + 27000.0, wz + 8900.0, 211, 4, regionScale * 0.68, seed)
  local basinPotential = 1.0 - noise.fbm(wx - 7100.0, wz - 29800.0, 223, 4, regionScale * 0.82, seed)

  local broadHills = noise.fbm(wx + 4100.0, wz - 3700.0, 19, 4, regionScale * 2.35, seed)
  local localHills = noise.fbm(x - 700.0, z + 350.0, 23, 4, s.detailScale or 0.026, seed)
  local surfaceDetail = noise.fbm(x - 90.0, z + 210.0, 31, 3, 0.052, seed)
  local localVariation = noise.fbm(x + 830.0, z - 620.0, 33, 2, 0.095, seed)

  local result = {
    x = x, z = z, warpedX = wx, warpedZ = wz, warpX = warpX, warpZ = warpZ,
    continentalness = continentalness,
    baseElevation = baseElevation,
    tectonicActivity = tectonicActivity,
    mountainPotential = mountainPotential,
    mountainChain = chain,
    ridge = ridge,
    erosionPotential = erosionPotential,
    geologicalAge = geologicalAge,
    latitude = latitude,
    latitudeTemperature = 1.0 - latitude,
    temperatureVariation = temperatureVariation,
    humidity = humidity,
    rainfallVariation = rainfallVariation,
    drainage = drainage,
    volcanism = volcanism,
    geologyRegion = geologyRegion,
    plateauPotential = plateauPotential,
    basinPotential = basinPotential,
    broadHills = broadHills,
    localHills = localHills,
    surfaceDetail = surfaceDetail,
    localVariation = localVariation
  }
  self.cache[key], self.cacheCount = result, self.cacheCount + 1
  return result
end

return Fields
