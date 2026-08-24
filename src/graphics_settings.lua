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
  -- Acceleration changes speed only. Input direction is applied immediately so
  -- mouse turns and key changes do not steer the player through a circular arc.
  acceleration = 55.0,
  airAcceleration = 14.0,
  flyAcceleration = 24.0,
  groundFriction = 46.0,
  airFriction = 2.0,
  flyFriction = 18.0,
  gravity = 19.5,
  -- Clears a full voxel with margin after discrete gravity integration.
  jumpSpeed = 7.4,
  stepHeight = 0.60,
  swimUpSpeed = 4.6,
  swimSinkSpeed = 0.65,
  swimAcceleration = 18.0,
  groundSnap = 0.36,
  coyoteTime = 0.10,
  jumpBufferTime = 0.12,
  mouseSensitivity = 0.085,
  reach = 6.0,
  showDebugBody = false
}

graphics.world = {
  terrainMaxHeight = 127,
  chunkRenderRadius = 8,
  -- Default menu Render Distance. This is a square outer chunk range; chunks
  -- fill progressively from the local full-detail radius to this LOD horizon.
  distantChunkRadius = 24,
  visualDistance = 320.0
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
  distantGenerationSteps = 8,
  distantBuildBudget = 2,
  distantFrameBudgetMs = 3.0,
  distantQueueRingBudget = 4,
  lightingStepBudget = 10,
  loadingChunkBudget = 2,
  loadingLightingStepBudget = 14,
  loadingMeshBudget = 2,
  loadingRequiredRadius = 1,
  loadingHaloRadius = 2,
  initialSpawnRadius = 1
}

graphics.atmosphere = {
  -- Visibility range for homogeneous aerial extinction. Height fog begins
  -- immediately at low altitude; these distances control the broader haze.
  fogStart = 48.0,
  fogEnd = 360.0,
  sunCycleSpeed = 0.005235987755982989,
  skyColor = {0.53, 0.81, 0.92},
  skyExposure = 0.62,
  cloudDensity = 1.35,
  cloudBottom = 132.0,
  cloudTop = 136.0,
  sunGlare = 0.58,
  maxFogAmount = 0.72,
  -- Extinction per block at sea level and its exponential falloff with height.
  heightFogDensity = 0.0045,
  heightFogFalloff = 0.055,
  horizonFog = 0.24,
  sunScatter = 0.65,
  -- Frustum-aligned froxel volume. XY is one cell per 8x8 pixels at 1280x720;
  -- logarithmic Z slices keep detail close to the camera.
  volumetricGridWidth = 160,
  volumetricGridHeight = 90,
  volumetricGridDepth = 64,
  volumetricNear = 0.5,
  volumetricFar = 360.0
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
  sunIntensity = 22.0,       -- radiance of the sun before scattering

  -- The sun is a limb-darkened disc shaded through the same atmosphere as the
  -- sky, not a sprite. Its true angular radius is 0.00465 rad -- about half a
  -- degree across, roughly seven pixels at this field of view -- which is
  -- correct but reads as a speck in a blocky world. This is enlarged; set it to
  -- 0.00465 for the literal size.
  sunAngularRadius = 0.012,
  -- Radiance of the disc, in the units the sky lands in after its own tone map.
  -- The scene target is half-float, so anything above 1.0 survives to be
  -- bloomed; this is what gives the sun its glow.
  sunDiscBrightness = 9.0
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

-- Real dielectric constants for transmissive voxel materials. The renderer
-- uses these with Fresnel reflection, Beer-Lambert absorption, refraction and
-- a GGX highlight instead of treating ice/glass as tinted opaque stone.
graphics.dielectrics = {
  ice = {
    ior = 1.31,
    roughness = 0.16,
    absorption = {0.045, 0.018, 0.008},
    refractionStrength = 0.010,
    cloudiness = 0.72
  },
  glass = {
    ior = 1.52,
    roughness = 0.035,
    absorption = {0.008, 0.004, 0.002},
    refractionStrength = 0.006,
    cloudiness = 0.04
  }
}

graphics.water = {
  level = 62.65,
  fftResolution = 256,
  fftOceanSize = 256.0,
  windSpeed = 11.0,
  windAngleDegrees = 45.0,
  -- Keep the silhouette rolling rather than folding into sharp triangular
  -- peaks. Fine normal detail still supplies lively small ripples.
  choppiness = 0.88,
  displacementScale = 1.0,
  nearTessellation = 2,
  -- Reuse the physically evolved FFT field at three decorrelated world scales.
  -- The smallest two chiefly provide surface detail; the largest carries swell.
  cascadeSizes = {36.0, 144.0, 576.0},
  cascadeDisplacementWeights = {0.075, 0.16, 0.40},
  cascadeNormalWeights = {0.48, 0.29, 0.16},
  -- Stable world-space fetch makes open ocean strongest without changing when
  -- the camera turns. Enclosed water keeps animated short ripples.
  openWaterWaveBoost = 1.08,
  refractionStrength = 0.014,
  -- Project FFT-driven light concentration onto submerged voxel faces.
  causticStrength = 0.42,
  -- Beer-Lambert absorption per metre: red disappears first in natural water.
  absorption = {0.16, 0.055, 0.026}
}

graphics.terrainGeneration = {
  seed = 1,
  seaLevel = 63,
  continentScale = 0.0025,
  continentSize = 1.0,
  biomeScale = 0.00092,
  regionScale = 0.00125,
  mountainScale = 0.00078,
  mountainFrequency = 1.0,
  riverScale = 0.00115,
  forestScale = 0.00165,
  macroWarpScale = 0.00062,
  macroWarpAmount = 360.0,
  detailScale = 0.026,
  continentThreshold = 0.455,
  continentFragmentation = 0.28,
  continentalShelfWidth = 0.115,
  terrainVerticalScale = 1.0,
  oceanDepthScale = 42.0,
  mountainHeight = 49.0,
  foothillHeight = 9.0,
  plateauFrequency = 0.18,
  plateauHeight = 18.0,
  basinDepth = 9.0,
  reliefGain = 2.4,
  localReliefGain = 2.0,
  -- Procedural erosion approximation. It damps short-wavelength relief and
  -- rounds mountain crests without changing the continent layout.
  erosionStrength = 0.28,
  riverCarveStrength = 0.86,
  lakeCarveStrength = 0.78,
  mountainSharpness = 1.65,
  shorelineWidth = 7.0,
  rockyShoreThreshold = 0.46,
  biomeClimateInfluence = 0.34,
  snowTemperature = 0.18,
  snowMinElevation = 12.0,
  elevationCooling = 0.0045,
  altitudeLapseRate = 0.0045,
  globalTemperatureOffset = 0.0,
  equatorTemperature = 0.96,
  poleTemperature = 0.06,
  temperatureNoiseStrength = 0.16,
  continentalTemperatureStrength = 0.08,
  climateLatitudeScale = 0.000075,
  globalMoistureOffset = 0.0,
  rainfallScale = 1.0,
  rainShadowStrength = 0.42,
  rainShadowSampleDistance = 420.0,
  prevailingWindAngle = 0.35,
  freezeTemperature = 0.08,
  riverDensity = 1.0,
  riverFrequency = 1.0,
  riverGridSize = 56.0,
  riverMinimumAccumulation = 5.5,
  riverAccumulationDepth = 56,
  riverWidthScale = 0.72,
  lakeFrequency = 0.20,
  lakeMinimumAccumulation = 4.0,
  volcanism = 0.35,
  volcanicFeatureScale = 0.00042,
  volcanoHeight = 36.0,
  calderaDepth = 14.0,
  geologicalFeatureFrequency = 0.20,
  surfaceDetailStrength = 1.0,
  worldWaterEnabled = true,
  grassTintStrength = 0.92,
  treeDensity = 0.95,
  grassDensity = 1.25
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

mergeSettings(graphics, loadSettings("data/config/settings.json"))

return graphics
