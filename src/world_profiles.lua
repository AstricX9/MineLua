-- Data-driven world definitions. A world is MineLua's dimension analogue:
-- terrain, atmosphere, lighting and player physics travel together under one
-- stable id. New worlds can be registered without extending menu conditionals.
local profiles = {
  byId = {},
  order = {}
}

local function copy3(value, fallback)
  value = value or fallback
  return {value[1], value[2], value[3]}
end

function profiles.register(definition)
  assert(type(definition) == "table", "world profile must be a table")
  local id = tostring(definition.id or ""):lower()
  assert(id:match("^[a-z][a-z0-9_]*$"), "world profile needs a stable lowercase id")
  assert(not profiles.byId[id], "world profile already registered: " .. id)
  assert(type(definition.name) == "string", "world profile needs a display name")
  assert(type(definition.generator) == "string", "world profile needs a generator id")
  local fallback = profiles.byId.earth
  if fallback then
    for _, key in ipairs({"gravityScale", "dayLengthScale", "hasClouds", "hasSurfaceWater",
        "surfaceMinTopY", "generation", "atmosphere", "sky"}) do
      if definition[key] == nil then definition[key] = fallback[key] end
    end
    if definition.description == nil then definition.description = definition.name end
  end
  definition.id = id
  profiles.byId[id] = definition
  profiles.order[#profiles.order + 1] = id
  return definition
end

function profiles.get(id)
  id = tostring(id or "earth"):lower()
  return profiles.byId[id] or profiles.byId.earth
end

function profiles.id(id)
  return profiles.get(id).id
end

function profiles.next(id)
  id = profiles.id(id)
  for index = 1, #profiles.order do
    if profiles.order[index] == id then
      return profiles.order[index % #profiles.order + 1]
    end
  end
  return profiles.order[1]
end

function profiles.list()
  local result = {}
  for index = 1, #profiles.order do
    result[index] = profiles.byId[profiles.order[index]]
  end
  return result
end

profiles.register({
  id = "earth",
  name = "Earth",
  generator = "pipeline",
  description = "Oceans, continents and a living climate",
  gravityScale = 1.0,
  dayLengthScale = 1.0,
  hasClouds = true,
  hasSurfaceWater = true,
  surfaceMinTopY = nil,
  generation = {
    caves = true,
    ores = true,
    vegetation = true
  },
  atmosphere = {
    solarIrradiance = 1.0,
    fogDensityScale = 1.0,
    fogDistanceScale = 1.0,
    dayFog = {0.72, 0.84, 1.00},
    duskFog = {0.78, 0.38, 0.24},
    nightFog = {0.025, 0.040, 0.075},
    moonFog = {0.055, 0.075, 0.120},
    daySkyLight = {0.62, 0.72, 0.86},
    nightSkyLight = {0.07, 0.09, 0.15},
    zenithDay = {0.34, 0.58, 0.92},
    zenithNight = {0.02, 0.03, 0.08},
    sunsetAmbient = {0.42, 0.30, 0.22},
    sunDay = {1.0, 0.96, 0.86},
    sunLow = {1.0, 0.55, 0.28},
    cloudDay = {0.95, 0.97, 1.0},
    cloudNight = {0.10, 0.13, 0.20},
    aureole = {1.0, 0.62, 0.32},
    moonAmount = 1.0
  },
  sky = {
    planetRadiusMeters = 6371000.0,
    atmosphereHeightMeters = 100000.0,
    rayleighScaleHeightMeters = 8000.0,
    dustScaleHeightMeters = 1200.0,
    rayleighBeta = {5.802e-6, 13.558e-6, 33.100e-6},
    dustBeta = {21.0e-6, 21.0e-6, 21.0e-6},
    dustAnisotropy = 0.758,
    sunAngularScale = 1.0,
    sunDiscScale = 1.0,
    scatterStrengthScale = 1.0,
    sunIntensityScale = 1.0,
    aureoleColor = {1.0, 0.58, 0.28},
    aureoleStrength = 0.16,
    aureoleFocus = 420.0
  }
})

profiles.register({
  id = "mars",
  name = "Mars",
  generator = "mars",
  description = "Cold basalt, iron-rich dust and impact terrain",
  -- 3.71 / 9.81. MineLua's tuned gravity is scaled by the physical ratio.
  gravityScale = 0.378,
  -- A Martian mean solar day is 24 h 39 m 35 s.
  dayLengthScale = 1.027491,
  hasClouds = false,
  hasSurfaceWater = false,
  -- Mars has no sea-level shoreline rule; every exposed column gets a surface.
  surfaceMinTopY = 1,
  generation = {
    caves = false,
    ores = false,
    vegetation = false,
    superflatLayers = {
      {block = "stone", height = 1},
      {block = "red_sandstone", height = 2},
      {block = "red_sand", height = 1}
    }
  },
  atmosphere = {
    -- Mean sunlight at 1.524 AU is about 43% of Earth's.
    solarIrradiance = 0.43,
    -- Approximate global mean; real pressure changes strongly with elevation
    -- and season. Composition fractions are retained for future survival and
    -- weather systems even though rendering currently consumes the optics.
    surfacePressurePa = 610.0,
    composition = {carbonDioxide = 0.953, nitrogen = 0.027, argon = 0.016},
    fogDensityScale = 0.62,
    fogDistanceScale = 1.18,
    dayFog = {0.76, 0.47, 0.29},
    duskFog = {0.62, 0.38, 0.31},
    nightFog = {0.020, 0.014, 0.018},
    moonFog = {0.020, 0.014, 0.018},
    daySkyLight = {0.78, 0.55, 0.39},
    nightSkyLight = {0.075, 0.052, 0.058},
    zenithDay = {0.69, 0.39, 0.23},
    zenithNight = {0.025, 0.014, 0.020},
    sunsetAmbient = {0.30, 0.34, 0.48},
    sunDay = {1.0, 0.91, 0.78},
    sunLow = {0.64, 0.73, 1.0},
    cloudDay = {0.72, 0.47, 0.33},
    cloudNight = {0.03, 0.02, 0.025},
    -- Fine airborne dust produces the characteristic blue-grey solar aureole.
    aureole = {0.38, 0.55, 1.0},
    moonAmount = 0.0
  },
  sky = {
    planetRadiusMeters = 3389500.0,
    atmosphereHeightMeters = 100000.0,
    rayleighScaleHeightMeters = 10800.0,
    dustScaleHeightMeters = 10500.0,
    -- Thin CO2 gas contributes little molecular scattering. Airborne mineral
    -- dust dominates and is spectrally warmer away from the solar aureole.
    rayleighBeta = {0.32e-6, 0.67e-6, 1.38e-6},
    dustBeta = {28.0e-6, 18.0e-6, 7.0e-6},
    dustAnisotropy = 0.86,
    sunAngularScale = 0.656,
    sunDiscScale = 0.72,
    scatterStrengthScale = 1.35,
    sunIntensityScale = 0.43,
    aureoleColor = {0.28, 0.46, 1.0},
    aureoleStrength = 0.30,
    aureoleFocus = 260.0
  }
})

-- Kept local so callers cannot accidentally use a shared fallback color as a
-- mutable scratch vector. World definitions themselves are treated as config.
function profiles.color(profileId, section, key, fallback)
  local profile = profiles.get(profileId)
  local value = profile[section] and profile[section][key]
  return copy3(value, fallback)
end

return profiles
