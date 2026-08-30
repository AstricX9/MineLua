local ffi = require("ffi")
local blocks = require("blocks")
local settings = require("graphics_settings").terrainGeneration or {}
local texture = require("texture")
local worldProfiles = require("world_profiles")
local showcase = require("showcase")
local voxelTrees = require("voxel_trees")

local terrain = {}

terrain.SEA_LEVEL = settings.seaLevel or 63
terrain.activeSeed = settings.seed or 1
terrain.activeWorldId = "earth"
terrain.activeProfile = worldProfiles.get(terrain.activeWorldId)

local function createWorldgen(profile, seed)
  local generator = require("worldgen." .. profile.generator)
  assert(type(generator) == "table" and type(generator.new) == "function",
    "world generator must expose new(settings, seed): " .. profile.generator)
  return generator.new(settings, seed)
end

local worldgen = createWorldgen(terrain.activeProfile, terrain.activeSeed)
local macroCache = {}
local macroCacheCount = 0
local MACRO_CACHE_LIMIT = 160000

function terrain.setWorldProfile(worldId)
  local profile = worldProfiles.get(worldId)
  if profile.id == terrain.activeWorldId then return profile end
  terrain.activeWorldId = profile.id
  terrain.activeProfile = profile
  worldgen = createWorldgen(profile, terrain.activeSeed)
  macroCache = {}
  macroCacheCount = 0
  return profile
end

function terrain.worldProfile()
  return terrain.activeProfile
end

function terrain.setSeed(seed)
  local nextSeed = tonumber(seed) or settings.seed or 1
  if terrain.activeSeed ~= nextSeed then
    terrain.activeSeed = nextSeed
    worldgen:setSeed(nextSeed)
    macroCache = {}
    macroCacheCount = 0
  end
end

function terrain.refreshGenerationSettings()
  terrain.SEA_LEVEL = settings.seaLevel or 63
  terrain.RELIEF_GAIN = settings.reliefGain or 2.4
  terrain.LOCAL_RELIEF_GAIN = settings.localReliefGain or 2.0
  worldgen:refresh(settings)
  macroCache = {}
  macroCacheCount = 0
end

local SUPERFLAT_LAYERS = {
  {block = "stone", height = 1},
  {block = "dirt", height = 2},
  {block = "grass", height = 1}
}

local biomeProfiles = {
  rainforest = {
    name = "Rainforest",
    color = 0x08FA36,
    foliageColor = 0x1FF458,
    temperature = 0.98,
    rainfall = 0.95,
    minHeight = 0.1,
    maxHeight = 0.35,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 7,
    treeChance = 0.52,
    treeGenerators = {"ceiba", "jungle", "jungle", "mangrove", "fig", "big"}
  },
  swampland = {
    name = "Swampland",
    color = 0x07F9B2,
    foliageColor = 0x8BBD6D,
    temperature = 0.65,
    rainfall = 0.85,
    minHeight = -0.1,
    maxHeight = 0.15,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 10,
    treeChance = 0.10,
    treeGenerators = {"willow", "mangrove", "fig", "jungle", "oak"}
  },
  seasonalForest = {
    name = "Seasonal Forest",
    color = 0x9BE023,
    temperature = 0.97,
    rainfall = 0.55,
    minHeight = 0.1,
    maxHeight = 0.32,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 8,
    treeChance = 0.28,
    treeGenerators = {"maple", "jungle", "acacia", "oak", "big"}
  },
  savanna = {
    name = "Savanna",
    color = 0xD9E023,
    temperature = 0.82,
    rainfall = 0.16,
    minHeight = 0.05,
    maxHeight = 0.20,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 13,
    treeChance = 0.05,
    treeGenerators = {"acacia", "acacia", "baobab", "oak"}
  },
  shrubland = {
    name = "Shrubland",
    color = 0xA1AD20,
    temperature = 0.66,
    rainfall = 0.30,
    minHeight = 0.08,
    maxHeight = 0.25,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 13,
    treeChance = 0.06,
    treeGenerators = {"acacia", "birch", "oak"}
  },
  plains = {
    name = "Plains",
    color = 0xFFEFC0,
    temperature = 0.8,
    rainfall = 0.30,
    minHeight = 0.1,
    maxHeight = 0.22,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 18,
    treeChance = 0.015,
    treeGenerators = {"oak", "birch"}
  },
  forest = {
    name = "Forest",
    color = 0x056621,
    foliageColor = 0x4EED31,
    temperature = 0.7,
    rainfall = 0.8,
    minHeight = 0.1,
    maxHeight = 0.3,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 7,
    treeChance = 0.38,
    treeGenerators = {"forest", "oak", "birch", "birch", "maple", "big"}
  },
  taiga = {
    name = "Taiga",
    color = 0x2EB153,
    foliageColor = 0x7BB731,
    temperature = 0.3,
    rainfall = 0.8,
    minHeight = 0.1,
    maxHeight = 0.4,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 8,
    treeChance = 0.34,
    snow = true,
    treeGenerators = {"spruce", "pine", "pine", "cypress"}
  },
  desert = {
    name = "Desert",
    color = 0xFA9418,
    temperature = 2.0,
    rainfall = 0.0,
    minHeight = 0.1,
    maxHeight = 0.2,
    topBlock = "sand",
    fillerBlock = "sand",
    treeSpacing = 13,
    treeChance = 0.0
  },
  iceDesert = {
    name = "Ice Desert",
    color = 0xFFF799,
    foliageColor = 0xC4DCDC,
    temperature = 0.0,
    rainfall = 0.0,
    minHeight = 0.0,
    maxHeight = 0.18,
    topBlock = "sand",
    fillerBlock = "sand",
    treeSpacing = 16,
    treeChance = 0.0,
    snow = true
  },
  tundra = {
    name = "Tundra",
    color = 0x57EBF9,
    foliageColor = 0xC4DCDC,
    temperature = 0.05,
    rainfall = 0.28,
    minHeight = 0.0,
    maxHeight = 0.24,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 16,
    treeChance = 0.0,
    snow = true
  },
  mountains = {
    name = "Extreme Hills",
    temperature = 0.2,
    rainfall = 0.3,
    minHeight = 0.2,
    maxHeight = 0.9,
    topBlock = "grass",
    fillerBlock = "dirt",
    treeSpacing = 13,
    treeChance = 0.05
  },
  ocean = {
    name = "Ocean",
    temperature = 0.5,
    rainfall = 0.5,
    minHeight = -1.0,
    maxHeight = 0.4,
    topBlock = "sand",
    fillerBlock = "sand",
    treeSpacing = 16,
    treeChance = 0.0
  },
  beach = {
    name = "Beach",
    temperature = 0.8,
    rainfall = 0.4,
    minHeight = 0.0,
    maxHeight = 0.1,
    topBlock = "sand",
    fillerBlock = "sand",
    treeSpacing = 12,
    treeChance = 0.18,
    treeGenerators = {"palm", "palm", "palm"}
  },
  rockyShore = {
    name = "Rocky Shore",
    temperature = 0.5,
    rainfall = 0.45,
    minHeight = 0.0,
    maxHeight = 0.12,
    topBlock = "gravel",
    fillerBlock = "stone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  frozenShore = {
    name = "Frozen Shore",
    temperature = 0.05,
    rainfall = 0.35,
    minHeight = 0.0,
    maxHeight = 0.12,
    topBlock = "gravel",
    fillerBlock = "dirt",
    treeSpacing = 16,
    treeChance = 0.0,
    snow = true
  },
  mars_lowlands = {
    name = "Martian Northern Plains",
    color = 0xA94F29,
    temperature = 0.18,
    rainfall = 0.0,
    topBlock = "red_sand",
    fillerBlock = "red_sandstone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  mars_highlands = {
    name = "Martian Cratered Highlands",
    color = 0xB86234,
    temperature = 0.14,
    rainfall = 0.0,
    topBlock = "red_sand",
    fillerBlock = "red_sandstone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  mars_crater = {
    name = "Martian Impact Terrain",
    color = 0x75402E,
    temperature = 0.13,
    rainfall = 0.0,
    topBlock = "red_sand",
    fillerBlock = "red_sandstone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  mars_volcanic = {
    name = "Martian Volcanic Rise",
    color = 0x312C2A,
    temperature = 0.12,
    rainfall = 0.0,
    topBlock = "stone",
    fillerBlock = "stone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  mars_canyon = {
    name = "Martian Fault Canyon",
    color = 0x65301F,
    temperature = 0.16,
    rainfall = 0.0,
    topBlock = "stone",
    fillerBlock = "red_sandstone",
    treeSpacing = 16,
    treeChance = 0.0
  },
  mars_polar = {
    name = "Martian Polar Cap",
    color = 0xD5DEE3,
    temperature = 0.02,
    rainfall = 0.0,
    topBlock = "packed_ice",
    fillerBlock = "packed_ice",
    treeSpacing = 16,
    treeChance = 0.0
  }
}

ffi.cdef[[
unsigned char *stbi_load(char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
void stbi_image_free(void *retval_from_stbi_load);
]]

local stbi = ffi.load("lib/stb_image.dll")
local grassColormap = false

-- Compensates for fbm() clustering near 0.5 (see terrain.heightAt). Tune this to
-- make the world hillier or flatter; 1.0 restores the original flat behaviour.
-- Columns generated between yields in fillChunk's density loop. Smaller means a
-- tighter frame budget cap and slightly more coroutine overhead.
local DENSITY_YIELD_COLUMNS = 4

terrain.RELIEF_GAIN = settings.reliefGain or 2.4
-- Extra gain on the short-wavelength terms, which are the only ones that vary
-- inside a single render distance. Raise for hillier ground, 1.0 to disable.
terrain.LOCAL_RELIEF_GAIN = settings.localReliefGain or 2.0

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function smoothstep(t)
  t = clamp(t, 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)
end

local function hash2(x, z, seed)
  seed = seed + (terrain.activeSeed or settings.seed or 1) * 101
  local n = x * 374761393 + z * 668265263 + seed * 1442695041
  n = math.sin(n) * 43758.5453123
  return n - math.floor(n)
end

local function valueNoise(x, z, seed)
  local x0 = math.floor(x)
  local z0 = math.floor(z)
  local x1 = x0 + 1
  local z1 = z0 + 1

  local sx = smoothstep(x - x0)
  local sz = smoothstep(z - z0)

  local n00 = hash2(x0, z0, seed)
  local n10 = hash2(x1, z0, seed)
  local n01 = hash2(x0, z1, seed)
  local n11 = hash2(x1, z1, seed)

  local ix0 = lerp(n00, n10, sx)
  local ix1 = lerp(n01, n11, sx)
  return lerp(ix0, ix1, sz)
end

local function hash3(x, y, z, seed)
  seed = seed + (terrain.activeSeed or settings.seed or 1) * 101
  local n = x * 374761393 + y * 1442695041 + z * 668265263 + seed * 1274126177
  n = math.sin(n) * 43758.5453123
  return n - math.floor(n)
end

local function valueNoise3(x, y, z, seed)
  local x0 = math.floor(x)
  local y0 = math.floor(y)
  local z0 = math.floor(z)
  local sx = smoothstep(x - x0)
  local sy = smoothstep(y - y0)
  local sz = smoothstep(z - z0)

  local function sample(dx, dy, dz)
    return hash3(x0 + dx, y0 + dy, z0 + dz, seed)
  end

  local x00 = lerp(sample(0, 0, 0), sample(1, 0, 0), sx)
  local x10 = lerp(sample(0, 1, 0), sample(1, 1, 0), sx)
  local x01 = lerp(sample(0, 0, 1), sample(1, 0, 1), sx)
  local x11 = lerp(sample(0, 1, 1), sample(1, 1, 1), sx)
  local y0v = lerp(x00, x10, sy)
  local y1v = lerp(x01, x11, sy)
  return lerp(y0v, y1v, sz)
end

local function fbm(x, z, seed, octaves, frequency)
  local total = 0.0
  local amplitude = 1.0
  local normalization = 0.0
  frequency = frequency or 0.05

  for octave = 1, octaves or 4 do
    total = total + valueNoise(x * frequency, z * frequency, seed + octave * 19) * amplitude
    normalization = normalization + amplitude
    amplitude = amplitude * 0.5
    frequency = frequency * 2.0
  end

  return total / normalization
end

local function fbm3(x, y, z, seed, octaves, frequency)
  local total = 0.0
  local amplitude = 1.0
  local normalization = 0.0
  frequency = frequency or 0.05

  for octave = 1, octaves or 3 do
    total = total + valueNoise3(x * frequency, y * frequency, z * frequency, seed + octave * 23) * amplitude
    normalization = normalization + amplitude
    amplitude = amplitude * 0.5
    frequency = frequency * 2.0
  end

  return total / normalization
end

local function edge(value, edge0, edge1)
  if edge0 == edge1 then
    return value >= edge1 and 1.0 or 0.0
  end
  return smoothstep((value - edge0) / (edge1 - edge0))
end

local function macroSignals(x, z)
  return worldgen:macroAt(x, z)
end

function terrain.macroAt(x, z)
  local key = tostring(x) .. "," .. tostring(z)
  local cached = macroCache[key]
  if cached then
    return cached
  end

  if macroCacheCount >= MACRO_CACHE_LIMIT then
    macroCache = {}
    macroCacheCount = 0
  end

  local signals = macroSignals(x, z)
  macroCache[key] = signals
  macroCacheCount = macroCacheCount + 1
  return signals
end

local function blockId(name, fallback)
  return blocks[name] or blocks[fallback] or blocks.stone or 1
end

local function fillSuperflatChunk(chunk, width, depth, maxHeight, layers, step)
  layers = layers or SUPERFLAT_LAYERS

  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local y = 0
      for i = 1, #layers do
        local layer = layers[i]
        local id = blockId(layer.block, "stone")
        local height = math.max(0, math.floor(layer.height or 0))
        for _ = 1, height do
          if y <= maxHeight then
            chunk:setBlock(x, y, z, id)
          end
          y = y + 1
        end
      end
    end
    if step then step() end
  end
end

local function loadGrassColormap()
  if grassColormap ~= false then
    return grassColormap
  end

  local path = texture.resolvePath("./textures/colormap/grass.png")
  local w, h, channels = ffi.new("int[1]"), ffi.new("int[1]"), ffi.new("int[1]")
  local data = stbi.stbi_load(path, w, h, channels, 4)
  if data == nil then
    grassColormap = nil
    return nil
  end

  grassColormap = {
    width = w[0],
    height = h[0],
    data = data
  }

  return grassColormap
end

local function sampleGrassColor(temperature, rainfall)
  temperature = clamp(temperature, 0.0, 1.0)
  rainfall = clamp(rainfall, 0.0, 1.0) * temperature

  local colormap = loadGrassColormap()
  if colormap then
    local x = clamp(math.floor((1.0 - temperature) * (colormap.width - 1)), 0, colormap.width - 1)
    local y = clamp(math.floor((1.0 - rainfall) * (colormap.height - 1)), 0, colormap.height - 1)
    local index = (y * colormap.width + x) * 4
    return {
      colormap.data[index] / 255.0,
      colormap.data[index + 1] / 255.0,
      colormap.data[index + 2] / 255.0
    }
  end

  local dry = {0.72, 0.66, 0.32}
  local lush = {0.35, 0.62, 0.20}
  local cold = {0.38, 0.56, 0.28}
  local warmWet = rainfall
  local coldMix = 1.0 - temperature
  return {
    lerp(lerp(dry[1], lush[1], warmWet), cold[1], coldMix * 0.45),
    lerp(lerp(dry[2], lush[2], warmWet), cold[2], coldMix * 0.45),
    lerp(lerp(dry[3], lush[3], warmWet), cold[3], coldMix * 0.45)
  }
end

function terrain.biomeAt(x, z)
  return worldgen:sampleColumn(x, z, 127).biome
end

function terrain.biomeProfileAt(x, z)
  local biome = terrain.biomeAt(x, z)
  return biomeProfiles[biome] or biomeProfiles.plains, biome
end

-- Climate is continuous even when the named biome changes. Biome profiles
-- influence the regional signal, elevation cools it, and the resulting values
-- drive snow, frozen water, and shoreline material using the same rules in the
-- RTS preview and full chunk generator.
function terrain.environmentAt(x, z, height, sourceBiome)
  local sample = worldgen:sampleColumn(x, z, 127)
  local biome = sample.biome
  return {
    biome = biome,
    profile = biomeProfiles[biome] or biomeProfiles.plains,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = sample.rainfall,
    hasSnow = sample.hasSnow,
    freezeWater = sample.freezeWater,
    coast = sample.coastType,
    geology = sample.geology,
    landform = sample.landform,
    hydrology = sample.waterKind
  }
end

function terrain.heightAt(x, z, maxHeight, fastPreview)
  return worldgen:heightAt(x, z, maxHeight or 127)
end

function terrain.columnAt(x, z, maxHeight)
  maxHeight = maxHeight or 127
  local sample = worldgen:sampleColumn(x, z, maxHeight)
  local height = sample.height
  local biome = sample.biome
  local profile = biomeProfiles[biome] or biomeProfiles.plains
  local stoneNoise = fbm(x, z, 41, 2, 1.0 / 16.0)
  local fillerDepth = math.floor((stoneNoise * 2.0 + 2.5 + hash2(x, z, 311) * 0.45) *
    (sample.soilDepthScale or 1.0))
  local topBlock = sample.topBlock or profile.topBlock
  local fillerBlock = sample.fillerBlock or profile.fillerBlock

  if biome == "beach" then
    topBlock = "sand"
    fillerBlock = "sand"
  elseif biome == "rockyShore" or biome == "frozenShore" then
    topBlock = blocks.gravel and "gravel" or "stone"
    fillerBlock = biome == "rockyShore" and "stone" or "dirt"
  elseif sample.riverCore > 0.22 and sample.waterLevel and height <= sample.waterLevel then
    local riverBedNoise = hash2(x, z, 617)
    if blocks.clay and riverBedNoise < 0.18 then
      topBlock = "clay"
      fillerBlock = "clay"
    elseif blocks.gravel and riverBedNoise < 0.68 then
      topBlock = "gravel"
      fillerBlock = "gravel"
    else
      topBlock = "sand"
      fillerBlock = "sand"
    end
  elseif sample.lake > 0.22 and sample.waterLevel and height <= sample.waterLevel then
    topBlock = blocks.clay and "clay" or "sand"
    fillerBlock = topBlock
  elseif biome == "ocean" and height > terrain.SEA_LEVEL - 7 then
    topBlock = "sand"
    fillerBlock = "sand"
  elseif biome == "ocean" and blocks.gravel then
    topBlock = "gravel"
    fillerBlock = "gravel"
  end

  return {
    height = height,
    biome = biome,
    profile = profile,
    biomeFamily = sample.biomeFamily,
    landform = sample.landform,
    geology = sample.geology,
    coastType = sample.coastType,
    waterKind = sample.waterKind,
    waterLevel = sample.waterLevel,
    river = sample.river,
    riverCore = sample.riverCore,
    riverAccumulation = sample.riverAccumulation,
    lake = sample.lake,
    drainage = sample.drainage,
    land = sample.land,
    mountain = sample.mountain,
    erosion = sample.erosion,
    ruggedness = sample.ruggedness,
    continentalness = sample.continentalness,
    volcanism = sample.volcanism,
    temperature = sample.temperature,
    moisture = sample.moisture,
    rainfall = sample.rainfall,
    hasSnow = sample.hasSnow,
    freezeWater = sample.freezeWater,
    topBlock = blockId(topBlock, "grass"),
    fillerBlock = blockId(fillerBlock, "dirt"),
    fillerDepth = math.max(1, fillerDepth)
  }
end

local unsafeSpawnBiomes = {
  ocean = true,
  beach = true,
  rockyShore = true,
  frozenShore = true,
  swampland = true,
  iceDesert = true,
  mars_polar = true
}

local function spawnCandidateAt(x, z, maxHeight)
  local center = terrain.columnAt(x, z, maxHeight)
  if center.waterLevel or center.height < terrain.SEA_LEVEL + 4 or center.land < 0.52 or center.hasSnow or
      center.river > 0.20 or center.lake > 0.20 or unsafeSpawnBiomes[center.biome] then
    return nil
  end

  local minimum, maximum = center.height, center.height
  for _, offset in ipairs({{-4, 0}, {4, 0}, {0, -4}, {0, 4}, {-3, -3}, {3, 3}}) do
    local nearby = terrain.columnAt(x + offset[1], z + offset[2], maxHeight)
    if nearby.waterLevel or nearby.height < terrain.SEA_LEVEL + 3 or nearby.hasSnow or
        nearby.river > 0.28 or nearby.lake > 0.28 or
        unsafeSpawnBiomes[nearby.biome] then
      return nil
    end
    minimum = math.min(minimum, nearby.height)
    maximum = math.max(maximum, nearby.height)
  end

  -- Leave enough reasonably level ground for the player's collision footprint
  -- and first few steps instead of balancing them on a steep river bank.
  if maximum - minimum > 4 then return nil end
  return center
end

function terrain.findSafeSpawn(preferredX, preferredZ, maxHeight)
  preferredX = math.floor(tonumber(preferredX) or 16)
  preferredZ = math.floor(tonumber(preferredZ) or 16)
  maxHeight = maxHeight or 127

  local goldenAngle = math.pi * (3.0 - math.sqrt(5.0))
  local fallback, fallbackRisk
  local dryFallback, dryFallbackRisk
  for index = 0, 8192 do
    local radius = index == 0 and 0.0 or 18.5 * math.sqrt(index)
    local angle = index * goldenAngle
    local x = math.floor(preferredX + math.cos(angle) * radius + 0.5)
    local z = math.floor(preferredZ + math.sin(angle) * radius + 0.5)
    local candidate = spawnCandidateAt(x, z, maxHeight)
    if candidate then return x + 0.5, z + 0.5, candidate end

    -- Keep the safest dry point as a last resort for extremely ocean-heavy
    -- seeds. This fallback still refuses actual ocean and active waterways.
    local column = terrain.columnAt(x, z, maxHeight)
    if not column.waterLevel and column.height >= terrain.SEA_LEVEL + 3 and not column.hasSnow and
        column.river < 0.34 and column.lake < 0.34 and not unsafeSpawnBiomes[column.biome] then
      local risk = radius * 0.002 + column.river * 8.0 + column.lake * 8.0
      if not fallbackRisk or risk < fallbackRisk then
        fallback, fallbackRisk = {x + 0.5, z + 0.5, column}, risk
      end
    end

    -- Beaches and rough ground are less comfortable than the preferred spawn,
    -- but still always beat an underwater fallback. Keep the nearest genuinely
    -- dry column as the final guarantee.
    if not column.waterLevel and column.biome ~= "ocean" then
      local dryRisk = radius * 0.002 + math.max(terrain.SEA_LEVEL + 1 - column.height, 0) * 4.0
      if not dryFallbackRisk or dryRisk < dryFallbackRisk then
        dryFallback, dryFallbackRisk = {x + 0.5, z + 0.5, column}, dryRisk
      end
    end
  end

  if fallback then return fallback[1], fallback[2], fallback[3] end
  if dryFallback then return dryFallback[1], dryFallback[2], dryFallback[3] end
  error("Unable to find a dry spawn column for this seed")
end

function terrain.grassColorAt(x, z)
  local profile = terrain.biomeProfileAt(x, z)
  local macro = terrain.macroAt(x, z)
  local temperature = profile.temperature
  local rainfall = profile.rainfall
  local localTemp = macro.temperature
  local localRain = macro.rainfall
  local strength = settings.grassTintStrength or 1.0

  temperature = clamp(lerp(temperature, localTemp, 0.32), 0.0, 1.0)
  rainfall = clamp(lerp(rainfall, localRain, 0.32), 0.0, 1.0)

  local color = sampleGrassColor(temperature, rainfall)
  local average = (color[1] + color[2] + color[3]) / 3.0
  color = {
    clamp(average + (color[1] - average) * 1.28 - 0.005, 0.0, 1.0),
    clamp(average + (color[2] - average) * 1.36 + 0.050, 0.0, 1.0),
    clamp(average + (color[3] - average) * 1.24 - 0.020, 0.0, 1.0)
  }

  if strength ~= 1.0 then
    color = {
      lerp(1.0, color[1], strength),
      lerp(1.0, color[2], strength),
      lerp(1.0, color[3], strength)
    }
  end

  return color
end

-- Amplitudes of the noise terms in terrainDensityAt. DENSITY_NOISE_BOUND is
-- derived from them, so if you change an amplitude the bound follows and
-- fillChunk's fast path stays correct. fbm3 returns [0, 1).
local DENSITY_LOW_AMPLITUDE = 8.0
local DENSITY_DETAIL_AMPLITUDE = 3.0
local DENSITY_MOUNTAIN_AMPLITUDE = 12.0
local DENSITY_MOUNTAIN_BIAS = 0.47

-- Largest distance the noise can move the density away from (column.height - y),
-- in either direction. deepBias is excluded on purpose: it is only ever positive
-- and only below y = 8, so it can push a cell towards solid but never towards air.
terrain.DENSITY_NOISE_BOUND = math.ceil(
  DENSITY_LOW_AMPLITUDE * 0.5 +
  DENSITY_DETAIL_AMPLITUDE * 0.5 +
  DENSITY_MOUNTAIN_AMPLITUDE * math.max(DENSITY_MOUNTAIN_BIAS, 1.0 - DENSITY_MOUNTAIN_BIAS)
)

local function terrainDensityAt(worldX, y, worldZ, maxHeight, column)
  local base = column.height - y
  local deepBias = y < 8 and (8 - y) * 1.6 or 0.0
  local upperFade = smoothstep((y - terrain.SEA_LEVEL - 18) / math.max(1, maxHeight - terrain.SEA_LEVEL - 24))
  local lowNoise = (fbm3(worldX, y, worldZ, 151, 3, 0.018) - 0.5) * DENSITY_LOW_AMPLITUDE
  local detailNoise = (fbm3(worldX + 900.0, y * 1.7, worldZ - 450.0, 163, 2, 0.045) - 0.5) * DENSITY_DETAIL_AMPLITUDE
  local mountainBoost = (column.mountain or 0.0) > 0.35 and (fbm3(worldX, y, worldZ, 167, 3, 0.026) - DENSITY_MOUNTAIN_BIAS) * DENSITY_MOUNTAIN_AMPLITUDE * upperFade or 0.0
  return base + deepBias + lowNoise + detailNoise + mountainBoost
end

local function isAirOrFluid(id)
  return id == blocks.air or id == blocks.water or id == blocks.lava
end

local function surfaceBlocksForColumn(column, y)
  local topBlock = column.topBlock
  local fillerBlock = column.fillerBlock
  local underFillerBlock = blocks.stone

  if column.biome == "desert" then
    topBlock = blocks.sand or topBlock
    fillerBlock = blocks.sand or fillerBlock
    underFillerBlock = blocks.sandstone or blocks.stone
  elseif column.biome == "beach" then
    topBlock = blocks.sand or topBlock
    fillerBlock = blocks.sand or fillerBlock
    underFillerBlock = blocks.sandstone or blocks.stone
  elseif column.biome == "rockyShore" then
    topBlock = blocks.gravel or blocks.stone
    fillerBlock = blocks.stone
    underFillerBlock = blocks.stone
  elseif column.biome == "frozenShore" then
    topBlock = blocks.gravel or blocks.dirt or blocks.stone
    fillerBlock = blocks.dirt or blocks.stone
    underFillerBlock = blocks.stone
  elseif (column.riverCore or 0.0) > 0.22 and column.waterLevel and y <= column.waterLevel then
    -- columnAt already selected a deterministic gravel/clay/sand riverbed.
    -- Preserve it here instead of flattening every channel back to sand.
    underFillerBlock = blocks.stone
  elseif (column.lake or 0.0) > 0.22 and column.waterLevel and y <= column.waterLevel then
    topBlock = blocks.clay or blocks.sand or topBlock
    fillerBlock = topBlock
  elseif column.biome == "iceDesert" then
    topBlock = blocks.snow or topBlock
    fillerBlock = blocks.dirt or fillerBlock
  elseif column.biome == "ocean" then
    if y > terrain.SEA_LEVEL - 7 then
      topBlock = blocks.sand or topBlock
      fillerBlock = blocks.sand or fillerBlock
      underFillerBlock = blocks.sandstone or blocks.stone
    elseif blocks.clay and hash2(column.worldX, column.worldZ, 619) < 0.10 then
      topBlock = blocks.clay
      fillerBlock = blocks.clay
    elseif blocks.gravel then
      topBlock = blocks.gravel
      fillerBlock = blocks.gravel
    end
  end

  return topBlock, fillerBlock, underFillerBlock
end

local function applySurfaceReplacement(chunk, offsetX, offsetZ, width, depth, maxHeight, step)
  local surfaceFloor = terrain.activeProfile.surfaceMinTopY or (terrain.SEA_LEVEL - 4)
  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local worldX = x + offsetX
      local worldZ = z + offsetZ
      local column = terrain.columnAt(worldX, worldZ, maxHeight)
      column.worldX = worldX
      column.worldZ = worldZ
      local depthLeft = -1
      local topBlock, fillerBlock, underFillerBlock = surfaceBlocksForColumn(column, column.height)

      for y = maxHeight, 1, -1 do
        local id = chunk:getBlock(x, y, z)
        if isAirOrFluid(id) then
          depthLeft = -1
        elseif id == blocks.stone then
          if depthLeft == -1 then
            depthLeft = column.fillerDepth
            if y >= surfaceFloor then
              chunk:setBlock(x, y, z, topBlock)
              if column.hasSnow and y > terrain.SEA_LEVEL and blocks.snow then
                chunk:setBlock(x, y, z, blocks.snow)
              end
            else
              chunk:setBlock(x, y, z, fillerBlock)
            end
          elseif depthLeft > 0 then
            chunk:setBlock(x, y, z, fillerBlock)
            depthLeft = depthLeft - 1
          elseif underFillerBlock ~= blocks.stone and depthLeft == 0 then
            chunk:setBlock(x, y, z, underFillerBlock)
            depthLeft = depthLeft - 1
          end
        end
      end
    end
    if step then step() end
  end
end

local function isTreeCenter(x, z, biome)
  local profile = biomeProfiles[biome]
  if not profile or profile.treeChance <= 0.0 then
    return false
  end

  local macro = terrain.macroAt(x, z)
  local minimumLand = biome == "beach" and 0.28 or 0.42
  if macro.river > 0.32 or macro.lake > 0.28 or macro.land < minimumLand then
    return false
  end

  local spacing = profile.treeSpacing
  local cellX = math.floor(x / spacing)
  local cellZ = math.floor(z / spacing)
  local jitterX = math.floor(hash2(cellX, cellZ, 211) * spacing)
  local jitterZ = math.floor(hash2(cellX, cellZ, 223) * spacing)
  local centerX = cellX * spacing + jitterX
  local centerZ = cellZ * spacing + jitterZ

  if centerX ~= x or centerZ ~= z then
    return false
  end

  local forestMass = fbm(x + 16000.0, z - 24000.0, 901, 3, settings.forestScale or 0.00165)
  local clearing = fbm(x - 2600.0, z + 15400.0, 907, 2, 0.0055)
  local densityScale = 1.0

  if biome == "forest" or biome == "seasonalForest" or biome == "rainforest" or biome == "taiga" then
    densityScale = lerp(0.25, 1.65, edge(forestMass, 0.35, 0.72))
    densityScale = densityScale * lerp(1.0, 0.25, edge(clearing, 0.76, 0.90))
  elseif biome == "plains" or biome == "savanna" or biome == "shrubland" then
    densityScale = lerp(0.30, 1.25, edge(forestMass, 0.62, 0.88))
  end

  return hash2(cellX, cellZ, 239) < profile.treeChance * (settings.treeDensity or 1.0) * densityScale
end

-- Trees are selected from one jittered point per biome-sized grid cell. Walking
-- every block in the overlap margin and running the full worldgen pipeline just
-- to reject almost all of them made vegetation more expensive than the terrain
-- itself, especially with the wide overlap needed by authored tree crowns.
-- Enumerate the possible jittered points for every spacing instead. The final
-- biome check in isTreeCenter keeps this exactly equivalent to the old scan.
local function treeCandidates(minX, minZ, maxX, maxZ)
  local spacings = {}
  for _, profile in pairs(biomeProfiles) do
    local spacing = profile.treeSpacing
    if profile.treeChance and profile.treeChance > 0.0 and spacing then
      spacings[spacing] = true
    end
  end

  local candidates, seen = {}, {}
  for spacing in pairs(spacings) do
    local minCellX, maxCellX = math.floor(minX / spacing), math.floor(maxX / spacing)
    local minCellZ, maxCellZ = math.floor(minZ / spacing), math.floor(maxZ / spacing)
    for cellX = minCellX, maxCellX do
      for cellZ = minCellZ, maxCellZ do
        local x = cellX * spacing + math.floor(hash2(cellX, cellZ, 211) * spacing)
        local z = cellZ * spacing + math.floor(hash2(cellX, cellZ, 223) * spacing)
        if x >= minX and x <= maxX and z >= minZ and z <= maxZ then
          local key = x .. "," .. z
          if not seen[key] then
            seen[key] = true
            candidates[#candidates + 1] = {x = x, z = z}
          end
        end
      end
    end
  end

  -- Preserve the old x-major/z-minor placement order. This matters when two
  -- neighbouring canopies overlap inside the same chunk.
  table.sort(candidates, function(a, b)
    return a.x == b.x and a.z < b.z or a.x < b.x
  end)
  return candidates
end

local function setLocalBlock(chunk, lx, y, lz, id)
  if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y < 0 or y > 255 then
    return
  end
  chunk:setBlock(lx, y, lz, id)
end

local function getLocalBlock(chunk, lx, y, lz)
  if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y < 0 or y > 255 then
    return nil
  end
  return chunk:getBlock(lx, y, lz)
end

local function randomInt(x, z, salt, bound)
  return math.floor(hash2(x, z, salt) * bound)
end

local function javaDiv(a, b)
  local value = a / b
  return value < 0 and math.ceil(value) or math.floor(value)
end

local function isOpaqueLocal(chunk, lx, y, lz)
  if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y < 0 or y > 255 then
    return false
  end

  local id = chunk:getBlock(lx, y, lz)
  local def = id and blocks.list[id]
  return def and def.properties and def.properties.solid and not def.properties.leaves
end

local function isLeafBlock(id)
  local def = id and blocks.list[id]
  return def and def.properties and def.properties.leaves
end

local function setIfNotOpaque(chunk, lx, y, lz, id)
  if not isOpaqueLocal(chunk, lx, y, lz) then
    setLocalBlock(chunk, lx, y, lz, id)
  end
end

local function chooseTreeGenerator(profile, x, z)
  local generators = profile.treeGenerators or {"oak"}
  local index = randomInt(x, z, 251, #generators) + 1
  return generators[index] or "oak"
end

function terrain.treeGeneratorForBiome(biome, x, z)
  return chooseTreeGenerator(biomeProfiles[biome] or biomeProfiles.plains, x, z)
end

local TREE_MATERIALS = {
  oak = {wood = "oak_log", leaves = "oak_leaves"},
  forest = {wood = "oak_log", leaves = "oak_leaves"},
  big = {wood = "oak_log", leaves = "oak_leaves"},
  maple = {wood = "oak_log", leaves = "oak_leaves"},
  willow = {wood = "oak_log", leaves = "oak_leaves"},
  spruce = {wood = "spruce_log", leaves = "spruce_leaves"},
  pine = {wood = "spruce_log", leaves = "spruce_leaves"},
  cypress = {wood = "spruce_log", leaves = "spruce_leaves"},
  taiga1 = {wood = "spruce_log", leaves = "spruce_leaves"},
  taiga2 = {wood = "spruce_log", leaves = "spruce_leaves"},
  birch = {wood = "birch_log", leaves = "birch_leaves"},
  acacia = {wood = "acacia_log", leaves = "acacia_leaves"},
  baobab = {wood = "acacia_log", leaves = "acacia_leaves"},
  ceiba = {wood = "ceiba_log", leaves = "ceiba_leaves"},
  jungle = {wood = "jungle_log", leaves = "jungle_leaves"},
  fig = {wood = "jungle_log", leaves = "jungle_leaves"},
  mangrove = {wood = "jungle_log", leaves = "jungle_leaves"}
}

local function addVoxelTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, species)
  local names = TREE_MATERIALS[species] or TREE_MATERIALS.oak
  local fallbackWood = blocks.oak_log or blocks.oak_planks or blocks.dirt
  local livingWood = blocks[names.wood .. "_alive"] or blocks[names.wood] or fallbackWood
  local material = {
    wood = livingWood,
    -- Living trunks intentionally keep one connected block family so angled
    -- branches are captured by whole-tree felling along with the main stem.
    woodX = blocks[names.wood .. "_alive_x"] or livingWood,
    woodZ = blocks[names.wood .. "_alive_z"] or livingWood,
    leaves = blocks[names.leaves] or blocks.oak_leaves or blocks.grass
  }
  material.leaves2 = material.leaves

  local seed = randomInt(treeX, treeZ, 397, 2147483000) + 1
  local cloud = voxelTrees.generate(species, seed)
  local localX, localZ = treeX - offsetX, treeZ - offsetZ
  setLocalBlock(chunk, localX, groundY, localZ, blocks.dirt or material.wood)
  voxelTrees.emit(cloud, localX, groundY + 1, localZ, material,
    function(x, y, z, id) setIfNotOpaque(chunk, x, y, z, id) end)
end

local function addClassicOakTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, generator)
  local trunkHeight = generator == "forest" and (randomInt(treeX, treeZ, 257, 3) + 5) or (randomInt(treeX, treeZ, 257, 3) + 4)

  local logId = generator == "birch" and
    (blocks.birch_log_alive or blocks.birch_log) or
    (blocks.oak_log_alive or blocks.oak_log)
  local leavesId = generator == "birch" and blocks.birch_leaves or blocks.oak_leaves
  logId = logId or blocks.oak_planks or blocks.dirt
  leavesId = leavesId or blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ

  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)

  for y = groundY + trunkHeight - 3, groundY + trunkHeight do
    local dy = y - (groundY + trunkHeight)
    local radius = 1 - javaDiv(dy, 2)

    for lx = localTreeX - radius, localTreeX + radius do
      local dx = lx - localTreeX
      for lz = localTreeZ - radius, localTreeZ + radius do
        local dz = lz - localTreeZ
        local isCorner = math.abs(dx) == radius and math.abs(dz) == radius
        local keepCorner = randomInt(treeX + dx, treeZ + dz, y + 271, 2) ~= 0 and dy ~= 0
        if (not isCorner or keepCorner) then
          setIfNotOpaque(chunk, lx, y, lz, leavesId)
        end
      end
    end
  end

  for y = 0, trunkHeight - 1 do
    local localY = groundY + 1 + y
    local existing = getLocalBlock(chunk, localTreeX, localY, localTreeZ)
    if existing == blocks.air or isLeafBlock(existing) then
      setLocalBlock(chunk, localTreeX, localY, localTreeZ, logId)
    end
  end
end


local function addTropicalCanopy(chunk, centerX, centerY, centerZ, leavesId, radius, layers)
  layers = layers or 3
  for dy = 0, layers - 1 do
    local taper = math.abs(dy - (layers - 1) * 0.5) / math.max(1, layers * 0.5)
    local layerRadius = math.max(1, radius - math.floor(taper * 1.5))
    local radiusSq = (layerRadius + 0.35) * (layerRadius + 0.35)
    for dx = -layerRadius, layerRadius do
      for dz = -layerRadius, layerRadius do
        if dx * dx + dz * dz <= radiusSq then
          setIfNotOpaque(chunk, centerX + dx, centerY + dy, centerZ + dz, leavesId)
        end
      end
    end
  end
end

local TREE_DIRECTIONS = {
  {1,0}, {1,1}, {0,1}, {-1,1}, {-1,0}, {-1,-1}, {0,-1}, {1,-1}
}

local function addCeibaTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local logId = blocks.ceiba_log_alive or blocks.ceiba_log or
    blocks.jungle_log_alive or blocks.jungle_log or blocks.oak_log_alive or blocks.oak_log
  local leavesId = blocks.ceiba_leaves or blocks.jungle_leaves or blocks.oak_leaves
  local localX, localZ = treeX - offsetX, treeZ - offsetZ
  local height = 17 + randomInt(treeX, treeZ, 331, 7)
  local crownY = groundY + height - 3
  setLocalBlock(chunk, localX, groundY, localZ, blocks.dirt or logId)

  -- Ceibas are defined by a towering, broad trunk and plank-like buttress
  -- roots. A 2x2 column keeps that mass visible even beneath the canopy.
  for y = groundY + 1, groundY + height - 1 do
    for dx = 0, 1 do for dz = 0, 1 do
      setIfNotOpaque(chunk, localX + dx, y, localZ + dz, logId)
    end end
  end
  for direction = 1, 8, 2 do
    local dx, dz = TREE_DIRECTIONS[direction][1], TREE_DIRECTIONS[direction][2]
    for reach = 1, 4 do
      local buttressHeight = math.max(1, 5 - reach)
      for rise = 0, buttressHeight - 1 do
        setIfNotOpaque(chunk, localX + dx * reach, groundY + 1 + rise,
          localZ + dz * reach, logId)
      end
    end
  end

  addTropicalCanopy(chunk, localX, crownY, localZ, leavesId, 5, 4)
  for direction = 1, #TREE_DIRECTIONS do
    local dx, dz = TREE_DIRECTIONS[direction][1], TREE_DIRECTIONS[direction][2]
    local reach = 3 + randomInt(treeX + direction, treeZ - direction, 337, 2)
    local branchY = crownY + (direction % 2)
    for step = 1, reach do
      local by = branchY + math.floor(step / 3)
      if step > 1 and by > branchY + math.floor((step - 1) / 3) then
        setIfNotOpaque(chunk, localX + dx * (step - 1), by,
          localZ + dz * (step - 1), logId)
      end
      if dx ~= 0 and dz ~= 0 then
        setIfNotOpaque(chunk, localX + dx * step, by,
          localZ + dz * (step - 1), logId)
      end
      setIfNotOpaque(chunk, localX + dx * step, by, localZ + dz * step, logId)
    end
    addTropicalCanopy(chunk, localX + dx * reach, branchY, localZ + dz * reach,
      leavesId, 2, 3)
  end
end

local function addJungleTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, fig)
  local logId = blocks.jungle_log_alive or blocks.jungle_log or
    blocks.ceiba_log_alive or blocks.ceiba_log or blocks.oak_log_alive or blocks.oak_log
  local leavesId = blocks.jungle_leaves or blocks.ceiba_leaves or blocks.oak_leaves
  local localX, localZ = treeX - offsetX, treeZ - offsetZ
  local height = (fig and 8 or 11) + randomInt(treeX, treeZ, fig and 347 or 349, fig and 5 or 6)
  local crownY = groundY + height - 3
  setLocalBlock(chunk, localX, groundY, localZ, blocks.dirt or logId)
  for y = groundY + 1, groundY + height - 1 do
    setIfNotOpaque(chunk, localX, y, localZ, logId)
  end
  if fig then
    -- Strangler-fig-like secondary stems make a low, irregular tropical form.
    for direction = 1, 4 do
      local d = TREE_DIRECTIONS[direction * 2 - 1]
      for y = groundY + 1, crownY - 1 do
        if y < groundY + 3 or (y + direction) % 3 == 0 then
          setIfNotOpaque(chunk, localX + d[1], y, localZ + d[2], logId)
        end
      end
    end
  end
  addTropicalCanopy(chunk, localX, crownY, localZ, leavesId, fig and 4 or 3, fig and 4 or 5)
  local branchCount = fig and 6 or 3
  for branch = 1, branchCount do
    local d = TREE_DIRECTIONS[1 + randomInt(treeX + branch, treeZ, 353, 8)]
    local reach = 2 + randomInt(treeX, treeZ + branch, 359, 2)
    for step = 1, reach do
      setIfNotOpaque(chunk, localX + d[1] * step, crownY + math.floor(step / 2),
        localZ + d[2] * step, logId)
    end
    addTropicalCanopy(chunk, localX + d[1] * reach, crownY,
      localZ + d[2] * reach, leavesId, 2, 3)
  end
end

local function addAcaciaTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local logId = blocks.acacia_log_alive or blocks.acacia_log or
    blocks.oak_log_alive or blocks.oak_log
  local leavesId = blocks.acacia_leaves or blocks.oak_leaves
  local localX, localZ = treeX - offsetX, treeZ - offsetZ
  local height = 6 + randomInt(treeX, treeZ, 367, 4)
  local direction = TREE_DIRECTIONS[1 + randomInt(treeX, treeZ, 369, 8)]
  local tx, tz = localX, localZ
  setLocalBlock(chunk, localX, groundY, localZ, blocks.dirt or logId)
  for rise = 1, height do
    if rise == height - 2 then
      setIfNotOpaque(chunk, tx, groundY + rise, tz, logId)
      tx, tz = tx + direction[1], tz + direction[2]
    end
    setIfNotOpaque(chunk, tx, groundY + rise, tz, logId)
  end
  addTropicalCanopy(chunk, tx, groundY + height, tz, leavesId, 3, 2)
  local side = TREE_DIRECTIONS[(1 + randomInt(treeX, treeZ, 373, 8))]
  for step = 1, 3 do
    setIfNotOpaque(chunk, tx + side[1] * step, groundY + height - 1,
      tz + side[2] * step, logId)
  end
  addTropicalCanopy(chunk, tx + side[1] * 3, groundY + height,
    tz + side[2] * 3, leavesId, 2, 2)
end

local function addPalmTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local logId = blocks.palm_log_alive or blocks.palm_log or
    blocks.jungle_log_alive or blocks.jungle_log or blocks.oak_log_alive or blocks.oak_log
  local leavesId = blocks.palm_leaves or blocks.jungle_leaves or blocks.oak_leaves
  local localX, localZ = treeX - offsetX, treeZ - offsetZ
  local height = 8 + randomInt(treeX, treeZ, 379, 5)
  local lean = TREE_DIRECTIONS[1 + randomInt(treeX, treeZ, 383, 8)]
  local tx, tz = localX, localZ
  for rise = 1, height do
    if rise == math.floor(height * 0.55) or rise == height - 1 then
      setIfNotOpaque(chunk, tx, groundY + rise, tz, logId)
      tx, tz = tx + lean[1], tz + lean[2]
    end
    setIfNotOpaque(chunk, tx, groundY + rise, tz, logId)
  end

  setIfNotOpaque(chunk, tx, groundY + height + 1, tz, leavesId)
  for direction = 1, #TREE_DIRECTIONS do
    local dx, dz = TREE_DIRECTIONS[direction][1], TREE_DIRECTIONS[direction][2]
    local reach = direction % 2 == 0 and 3 or 4
    for step = 1, reach do
      local drop = step == reach and 1 or 0
      setIfNotOpaque(chunk, tx + dx * step, groundY + height + 1 - drop,
        tz + dz * step, leavesId)
    end
  end
end

local function addBigTreeCluster(chunk, centerX, centerY, centerZ, leavesId)
  for layer = 0, 3 do
    local y = centerY + layer
    local radius = (layer == 0 or layer == 3) and 2 or 3
    local radiusSq = (radius + 0.5) * (radius + 0.5)

    for lx = centerX - radius, centerX + radius do
      local dx = lx - centerX
      for lz = centerZ - radius, centerZ + radius do
        local dz = lz - centerZ
        if dx * dx + dz * dz <= radiusSq then
          setIfNotOpaque(chunk, lx, y, lz, leavesId)
        end
      end
    end
  end
end

local function addBigTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local heightLimit = randomInt(treeX, treeZ, 263, 12) + 5
  local trunkHeight = math.floor(heightLimit * 0.618)
  if trunkHeight >= heightLimit then
    trunkHeight = heightLimit - 1
  end

  local logId = blocks.oak_log_alive or blocks.oak_log or blocks.oak_planks or blocks.dirt
  local leavesId = blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ
  local crownBase = groundY + heightLimit - 4

  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)

  addBigTreeCluster(chunk, localTreeX, crownBase, localTreeZ, leavesId)

  local branchCount = 2 + randomInt(treeX, treeZ, 267, 3)
  for branch = 1, branchCount do
    local angleIndex = randomInt(treeX + branch, treeZ - branch, 269, 8)
    local dx = ({1, 1, 0, -1, -1, -1, 0, 1})[angleIndex + 1]
    local dz = ({0, 1, 1, 1, 0, -1, -1, -1})[angleIndex + 1]
    local reach = 2 + randomInt(treeX + branch, treeZ + branch, 273, 2)
    local clusterX = localTreeX + dx * reach
    local clusterZ = localTreeZ + dz * reach
    local clusterY = crownBase - 1 - randomInt(treeX - branch, treeZ + branch, 277, 2)
    addBigTreeCluster(chunk, clusterX, clusterY, clusterZ, leavesId)

    for step = 1, reach do
      local bx = localTreeX + dx * step
      local bz = localTreeZ + dz * step
      local by = clusterY - 1 + math.floor((step / reach) * 2)
      local existing = getLocalBlock(chunk, bx, by, bz)
      if existing == blocks.air or isLeafBlock(existing) then
        setLocalBlock(chunk, bx, by, bz, logId)
      end
    end
  end

  for y = 0, trunkHeight do
    local localY = groundY + 1 + y
    local existing = getLocalBlock(chunk, localTreeX, localY, localTreeZ)
    if existing == blocks.air or isLeafBlock(existing) then
      setLocalBlock(chunk, localTreeX, localY, localTreeZ, logId)
    end
  end
end

local function addTaiga1Tree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local height = randomInt(treeX, treeZ, 281, 6) + 13
  local leafHeight = 7 + randomInt(treeX, treeZ, 283, 4)
  local trunkBareHeight = height - leafHeight
  local maxRadius = 3 + randomInt(treeX, treeZ, 287, 2)
  local logId = blocks.spruce_log_alive or blocks.spruce_log or
    blocks.oak_log_alive or blocks.oak_log or blocks.oak_planks or blocks.dirt
  local leavesId = blocks.spruce_leaves or blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ

  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)

  for y = groundY + height, groundY + trunkBareHeight, -1 do
    local layer=groundY+height-y
    local radius=math.min(maxRadius,
      math.floor((layer/math.max(1,leafHeight))*maxRadius+0.35))
    for lx = localTreeX - radius, localTreeX + radius do
      local dx = lx - localTreeX
      for lz = localTreeZ - radius, localTreeZ + radius do
        local dz = lz - localTreeZ
        if (math.abs(dx) ~= radius or math.abs(dz) ~= radius or radius <= 0) then
          setIfNotOpaque(chunk, lx, y, lz, leavesId)
        end
      end
    end

  end

  for y = 0, height - 2 do
    local localY = groundY + 1 + y
    local existing = getLocalBlock(chunk, localTreeX, localY, localTreeZ)
    if existing == blocks.air or isLeafBlock(existing) then
      setLocalBlock(chunk, localTreeX, localY, localTreeZ, logId)
    end
  end
end

local function addTaiga2Tree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local height = randomInt(treeX, treeZ, 293, 5) + 11
  local leafStart = 2 + randomInt(treeX, treeZ, 307, 2)
  local leafLayers = height - leafStart
  local maxRadius = 3 + randomInt(treeX, treeZ, 311, 2)
  local logId = blocks.spruce_log_alive or blocks.spruce_log or
    blocks.oak_log_alive or blocks.oak_log or blocks.oak_planks or blocks.dirt
  local leavesId = blocks.spruce_leaves or blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ

  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)

  local radius = randomInt(treeX, treeZ, 313, 2)
  local radiusTarget = 1
  local previousTarget = 0

  for layer = 0, leafLayers do
    local y = groundY + height - layer
    for lx = localTreeX - radius, localTreeX + radius do
      local dx = lx - localTreeX
      for lz = localTreeZ - radius, localTreeZ + radius do
        local dz = lz - localTreeZ
        if (math.abs(dx) ~= radius or math.abs(dz) ~= radius or radius <= 0) then
          setIfNotOpaque(chunk, lx, y, lz, leavesId)
        end
      end
    end

    if radius >= radiusTarget then
      radius = previousTarget
      previousTarget = 1
      radiusTarget = math.min(radiusTarget + 1, maxRadius)
    else
      radius = radius + 1
    end
  end

  local missingTop = randomInt(treeX, treeZ, 317, 3)
  for y = 0, height - missingTop - 1 do
    local localY = groundY + 1 + y
    local existing = getLocalBlock(chunk, localTreeX, localY, localTreeZ)
    if existing == blocks.air or isLeafBlock(existing) then
      setLocalBlock(chunk, localTreeX, localY, localTreeZ, logId)
    end
  end
end

local function addTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, biome)
  local profile = biomeProfiles[biome] or biomeProfiles.plains
  local generator = chooseTreeGenerator(profile, treeX, treeZ)
  if generator == "palm" then
    addPalmTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  else
    addVoxelTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, generator)
  end
end

-- Shared by world decoration now and sapling growth later; keeping the same
-- deterministic selector means a planted/debug-generated tree has the biome's
-- real silhouette instead of a separate miniature implementation.
terrain.addTree = addTree

local foliageProfiles = {
  rainforest = {
    grass = 0.64, doubleGrass = 0.070, flowers = 0.055,
    flowerTypes = {"blue_orchid", "allium", "dandelion", "poppy"}
  },
  swampland = {
    grass = 0.38, doubleGrass = 0.030, flowers = 0.085,
    flowerTypes = {"blue_orchid", "blue_orchid", "dandelion"}
  },
  seasonalForest = {
    grass = 0.58, doubleGrass = 0.055, flowers = 0.090,
    flowerTypes = {"poppy", "dandelion", "allium", "oxeye_daisy"}
  },
  savanna = {
    grass = 0.32, doubleGrass = 0.018, flowers = 0.032,
    flowerTypes = {"dandelion", "poppy"}
  },
  shrubland = {
    grass = 0.48, doubleGrass = 0.032, flowers = 0.075,
    flowerTypes = {"dandelion", "poppy", "allium"}
  },
  plains = {
    grass = 0.68, doubleGrass = 0.065, flowers = 0.145,
    flowerTypes = {
      "dandelion", "poppy", "oxeye_daisy", "red_tulip", "orange_tulip",
      "pink_tulip", "white_tulip"
    }
  },
  forest = {
    grass = 0.54, doubleGrass = 0.045, flowers = 0.072,
    flowerTypes = {"poppy", "allium", "oxeye_daisy", "dandelion"}
  },
  taiga = {
    grass = 0.27, doubleGrass = 0.010, flowers = 0.024,
    flowerTypes = {"dandelion", "oxeye_daisy"}
  },
  mountains = {
    grass = 0.22, doubleGrass = 0.010, flowers = 0.028,
    flowerTypes = {"dandelion", "allium", "oxeye_daisy"}
  }
}

local function flowerFor(foliage, worldX, worldZ)
  local types = foliage.flowerTypes
  if not types or #types == 0 then return nil end

  -- Quantizing the selector makes nearby flowers favour the same species,
  -- producing recognisable beds instead of evenly distributed confetti.
  local patchX = math.floor(worldX / 5)
  local patchZ = math.floor(worldZ / 5)
  local index = 1 + math.floor(hash2(patchX, patchZ, 919) * #types)
  return blocks[types[index]]
end

local function isPlantAir(id)
  return id == nil or id == blocks.air or id == 0
end

local function surfaceYForFoliage(chunk, lx, lz, maxHeight)
  for y = maxHeight, terrain.SEA_LEVEL + 1, -1 do
    local id = chunk:getBlock(lx, y, lz)
    if id ~= blocks.air and id ~= blocks.water and id ~= blocks.lava and not isLeafBlock(id) then
      return y, id
    end
  end
  return nil, nil
end

local function populateGrassFoliage(chunk, offsetX, offsetZ, width, depth, maxHeight, step)
  local tallGrassId = blocks.tall_grass
  local doubleLowerId = blocks.double_grass_lower
  local doubleUpperId = blocks.double_grass_upper
  if not tallGrassId then
    return
  end

  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local worldX = offsetX + x
      local worldZ = offsetZ + z
      local column = terrain.columnAt(worldX, worldZ, maxHeight)
      local foliage = foliageProfiles[column.biome]
      if foliage and not column.waterLevel then
        local groundY, groundId = surfaceYForFoliage(chunk, x, z, maxHeight)
        if groundY and groundId == blocks.grass and groundY + 1 <= maxHeight and isPlantAir(chunk:getBlock(x, groundY + 1, z)) then
          local waterClearance = 1.0 - clamp(math.max(column.river or 0.0, column.lake or 0.0) * 1.7, 0.0, 1.0)
          local patchNoise = fbm(worldX + 2600.0, worldZ - 1300.0, 887, 2, 0.055)
          local meadowNoise = fbm(worldX - 9800.0, worldZ + 4300.0, 889, 3, 0.0065)
          local lushness = settings.grassDensity or 1.0
          local density = clamp(foliage.grass * lushness * lerp(0.42, 1.55, patchNoise) *
            lerp(0.72, 1.28, meadowNoise) * waterClearance, 0.0, 0.94)
          local flowerPatch = fbm(worldX + 5700.0, worldZ - 8100.0, 911, 3, 0.021)
          local flowerDensity = (foliage.flowers or 0.0) * math.sqrt(lushness) *
            lerp(0.08, 2.15, edge(flowerPatch, 0.38, 0.76)) * waterClearance
          local flowerId = flowerFor(foliage, worldX, worldZ)

          if flowerId and hash2(worldX, worldZ, 913) < flowerDensity then
            chunk:setBlock(x, groundY + 1, z, flowerId)
          elseif hash2(worldX, worldZ, 881) < density then
            if doubleLowerId and doubleUpperId and groundY + 2 <= maxHeight and isPlantAir(chunk:getBlock(x, groundY + 2, z)) and hash2(worldX, worldZ, 883) < foliage.doubleGrass then
              chunk:setBlock(x, groundY + 1, z, doubleLowerId)
              chunk:setBlock(x, groundY + 2, z, doubleUpperId)
            else
              chunk:setBlock(x, groundY + 1, z, tallGrassId)
            end
          end
        end
      end
    end
    if step then step() end
  end
end

local function carveEllipsoid(chunk, offsetX, offsetZ, cx, cy, cz, rx, ry, rz, maxHeight)
  local minX = math.floor(cx - rx) - offsetX
  local maxX = math.floor(cx + rx) - offsetX
  local minZ = math.floor(cz - rz) - offsetZ
  local maxZ = math.floor(cz + rz) - offsetZ
  local minY = math.floor(cy - ry)
  local maxY = math.floor(cy + ry)

  for lx = minX, maxX do
    for lz = minZ, maxZ do
      for y = minY, maxY do
        if lx >= 0 and lx < 16 and lz >= 0 and lz < 16 and y > 1 and y <= maxHeight then
          local dx = (lx + offsetX + 0.5 - cx) / rx
          local dy = (y + 0.5 - cy) / ry
          local dz = (lz + offsetZ + 0.5 - cz) / rz
          if dx * dx + dy * dy + dz * dz < 1.0 then
            local existing = chunk:getBlock(lx, y, lz)
            if existing ~= blocks.water and existing ~= blocks.lava then
              chunk:setBlock(lx, y, lz, y <= 10 and (blocks.lava or blocks.air) or blocks.air)
            end
          end
        end
      end
    end
  end
end

local function carveCaveSystem(chunk, offsetX, offsetZ, startX, startY, startZ, yaw, pitch, length, radius, maxHeight, salt)
  local x = startX
  local y = startY
  local z = startZ
  local localYaw = yaw
  local localPitch = pitch

  for step = 1, length do
    local progress = step / length
    local tunnelRadius = radius * (0.55 + math.sin(progress * math.pi) * 0.75)
    carveEllipsoid(chunk, offsetX, offsetZ, x, y, z, tunnelRadius, tunnelRadius * 0.65, tunnelRadius, maxHeight)

    x = x + math.cos(localYaw) * math.cos(localPitch)
    y = y + math.sin(localPitch) * 0.7
    z = z + math.sin(localYaw) * math.cos(localPitch)
    localYaw = localYaw + (hash3(math.floor(x), step, math.floor(z), salt) - 0.5) * 0.22
    localPitch = localPitch * 0.74 + (hash3(math.floor(x), step, math.floor(z), salt + 17) - 0.5) * 0.14
  end
end

local function carveRavine(chunk, offsetX, offsetZ, startX, startY, startZ, yaw, length, maxHeight, salt)
  local x = startX
  local z = startZ
  local localYaw = yaw

  for step = 1, length do
    local progress = step / length
    local width = 1.4 + math.sin(progress * math.pi) * 3.2
    local height = 6.0 + math.sin(progress * math.pi) * 9.0
    local y = startY + math.sin(progress * math.pi * 2.0) * 4.0
    carveEllipsoid(chunk, offsetX, offsetZ, x, y, z, width, height, width * 0.75, maxHeight)
    x = x + math.cos(localYaw) * 1.8
    z = z + math.sin(localYaw) * 1.8
    localYaw = localYaw + (hash3(math.floor(x), step, math.floor(z), salt) - 0.5) * 0.10
  end
end

local function carveChunkCaves(chunk, offsetX, offsetZ, maxHeight)
  local chunkX = math.floor(offsetX / 16)
  local chunkZ = math.floor(offsetZ / 16)

  for sx = chunkX - 1, chunkX + 1 do
    for sz = chunkZ - 1, chunkZ + 1 do
      if hash2(sx, sz, 701) < 0.24 then
        local systems = 1 + randomInt(sx, sz, 703, 2)
        for i = 1, systems do
          local startX = sx * 16 + randomInt(sx + i, sz, 709, 16)
          local startZ = sz * 16 + randomInt(sx, sz + i, 719, 16)
          local startY = 8 + randomInt(sx - i, sz + i, 727, 72)
          local yaw = hash2(sx + i, sz - i, 733) * math.pi * 2.0
          local pitch = (hash2(sx - i, sz + i, 739) - 0.5) * 0.35
          local length = 24 + randomInt(sx + i, sz + i, 743, 38)
          local radius = 1.2 + hash2(sx - i, sz - i, 751) * 1.6
          carveCaveSystem(chunk, offsetX, offsetZ, startX, startY, startZ, yaw, pitch, length, radius, maxHeight, 757 + i)

          if hash2(sx + i, sz + i, 761) < 0.35 then
            carveCaveSystem(chunk, offsetX, offsetZ, startX, startY, startZ, yaw + 1.45, pitch * 0.5, math.floor(length * 0.55), radius * 0.8, maxHeight, 769 + i)
          end
        end
      end

      if hash2(sx, sz, 787) < 0.035 then
        local startX = sx * 16 + randomInt(sx, sz, 797, 16)
        local startZ = sz * 16 + randomInt(sx, sz, 809, 16)
        local startY = 24 + randomInt(sx, sz, 811, 42)
        carveRavine(chunk, offsetX, offsetZ, startX, startY, startZ, hash2(sx, sz, 821) * math.pi * 2.0, 42 + randomInt(sx, sz, 823, 36), maxHeight, 827)
      end

      if hash2(sx, sz, 829) < 0.16 then
        local lavaX = sx * 16 + randomInt(sx, sz, 831, 16)
        local lavaZ = sz * 16 + randomInt(sx, sz, 833, 16)
        local lavaY = 5 + randomInt(sx, sz, 835, 6)
        carveEllipsoid(chunk, offsetX, offsetZ, lavaX, lavaY, lavaZ, 2.2, 1.1, 2.2, maxHeight)
      end
    end
  end
end

local ORE_VEINS = {
  {block = "coal_ore", count = 10, size = 8, minY = 8, maxY = 96},
  {block = "iron_ore", count = 8, size = 6, minY = 8, maxY = 64},
  {block = "gold_ore", count = 2, size = 5, minY = 5, maxY = 32},
  {block = "redstone_ore", count = 4, size = 4, minY = 5, maxY = 16},
  {block = "lapis_ore", count = 1, size = 4, minY = 12, maxY = 30},
  {block = "diamond_ore", count = 1, size = 4, minY = 5, maxY = 16},
  {block = "emerald_ore", count = 1, size = 4, minY = 4, maxY = 32, biome = "mountains"}
}

local function placeOreVein(chunk, offsetX, offsetZ, oreId, startX, startY, startZ, size, salt)
  local angle = hash3(startX, startY, startZ, salt) * math.pi
  local dx = math.cos(angle) * size / 8.0
  local dz = math.sin(angle) * size / 8.0
  local x1 = startX + dx
  local x2 = startX - dx
  local z1 = startZ + dz
  local z2 = startZ - dz

  for i = 0, size - 1 do
    local t = size <= 1 and 0.0 or i / (size - 1)
    local cx = lerp(x1, x2, t)
    local cy = startY + (hash3(startX, i, startZ, salt + 3) - 0.5) * 2.0
    local cz = lerp(z1, z2, t)
    local radius = (math.sin(t * math.pi) + 0.65) * (0.24 + hash3(startX, i, startZ, salt + 7) * 0.34)
    for lx = math.floor(cx - radius) - offsetX, math.floor(cx + radius) - offsetX do
      for lz = math.floor(cz - radius) - offsetZ, math.floor(cz + radius) - offsetZ do
        for y = math.floor(cy - radius), math.floor(cy + radius) do
          if lx >= 0 and lx < 16 and lz >= 0 and lz < 16 and y > 1 and y < 256 and chunk:getBlock(lx, y, lz) == blocks.stone then
            local ddx = lx + offsetX + 0.5 - cx
            local ddy = y + 0.5 - cy
            local ddz = lz + offsetZ + 0.5 - cz
            if ddx * ddx + ddy * ddy + ddz * ddz <= radius * radius then
              chunk:setBlock(lx, y, lz, oreId)
            end
          end
        end
      end
    end
  end
end

local function populateOres(chunk, offsetX, offsetZ)
  local chunkX = math.floor(offsetX / 16)
  local chunkZ = math.floor(offsetZ / 16)

  for i = 1, #ORE_VEINS do
    local ore = ORE_VEINS[i]
    local oreId = blocks[ore.block]
    if oreId then
      for n = 1, ore.count do
        local x = offsetX + randomInt(chunkX + n, chunkZ, 839 + i, 16)
        local z = offsetZ + randomInt(chunkX, chunkZ + n, 853 + i, 16)
        local y = ore.minY + randomInt(chunkX - n, chunkZ + n, 857 + i, ore.maxY - ore.minY + 1)
        if (not ore.biome) or terrain.biomeAt(x, z) == ore.biome then
          placeOreVein(chunk, offsetX, offsetZ, oreId, x, y, z, ore.size, 863 + i * 17 + n)
        end
      end
    end
  end
end

function terrain.fillChunk(chunk, offsetX, offsetZ, width, depth, maxHeight, options)
  options = options or {}
  local step = options.yieldStep
  if options.generatorType == "superflat" or options.generatorType == "showcase" then
    local profileLayers = terrain.activeProfile.generation and terrain.activeProfile.generation.superflatLayers
    fillSuperflatChunk(chunk, width, depth, maxHeight, options.superflatLayers or profileLayers, step)
    if options.generatorType == "showcase" then
      showcase.decorateChunk(chunk, offsetX, offsetZ, width, depth, maxHeight)
    end
    chunk.environment = {
      world = terrain.activeWorldId,
      biome = options.generatorType == "showcase" and "showcase" or
        (terrain.activeWorldId == "mars" and "mars_lowlands" or "superflat"),
      landform = "plain",
      averageElevation = 3
    }
    return
  end

  chunk.environment = worldgen:sampleChunkEnvironment(offsetX, offsetZ, width, depth, maxHeight)
  chunk.waterSurface = {}

  local waterId = blocks.water or blocks.water_still

  -- Density is (column.height - y) plus noise that cannot exceed
  -- DENSITY_NOISE_BOUND, so outside a band of that width around the surface the
  -- sign is already decided and evaluating the noise cannot change the result.
  -- Skipping those levels is exact, not an approximation.
  local bound = terrain.DENSITY_NOISE_BOUND

  -- A whole x-slice was one step, which is several ms of work. The frame budget
  -- can only stop between steps, so it overshot by that much every time it hit
  -- the cap. Yielding every few columns makes the cap tight.
  local sinceYield = 0

  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local worldX = x + offsetX
      local worldZ = z + offsetZ
      local column = terrain.columnAt(worldX, worldZ, maxHeight)
      if column.waterLevel then
        chunk.waterSurface[x + z * 16 + 1] = column.waterLevel - 0.35
      end
      local bandLow = column.height - bound
      local bandHigh = column.height + bound

      for y = 0, maxHeight do
        local solid
        if y == 0 or y < bandLow then
          solid = true
        elseif y > bandHigh then
          solid = false
        else
          solid = terrainDensityAt(worldX, y, worldZ, maxHeight, column) > 0.0
        end

        -- Density noise must not rebuild rock through a channel after the
        -- hydrology stage carved it. Rivers and lakes own local water levels.
        if column.waterLevel and y > column.height and y <= column.waterLevel then
          solid = false
        end

        if solid then
          chunk:setBlock(x, y, z, blocks.stone)
        elseif column.waterLevel and y <= column.waterLevel and waterId then
          if y == column.waterLevel and column.freezeWater and blocks.ice then
            chunk:setBlock(x, y, z, blocks.ice)
          else
            chunk:setBlock(x, y, z, waterId)
          end
        end
      end

      sinceYield = sinceYield + 1
      if step and sinceYield >= DENSITY_YIELD_COLUMNS then
        sinceYield = 0
        step()
      end
    end
  end

  applySurfaceReplacement(chunk, offsetX, offsetZ, width, depth, maxHeight, step)
  local generation = terrain.activeProfile.generation or {}
  if generation.ores ~= false then populateOres(chunk, offsetX, offsetZ) end
  if step then step() end
  if generation.caves ~= false then carveChunkCaves(chunk, offsetX, offsetZ, maxHeight) end
  if step then step() end

  if generation.vegetation ~= false then
    -- The authored ceiba and jungle crowns can reach eighteen blocks from the
    -- trunk. Include that overlap so a tree remains whole across chunk edges.
    local candidates = treeCandidates(
      offsetX - 18, offsetZ - 18, offsetX + width + 17, offsetZ + depth + 17)
    for i = 1, #candidates do
      local treeX, treeZ = candidates[i].x, candidates[i].z
      local column = terrain.columnAt(treeX, treeZ, maxHeight)
      local lx = treeX - offsetX
      local lz = treeZ - offsetZ
      local groundY = nil

      if lx >= 0 and lx < 16 and lz >= 0 and lz < 16 then
        for y = maxHeight, terrain.SEA_LEVEL + 1, -1 do
          local id = chunk:getBlock(lx, y, lz)
          if id and id ~= blocks.air and id ~= blocks.water and id ~= blocks.lava and not isLeafBlock(id) then
            groundY = y
            break
          end
        end
      else
        groundY = column.height
      end

      if groundY and not column.waterLevel and groundY >= terrain.SEA_LEVEL + 1 and
          isTreeCenter(treeX, treeZ, column.biome) then
        addTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, column.biome, maxHeight)
      end
      if step and i % 8 == 0 then step() end
    end
    populateGrassFoliage(chunk, offsetX, offsetZ, width, depth, maxHeight, step)
  end
end

-- Stable development interface for field maps, F3 information and future
-- editor overlays. Callers do not need to know which pipeline stage owns a
-- value, so modules can be replaced without changing the visualisation tools.
function terrain.debugFieldsAt(x, z, maxHeight)
  return worldgen:debugFieldsAt(x, z, maxHeight or 127)
end

function terrain.debugColorAt(mode, x, z, maxHeight)
  return worldgen:debugColorAt(mode, x, z, maxHeight or 127)
end

function terrain.heightExplanationAt(x, z, maxHeight)
  return worldgen:heightExplanationAt(x, z, maxHeight or 127)
end

function terrain.chunkEnvironmentAt(offsetX, offsetZ, width, depth, maxHeight)
  return worldgen:sampleChunkEnvironment(offsetX, offsetZ, width or 16, depth or 16, maxHeight or 127)
end

return terrain
