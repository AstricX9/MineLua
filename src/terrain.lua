local ffi = require("ffi")
local bit = require("bit")
local blocks = require("blocks")
local settings = require("graphics_settings").terrainGeneration or {}
local texture = require("texture")

local terrain = {}

terrain.SEA_LEVEL = settings.seaLevel or 63
terrain.activeSeed = settings.seed or 1
local macroCache = {}
local macroCacheCount = 0
local MACRO_CACHE_LIMIT = 160000

function terrain.setSeed(seed)
  local nextSeed = tonumber(seed) or settings.seed or 1
  if terrain.activeSeed ~= nextSeed then
    terrain.activeSeed = nextSeed
    terrain.refreshSeedSalt()
    macroCache = {}
    macroCacheCount = 0
  end
end

function terrain.refreshGenerationSettings()
  terrain.SEA_LEVEL = settings.seaLevel or 63
  terrain.RELIEF_GAIN = settings.reliefGain or 2.4
  terrain.LOCAL_RELIEF_GAIN = settings.localReliefGain or 2.0
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
    treeSpacing = 6,
    treeChance = 0.48,
    treeGenerators = {"big", "oak", "oak"}
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
    treeGenerators = {"oak"}
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
    treeGenerators = {"oak", "oak", "big"}
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
    treeGenerators = {"oak"}
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
    treeGenerators = {"oak"}
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
    treeGenerators = {"oak"}
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
    treeGenerators = {"forest", "oak", "oak", "big"}
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
    treeGenerators = {"taiga1", "taiga2", "taiga2"}
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
    treeSpacing = 16,
    treeChance = 0.0
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

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt

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

-- Value-noise hashing. The previous implementation ran every lattice corner
-- through math.sin of a very large argument, which measured 44 ns per call and
-- made a single 16-cube planet chunk cost 178 ms. Integer mixing on 32-bit
-- words lowers to a handful of instructions: 6 ns per call, and the output is
-- closer to uniform (stddev 0.2886 against the ideal 0.2887; the sine hash
-- drifted). No chunk data is persisted, so changing the hash re-rolls worlds
-- without seaming anything.
local band, bxor, rshift, tobit = bit.band, bit.bxor, bit.rshift, bit.tobit
local HASH_SCALE = 1.0 / 16777216.0
local seedSalt = (terrain.activeSeed or settings.seed or 1) * 101

function terrain.refreshSeedSalt()
  seedSalt = (terrain.activeSeed or settings.seed or 1) * 101
end

local function mix32(h)
  h = tobit(bxor(h, rshift(h, 15)) * 2246822519)
  h = tobit(bxor(h, rshift(h, 13)) * 3266489917)
  return band(bxor(h, rshift(h, 16)), 0x00ffffff) * HASH_SCALE
end

local function hash2(x, z, seed)
  seed = seed + seedSalt
  return mix32(bxor(bxor(tobit(x * 374761393), tobit(z * 668265263)), tobit(seed * 1442695041)))
end

local function hash3(x, y, z, seed)
  seed = seed + seedSalt
  return mix32(bxor(bxor(bxor(tobit(x * 374761393), tobit(y * 1442695041)),
    tobit(z * 668265263)), tobit(seed * 1274126177)))
end

local function valueNoise(x, z, seed)
  local x0 = floor(x)
  local z0 = floor(z)
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

-- The eight corner reads used to go through a closure created per call, which
-- allocated once per octave per voxel. They are spelled out instead.
local function valueNoise3(x, y, z, seed)
  local x0 = floor(x)
  local y0 = floor(y)
  local z0 = floor(z)
  local x1, y1, z1 = x0 + 1, y0 + 1, z0 + 1
  local sx = smoothstep(x - x0)
  local sy = smoothstep(y - y0)
  local sz = smoothstep(z - z0)

  local x00 = lerp(hash3(x0, y0, z0, seed), hash3(x1, y0, z0, seed), sx)
  local x10 = lerp(hash3(x0, y1, z0, seed), hash3(x1, y1, z0, seed), sx)
  local x01 = lerp(hash3(x0, y0, z1, seed), hash3(x1, y0, z1, seed), sx)
  local x11 = lerp(hash3(x0, y1, z1, seed), hash3(x1, y1, z1, seed), sx)
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

local function ridged(value)
  return 1.0 - math.abs(value * 2.0 - 1.0)
end

-- A C1 lower bound: values a full softness above floorValue pass through
-- unchanged, values a full softness below settle onto it, and the join between
-- them is a parabola rather than a crease.
local function softFloor(value, floorValue, softness)
  local delta = value - floorValue
  if delta >= softness then return value end
  if delta <= -softness then return floorValue end
  local t = (delta + softness) / (2.0 * softness)
  return floorValue + softness * t * t
end

local function edge(value, edge0, edge1)
  if edge0 == edge1 then
    return value >= edge1 and 1.0 or 0.0
  end
  return smoothstep((value - edge0) / (edge1 - edge0))
end

local function rotated(x, z, angle)
  local c = math.cos(angle)
  local s = math.sin(angle)
  return x * c + z * s, -x * s + z * c
end

local function mountainChain(x, z, seed, scale, angle, stretch)
  local rx, rz = rotated(x, z, angle)
  return ridged(fbm(rx, rz * stretch, seed, 5, scale))
end

-- Lakes are discrete drainage basins, rather than another thresholded noise
-- field.  The basin id owns one integer surface elevation, so a lake stays
-- perfectly level even when it crosses a chunk boundary.  Neighbouring basin
-- cells can still choose different elevations.
local function lakeBasinAt(x, z, land, mountain, regionScale)
  local cellSize = settings.lakeCellSize or 176.0
  local cellX = math.floor(x / cellSize)
  local cellZ = math.floor(z / cellSize)
  local bestMask, bestLevel = 0.0, nil

  for dz = -1, 1 do
    for dx = -1, 1 do
      local basinX = cellX + dx
      local basinZ = cellZ + dz
      if hash2(basinX, basinZ, 421) < (settings.lakeBasinChance or 0.34) then
        local centerX = (basinX + 0.18 + hash2(basinX, basinZ, 423) * 0.64) * cellSize
        local centerZ = (basinZ + 0.18 + hash2(basinX, basinZ, 425) * 0.64) * cellSize
        local radiusX = 24.0 + hash2(basinX, basinZ, 427) * 34.0
        local radiusZ = 22.0 + hash2(basinX, basinZ, 429) * 32.0
        local angle = (hash2(basinX, basinZ, 431) - 0.5) * math.pi
        local localX, localZ = rotated(x - centerX, z - centerZ, angle)
        local distance = math.sqrt((localX / radiusX) ^ 2 + (localZ / radiusZ) ^ 2)
        local shape = 1.0 - smoothstep((distance - 0.68) / 0.32)
        local mask = shape * edge(land, 0.48, 0.88) * (1.0 - mountain * 0.82)

        if mask > bestMask then
          -- Sample only broad elevation at the owning basin centre.  This is
          -- intentionally independent of the per-column terrain height: using
          -- the latter would make the supposedly level lake tilt and ripple.
          local regional = fbm(centerX - 14000.0, centerZ + 9300.0, 17, 4, regionScale)
          local broad = fbm(centerX + 4100.0, centerZ - 3700.0, 19, 4, regionScale * 2.35)
          local lift = clamp((regional - 0.30) * 22.0 + (broad - 0.50) * 4.0, 3.0, 19.0)
          bestMask = mask
          bestLevel = terrain.SEA_LEVEL + math.floor(lift + 0.5)
        end
      end
    end
  end

  return bestMask, bestLevel
end

local function macroSignals(x, z)
  local continentScale = settings.continentScale or 0.00036
  local biomeScale = settings.biomeScale or 0.00092
  local regionScale = settings.regionScale or 0.00125
  local mountainScale = settings.mountainScale or 0.00078
  local riverScale = settings.riverScale or 0.00115
  local warpScale = settings.macroWarpScale or 0.00062
  local warpAmount = settings.macroWarpAmount or 360.0

  local warpX = (fbm(x + 9100.0, z - 4100.0, 53, 3, warpScale) - 0.5) * warpAmount
  local warpZ = (fbm(x - 2800.0, z + 7600.0, 59, 3, warpScale) - 0.5) * warpAmount
  local wx = x + warpX
  local wz = z + warpZ

  local continentBase = fbm(wx, wz, 11, 6, continentScale)
  local continentShape = fbm(wx + 6200.0, wz - 5800.0, 13, 4, continentScale * 2.15)
  local continent = clamp(continentBase * 0.78 + continentShape * 0.22, 0.0, 1.0)
  local land = edge(continent, 0.38, 0.53)

  local regionalElevation = fbm(wx - 14000.0, wz + 9300.0, 17, 4, regionScale)
  local broadHills = fbm(wx + 4100.0, wz - 3700.0, 19, 4, regionScale * 2.35)
  local localHills = fbm(x - 700.0, z + 350.0, 23, 4, settings.detailScale or 0.026)
  local surfaceDetail = fbm(x - 90.0, z + 210.0, 31, 3, 0.052)
  local micro = fbm(x + 830.0, z - 620.0, 33, 2, 0.095)

  local chainA = mountainChain(wx + 300.0, wz - 450.0, 97, mountainScale, 0.58, 0.34)
  local chainB = mountainChain(wx - 12000.0, wz + 9400.0, 101, mountainScale * 0.72, -0.82, 0.28)
  local chainC = mountainChain(wx + 19000.0, wz + 2100.0, 103, mountainScale * 1.18, 1.36, 0.42)
  local chainNoise = math.max(chainA, chainB * 0.92, chainC * 0.72)
  local mountainGate = edge(regionalElevation, 0.50, 0.78) * edge(land, 0.35, 0.80)
  local mountain = edge(chainNoise, 0.50, 0.82) * mountainGate
  local ridge = ridged(fbm(wx + 1700.0, wz - 2200.0, 37, 5, 0.0048))

  local riverBase = ridged(fbm(wx + 3200.0, wz - 8400.0, 401, 5, riverScale))
  local riverDetail = ridged(fbm(wx - 2300.0, wz + 5100.0, 409, 4, riverScale * 2.15))
  local riverField = riverBase * 0.82 + riverDetail * 0.18
  local river = edge(riverField, 0.86, 0.98) * edge(land, 0.28, 0.76) * (1.0 - mountain * 0.62)

  local lake, lakeLevel = lakeBasinAt(x, z, land, mountain, regionScale)

  -- Rivers use a much broader drainage potential than their channel mask.
  -- Quantising it gives Minecraft-like level reaches with occasional one-block
  -- falls, while the continental blend brings every channel back down to sea
  -- level near its outlet.
  local drainage = fbm(wx - 18600.0, wz + 7400.0, 433, 3, regionScale * 0.34)
  local inlandLift = clamp(
    (regionalElevation - 0.28) * 21.0 + (drainage - 0.50) * 5.0,
    1.0,
    20.0
  )
  local outletBlend = edge(land, 0.32, 0.78)
  local riverLevel = terrain.SEA_LEVEL + math.floor(lerp(1.0, inlandLift, outletBlend) + 0.5)

  local temperatureRaw = fbm(wx + 1200.0, wz - 800.0, 71, 4, biomeScale)
  local rainfallRaw = fbm(wx - 500.0, wz + 900.0, 83, 4, biomeScale * 1.18)
  local temperature = clamp((temperatureRaw - 0.28) / 0.46, 0.0, 1.0)
  local rainfall = clamp((rainfallRaw - 0.24) / 0.52, 0.0, 1.0)

  return {
    continent = continent,
    land = land,
    coast = 1.0 - math.abs(land * 2.0 - 1.0),
    regionalElevation = regionalElevation,
    broadHills = broadHills,
    localHills = localHills,
    surfaceDetail = surfaceDetail,
    micro = micro,
    mountain = mountain,
    ridge = ridge,
    river = river,
    lake = lake,
    riverLevel = riverLevel,
    lakeLevel = lakeLevel,
    temperature = temperature,
    rainfall = rainfall,
    warpX = warpX,
    warpZ = warpZ
  }
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

local function biomeSignals(x, z)
  local macro = terrain.macroAt(x, z)
  return macro.temperature, macro.rainfall, macro.mountain, macro.land
end

local function classicBiomeForClimate(temperature, rainfall)
  rainfall = rainfall * temperature

  if temperature < 0.1 then
    return "tundra"
  end

  if rainfall < 0.2 then
    if temperature < 0.5 then
      return "tundra"
    elseif temperature < 0.95 then
      return "savanna"
    end
    return "desert"
  end

  if rainfall > 0.5 and temperature < 0.7 then
    return "swampland"
  end

  if temperature < 0.5 then
    return "taiga"
  elseif temperature < 0.97 then
    return rainfall < 0.35 and "shrubland" or "forest"
  elseif rainfall < 0.45 then
    return "plains"
  elseif rainfall < 0.9 then
    return "seasonalForest"
  end

  return "rainforest"
end

function terrain.biomeAt(x, z)
  local temperature, rainfall, mountain, continent = biomeSignals(x, z)

  if continent < 0.22 then
    return "ocean"
  end
  if mountain > 0.56 then
    return "mountains"
  end

  return classicBiomeForClimate(temperature, rainfall)
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
  local macro = terrain.macroAt(x, z)
  sourceBiome = sourceBiome or terrain.biomeAt(x, z)
  local profile = biomeProfiles[sourceBiome] or biomeProfiles.plains
  local influence = clamp(settings.biomeClimateInfluence or 0.34, 0.0, 1.0)
  if sourceBiome == "mountains" or sourceBiome == "ocean" or sourceBiome == "beach" then
    influence = influence * 0.25
  end

  local profileTemperature = clamp(profile.temperature or macro.temperature, 0.0, 1.0)
  local profileRainfall = clamp(profile.rainfall or macro.rainfall, 0.0, 1.0)
  local temperature = lerp(macro.temperature, profileTemperature, influence)
  local rainfall = lerp(macro.rainfall, profileRainfall, influence)
  local elevation = math.max(0.0, height - terrain.SEA_LEVEL)
  temperature = clamp(temperature - elevation * (settings.elevationCooling or 0.0045), 0.0, 1.0)

  local snowNoise = fbm(x + 4400.0, z - 7100.0, 733, 2, 0.018)
  local snowThreshold = (settings.snowTemperature or 0.18) + (snowNoise - 0.5) * 0.045
  local hasSnow = temperature < snowThreshold and (rainfall > 0.10 or temperature < 0.055)
  local freezeWater = temperature < (settings.freezeTemperature or 0.08)

  local biome = sourceBiome
  local shorelineWidth = settings.shorelineWidth or 5.0
  local nearSea = height <= terrain.SEA_LEVEL + shorelineWidth and macro.land > 0.08 and macro.land < 0.98
  if nearSea and macro.river < 0.45 and macro.lake < 0.50 and sourceBiome ~= "ocean" then
    local coastalEnergy = macro.mountain * 0.72 + math.abs(macro.localHills - 0.5) * 0.70 +
      math.abs(macro.surfaceDetail - 0.5) * 0.42
    if temperature < 0.14 then
      biome = "frozenShore"
    elseif coastalEnergy > (settings.rockyShoreThreshold or 0.24) then
      biome = "rockyShore"
    else
      biome = "beach"
    end
  end

  return {
    biome = biome,
    profile = biomeProfiles[biome] or profile,
    temperature = temperature,
    rainfall = rainfall,
    hasSnow = hasSnow,
    freezeWater = freezeWater,
    coast = macro.coast
  }
end

local function smoothedBiomeHeight(x, z, fastPreview)
  local centerProfile = terrain.biomeProfileAt(x, z)
  if fastPreview then
    return centerProfile.minHeight, centerProfile.maxHeight
  end
  local totalMin = 0.0
  local totalMax = 0.0
  local totalWeight = 0.0

  for dx = -2, 2 do
    for dz = -2, 2 do
      local profile = terrain.biomeProfileAt(x + dx * 8, z + dz * 8)
      local weight = 10.0 / math.sqrt(dx * dx + dz * dz + 0.2)
      if profile.minHeight > centerProfile.minHeight then
        weight = weight * 0.5
      end

      totalMin = totalMin + profile.minHeight * weight
      totalMax = totalMax + profile.maxHeight * weight
      totalWeight = totalWeight + weight
    end
  end

  return totalMin / totalWeight, totalMax / totalWeight
end

local function waterSurfaceForMacro(macro)
  -- The coast and open ocean retain the global datum. Inland bodies own their
  -- elevation. A lake keeps ownership through a river intersection so its
  -- entire connected basin remains exactly level.
  if macro.land < 0.42 then
    return terrain.SEA_LEVEL, "ocean", 1.0
  end

  local lakeStrength = macro.lake or 0.0
  local riverStrength = macro.river or 0.0
  local lakeLevel = lakeStrength > 0.075 and macro.lakeLevel or nil
  local riverLevel = riverStrength > 0.10 and macro.riverLevel or nil

  if lakeLevel then
    return lakeLevel, "lake", lakeStrength
  elseif riverLevel then
    return riverLevel, "river", riverStrength
  end

  return nil, nil, 0.0
end

function terrain.waterSurfaceAt(x, z)
  return waterSurfaceForMacro(terrain.macroAt(x, z))
end

function terrain.heightAt(x, z, maxHeight, fastPreview)
  local sea = terrain.SEA_LEVEL
  local macro = terrain.macroAt(x, z)
  local biomeMin, biomeMax = smoothedBiomeHeight(x, z, fastPreview)
  local land = macro.land
  local mountainMask = macro.mountain
  local broadHills = macro.broadHills
  local erosion = clamp(settings.erosionStrength or 0.0, 0.0, 1.0)
  local fineRelief = 1.0 - erosion * 0.72
  local lowlands = 0.5 + (macro.localHills - 0.5) * (1.0 - erosion * 0.35)
  local roughness = 0.5 + (macro.surfaceDetail - 0.5) * fineRelief
  local detail = 0.5 + (macro.micro - 0.5) * fineRelief
  local ridgeNoise = macro.ridge

  local oceanFloor = sea - 34.0 + macro.continent * 28.0 + (broadHills - 0.50) * 8.0 + (roughness - 0.50) * 4.5
  local coastlineShelf = sea - 4.0 + (broadHills - 0.50) * 5.0
  oceanFloor = lerp(oceanFloor, coastlineShelf, edge(land, 0.15, 0.42))

  -- fbm() returns the amplitude-weighted mean of its octaves, and averaging
  -- concentrates the result near 0.5: the hill signals measure a stddev of
  -- 0.12-0.18 where a full-range [0,1] signal would be about 0.29. Left alone,
  -- the amplitudes below deliver roughly a third of what they claim, which is
  -- what made the surface read as a flat plane. This gain restores them.
  local relief = terrain.RELIEF_GAIN

  -- broadHills runs at ~340 blocks and regionalElevation at ~800, so neither
  -- changes much inside a single view. The terms that actually shape what you
  -- can see are localHills (~38 blocks), surfaceDetail (~19) and micro (~10),
  -- which is why they carry their own gain.
  local localRelief = relief * terrain.LOCAL_RELIEF_GAIN

  local continentalBase = sea + 2.0 + land * 18.0 + (macro.regionalElevation - 0.50) * 11.0 * relief
  local plainsAndHills =
    (broadHills - 0.50) * 13.0 * relief +
    ((lowlands - 0.50) * 6.5 + (roughness - 0.50) * 3.4 + (detail - 0.50) * 1.1) * localRelief
  local biomeLift = biomeMin * 5.5 + biomeMax * 5.0
  local height = continentalBase + plainsAndHills + biomeLift

  local mountainSharpness = settings.mountainSharpness or 1.65
  local mountainErosion = 1.0 - erosion * 0.38
  local chainHeight = (mountainMask ^ mountainSharpness) * (14.0 + ridgeNoise * ridgeNoise * 23.0) * mountainErosion
  local foothills = edge(mountainMask, 0.08, 0.42) * ridgeNoise * 7.0 * (1.0 - erosion * 0.18)
  height = height + chainHeight + foothills
  height = lerp(oceanFloor, height, land)

  local localWaterLevel, waterKind, waterStrength = waterSurfaceForMacro(macro)
  if waterKind == "lake" and height > localWaterLevel - 2.0 then
    local lakeBed = localWaterLevel - 2.4 + (roughness - 0.5) * 1.1
    height = lerp(height, lakeBed, waterStrength * (settings.lakeCarveStrength or 0.92))
  elseif waterKind == "river" and height > localWaterLevel - 2.0 then
    local riverBed = localWaterLevel - 2.2 + (roughness - 0.5) * 0.8
    height = lerp(height, riverBed, waterStrength * (settings.riverCarveStrength or 0.94))
  end

  local profile, biome = terrain.biomeProfileAt(x, z)
  if biome == "desert" then
    height = height - 1.0 - math.abs(roughness - 0.5) * 1.4
  elseif biome == "beach" then
    height = lerp(height, sea - 1.0 + (roughness - 0.5) * 1.5, 0.55)
  elseif biome == "forest" then
    height = height + 0.8 + (lowlands - 0.5) * 1.7
  elseif biome == "taiga" then
    height = height + ridgeNoise * 1.8
  elseif biome == "mountains" then
    height = height + 1.5 + ridgeNoise * 3.0 + profile.maxHeight
  end

  local shelfNoise = fbm(x + 150.0, z - 910.0, 39, 2, 0.020)
  height = height + (shelfNoise - 0.5) * lerp(0.8, 1.8, land)

  return clamp(math.floor(height), 2, math.max(2, maxHeight - 4))
end

function terrain.columnAt(x, z, maxHeight)
  local macro = terrain.macroAt(x, z)
  local height = terrain.heightAt(x, z, maxHeight)
  local waterLevel, waterKind, waterStrength = waterSurfaceForMacro(macro)
  local hasWater = waterLevel ~= nil and height < waterLevel
  local profile, biome = terrain.biomeProfileAt(x, z)
  local environment = terrain.environmentAt(x, z, height, biome)
  biome = environment.biome
  profile = environment.profile
  local stoneNoise = fbm(x, z, 41, 2, 1.0 / 16.0)
  local fillerDepth = math.floor(stoneNoise * 2.0 + 2.5 + hash2(x, z, 311) * 0.45)
  local topBlock = profile.topBlock
  local fillerBlock = profile.fillerBlock

  if biome == "beach" then
    topBlock = "sand"
    fillerBlock = "sand"
  elseif biome == "rockyShore" or biome == "frozenShore" then
    topBlock = blocks.gravel and "gravel" or "stone"
    fillerBlock = biome == "rockyShore" and "stone" or "dirt"
  elseif waterKind == "river" and hasWater then
    topBlock = "sand"
    fillerBlock = "sand"
  elseif waterKind == "lake" and hasWater then
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
    river = macro.river,
    lake = macro.lake,
    waterLevel = hasWater and waterLevel or nil,
    waterKind = hasWater and waterKind or nil,
    waterStrength = hasWater and waterStrength or 0.0,
    land = macro.land,
    mountain = macro.mountain,
    temperature = environment.temperature,
    rainfall = environment.rainfall,
    hasSnow = environment.hasSnow,
    freezeWater = environment.freezeWater,
    topBlock = blockId(topBlock, "grass"),
    fillerBlock = blockId(fillerBlock, "dirt"),
    fillerDepth = math.max(1, fillerDepth)
  }
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
  elseif column.waterKind == "river" and column.waterLevel and y < column.waterLevel then
    topBlock = blocks.sand or topBlock
    fillerBlock = blocks.sand or fillerBlock
    underFillerBlock = blocks.sandstone or blocks.stone
  elseif column.waterKind == "lake" and column.waterLevel and y < column.waterLevel then
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
            local surfaceDatum = column.waterLevel or terrain.SEA_LEVEL
            if y >= surfaceDatum - 4 then
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
  if macro.river > 0.32 or macro.lake > 0.28 or macro.land < 0.42 then
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

local TREE_DIRECTIONS = {
  {1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}
}

local function setLogIfReplaceable(chunk, lx, y, lz, logId)
  local existing = getLocalBlock(chunk, lx, y, lz)
  if existing == blocks.air or isLeafBlock(existing) then
    setLocalBlock(chunk, lx, y, lz, logId)
  end
end

local function addLogLine(chunk, x0, y0, z0, x1, y1, z1, logId, logXId, logZId)
  local steps = math.max(math.abs(x1-x0), math.abs(y1-y0), math.abs(z1-z0), 1)
  local dx, dy, dz = math.abs(x1-x0), math.abs(y1-y0), math.abs(z1-z0)
  local orientedLogId = logId
  if dx > dy or dz > dy then
    orientedLogId = dx >= dz and (logXId or logId) or (logZId or logId)
  end
  for step=0,steps do
    local t=step/steps
    setLogIfReplaceable(chunk,
      math.floor(x0+(x1-x0)*t+0.5),
      math.floor(y0+(y1-y0)*t+0.5),
      math.floor(z0+(z1-z0)*t+0.5),orientedLogId)
  end
end

local BRANCH_SHEATH_DIRECTIONS = {
  {1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}
}

local function sheatheLogLine(chunk, x0, y0, z0, x1, y1, z1, leavesId)
  local steps=math.max(math.abs(x1-x0),math.abs(y1-y0),math.abs(z1-z0),1)
  for step=0,steps do
    local t=step/steps
    local x=math.floor(x0+(x1-x0)*t+0.5)
    local y=math.floor(y0+(y1-y0)*t+0.5)
    local z=math.floor(z0+(z1-z0)*t+0.5)
    for _,direction in ipairs(BRANCH_SHEATH_DIRECTIONS) do
      setIfNotOpaque(chunk,x+direction[1],y+direction[2],z+direction[3],leavesId)
    end
  end
end

local function addOrganicLeafCluster(chunk, cx, cy, cz, rx, ry, rz, leavesId, seedX, seedZ, salt)
  for y=math.floor(cy-ry),math.ceil(cy+ry) do
    local dy=(y-cy)/math.max(ry,0.5)
    for lx=math.floor(cx-rx),math.ceil(cx+rx) do
      local dx=(lx-cx)/math.max(rx,0.5)
      for lz=math.floor(cz-rz),math.ceil(cz+rz) do
        local dz=(lz-cz)/math.max(rz,0.5)
        local distance=dx*dx+dy*dy+dz*dz
        local irregular=0.92+hash2(seedX+lx*3+y,seedZ+lz*5-y,salt)*0.25
        if distance<=irregular and (distance<0.84 or hash2(seedX+lx,seedZ+lz,salt+y*13)>0.035) then
          setIfNotOpaque(chunk,lx,y,lz,leavesId)
        end
      end
    end
  end
end

local function addLeafBridge(chunk, x0, y0, z0, x1, y1, z1, leavesId, seedX, seedZ, salt, radius)
  local steps=math.max(math.abs(x1-x0),math.abs(y1-y0),math.abs(z1-z0),1)
  for step=1,steps-1 do
    local t=step/steps
    local cx=math.floor(x0+(x1-x0)*t+0.5)
    local cy=math.floor(y0+(y1-y0)*t+0.5)+1
    local cz=math.floor(z0+(z1-z0)*t+0.5)
    addOrganicLeafCluster(chunk,cx,cy,cz,radius,1.05,radius,leavesId,seedX,seedZ,salt+step*17)
  end
end

local function addClassicOakTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, generator)
  local trunkHeight=(generator=="forest" and 6 or 5)+randomInt(treeX,treeZ,257,3)
  local logId = blocks.oak_log or blocks.oak_planks or blocks.dirt
  local logXId = blocks.oak_log_x or logId
  local logZId = blocks.oak_log_z or logId
  local leavesId = blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ
  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)
  local bendIndex=randomInt(treeX,treeZ,259,8)+1
  local bend=TREE_DIRECTIONS[bendIndex]
  local bendStart=trunkHeight-2
  local topX,topZ=localTreeX,localTreeZ
  for level=1,trunkHeight do
    if level>bendStart and generator=="forest" then
      topX=localTreeX+math.floor(bend[1]*(level-bendStart)/2+0.5)
      topZ=localTreeZ+math.floor(bend[2]*(level-bendStart)/2+0.5)
    end
    setLogIfReplaceable(chunk,topX,groundY+level,topZ,logId)
  end

  local topY=groundY+trunkHeight
  addOrganicLeafCluster(chunk,topX,topY,topZ,2.5,2.0,2.5,leavesId,treeX,treeZ,271)
  addOrganicLeafCluster(chunk,topX,topY+1,topZ,1.7,1.35,1.7,leavesId,treeX,treeZ,273)

  local branchCount=2+randomInt(treeX,treeZ,275,3)
  local directionStart=randomInt(treeX,treeZ,277,8)
  for branch=1,branchCount do
    local direction=TREE_DIRECTIONS[(directionStart+(branch-1)*2)%8+1]
    local reach=2+randomInt(treeX+branch,treeZ-branch,279,2)
    local startY=topY-2+((branch-1)%2)
    local endX=topX+direction[1]*reach
    local endZ=topZ+direction[2]*reach
    local endY=startY+1+randomInt(treeX-branch,treeZ+branch,281,2)
    addLogLine(chunk,topX,startY,topZ,endX,endY,endZ,logId,logXId,logZId)
    sheatheLogLine(chunk,topX,startY,topZ,endX,endY,endZ,leavesId)
    addLeafBridge(chunk,topX,startY,topZ,endX,endY,endZ,leavesId,treeX,treeZ,283+branch*29,1.35)
    addOrganicLeafCluster(chunk,endX,endY+1,endZ,2.05,1.60,2.05,leavesId,treeX,treeZ,283+branch*7)
  end
end

local function addBigTreeCluster(chunk, centerX, centerY, centerZ, leavesId, treeX, treeZ)
  -- Seed canopy irregularity from world coordinates. Local chunk coordinates
  -- change for the same tree when it is rebuilt by a neighbouring chunk.
  addOrganicLeafCluster(chunk,centerX,centerY+1,centerZ,3.65,2.35,3.65,leavesId,treeX,treeZ,337+centerY)
end

local function addBigTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  local heightLimit=11+randomInt(treeX,treeZ,263,6)
  local trunkHeight=heightLimit-2
  local logId = blocks.oak_log or blocks.oak_planks or blocks.dirt
  local logXId = blocks.oak_log_x or logId
  local logZId = blocks.oak_log_z or logId
  local leavesId = blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ
  local crownBase=groundY+heightLimit-3
  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)

  local broadTrunk=heightLimit>=16
  for level=1,trunkHeight do
    setLogIfReplaceable(chunk,localTreeX,groundY+level,localTreeZ,logId)
    if broadTrunk and level<trunkHeight-4 then
      setLogIfReplaceable(chunk,localTreeX+1,groundY+level,localTreeZ,logId)
      if level<trunkHeight-7 then setLogIfReplaceable(chunk,localTreeX,groundY+level,localTreeZ+1,logId) end
    end
  end
  addBigTreeCluster(chunk,localTreeX,crownBase,localTreeZ,leavesId,treeX,treeZ)
  addOrganicLeafCluster(chunk,localTreeX,crownBase+3,localTreeZ,2.3,2.0,2.3,leavesId,treeX,treeZ,347)

  local branchCount=6+randomInt(treeX,treeZ,267,3)
  local startDirection=randomInt(treeX,treeZ,269,8)
  for branch=1,branchCount do
    local direction=TREE_DIRECTIONS[(startDirection+branch*3)%8+1]
    local tier=(branch-1)%3
    local reach=3+randomInt(treeX+branch,treeZ-branch,273,3)
    local startY=crownBase-4+tier*2
    local endX=localTreeX+direction[1]*reach
    local endZ=localTreeZ+direction[2]*reach
    local endY=startY+1+randomInt(treeX-branch,treeZ+branch,277,3)
    addLogLine(chunk,localTreeX,startY,localTreeZ,endX,endY,endZ,logId,logXId,logZId)
    sheatheLogLine(chunk,localTreeX,startY,localTreeZ,endX,endY,endZ,leavesId)
    addLeafBridge(chunk,localTreeX,startY,localTreeZ,endX,endY,endZ,leavesId,treeX,treeZ,359+branch*31,1.55)
    addOrganicLeafCluster(chunk,endX,endY+1,endZ,2.6,1.85,2.6,leavesId,treeX,treeZ,359+branch*11)
    if branch%2==0 then
      local side=TREE_DIRECTIONS[(startDirection+branch*3+1)%8+1]
      local splitX=endX+side[1]*2 local splitZ=endZ+side[2]*2
      addLogLine(chunk,endX,endY,endZ,splitX,endY+1,splitZ,logId,logXId,logZId)
      sheatheLogLine(chunk,endX,endY,endZ,splitX,endY+1,splitZ,leavesId)
      addLeafBridge(chunk,endX,endY,endZ,splitX,endY+1,splitZ,leavesId,treeX,treeZ,401+branch*37,1.25)
      addOrganicLeafCluster(chunk,splitX,endY+2,splitZ,1.9,1.45,1.9,leavesId,treeX,treeZ,401+branch*13)
    end
  end
end

local function addSpruceTree(chunk,offsetX,offsetZ,treeX,treeZ,groundY,broad)
  local height=(broad and 10 or 12)+randomInt(treeX,treeZ,281,broad and 5 or 6)
  local bareHeight=(broad and 3 or 5)+randomInt(treeX,treeZ,283,3)
  local maxRadius=(broad and 4 or 3)+randomInt(treeX,treeZ,287,2)
  local logId = blocks.spruce_log or blocks.oak_log or blocks.oak_planks or blocks.dirt
  local logXId = blocks.spruce_log_x or logId
  local logZId = blocks.spruce_log_z or logId
  local leavesId = blocks.spruce_leaves or blocks.oak_leaves or blocks.grass
  local localTreeX = treeX - offsetX
  local localTreeZ = treeZ - offsetZ
  setLocalBlock(chunk, localTreeX, groundY, localTreeZ, blocks.dirt or logId)
  for level=1,height do setLogIfReplaceable(chunk,localTreeX,groundY+level,localTreeZ,logId) end

  local crownBottom=groundY+bareHeight
  local crownTop=groundY+height
  for y=crownBottom,crownTop do
    local fromTop=crownTop-y
    local envelope=math.min(maxRadius,1+math.floor(fromTop*(broad and 0.46 or 0.36)))
    local tier=fromTop%3
    local radius=math.max(0,envelope-(tier==2 and 1 or 0))
    if fromTop<=1 then radius=fromTop end
    for lx=localTreeX-radius,localTreeX+radius do
      local dx=lx-localTreeX
      for lz=localTreeZ-radius,localTreeZ+radius do
        local dz=lz-localTreeZ
        local distance=dx*dx+dz*dz
        local limit=(radius+0.35)*(radius+0.35)
        local noise=hash2(treeX+dx*7+y,treeZ+dz*11-y,313)
        if distance<=limit and (distance<radius*radius*0.55 or noise>0.12) then
          setIfNotOpaque(chunk,lx,y,lz,leavesId)
        end
      end
    end

    if tier==0 and radius>=2 then
      local rotation=randomInt(treeX+y,treeZ-y,317,2)
      for branch=0,3 do
        local direction=TREE_DIRECTIONS[((branch*2+rotation)%8)+1]
        local reach=math.max(1,radius-1)
        addLogLine(chunk,localTreeX,y,localTreeZ,localTreeX+direction[1]*reach,y,localTreeZ+direction[2]*reach,logId,logXId,logZId)
        sheatheLogLine(chunk,localTreeX,y,localTreeZ,localTreeX+direction[1]*reach,y,localTreeZ+direction[2]*reach,leavesId)
      end
    end
  end
  addOrganicLeafCluster(chunk,localTreeX,crownTop,localTreeZ,1.15,1.8,1.15,leavesId,treeX,treeZ,331)
end

local function addTaiga1Tree(chunk,offsetX,offsetZ,treeX,treeZ,groundY)
  addSpruceTree(chunk,offsetX,offsetZ,treeX,treeZ,groundY,false)
end

local function addTaiga2Tree(chunk,offsetX,offsetZ,treeX,treeZ,groundY)
  addSpruceTree(chunk,offsetX,offsetZ,treeX,treeZ,groundY,true)
end

local function addTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, biome)
  local profile = biomeProfiles[biome] or biomeProfiles.plains
  local generator = chooseTreeGenerator(profile, treeX, treeZ)
  if generator == "taiga1" then
    addTaiga1Tree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  elseif generator == "taiga2" then
    addTaiga2Tree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  elseif generator == "big" then
    addBigTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY)
  else
    addClassicOakTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, generator)
  end
end

local foliageProfiles = {
  rainforest = {grass = 0.42, doubleGrass = 0.055},
  swampland = {grass = 0.22, doubleGrass = 0.020},
  seasonalForest = {grass = 0.36, doubleGrass = 0.040},
  savanna = {grass = 0.20, doubleGrass = 0.012},
  shrubland = {grass = 0.28, doubleGrass = 0.020},
  plains = {grass = 0.44, doubleGrass = 0.048},
  forest = {grass = 0.32, doubleGrass = 0.030},
  -- Temperate taiga supports a continuous grassy understory. The old 0.16
  -- baseline combined with low patch noise could leave entire green hills bare.
  taiga = {grass = 0.34, doubleGrass = 0.020},
  mountains = {grass = 0.18, doubleGrass = 0.010}
}

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
      if foliage then
        local groundY, groundId = surfaceYForFoliage(chunk, x, z, maxHeight)
        if groundY and groundId == blocks.grass and groundY + 1 <= maxHeight and isPlantAir(chunk:getBlock(x, groundY + 1, z)) then
          -- The macro river/lake fields remain broad around coastal terrain and
          -- used to erase vegetation even when the final surface was dry grass.
          -- Block/material checks already exclude water and sand, so wetness is
          -- only a mild shoreline bias here, never a zero-density veto.
          local wetness = clamp(math.max(column.river or 0.0, column.lake or 0.0), 0.0, 1.0)
          local waterClearance = lerp(1.0, 0.72, wetness)
          local patchNoise = fbm(worldX + 2600.0, worldZ - 1300.0, 887, 2, 0.055)
          local meadowNoise = fbm(worldX - 9800.0, worldZ + 4300.0, 889, 3, 0.0065)
          local density = foliage.grass * (settings.grassDensity or 1.35)
            * lerp(0.72, 1.35, patchNoise) * lerp(0.82, 1.12, meadowNoise) * waterClearance
          density = math.min(density, 0.92)
          if hash2(worldX, worldZ, 881) < density then
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

-- Planet terrain is sampled directly in 3D from the unit radial direction.
-- None of these signals use longitude/latitude, so there is no meridian seam
-- and no special polar case. Frequencies are expressed as approximate surface
-- wavelengths by scaling the unit vector with radius / wavelength.
local function sphericalFbm(direction, wavelengthMeters, seed, octaves, planet)
  local scale = planet.radiusMeters / wavelengthMeters
  return fbm3(direction[1] * scale, direction[2] * scale, direction[3] * scale, seed, octaves, 1.0)
end

-- fbm3 averages its octaves, so its output clusters hard around 0.5 instead of
-- filling [0, 1]. Measured standard deviation by octave count, over 20k
-- directions:
local FBM_SIGMA = {0.1857, 0.1364, 0.1217, 0.1131, 0.1106, 0.1079}

-- A signed signal normalised to roughly unit standard deviation, so an
-- amplitude written in metres below is the metres it actually delivers. The
-- clamp only bites on the far tail, about four sigma out.
local function sphericalSigned(direction, wavelengthMeters, seed, octaves, planet)
  local sigma = FBM_SIGMA[octaves] or FBM_SIGMA[#FBM_SIGMA]
  return clamp((sphericalFbm(direction, wavelengthMeters, seed, octaves, planet) - 0.5) / sigma, -4.0, 4.0)
end

local function sphericalBiome(temperature, rainfall, mountain, land)
  if land < 0.40 then return "ocean" end
  if mountain > 0.68 then return "mountains" end
  if temperature < 0.12 then return rainfall > 0.30 and "taiga" or "tundra" end
  if temperature > 0.78 and rainfall < 0.20 then return "desert" end
  if rainfall > 0.72 then return temperature > 0.72 and "rainforest" or "forest" end
  if rainfall < 0.30 then return temperature > 0.62 and "savanna" or "shrubland" end
  return rainfall > 0.52 and "forest" or "plains"
end

-- The elevation stack runs from continent width down to a wavelength of a few
-- voxels. The short end is the whole point: the loaded world is a ball of about
-- 96 m radius, so anything with a wavelength above a couple of kilometres is a
-- constant tilt from inside it. Measured before this stack existed, a 200 m
-- walk changed elevation by 0.9 m, which is why the ground read as a plane.
function terrain.surfaceAtDirection(direction, planet)
  local reliefGain = (terrain.RELIEF_GAIN or 2.4) / 2.4
  local localGain = (terrain.LOCAL_RELIEF_GAIN or 2.0) / 2.0

  local continent = sphericalSigned(direction, 2400000.0, 1103, 5, planet)
  local continentDetail = sphericalSigned(direction, 520000.0, 1117, 4, planet)
  local regional = sphericalSigned(direction, 62000.0, 1129, 4, planet)
  local upland = sphericalSigned(direction, 9200.0, 1289, 4, planet)
  local hills = sphericalSigned(direction, 1500.0, 1151, 4, planet)
  local knolls = sphericalSigned(direction, 430.0, 1301, 4, planet)
  local detail = sphericalSigned(direction, 115.0, 1163, 3, planet)
  local micro = sphericalSigned(direction, 36.0, 1307, 2, planet)
  local grain = sphericalSigned(direction, 14.0, 1319, 2, planet)
  local ridgeSignal = sphericalFbm(direction, 26000.0, 1171, 5, planet)
  local ridge = ridged(ridgeSignal)
  ridge = ridge * ridge

  local land = smoothstep(continent * 0.62 + continentDetail * 0.24 + 0.42)
  local landCore = smoothstep((land - 0.45) / 0.50)
  local mountainMask = smoothstep(ridge * (1.35 + regional * 0.45) - 0.42) * land
  local mountain = mountainMask

  -- Ruggedness decides whether the metre scale reads as prairie or as broken
  -- ground. Without it every biome gets identical roughness and the world is
  -- uniformly lumpy, which is as characterless as uniformly flat.
  local rugged = clamp(0.30 + mountainMask * 1.15 + smoothstep(upland * 0.8 + 0.5) * 0.55, 0.22, 2.0)

  -- The last two terms are what stop a gentle dome from voxelising into
  -- concentric contour rings. On a 1:20 slope 1.7 m of relief displaces a
  -- contour line by thirty metres, which turns the terraces into irregular
  -- patches instead of a wedding cake.
  local localRelief = (hills * 15.0 + knolls * 7.2 + detail * 2.3 + micro * 1.7 + grain * 0.6)
    * rugged * localGain

  local oceanFloor = (-165.0 + regional * 34.0 + upland * 12.0) * reliefGain + localRelief * 0.35
  -- The regional and upland terms are symmetric, so on their own they sink a
  -- fair share of every continent below sea level. softFloor lifts only the
  -- deep tail, turning a would-be hole into a broad low plain and leaving
  -- anything already above the datum untouched.
  local landBase = softFloor((8.0 + landCore * 38.0 + regional * 24.0 + upland * 15.0) * reliefGain, 1.5, 20.0)
  local peaks = mountainMask * mountainMask * (90.0 + ridge * 150.0) * reliefGain
  local landHeight = landBase + peaks + localRelief

  -- The shore is a separate, sharper blend than the continental mask so that
  -- beaches stay narrow instead of the coast being a hundred-kilometre ramp.
  local shore = smoothstep((land - 0.34) / 0.14)
  local elevationMeters = lerp(oceanFloor, landHeight, shore)
  elevationMeters = clamp(elevationMeters, planet.minTerrainElevationMeters, planet.maxTerrainElevationMeters)

  -- Inland water is owned by a local radial level.  Quantising the very
  -- low-frequency level field keeps each basin effectively level while the
  -- water surface itself remains a true sphere concentric with the planet.
  -- Across a lake-sized footprint Earth curvature is only millimetres, which
  -- is exactly the visually-flat/local-but-globally-spherical behaviour wanted.
  local lakeNoise = sphericalFbm(direction, 26000.0, 1181, 4, planet)
  local lakeLevelNoise = sphericalFbm(direction, 310000.0, 1187, 3, planet)
  local lakeLevelMeters = 6.0 + floor(lakeLevelNoise * 8.0) * 4.0
  local inland = smoothstep((land - 0.58) / 0.18)
  local heightFit = 1.0 - smoothstep((abs(elevationMeters - lakeLevelMeters) - 9.0) / 18.0)
  local lakeStrength = smoothstep((lakeNoise - 0.70) / 0.13) * inland * heightFit * (1.0 - mountain)
  local waterKind, waterSurfaceRadiusVoxels
  if lakeStrength > 0.08 then
    elevationMeters = lerp(elevationMeters, lakeLevelMeters - 3.2, smoothstep(lakeStrength) * 0.94)
    waterKind = "lake"
    waterSurfaceRadiusVoxels = planet.radiusVoxels + lakeLevelMeters / planet.voxelSizeMeters
  end

  local latitudeTemperature = 1.0 - abs(direction[2])
  local climateNoise = sphericalFbm(direction, 720000.0, 1193, 4, planet)
  local rainfallNoise = sphericalFbm(direction, 510000.0, 1201, 4, planet)
  -- Cooling with height is per metre, so it has to be retuned whenever the
  -- elevation range moves. At 0.0025 the new peaks came out 0.75 colder, which
  -- made everything above 400 m arctic.
  local temperature = clamp(latitudeTemperature * 0.78 + climateNoise * 0.38 - math.max(0.0, elevationMeters) * 0.0009, 0.0, 1.0)
  local rainfall = clamp(rainfallNoise * 0.88 + sphericalFbm(direction, 92000.0, 1213, 3, planet) * 0.22 - 0.05, 0.0, 1.0)
  local biome = sphericalBiome(temperature, rainfall, mountain, land)
  if land >= 0.36 and land < 0.48 and elevationMeters < 5.0 then
    biome = temperature < 0.16 and "frozenShore" or "beach"
  end

  return {
    elevationMeters = elevationMeters,
    surfaceRadiusVoxels = planet.radiusVoxels + elevationMeters / planet.voxelSizeMeters,
    biome = biome,
    profile = biomeProfiles[biome] or biomeProfiles.plains,
    temperature = temperature,
    rainfall = rainfall,
    land = land,
    mountain = mountain,
    ruggedness = rugged,
    lake = lakeStrength,
    waterKind = waterKind,
    waterLevelMeters = waterKind and lakeLevelMeters or planet.seaLevelOffsetMeters,
    waterSurfaceRadiusVoxels = waterSurfaceRadiusVoxels,
    hasSnow = temperature < 0.15 and elevationMeters > planet.seaLevelOffsetMeters
  }
end

function terrain.surfaceAtPosition(x, y, z, planet)
  local rx, ry, rz = x - planet.center[1], y - planet.center[2], z - planet.center[3]
  local distance = math.sqrt(rx * rx + ry * ry + rz * rz)
  if distance == 0.0 then
    return terrain.surfaceAtDirection({0.0, 1.0, 0.0}, planet), 0.0, {0.0, 1.0, 0.0}
  end
  local direction = {rx / distance, ry / distance, rz / distance}
  return terrain.surfaceAtDirection(direction, planet), distance, direction
end

function terrain.biomeAtPosition(x, y, z, planet)
  local sample = terrain.surfaceAtPosition(x, y, z, planet)
  return sample.biome
end

function terrain.grassColorAtPosition(x, y, z, planet)
  local sample = terrain.surfaceAtPosition(x, y, z, planet)
  return sampleGrassColor(sample.temperature, sample.rainfall)
end

local function sphericalSurfaceBlocks(sample)
  local profile = sample.profile or biomeProfiles.plains
  local top = blocks[profile.topBlock] or blocks.grass or blocks.stone
  local filler = blocks[profile.fillerBlock] or blocks.dirt or blocks.stone
  local under = blocks.stone
  if sample.biome == "ocean" or sample.biome == "beach" or sample.biome == "desert" then
    top = blocks.sand or top
    filler = blocks.sand or filler
    under = blocks.sandstone or blocks.stone
  elseif sample.biome == "rockyShore" or sample.biome == "frozenShore" then
    top = blocks.gravel or blocks.stone
    filler = sample.biome == "rockyShore" and blocks.stone or (blocks.dirt or blocks.stone)
  end
  return top, filler, under
end

local function sphericalCaveAt(x, y, z, depthVoxels, planet)
  if depthVoxels < 5.0 or depthVoxels > planet.generatedInteriorDepthMeters / planet.voxelSizeMeters then
    return false
  end
  local large = fbm3(x, y, z, 1231, 3, 0.010)
  local tunnel = fbm3(x + 3100.0, y - 1700.0, z + 730.0, 1249, 3, 0.028)
  local detail = fbm3(x - 910.0, y + 2400.0, z - 1800.0, 1259, 2, 0.061)
  local threshold = depthVoxels < 16.0 and 0.78 or 0.70
  return large * 0.42 + tunnel * 0.43 + detail * 0.15 > threshold
end

local function decoratePlanetChunk(chunk, offsetX, offsetY, offsetZ, planet)
  local grassId = blocks.tall_grass
  local logId = blocks.oak_log or blocks.spruce_log
  local leavesId = blocks.oak_leaves or blocks.spruce_leaves
  if not grassId and not (logId and leavesId) then return end

  local function inChunk(x, y, z)
    return x >= 0 and x < 16 and y >= 0 and y < 16 and z >= 0 and z < 16
  end

  for x = 0, 15 do
    for y = 0, 15 do
      for z = 0, 15 do
        local id = chunk:getBlock(x, y, z)
        if id == blocks.grass or id == blocks.sand or id == blocks.gravel then
          local wx, wy, wz = offsetX + x + 0.5, offsetY + y + 0.5, offsetZ + z + 0.5
          local ux, uy, uz = planet:dominantUpStep({wx, wy, wz})
          local orientedLogId=logId
          if ux~=0 then orientedLogId=blocks.oak_log_x or blocks.spruce_log_x or logId
          elseif uz~=0 then orientedLogId=blocks.oak_log_z or blocks.spruce_log_z or logId end
          local nx, ny, nz = x + ux, y + uy, z + uz
          if inChunk(nx, ny, nz) and chunk:getBlock(nx, ny, nz) == (blocks.air or 0) then
            local rootHash = hash3(offsetX + x, offsetY + y, offsetZ + z, 1277)
            local sample = terrain.surfaceAtPosition(wx, wy, wz, planet)
            local wooded = sample.biome == "forest" or sample.biome == "rainforest" or sample.biome == "taiga"
            if grassId and id == blocks.grass and rootHash < 0.075 then
              chunk:setBlock(nx, ny, nz, grassId)
            elseif wooded and logId and leavesId and rootHash > 0.9975 then
              local height = 4 + math.floor(hash3(offsetX + x, offsetY + y, offsetZ + z, 1283) * 3)
              local topX, topY, topZ = nx, ny, nz
              local fits = true
              for level = 0, height - 1 do
                local tx, ty, tz = nx + ux * level, ny + uy * level, nz + uz * level
                if not inChunk(tx, ty, tz) then fits = false break end
              end
              if fits then
                for level = 0, height - 1 do
                  topX, topY, topZ = nx + ux * level, ny + uy * level, nz + uz * level
                  chunk:setBlock(topX,topY,topZ,orientedLogId)
                end
                for lx = topX - 2, topX + 2 do
                  for ly = topY - 2, topY + 2 do
                    for lz = topZ - 2, topZ + 2 do
                      if inChunk(lx, ly, lz) and chunk:getBlock(lx, ly, lz) == (blocks.air or 0) then
                        local dx, dy, dz = lx - topX, ly - topY, lz - topZ
                        if dx * dx + dy * dy + dz * dz <= 5 then
                          chunk:setBlock(lx, ly, lz, leavesId)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

function terrain.fillPlanetChunk(chunk, offsetX, offsetY, offsetZ, planet, options)
  options = options or {}
  local step = options.yieldStep
  local waterId = blocks.water or blocks.water_still
  local airId = blocks.air or 0
  local processed = 0

  for x = 0, 15 do
    for y = 0, 15 do
      for z = 0, 15 do
        local wx, wy, wz = offsetX + x + 0.5, offsetY + y + 0.5, offsetZ + z + 0.5
        local sample, radialDistance = terrain.surfaceAtPosition(wx, wy, wz, planet)
        local depth = sample.surfaceRadiusVoxels - radialDistance
        if depth >= 0.0 and not sphericalCaveAt(wx, wy, wz, depth, planet) then
          local top, filler, under = sphericalSurfaceBlocks(sample)
          local id = depth < 1.25 and top or (depth < 5.0 and filler or (depth < 9.0 and under or blocks.stone))
          if sample.hasSnow and depth < 1.25 and blocks.snow then id = blocks.snow end
          chunk:setBlock(x, y, z, id or blocks.stone)
        elseif waterId and (radialDistance <= planet.seaLevelRadiusVoxels or
            (sample.waterSurfaceRadiusVoxels and radialDistance <= sample.waterSurfaceRadiusVoxels)) then
          chunk:setBlock(x, y, z, waterId)
        else
          chunk:setBlock(x, y, z, airId)
        end

        processed = processed + 1
        if step and processed % 256 == 0 then step() end
      end
    end
  end

  decoratePlanetChunk(chunk, offsetX, offsetY, offsetZ, planet)
  if step then step() end
end

function terrain.fillChunk(chunk, offsetX, offsetZ, width, depth, maxHeight, options)
  options = options or {}
  local step = options.yieldStep
  if options.generatorType == "superflat" then
    fillSuperflatChunk(chunk, width, depth, maxHeight, options.superflatLayers, step)
    return
  end

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
  populateOres(chunk, offsetX, offsetZ)
  if step then step() end
  carveChunkCaves(chunk, offsetX, offsetZ, maxHeight)
  if step then step() end

  -- Decorate from a halo as wide as the largest branch/crown reach. Every
  -- chunk evaluates the same world-space tree centers, so trees crossing a
  -- border continue naturally instead of being sliced into log poles.
  for x = -9, width + 8 do
    for z = -9, depth + 8 do
      local treeX = offsetX + x
      local treeZ = offsetZ + z
      local column = terrain.columnAt(treeX, treeZ, maxHeight)
      -- Always derive the root from the world-space column. Looking up the
      -- already-built surface only for centers inside this chunk made a border
      -- tree use a different root height when its crown was rebuilt next door.
      local groundY = column.height

      if groundY and not column.waterLevel and groundY > terrain.SEA_LEVEL + 1 and
          isTreeCenter(treeX, treeZ, column.biome) then
        addTree(chunk, offsetX, offsetZ, treeX, treeZ, groundY, column.biome, maxHeight)
      end
    end
    if step then step() end
  end

  populateGrassFoliage(chunk, offsetX, offsetZ, width, depth, maxHeight, step)
end

return terrain
