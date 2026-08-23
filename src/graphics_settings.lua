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
  gravity = 9.81,
  jumpSpeed = 6.4,
  stepHeight = 1.08,
  groundSnap = 0.36,
  coyoteTime = 0.10,
  jumpBufferTime = 0.12,
  mouseSensitivity = 0.085,
  reach = 6.0,
  -- Any standard 64x64 Java Edition skin can be dropped here. Use "slim"
  -- for three-pixel Alex arms and "classic" for four-pixel Steve arms.
  skinPath = "assets/textures/entity/steve.png",
  skinModel = "classic",
  showDebugBody = false
}

graphics.world = {
  terrainMaxHeight = 127,
  chunkRenderRadius = 8,
  -- The loaded region is an ellipsoid around the player, wide across the ground
  -- and shallow through it. It must reach past chunkRenderRadius, or the
  -- renderer draws to where the world stops existing.
  chunkLoadRadius = 9,
  chunkLoadRadiusVertical = 5,
  -- Voxels are individually rotated so their local up is radial, addressed on
  -- a cube-sphere. See src/spherical_grid.lua. Set false for the old globally
  -- aligned Cartesian lattice.
  sphericalVoxels = true,
  -- Column stacks kept loaded around the player, in 16-voxel chunks.
  gridLoadRadius = 6,
  visualDistance = 320.0
}

graphics.planet = {
  center = {0.0, 0.0, 0.0},
  radiusMeters = 6371000.0,
  voxelSizeMeters = 1.0,
  seaLevelOffsetMeters = 0.0,
  gravityAcceleration = 9.81,
  minTerrainElevationMeters = -96.0,
  maxTerrainElevationMeters = 160.0,
  generatedInteriorDepthMeters = 192.0,
  renderOriginGridMeters = 256.0
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

-- The astronomical model behind day and night. See src/celestial.lua: the sun
-- is one astronomical unit away and 696,000 km across, and the sky turns
-- because the planet does. dayLengthSeconds is the only speed control -- 3600
-- gives thirty minutes of daylight and thirty of night at the equator.
graphics.celestial = {
  dayLengthSeconds = 3600.0,
  yearLengthSeconds = 3600.0 * 365.25,
  axialTiltRadians = 0.40910517666747087,
  orbitRadiusMeters = 149597870700.0,
  sunRadiusMeters = 695700000.0,
  -- Start mid-morning rather than in the dark. A spawn near longitude 90
  -- reads about 09:00 at this phase.
  rotationPhase = 0.125,
  orbitPhase = 0.0,
  -- Multiplies the sun mesh only. The true angular radius is about five pixels
  -- at 720p and a 70 degree field of view, which is correct and small; raise
  -- this if a blocky world wants a more legible sun.
  sunSizeScale = 1.0,
  sunBrightness = 24.0
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
  -- Smooth render-only shells.  These are radial altitudes, not global Y.
  cloudBottom = 1800.0,
  cloudTop = 4200.0,
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
  bottomLight = 0.58,
  foliageWindStrength = 1.0,
  -- Grass is smoothly thinned between these radii and completely absent past
  -- the end distance. Its animation fades out by the start distance.
  grassCullStart = 64.0,
  grassCullEnd = 104.0,
  leafWindDistance = 112.0
}

graphics.shadows = {
  mapSize = 2048,
  distance = 60.0,
  near = 8.0,
  far = 132.0
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
  farChunkRadius = 18,
  farCoverageSubdivisions = 4,
  farTileSubdivisions = 8,
  farBuildBudget = 8,
  farBuildBudgetMs = 2.0,
  -- Reuse the physically evolved FFT field at three decorrelated world scales.
  -- The smallest two chiefly provide surface detail; the largest carries swell.
  cascadeSizes = {36.0, 144.0, 576.0},
  cascadeDisplacementWeights = {0.075, 0.16, 0.40},
  cascadeNormalWeights = {0.48, 0.29, 0.16},
  -- Stable world-space fetch makes open ocean strongest without changing when
  -- the camera turns. Enclosed water keeps animated short ripples.
  openWaterWaveBoost = 1.08,
  -- Analytic shoreline profile layered over FFT swell. Bathymetry determines
  -- where it appears and bends its travel direction toward the coast.
  shoreBreakerHeight = 0.48,
  shoreBreakerWavelength = 7.5,
  shoreBreakerSpeed = 2.2,
  shoreBreakerCurl = 0.28,
  refractionStrength = 0.014,
  -- 1.0 is the physical 1.333-IOR Snell window. A subtle expansion preserves
  -- TIR while making the above-water view less vertically compressed in play.
  snellWindowScale = 1.20,
  snellProjectionDistance = 1536.0,
  -- Project FFT-driven light concentration onto submerged voxel faces.
  causticStrength = 0.42,
  -- Beer-Lambert absorption per metre: red disappears first in natural water.
  absorption = {0.16, 0.055, 0.026}
}

graphics.ice = {
  -- Clear ice is only weakly absorptive; red is removed first, producing the
  -- subtle blue-green tint of real thick ice rather than an opaque blue cube.
  absorption = {0.045, 0.018, 0.008},
  refractionStrength = 0.010,
  cloudiness = 1.0
}

graphics.terrainGeneration = {
  seed = 1,
  seaLevel = 63,
  continentScale = 0.0025,
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
  -- Procedural erosion approximation. It damps short-wavelength relief and
  -- rounds mountain crests without changing the continent layout.
  erosionStrength = 0.0,
  -- Inland hydrology owns local elevations. Lakes are discrete, level basin
  -- cells; rivers use broader stepped drainage reaches between them and sea.
  riverCarveStrength = 0.94,
  lakeCarveStrength = 0.92,
  lakeCellSize = 176.0,
  lakeBasinChance = 0.34,
  mountainSharpness = 1.65,
  shorelineWidth = 5.0,
  rockyShoreThreshold = 0.24,
  biomeClimateInfluence = 0.34,
  snowTemperature = 0.18,
  elevationCooling = 0.0045,
  freezeTemperature = 0.08,
  grassTintStrength = 0.92,
  treeDensity = 0.78,
  grassDensity = 1.35
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

-- Normalise the load region after the merge. It must reach at least one chunk
-- past what the renderer draws: if it does not, the renderer draws to where the
-- world stops existing and the far side of the loaded region appears in frame
-- as flat plateaus and floating islands.
local world = graphics.world
world.chunkRenderRadius = math.max(1, math.floor(world.chunkRenderRadius or 8))
world.chunkLoadRadius = math.max(
  math.floor(world.chunkLoadRadius or (world.chunkRenderRadius + 1)),
  world.chunkRenderRadius + 1)
world.chunkLoadRadiusVertical = math.max(1, math.min(
  math.floor(world.chunkLoadRadiusVertical or math.ceil(world.chunkLoadRadius * 0.55)),
  world.chunkLoadRadius))

return graphics
