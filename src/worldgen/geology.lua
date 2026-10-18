local noise = require("worldgen.noise")

local Geology = {}
Geology.__index = Geology

local TYPES = {
  {name = "sedimentary", hardness = 0.34, soilDepth = 1.35},
  {name = "limestone", hardness = 0.48, soilDepth = 1.08},
  {name = "sandstone", hardness = 0.40, soilDepth = 0.72},
  {name = "granite", hardness = 0.88, soilDepth = 0.62},
  {name = "metamorphic", hardness = 0.78, soilDepth = 0.68},
  {name = "basalt", hardness = 0.72, soilDepth = 0.54}
}

function Geology.new(settings, seed)
  return setmetatable({settings = settings or {}, seed = seed or 1}, Geology)
end

function Geology:setSeed(seed) self.seed = tonumber(seed) or 1 end
function Geology:setSettings(settings) self.settings = settings or self.settings end

local function geologyType(fields)
  if fields.volcanism > 0.73 and fields.tectonicActivity > 0.52 then
    return {name = "volcanic", hardness = 0.76, soilDepth = 0.45}
  end
  local index = math.min(#TYPES, math.floor(fields.geologyRegion * #TYPES) + 1)
  return TYPES[index]
end

-- Biome and landform are deliberately independent. This stage answers what
-- built the relief; climate decides what grows on it later.
function Geology:sample(x, z, fields)
  local s = self.settings
  local rock = geologyType(fields)
  local featureScale = noise.clamp((s.geologicalFeatureFrequency or 0.20) / 0.20, 0.0, 2.5)
  local plateauScale = noise.clamp((s.plateauFrequency or 0.18) / 0.18, 0.0, 2.5)
  local mountain = fields.mountainPotential
  local plateauGate = noise.edge(fields.plateauPotential, 0.66, 0.84) *
    noise.edge(fields.continentalness, 0.50, 0.72) * (1.0 - mountain * 0.65) * plateauScale
  local basinGate = noise.edge(fields.basinPotential, 0.70, 0.90) *
    noise.edge(fields.continentalness, 0.46, 0.68) * (1.0 - mountain) * featureScale
  local volcanicGate = noise.edge(fields.volcanism, 0.74, 0.92) *
    noise.edge(fields.tectonicActivity, 0.48, 0.78) *
    noise.clamp((s.volcanism or 0.35) / 0.35, 0.0, 2.5)

  local volcanicScale = s.volcanicFeatureScale or 0.00042
  local coneNoise = noise.fbm(x + 61000.0, z - 45000.0, 307, 3, volcanicScale, self.seed)
  local cone = volcanicGate * noise.edge(coneNoise, 0.68, 0.88)
  local calderaNoise = noise.fbm(x - 38000.0, z + 69000.0, 313, 3, volcanicScale * 0.58, self.seed)
  local caldera = volcanicGate * noise.edge(calderaNoise, 0.72, 0.90)

  local landform = "plain"
  if caldera > 0.42 then
    landform = "caldera"
  elseif cone > 0.38 then
    landform = "volcano"
  elseif mountain > 0.56 then
    landform = "mountainRange"
  elseif mountain > 0.18 then
    landform = "foothills"
  elseif plateauGate > 0.42 then
    landform = "plateau"
  elseif basinGate > 0.45 then
    landform = "basin"
  elseif fields.broadHills > 0.54 then
    landform = "rollingHills"
  end

  local ageErosion = fields.erosionPotential * (0.45 + fields.geologicalAge * 0.55)
  local hardnessProtection = 1.0 - rock.hardness * 0.52
  local effectiveErosion = noise.clamp(
    (s.erosionStrength or 0.28) * 0.55 + ageErosion * 0.45, 0.0, 1.0) * hardnessProtection

  return {
    type = rock.name,
    hardness = rock.hardness,
    soilDepth = rock.soilDepth,
    landform = landform,
    plateau = plateauGate,
    basin = basinGate,
    volcanicCone = cone,
    caldera = caldera,
    volcanic = volcanicGate > 0.35,
    erosion = effectiveErosion,
    ruggedness = noise.clamp(mountain * 0.82 + rock.hardness * 0.28 +
      math.abs(fields.surfaceDetail - 0.5) * 0.62, 0.0, 1.0)
  }
end

return Geology
