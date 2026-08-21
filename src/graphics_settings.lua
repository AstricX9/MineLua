local graphics = {}

graphics.window = {
  width = 1280,
  height = 720,
  fovDegrees = 70,
  -- false uncaps the frame rate, so the debug screen shows true frame cost
  -- rather than the display refresh interval.
  vsync = true
}

graphics.player = {
  eyeHeight = 1.62,
  crouchEyeHeight = 1.24,
  radius = 0.30,
  walkSpeed = 5.1,
  sprintSpeed = 7.2,
  crouchSpeed = 2.4,
  flySpeed = 9.5,
  acceleration = 34.0,
  airAcceleration = 8.0,
  flyAcceleration = 24.0,
  groundFriction = 38.0,
  airFriction = 2.0,
  flyFriction = 18.0,
  gravity = 19.5,
  jumpSpeed = 6.4,
  stepHeight = 1.08,
  groundSnap = 0.36,
  coyoteTime = 0.10,
  jumpBufferTime = 0.12,
  mouseSensitivity = 0.085,
  reach = 6.0,
  showDebugBody = false
}

graphics.world = {
  terrainMaxHeight = 127,
  chunkRenderRadius = 4,
  visualDistance = 192.0
}

graphics.performance = {
  -- Safety cap only; terrainFrameBudgetMs is what actually limits the frame.
  -- Generation yields every 4 columns now, so this must be high enough that the
  -- step count never binds before the time budget does.
  terrainWorkBudget = 64,
  -- ~9 chunks arrive per chunk-border crossing at about 120 ms each, so keeping
  -- up needs ~340 ms/s walking and ~470 ms/s flying. 8 ms/frame covers both at
  -- 60 fps. Raise to stream faster, lower for steadier frames.
  terrainFrameBudgetMs = 8.0,
  chunkQueueBudget = 4,
  chunkQueueBacklog = 16,
  lightingStepBudget = 10,
  loadingChunkBudget = 2,
  loadingLightingStepBudget = 14,
  loadingMeshBudget = 2,
  loadingRequiredRadius = 1,
  loadingHaloRadius = 2,
  initialSpawnRadius = 1
}

graphics.atmosphere = {
  fogStart = 220.0,
  fogEnd = 1250.0,
  sunCycleSpeed = 0.005235987755982989,
  skyColor = {0.53, 0.81, 0.92},
  skyExposure = 0.62,
  cloudDensity = 1.35,
  cloudBottom = 132.0,
  cloudTop = 136.0,
  sunGlare = 0.58,
  maxFogAmount = 0.58,
  heightFogDensity = 0.08,
  heightFogFalloff = 0.080,
  horizonFog = 0.10,
  sunScatter = 0.45
}

-- Post-processing / colour grading. The scene renders to a half-float target,
-- so values above 1.0 survive to be bloomed and tone mapped instead of clipping.
-- Defaults are deliberately neutral: exposure, saturation and contrast are all
-- identity, and the tone curve does nothing below its knee. The scene was
-- already authored to look right, so grading must only handle the overbrights
-- the HDR target newly preserves. Anything punchier is a taste choice to dial
-- in from here, not a starting point.
graphics.post = {
  bloom = true,
  bloomThreshold = 0.85,   -- scene brightness where bloom starts
  bloomSoftKnee = 0.60,    -- 0 = hard cutoff, 1 = very gradual
  bloomStrength = 0.06,    -- how much bloom is added back
  bloomRadius = 1.0,       -- tent filter spread during upsample
  bloomLevels = 6,         -- mip chain depth; more = wider glow
  bloomClamp = 12.0,       -- guards against fireflies from very bright pixels

  -- "rolloff" = identity below the knee, compress above (recommended)
  -- "aces"    = filmic, scene-referred, adds its own contrast and saturation
  -- false     = no tone mapping at all
  tonemap = "rolloff",
  tonemapKnee = 0.80,      -- below this, pixels pass through untouched
  tonemapWhite = 2.2,      -- value that maps to display white

  exposure = 1.0,
  saturation = 1.0,
  contrast = 1.0
}

-- Physical sky: Rayleigh + Mie single scattering, marched per pixel. Sample
-- counts are compiled into the shader, so changing them needs a restart.
graphics.sky = {
  scatterViewSamples = 16,   -- steps along the view ray
  scatterLightSamples = 8,   -- steps along each ray toward the sun
  -- Brightness knob. The sun intensity below is in arbitrary units, so absolute
  -- radiance is not calibrated to anything; 2.5 puts the zenith at roughly the
  -- brightness the previous authored gradient had. Lower for a deeper, more
  -- literal sky, higher for a brighter one.
  scatterStrength = 2.5,
  sunIntensity = 22.0        -- radiance of the sun before scattering
}

graphics.terrain = {
  exposure = 1.04,
  topLight = 1.00,
  sideLight = 0.82,
  bottomLight = 0.58
}

graphics.shadows = {
  mapSize = 2048,
  distance = 60.0,
  near = 8.0,
  far = 132.0
}

graphics.water = {
  level = 62.65,
  radius = 1024.0
}

graphics.terrainGeneration = {
  seed = 1,
  seaLevel = 63,
  continentScale = 0.00036,
  biomeScale = 0.00092,
  regionScale = 0.00125,
  mountainScale = 0.00078,
  riverScale = 0.00115,
  forestScale = 0.00165,
  macroWarpScale = 0.00062,
  macroWarpAmount = 360.0,
  detailScale = 0.026,
  reliefGain = 2.4,
  localReliefGain = 2.0,
  grassTintStrength = 0.92,
  treeDensity = 0.78
}

local function isArray(value)
  return type(value) == "table" and value[1] ~= nil
end

local function mergeSettings(target, source)
  if type(source) ~= "table" then
    return target
  end

  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" and not isArray(value) then
      mergeSettings(target[key], value)
    else
      target[key] = value
    end
  end

  return target
end

local function loadSettings(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, decoded = pcall(require("json").decode, content)
  if ok and type(decoded) == "table" then
    return decoded
  end

  io.stderr:write("Skipping invalid settings file: " .. path .. "\n")
  return nil
end

mergeSettings(graphics, loadSettings("data/settings.json"))

return graphics
