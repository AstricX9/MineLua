local ffi = require("ffi")
local glfw = require("glfw")
local GL = require("gl")
local atmosphere = require("atmosphere")
local blocks = require("blocks")
local camera = require("camera")
local character = require("character")
local DistantTerrain = require("distant_terrain")
local DevMenu = require("dev_menu")
local DroppedItems = require("dropped_items")
local effects = require("render_effects")
local graphics = require("graphics_settings")
local hud = require("hud")
local Inventory = require("inventory")
local math3d = require("math3d")
local rendering = require("rendering")
local saves = require("saves")
local shaderModule = require("shader")
local heldItem = require("held_item")
local spawnLoading = require("spawn_loading")
local terrain = require("terrain")
local texture = require("texture")
local uiFlow = require("ui_flow")
local voxel = require("voxel")
local World = require("world")
local worldInteraction = require("world_interaction")
local worldProfiles = require("world_profiles")

local game = {}

local gl = GL.gl

local GL_COLOR_BUFFER_BIT = 0x00004000
local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_DEPTH_TEST = 0x0B71
local GL_LESS = 0x0201
local GL_BLEND = 0x0BE2
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303
local GL_TEXTURE_2D = 0x0DE1
local GL_TEXTURE_MIN_FILTER = 0x2801
local GL_TEXTURE_MAG_FILTER = 0x2800
local GL_TEXTURE_MAX_LEVEL = 0x813D
local GL_NEAREST = 0x2600
local GL_NEAREST_MIPMAP_LINEAR = 0x2702
local GL_RGBA = 0x1908
local GL_UNSIGNED_BYTE = 0x1401
local GL_ARRAY_BUFFER = 0x8892
local GL_STATIC_DRAW = 0x88E4
local GL_FLOAT = 0x1406
local GL_TEXTURE0 = 0x84C0
local GL_TEXTURE1 = 0x84C1
local GL_TEXTURE2 = 0x84C2
local GL_TEXTURE3 = 0x84C3
local GL_TEXTURE_CUBE_MAP = 0x8513
local GL_TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515
local GL_TEXTURE_WRAP_S = 0x2802
local GL_TEXTURE_WRAP_T = 0x2803
local GL_TEXTURE_WRAP_R = 0x8072
local GL_LINEAR = 0x2601
local GL_CLAMP_TO_EDGE = 0x812F
local GL_REPEAT = 0x2901
local GL_TEXTURE_CUBE_MAP_SEAMLESS = 0x884F
local GL_FRAMEBUFFER = 0x8D40
local GL_CULL_FACE = 0x0B44
local GL_BACK = 0x0405

local WINDOW_W = graphics.window.width
local WINDOW_H = graphics.window.height
local windowWidth = WINDOW_W
local windowHeight = WINDOW_H
local CAMERA_FOV = math.rad(graphics.window.fovDegrees)
-- Set graphics.window.vsync = false (data/config/settings.json) to uncap the frame rate
-- and have the debug screen report real frame cost instead of the refresh rate.
local VSYNC_ENABLED = graphics.window.vsync ~= false
local CAMERA_NEAR = 0.1
local CAMERA_FAR = math.max(graphics.world.visualDistance or 4096.0, 4096.0)
local TERRAIN_MAX_H = graphics.world.terrainMaxHeight
-- Full voxel meshes stay deliberately local. The menu's Render Distance is
-- the outer generated/LOD square, not a request for tens of thousands of full
-- meshes when set to 128.
local CHUNK_RENDER_RADIUS = graphics.world.chunkRenderRadius
local SIMPLE_VERTEX_STRIDE_FLOATS = 11
local TERRAIN_VERTEX_STRIDE_FLOATS = voxel.STRIDE_FLOATS or 14
local FOG_START = graphics.atmosphere.fogStart
local FOG_END = graphics.atmosphere.fogEnd
local SUN_CYCLE_SPEED = graphics.atmosphere.sunCycleSpeed
local SHADOW_MAP_SIZE = graphics.shadows.mapSize
local SHADOW_DISTANCE = graphics.shadows.distance
local SHADOW_NEAR = graphics.shadows.near
local SHADOW_FAR = graphics.shadows.far
local WATER_LEVEL = graphics.water.level
local WATER_NEAR_TESSELLATION = graphics.water.nearTessellation or 2
local DISTANT_CHUNK_RADIUS = graphics.world.distantChunkRadius or 24
local CLOUD_CELL_SIZE = 12.0
local CLOUD_MESH_CELLS = 256
local CLOUD_BOTTOM = graphics.atmosphere.cloudBottom or 132.0
local CLOUD_TOP = graphics.atmosphere.cloudTop or (CLOUD_BOTTOM + 4.0)
local CLOUD_ALPHA = 0.76
local FOG_GRID_WIDTH = graphics.atmosphere.volumetricGridWidth or 160
local FOG_GRID_HEIGHT = graphics.atmosphere.volumetricGridHeight or 90
local FOG_GRID_DEPTH = graphics.atmosphere.volumetricGridDepth or 64
local PERFORMANCE = graphics.performance or {}
local POST = graphics.post or {}
local SKY = graphics.sky or {}
local DISTANT_GENERATION_STEPS = PERFORMANCE.distantGenerationSteps or 8
local DISTANT_BUILD_BUDGET = PERFORMANCE.distantBuildBudget or 2
local DISTANT_FRAME_BUDGET_MS = PERFORMANCE.distantFrameBudgetMs or 3.0
local DISTANT_RING_BUDGET = PERFORMANCE.distantQueueRingBudget or 4
local TERRAIN_WORK_BUDGET = PERFORMANCE.terrainWorkBudget or 10
-- Step counts are a poor budget: a single step ranges from under 1 ms to about
-- 20 ms, so a fixed count of them produces wildly uneven frames. The step count
-- stays as an upper bound; this is what actually caps the frame.
local TERRAIN_FRAME_BUDGET = (PERFORMANCE.terrainFrameBudgetMs or 6.0) / 1000.0
local CHUNK_QUEUE_BUDGET = PERFORMANCE.chunkQueueBudget or 2
local CHUNK_QUEUE_BACKLOG = PERFORMANCE.chunkQueueBacklog or math.max(CHUNK_QUEUE_BUDGET * 3, 4)
local LIGHTING_STEP_BUDGET = PERFORMANCE.lightingStepBudget or 10
local LOADING_CHUNK_BUDGET = PERFORMANCE.loadingChunkBudget or 2
local LOADING_LIGHTING_STEP_BUDGET = PERFORMANCE.loadingLightingStepBudget or 14
local LOADING_MESH_BUDGET = PERFORMANCE.loadingMeshBudget or 2
local LOADING_REQUIRED_RADIUS = PERFORMANCE.loadingRequiredRadius or PERFORMANCE.initialSpawnRadius or 1
local LOADING_HALO_RADIUS = math.max(LOADING_REQUIRED_RADIUS, PERFORMANCE.loadingHaloRadius or 2)
local DEFAULT_SPAWN_X = 16.5
local DEFAULT_SPAWN_Z = 16.5
local PLAYER_AUTOSAVE_INTERVAL = 10.0
local TWO_PI = math.pi * 2.0

local function timeOfDayForSimulationTime(time, cycleSpeed)
  local phase = (time * (cycleSpeed or SUN_CYCLE_SPEED)) % TWO_PI
  return (phase / TWO_PI * 24.0 + 6.0) % 24.0
end

local function simulationTimeForTimeOfDay(hour, cycleSpeed)
  local phase = ((hour - 6.0) / 24.0) * TWO_PI
  return phase / (cycleSpeed or SUN_CYCLE_SPEED)
end

local function updateRuntimeAtmosphereSettings(runtime, strength, worldProfile)
  for key, value in pairs(graphics.atmosphere) do
    runtime[key] = value
  end

  strength = math.max(0.0, math.min(strength or 1.0, 3.0))
  local densityScale = worldProfile and worldProfile.atmosphere and
    (worldProfile.atmosphere.fogDensityScale or 1.0) or 1.0
  local scaledStrength = strength * densityScale
  runtime.heightFogDensity = (graphics.atmosphere.heightFogDensity or 0.0045) * scaledStrength
  runtime.horizonFog = (graphics.atmosphere.horizonFog or 0.24) * scaledStrength
  runtime.distanceFogDensity = (graphics.atmosphere.distanceFogDensity or 0.0015) * scaledStrength
  runtime.airScatter = (graphics.atmosphere.airScatter or 0.12) * scaledStrength

  local authoredOpacity = graphics.atmosphere.fogMaxOpacity or graphics.atmosphere.maxFogAmount or 0.82
  runtime.fogMaxOpacity = 1.0 - ((1.0 - authoredOpacity) ^ scaledStrength)
  runtime.maxFogAmount = runtime.fogMaxOpacity
end

local function createShaderProgram()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;
layout (location = 4) in vec3 aInfo;
out vec3 vColor;
out vec3 vNormal;
out vec3 vFragPos;
out vec2 vTexCoord;
out vec3 vInfo;
uniform mat4 uProjection;
uniform mat4 uView;
uniform mat4 uModel;
uniform float time;
void main() {
  vec3 localPosition = aPos;
  vec3 worldPosition = vec3(uModel * vec4(localPosition, 1.0));
  if (aInfo.x > 0.5) {
    float mainWave = sin(dot(worldPosition.xz, vec2(0.8, 0.6)) + time * 1.5);
    float detailWave = sin(dot(worldPosition.xz, vec2(-0.4, 1.1)) + time * 2.3);
    float sway = mainWave + detailWave * 0.25;
    float strength = aInfo.x > 1.5 ? 0.025 : 0.010;
    vec2 windDirection = normalize(vec2(0.85, 0.35));
    worldPosition.xz += windDirection * sway * strength * clamp(aInfo.y, 0.0, 1.0);
  }
  vFragPos = worldPosition;
  vNormal = mat3(transpose(inverse(uModel))) * aNormal;
  vColor = aColor;
  vTexCoord = aTexCoord;
  vInfo = aInfo;
  gl_Position = uProjection * uView * vec4(worldPosition, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec3 vColor;
in vec3 vNormal;
in vec3 vFragPos;
in vec2 vTexCoord;
in vec3 vInfo;
out vec4 FragColor;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform sampler2D tex0;
uniform sampler2D shadowMap;
uniform vec3 ambientColor;
uniform vec3 lightColor;
uniform vec3 moonLightColor;
uniform vec3 lightingParams;
uniform vec3 faceLight;
uniform float exposure;
uniform float shadowStrength;
uniform mat4 lightSpaceMatrix;
uniform float waterLevel;
uniform sampler2D waterNormalMap;
uniform vec3 waterCascadeSizes;
uniform vec3 waterNormalWeights;
uniform float causticStrength;
uniform float time;

vec3 srgbToLinear(vec3 color) {
  return pow(max(color, vec3(0.0)), vec3(2.2));
}

vec3 linearToSrgb(vec3 color) {
  return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
}

float fixedFaceShade(vec3 normal, float material) {
  if (material > 1.5) {
    return 0.94;
  }
  if (material > 0.5) {
    return 0.92;
  }
  if (normal.y > 0.9) return 1.00;
  if (normal.y < -0.9) return 0.50;
  if (abs(normal.x) > 0.9) return 0.60;
  return 0.80;
}

float shadowAt(vec3 normal, vec3 light, float diff) {
  vec4 lightSpacePos = lightSpaceMatrix * vec4(vFragPos, 1.0);
  vec3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
  projCoords = projCoords * 0.5 + 0.5;

  if (projCoords.z > 1.0 || projCoords.x < 0.0 || projCoords.x > 1.0 || projCoords.y < 0.0 || projCoords.y > 1.0) {
    return 0.0;
  }

  float bias = max(0.0025 * (1.0 - dot(normal, light)), 0.0007);
  vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
  float shadow = 0.0;
  for (int x = -1; x <= 1; ++x) {
    for (int y = -1; y <= 1; ++y) {
      float closestDepth = texture(shadowMap, projCoords.xy + vec2(x, y) * texelSize).r;
      shadow += projCoords.z - bias > closestDepth ? 1.0 : 0.0;
    }
  }

  return shadow / 9.0 * smoothstep(0.02, 0.18, diff);
}

float voxelCaustics(vec3 worldPosition, vec3 surfaceNormal, vec3 sunlight) {
  float waterDepth = waterLevel - worldPosition.y;
  if (waterDepth <= 0.02 || sunlight.y <= 0.015) return 0.0;

  // Trace the sun into water using the physical air/water index ratio, then
  // evaluate the animated surface above this voxel rather than screen UVs.
  // This keeps the projection fixed to block faces as the camera moves.
  vec3 transmitted = refract(-sunlight, vec3(0.0, 1.0, 0.0), 1.0 / 1.333);
  float verticalTravel = max(-transmitted.y, 0.08);
  vec2 surfacePosition = worldPosition.xz - transmitted.xz * (waterDepth / verticalTravel);

  vec4 wave0 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.x + vec2(0.17, 0.61));
  vec4 wave1 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.y + vec2(0.73, 0.29));
  vec4 wave2 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.z + vec2(0.41, 0.83));
  vec2 waveSlope = wave0.xz * waterNormalWeights.x +
    wave1.xz * waterNormalWeights.y + wave2.xz * waterNormalWeights.z;

  // The FFT stores its horizontal deformation Jacobian in alpha. Compressed
  // surface patches concentrate refracted light; narrow, domain-warped ridges
  // fill in the characteristic moving caustic network between fold events.
  float compression = 1.0 - clamp(min(wave0.a, min(wave1.a, wave2.a)), 0.0, 1.0);
  vec2 warped = surfacePosition + waveSlope * mix(2.2, 0.45, exp(-waterDepth * 0.05));
  float ridge0 = pow(1.0 - abs(sin(dot(warped, normalize(vec2(0.82, 0.57))) * 1.72 + time * 1.18)), 12.0);
  float ridge1 = pow(1.0 - abs(sin(dot(warped, normalize(vec2(-0.31, 0.95))) * 1.31 - time * 0.91)), 12.0);
  float ridge2 = pow(1.0 - abs(sin(dot(warped, normalize(vec2(0.98, -0.18))) * 2.08 + time * 1.43)), 14.0);
  float network = clamp((ridge0 + ridge1 + ridge2) * 0.52, 0.0, 1.0);
  float focusing = max(network * (0.45 + compression * 1.4),
    smoothstep(0.055, 0.52, compression) * 0.82);

  float depthFade = exp(-waterDepth * 0.052);
  float daylight = smoothstep(0.015, 0.22, sunlight.y);
  float receiving = 0.18 + 0.82 * max(dot(surfaceNormal, -transmitted), 0.0);
  return clamp(focusing * depthFade * daylight * receiving, 0.0, 1.35);
}

void main() {
  float material = vInfo.x;
  vec3 norm = normalize(vNormal);
  if (material > 1.5) {
    norm = normalize(mix(norm, vec3(0.0, 1.0, 0.0), 0.65));
  } else if (material > 0.5) {
    norm = normalize(mix(norm, vec3(0.0, 1.0, 0.0), 0.35));
  }
  vec3 light = normalize(-lightDir);
  float diff = max(dot(norm, light), 0.0);
  vec4 texColor = texture(tex0, vTexCoord);
  if(texColor.a < 0.5) discard;
  vec3 albedo = srgbToLinear(texColor.rgb) * srgbToLinear(vColor);

  float voxelLight = vInfo.z > 0.0 ? clamp(vInfo.z, 0.0, 1.0) : 1.0;
  if (material > 0.5) {
    voxelLight = max(voxelLight, 0.34);
  }

  float sunDiffuse = material > 1.5 ? mix(0.88, 1.0, diff) : mix(0.68, 1.0, diff);
  float faceShadeValue = fixedFaceShade(normalize(vNormal), material);
  float shadowAmount = shadowAt(norm, light, diff) * shadowStrength;
  float shadowVisibility = mix(1.0, 0.45, clamp(shadowAmount, 0.0, 1.0));
  float daylight = lightingParams.x;
  float ambientFloor = lightingParams.z;

  vec3 skyContribution = ambientColor * voxelLight;
  vec3 sunContribution = lightColor * faceShadeValue * sunDiffuse * shadowVisibility * voxelLight;
  vec3 moonContribution = moonLightColor * mix(0.76, 1.0, max(dot(norm, -light), 0.0)) * faceShadeValue * voxelLight;
  vec3 totalLight = skyContribution + sunContribution + moonContribution;
  totalLight = max(totalLight, vec3(ambientFloor));

  vec3 litColor = albedo * totalLight * exposure;
  float caustic = voxelCaustics(vFragPos, norm, light) * daylight * shadowVisibility * voxelLight;
  vec3 causticColor = srgbToLinear(vec3(0.52, 0.90, 1.0));
  litColor += albedo * lightColor * causticColor * caustic * causticStrength;
  vec3 finalColor = linearToSrgb(litColor);
  float luminance = dot(finalColor, vec3(0.2126, 0.7152, 0.0722));
  float nightSaturation = mix(0.55, 1.0, daylight);
  finalColor = mix(vec3(luminance), finalColor, nightSaturation);
  FragColor = vec4(finalColor, texColor.a);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function createSkyShaderProgram()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
out vec2 vUv;
void main() {
  vUv = aPos.xy * 0.5 + 0.5;
  gl_Position = vec4(aPos.xy, 0.0, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec2 vUv;
out vec4 FragColor;
uniform vec3 sunDir;
uniform vec3 time;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 cameraPosition;
uniform vec3 cameraProjection;
uniform vec3 skyTuning;
uniform vec3 skyParams;   // scatterStrength, unused, sunIntensity
uniform vec3 fogColor;
uniform sampler2D moonTex;
uniform vec3 sunDisc;
uniform vec3 scatteringPlanet;   // radius, atmosphere height, surface datum
uniform vec3 scatteringScale;    // molecular height, dust height, anisotropy
uniform vec3 scatteringRayleigh;
uniform vec3 scatteringDust;
uniform vec3 aureoleColor;
uniform vec3 aureoleParams;      // focus, strength, unused

const mat3 cloudMatrix = mat3(
   0.0,  1.60,  1.20,
  -1.6,  0.72, -0.96,
  -1.2, -0.96,  1.28
);

float hash(float n) {
  return fract(sin(n) * 43758.5453123);
}

float noise(vec3 x) {
  vec3 f = fract(x);
  float n = dot(floor(x), vec3(1.0, 157.0, 113.0));
  return mix(
    mix(
      mix(hash(n + 0.0), hash(n + 1.0), f.x),
      mix(hash(n + 157.0), hash(n + 158.0), f.x),
      f.y
    ),
    mix(
      mix(hash(n + 113.0), hash(n + 114.0), f.x),
      mix(hash(n + 270.0), hash(n + 271.0), f.x),
      f.y
    ),
    f.z
  );
}

float fbm(vec3 p) {
  float f = 0.0;
  f += noise(p) / 2.0;
  p = cloudMatrix * p * 1.1;
  f += noise(p) / 4.0;
  p = cloudMatrix * p * 1.2;
  f += noise(p) / 6.0;
  p = cloudMatrix * p * 1.3;
  f += noise(p) / 12.0;
  p = cloudMatrix * p * 1.4;
  f += noise(p) / 24.0;
  return f;
}

float hash2(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float stars(vec3 dir) {
  vec2 uv = vec2(atan(dir.z, dir.x) * 0.1591549 + 0.5, asin(clamp(dir.y, -1.0, 1.0)) * 0.3183099 + 0.5);
  vec2 grid = floor(uv * vec2(360.0, 160.0));
  vec2 cell = fract(uv * vec2(360.0, 160.0)) - 0.5;
  float rnd = hash2(grid);
  float star = 1.0 - smoothstep(0.0, 0.030, length(cell - vec2(hash2(grid + 17.0), hash2(grid + 41.0)) * 0.72 + 0.14));
  return star * step(0.986, rnd) * mix(0.45, 1.35, hash2(grid + 91.0));
}

vec3 moonTexture(vec2 uv) {
  float r = length(uv);
  float shade = 1.0 - smoothstep(0.72, 1.0, r);
  float craters = 0.0;
  craters += (1.0 - smoothstep(0.02, 0.22, length(uv - vec2(-0.24, 0.20)))) * 0.35;
  craters += (1.0 - smoothstep(0.03, 0.18, length(uv - vec2(0.30, -0.12)))) * 0.28;
  craters += (1.0 - smoothstep(0.02, 0.12, length(uv - vec2(0.08, 0.34)))) * 0.20;
  craters += (1.0 - smoothstep(0.02, 0.10, length(uv - vec2(-0.12, -0.30)))) * 0.18;
  float grain = fbm(vec3(uv * 5.0, 2.5)) * 0.22;
  return vec3(0.78, 0.80, 0.76) * (shade + grain - craters);
}

// ---------------------------------------------------------------------------
// Rayleigh + Mie single scattering (Nishita). The view ray is marched through
// the atmosphere; at each step a second march toward the sun gives the optical
// depth light travelled to get there. Sunset reds, the blue zenith and horizon
// brightening all fall out of the wavelength dependence rather than being
// authored -- Rayleigh scatters blue ~5.7x more strongly than red, so a long
// grazing path through air has the blue removed from it.
// ---------------------------------------------------------------------------
const float PI_SKY = 3.14159265359;
const int SCATTER_VIEW_SAMPLES = @VIEW_SAMPLES@;
const int SCATTER_LIGHT_SAMPLES = @LIGHT_SAMPLES@;

// Distance to the far intersection with a sphere centred on the origin.
float raySphereFar(vec3 origin, vec3 dir, float radius) {
  float b = dot(origin, dir);
  float c = dot(origin, origin) - radius * radius;
  float d = b * b - c;
  if (d < 0.0) return -1.0;
  return -b + sqrt(d);
}

// Distance to the near intersection, or -1 when the ray misses or starts past it.
float raySphereNear(vec3 origin, vec3 dir, float radius) {
  float b = dot(origin, dir);
  float c = dot(origin, origin) - radius * radius;
  float d = b * b - c;
  if (d < 0.0) return -1.0;
  float t = -b - sqrt(d);
  return t > 0.0 ? t : -1.0;
}

vec3 atmosphericScattering(vec3 rayDir, vec3 sunDirection, float observerAltitude, float sunIntensity) {
  float planetRadius = scatteringPlanet.x;
  float atmosphereRadius = planetRadius + scatteringPlanet.y;
  vec3 origin = vec3(0.0, planetRadius + observerAltitude, 0.0);

  float rayLength = raySphereFar(origin, rayDir, atmosphereRadius);
  if (rayLength <= 0.0) return vec3(0.0);

  // Looking down into the planet: stop at the surface.
  float groundHit = raySphereNear(origin, rayDir, planetRadius);
  if (groundHit > 0.0) rayLength = min(rayLength, groundHit);

  float mu = dot(rayDir, sunDirection);
  float phaseRayleigh = 3.0 / (16.0 * PI_SKY) * (1.0 + mu * mu);
  float dustG = scatteringScale.z;
  float g2 = dustG * dustG;
  float phaseMie = 3.0 / (8.0 * PI_SKY) * ((1.0 - g2) * (1.0 + mu * mu)) /
                   ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * dustG * mu, 1e-4), 1.5));

  float stepSize = rayLength / float(SCATTER_VIEW_SAMPLES);
  float travelled = 0.0;
  float opticalDepthR = 0.0;
  float opticalDepthM = 0.0;
  vec3 accumR = vec3(0.0);
  vec3 accumM = vec3(0.0);

  for (int i = 0; i < SCATTER_VIEW_SAMPLES; i++) {
    vec3 samplePos = origin + rayDir * (travelled + stepSize * 0.5);
    float height = length(samplePos) - planetRadius;

    float densityR = exp(-height / scatteringScale.x) * stepSize;
    float densityM = exp(-height / scatteringScale.y) * stepSize;
    opticalDepthR += densityR;
    opticalDepthM += densityM;

    // second march: how much air the sunlight crossed to reach this sample
    float lightLength = raySphereFar(samplePos, sunDirection, atmosphereRadius);
    float lightStep = lightLength / float(SCATTER_LIGHT_SAMPLES);
    float lightTravelled = 0.0;
    float lightDepthR = 0.0;
    float lightDepthM = 0.0;
    bool occluded = false;

    for (int j = 0; j < SCATTER_LIGHT_SAMPLES; j++) {
      vec3 lightPos = samplePos + sunDirection * (lightTravelled + lightStep * 0.5);
      float lightHeight = length(lightPos) - planetRadius;
      if (lightHeight < 0.0) { occluded = true; break; }
      lightDepthR += exp(-lightHeight / scatteringScale.x) * lightStep;
      lightDepthM += exp(-lightHeight / scatteringScale.y) * lightStep;
      lightTravelled += lightStep;
    }

    if (!occluded) {
      vec3 tau = scatteringRayleigh * (opticalDepthR + lightDepthR) +
                 scatteringDust * 1.1 * (opticalDepthM + lightDepthM);
      vec3 transmittance = exp(-tau);
      accumR += transmittance * densityR;
      accumM += transmittance * densityM;
    }

    travelled += stepSize;
  }

  return sunIntensity * (accumR * scatteringRayleigh * phaseRayleigh +
                         accumM * scatteringDust * phaseMie);
}

// Transmittance from the observer to the top of the atmosphere. The scattering
// march already computes this for the light rays it traces; the sun disc needs
// it along the view ray instead, so that the same air that turns the sky red at
// dusk dims and reddens the disc itself rather than a tint being authored for
// it. Returns black once the ray meets the planet, which is what makes the sun
// set instead of sitting on the horizon.
vec3 sunTransmittance(vec3 rayDir, float observerAltitude) {
  float planetRadius = scatteringPlanet.x;
  float atmosphereRadius = planetRadius + scatteringPlanet.y;
  vec3 origin = vec3(0.0, planetRadius + observerAltitude, 0.0);

  float rayLength = raySphereFar(origin, rayDir, atmosphereRadius);
  if (rayLength <= 0.0) return vec3(0.0);
  if (raySphereNear(origin, rayDir, planetRadius) > 0.0) return vec3(0.0);

  float stepSize = rayLength / float(SCATTER_LIGHT_SAMPLES);
  float travelled = 0.0;
  float depthR = 0.0;
  float depthM = 0.0;

  for (int i = 0; i < SCATTER_LIGHT_SAMPLES; i++) {
    vec3 samplePos = origin + rayDir * (travelled + stepSize * 0.5);
    float height = max(length(samplePos) - planetRadius, 0.0);
    depthR += exp(-height / scatteringScale.x) * stepSize;
    depthM += exp(-height / scatteringScale.y) * stepSize;
    travelled += stepSize;
  }

  return exp(-(scatteringRayleigh * depthR + scatteringDust * 1.1 * depthM));
}

void main() {
  vec2 p = vUv * 2.0 - 1.0;
  vec3 pos = normalize(
    cameraForward +
    cameraRight * p.x * cameraProjection.x +
    cameraUp * p.y * cameraProjection.y
  );
  vec3 sun = normalize(sunDir);
  vec3 moon = -sun;
  float dayAmount = smoothstep(-0.08, 0.22, sun.y);
  float nightAmount = 1.0 - smoothstep(-0.18, 0.08, sun.y);
  float horizonWarmth = 1.0 - smoothstep(-0.03, 0.34, abs(sun.y));
  float skyMask = smoothstep(-0.08, 0.08, pos.y);
  vec3 skyPos = normalize(vec3(pos.x, max(pos.y, 0.015), pos.z));

  float altitude = smoothstep(0.0, 0.92, skyPos.y);

  // The physical model produces daylight only; it correctly falls to black once
  // the sun is below the horizon, so the authored night sky sits underneath it
  // rather than being cross-faded against it.
  float observerAltitude = max(cameraPosition.y - scatteringPlanet.z, 1.0);
  vec3 scattered = atmosphericScattering(skyPos, sun, observerAltitude, skyParams.z);
  vec3 nightSky = mix(fogColor * 1.7, fogColor * 0.55, altitude);
  vec3 color = nightSky * nightAmount + scattered * skyParams.x;

  float moonVisible = smoothstep(-0.06, 0.08, moon.y) * nightAmount * skyParams.y;
  vec3 moonBasisUp = abs(moon.y) > 0.96 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
  vec3 moonRight = normalize(cross(moonBasisUp, moon));
  vec3 moonUp = normalize(cross(moon, moonRight));
  vec2 moonUv = vec2(dot(skyPos, moonRight), dot(skyPos, moonUp)) / 0.052;
  vec2 moonSampleUv = moonUv * 0.5 + 0.5;
  vec2 moonAtlasUv = vec2(moonSampleUv.x * 0.25, moonSampleUv.y * 0.5);
  vec4 moonTextureColor = texture(moonTex, moonAtlasUv);
  float moonSquare = step(max(abs(moonUv.x), abs(moonUv.y)), 1.0);
  float moonLuma = max(max(moonTextureColor.r, moonTextureColor.g), moonTextureColor.b);
  float moonMask = moonSquare * moonVisible * moonTextureColor.a * smoothstep(0.025, 0.11, moonLuma);
  color = mix(color, moonTextureColor.rgb, moonMask);

  // Aureole only -- the disc itself is added after tone mapping, below. This
  // term uses skyPos rather than pos so the glow survives once the disc has
  // dropped under the horizon, which is what a sunset looks like.
  float sunAmount = max(dot(skyPos, sun), 0.0);
  color += aureoleColor * pow(sunAmount, aureoleParams.x) * aureoleParams.y *
    max(dayAmount, 0.15) * skyTuning.z;

  color += vec3(0.82, 0.88, 1.0) * stars(pos) * nightAmount * smoothstep(0.0, 0.18, pos.y);
  color = mix(color, fogColor * 1.08, horizonWarmth * smoothstep(0.0, 0.12, skyPos.y) * 0.15);
  color += noise(skyPos * 1000.0) * 0.006;
  color = vec3(1.0) - exp(-color * skyTuning.x);
  color = pow(color, vec3(1.08));

  // The disc goes in after the sky's own tone map, so it keeps values above 1.0
  // in the half-float target. Folded in before, it would be rolled off to white
  // along with the sky and bloom would have nothing to pick up.
  //
  // Nothing here is sampled: the edge is the true angular radius, the shading
  // across it is the linear limb-darkening law, and the colour is whatever the
  // atmosphere lets through along that ray.
  float sunAngularRadius = max(sunDisc.x, 0.0002);
  float sunAngle = acos(clamp(dot(pos, sun), -1.0, 1.0));
  // fwidth has to be evaluated outside the branch: derivatives are undefined
  // in non-uniform control flow.
  float limbWidth = max(fwidth(sunAngle), 1.0e-5);
  float discMask = 1.0 - smoothstep(sunAngularRadius - limbWidth, sunAngularRadius + limbWidth, sunAngle);
  if (discMask > 0.0) {
    float discRadius = clamp(sunAngle / sunAngularRadius, 0.0, 1.0);
    float mu = sqrt(max(1.0 - discRadius * discRadius, 0.0));
    // Coefficients near 610/550/470 nm. Red is darkened least, so the rim runs
    // warm and the centre stays white without a tint being painted on.
    vec3 limb = vec3(1.0) - vec3(0.397, 0.503, 0.652) * (1.0 - mu);
    color += limb * sunTransmittance(pos, observerAltitude) * sunDisc.y * discMask;
  }

  color = mix(fogColor, color, skyMask);
  FragColor = vec4(color, 1.0);
}
]]

  -- Sample counts must be compile-time constants for the loops to unroll, so
  -- they are substituted into the source rather than passed as uniforms.
  fragSource = fragSource
    :gsub("@VIEW_SAMPLES@", tostring(SKY.scatterViewSamples or 16))
    :gsub("@LIGHT_SAMPLES@", tostring(SKY.scatterLightSamples or 8))

  return shaderModule.fromSource(vertSource, fragSource)
end

local function createCloudShaderProgram()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 2) in vec3 aColor;
out vec3 vColor;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 cloudOffset;
void main() {
  vec3 worldPos = aPos + cloudOffset;
  vColor = aColor;
  gl_Position = uProjection * uView * vec4(worldPos, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec3 vColor;
out vec4 FragColor;
uniform float cloudAlpha;
uniform vec3 cloudTint;
void main() {
  FragColor = vec4(vColor * cloudTint, cloudAlpha);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function createWorldgenPreviewShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
out vec3 vNormal;
out vec3 vColor;
uniform mat4 uProjection;
uniform mat4 uView;
void main() {
  vNormal = aNormal;
  vColor = aColor;
  gl_Position = uProjection * uView * vec4(aPos, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec3 vNormal;
in vec3 vColor;
out vec4 FragColor;
uniform vec3 lightDir;
void main() {
  float diffuse = max(dot(normalize(vNormal), normalize(-lightDir)), 0.0);
  float light = 0.48 + diffuse * 0.52;
  FragColor = vec4(vColor * light, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function configureVertexAttributes(strideFloats, hasInfo)
  local stride = strideFloats * 4
  gl.glVertexAttribPointer(0, 3, GL_FLOAT, 0, stride, nil)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(1, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 3 * 4))
  gl.glEnableVertexAttribArray(1)
  gl.glVertexAttribPointer(2, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 6 * 4))
  gl.glEnableVertexAttribArray(2)
  gl.glVertexAttribPointer(3, 2, GL_FLOAT, 0, stride, ffi.cast("void*", 9 * 4))
  gl.glEnableVertexAttribArray(3)
  if hasInfo then
    gl.glVertexAttribPointer(4, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 11 * 4))
    gl.glEnableVertexAttribArray(4)
  end
end

local function uploadMesh(vertices, strideFloats, hasInfo)
  strideFloats = strideFloats or SIMPLE_VERTEX_STRIDE_FLOATS
  local vao = ffi.new("GLuint[1]")
  local vbo = ffi.new("GLuint[1]")
  local data = ffi.new("float[?]", #vertices, vertices)

  gl.glGenVertexArrays(1, vao)
  gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1, vbo)
  gl.glBindBuffer(GL_ARRAY_BUFFER, vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER, #vertices * 4, data, GL_STATIC_DRAW)
  configureVertexAttributes(strideFloats, hasInfo)

  return {
    vao = vao,
    vbo = vbo,
    count = #vertices / strideFloats,
    data = data
  }
end

local PREVIEW_BIOME_COLORS = {
  ocean = {0.075, 0.30, 0.48},
  beach = {0.76, 0.69, 0.43},
  desert = {0.76, 0.62, 0.31},
  savanna = {0.55, 0.58, 0.24},
  plains = {0.27, 0.55, 0.24},
  shrubland = {0.36, 0.49, 0.25},
  forest = {0.12, 0.37, 0.16},
  seasonalForest = {0.18, 0.42, 0.17},
  rainforest = {0.07, 0.32, 0.13},
  swampland = {0.17, 0.33, 0.22},
  taiga = {0.22, 0.40, 0.31},
  tundra = {0.48, 0.54, 0.42},
  iceDesert = {0.72, 0.78, 0.76},
  mountains = {0.43, 0.45, 0.42},
  rockyShore = {0.37, 0.39, 0.38},
  frozenShore = {0.72, 0.77, 0.76},
  mars_lowlands = {0.64, 0.30, 0.16},
  mars_highlands = {0.72, 0.38, 0.22},
  mars_crater = {0.43, 0.24, 0.18},
  mars_volcanic = {0.18, 0.16, 0.16},
  mars_canyon = {0.34, 0.17, 0.12},
  mars_polar = {0.82, 0.88, 0.90}
}

local function worldgenPreviewVertices(centerX, centerZ, extent, resolution)
  local vertices = {}
  local side = resolution + 1
  local step = extent / resolution
  local originX = math.floor((centerX - extent * 0.5) / step) * step
  local originZ = math.floor((centerZ - extent * 0.5) / step) * step
  local seaLevel = terrain.SEA_LEVEL
  local heights = {}
  local colors = {}

  for z = 0, resolution do
    for x = 0, resolution do
      local worldX = originX + x * step
      local worldZ = originZ + z * step
      local rawHeight = terrain.heightAt(worldX, worldZ, TERRAIN_MAX_H)
      local index = z * side + x + 1
      local underwater = terrain.activeProfile.hasSurfaceWater and rawHeight <= seaLevel
      heights[index] = underwater and (seaLevel - 0.35) or rawHeight
      local sourceBiome = terrain.biomeAt(worldX, worldZ)
      local environment = terrain.environmentAt(worldX, worldZ, rawHeight, sourceBiome)
      if underwater and environment.freezeWater then
        colors[index] = {0.64, 0.78, 0.84}
      elseif underwater then
        colors[index] = PREVIEW_BIOME_COLORS.ocean
      elseif environment.hasSnow then
        colors[index] = {0.88, 0.91, 0.92}
      else
        colors[index] = PREVIEW_BIOME_COLORS[environment.biome] or PREVIEW_BIOME_COLORS.plains
      end
    end
  end

  local function sampleHeight(x, z)
    x = math.max(0, math.min(resolution, x))
    z = math.max(0, math.min(resolution, z))
    return heights[z * side + x + 1]
  end

  local function appendVertex(x, z)
    local index = z * side + x + 1
    local normal = math3d.normalize({
      sampleHeight(x - 1, z) - sampleHeight(x + 1, z),
      step * 2.0,
      sampleHeight(x, z - 1) - sampleHeight(x, z + 1)
    })
    local color = colors[index]
    vertices[#vertices + 1] = originX + x * step
    vertices[#vertices + 1] = heights[index]
    vertices[#vertices + 1] = originZ + z * step
    vertices[#vertices + 1] = normal[1]
    vertices[#vertices + 1] = normal[2]
    vertices[#vertices + 1] = normal[3]
    vertices[#vertices + 1] = color[1]
    vertices[#vertices + 1] = color[2]
    vertices[#vertices + 1] = color[3]
    vertices[#vertices + 1] = 0.0
    vertices[#vertices + 1] = 0.0
  end

  for z = 0, resolution - 1 do
    for x = 0, resolution - 1 do
      appendVertex(x, z)
      appendVertex(x, z + 1)
      appendVertex(x + 1, z)
      appendVertex(x + 1, z)
      appendVertex(x, z + 1)
      appendVertex(x + 1, z + 1)
    end
  end

  return vertices
end

local function rebuildWorldgenPreview(previousMesh, stagedSettings, liveSeed, centerX, centerZ)
  local liveSettings = {}
  for key, value in pairs(graphics.terrainGeneration) do
    liveSettings[key] = value
  end

  for key, value in pairs(stagedSettings) do
    graphics.terrainGeneration[key] = value
  end
  terrain.refreshGenerationSettings()
  terrain.setSeed(stagedSettings.seed)

  local ok, result = pcall(worldgenPreviewVertices, centerX, centerZ, 3072.0, 64)

  for key in pairs(graphics.terrainGeneration) do
    graphics.terrainGeneration[key] = nil
  end
  for key, value in pairs(liveSettings) do
    graphics.terrainGeneration[key] = value
  end
  terrain.refreshGenerationSettings()
  terrain.setSeed(liveSeed)

  if not ok then
    error(result)
  end

  rendering.release(previousMesh)
  return uploadMesh(result)
end

local function updateWorldgenPreviewCamera(state, cameraObject, window, dt, allowEdgePan)
  local speed = state.distance * 0.70
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_LEFT_SHIFT) == glfw.GLFW_PRESS then
    speed = speed * 3.0
  end
  local move = speed * math.min(dt, 0.05)
  local yaw = math.rad(state.yaw)
  local forwardX, forwardZ = math.cos(yaw), math.sin(yaw)
  local rightX, rightZ = -forwardZ, forwardX

  if glfw.glfwGetKey(window, glfw.GLFW_KEY_W) == glfw.GLFW_PRESS then
    state.centerX = state.centerX + forwardX * move
    state.centerZ = state.centerZ + forwardZ * move
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_S) == glfw.GLFW_PRESS then
    state.centerX = state.centerX - forwardX * move
    state.centerZ = state.centerZ - forwardZ * move
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_D) == glfw.GLFW_PRESS then
    state.centerX = state.centerX + rightX * move
    state.centerZ = state.centerZ + rightZ * move
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_A) == glfw.GLFW_PRESS then
    state.centerX = state.centerX - rightX * move
    state.centerZ = state.centerZ - rightZ * move
  end
  if allowEdgePan then
    local cursorX, cursorY = ffi.new("double[1]"), ffi.new("double[1]")
    local clientWidth, clientHeight = ffi.new("int[1]"), ffi.new("int[1]")
    glfw.glfwGetCursorPos(window, cursorX, cursorY)
    glfw.glfwGetWindowSize(window, clientWidth, clientHeight)
    local edge = 12.0
    if cursorX[0] <= edge then
      state.centerX = state.centerX - rightX * move
      state.centerZ = state.centerZ - rightZ * move
    elseif cursorX[0] >= clientWidth[0] - edge then
      state.centerX = state.centerX + rightX * move
      state.centerZ = state.centerZ + rightZ * move
    end
    if cursorY[0] <= edge then
      state.centerX = state.centerX + forwardX * move
      state.centerZ = state.centerZ + forwardZ * move
    elseif cursorY[0] >= clientHeight[0] - edge then
      state.centerX = state.centerX - forwardX * move
      state.centerZ = state.centerZ - forwardZ * move
    end
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_Q) == glfw.GLFW_PRESS then state.yaw = state.yaw - 55.0 * dt end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_E) == glfw.GLFW_PRESS then state.yaw = state.yaw + 55.0 * dt end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_R) == glfw.GLFW_PRESS then state.distance = state.distance * math.exp(-1.5 * dt) end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_F) == glfw.GLFW_PRESS then state.distance = state.distance * math.exp(1.5 * dt) end
  state.distance = math.max(180.0, math.min(2600.0, state.distance))

  yaw = math.rad(state.yaw)
  local pitch = math.rad(54.0)
  local horizontalDistance = math.cos(pitch) * state.distance
  cameraObject.position[1] = state.centerX - math.cos(yaw) * horizontalDistance
  cameraObject.position[2] = terrain.SEA_LEVEL + 18.0 + math.sin(pitch) * state.distance
  cameraObject.position[3] = state.centerZ - math.sin(yaw) * horizontalDistance
  cameraObject.yaw = state.yaw
  cameraObject.pitch = -54.0
end

local function uploadTerrainMesh(vertices)
  return uploadMesh(vertices, TERRAIN_VERTEX_STRIDE_FLOATS, true)
end

local function terrainChunkBounds(entry)
  return {
    minX = entry.offsetX,
    minY = 0,
    minZ = entry.offsetZ,
    maxX = entry.offsetX + 16,
    maxY = TERRAIN_MAX_H + 1,
    maxZ = entry.offsetZ + 16
  }
end

local function saturate(value)
  return math.max(0.0, math.min(1.0, value))
end

local function classifyWaterWaves(x, z)
  local macro = terrain.macroAt(x, z)
  -- `land` is a continuous continent field, so this naturally eases from full
  -- ocean fetch through bays and coastal shallows. River/lake masks retain a
  -- smaller but non-zero animated response inland.
  local oceanFetch = saturate((0.34 - macro.land) / 0.24)
  local inlandDynamic = saturate(math.max(macro.river * 0.85, macro.lake * 0.65) * 1.4)
  local inlandExposure = 0.14 + inlandDynamic * 0.25
  local inlandShore = 0.42 + inlandDynamic * 0.30
  local exposure = inlandExposure + (1.0 - inlandExposure) * oceanFetch
  local shore = inlandShore + (1.0 - inlandShore) * oceanFetch
  return exposure, shore
end

local function createWaterWaveSampler(world)
  local samples = {}
  local depthSamples = {}
  local surfaceY = math.floor(WATER_LEVEL)

  local function isWater(id)
    return id == blocks.water or (blocks.water_still and id == blocks.water_still)
  end

  local function depthFactorAt(cellX, cellZ)
    local key = cellX .. "," .. cellZ
    local cached = depthSamples[key]
    if cached ~= nil then return cached end

    local depth = 4
    if world then
      local surfaceBlock = world:blockAt(cellX, surfaceY, cellZ)
      if surfaceBlock == nil then
        -- A vertex on a loaded chunk border can consult an as-yet unloaded
        -- neighbour. Use the deterministic terrain surface until that chunk
        -- arrives so the edge is not incorrectly treated as a cliff.
        depth = math.max(0, surfaceY - terrain.heightAt(cellX, cellZ, TERRAIN_MAX_H, true))
      elseif not isWater(surfaceBlock) then
        depth = 0
      else
        depth = 0
        for y = surfaceY, math.max(0, surfaceY - 5), -1 do
          if not isWater(world:blockAt(cellX, y, cellZ)) then break end
          depth = depth + 1
        end
      end
    end

    -- One-block-deep water must remain nearly flat or displaced triangles cut
    -- through the voxel seabed. Full geometric waves return smoothly by four
    -- blocks of depth; normal-map ripples remain visible in the shallows.
    local t = saturate((depth - 0.75) / 2.75)
    cached = t * t * (3.0 - 2.0 * t)
    depthSamples[key] = cached
    return cached
  end

  local function vertexDepthFactor(x, z)
    if not world then return 1.0 end
    -- A grid vertex belongs to four water cells. Averaging those cells produces
    -- a continuous shoreline falloff and identical values on shared chunk edges.
    return (
      depthFactorAt(x - 1, z - 1) + depthFactorAt(x, z - 1) +
      depthFactorAt(x - 1, z) + depthFactorAt(x, z)
    ) * 0.25
  end

  local function sample(x, z)
    local key = x .. "," .. z
    local value = samples[key]
    if not value then
      local exposure, shore = classifyWaterWaves(x, z)
      local depthFactor = vertexDepthFactor(x, z)
      -- Macro shoreline classification controls the character of the water;
      -- actual bathymetry adds a stricter geometric safety limit up close.
      shore = math.min(shore, 0.025 + depthFactor * 0.975)
      value = {exposure, shore}
      samples[key] = value
    end
    return value[1], value[2]
  end

  -- Classification is evaluated only on the integer grid (mostly already in
  -- terrain.macroAt's generation cache), then bilinearly interpolated onto the
  -- half-block water tessellation. Shared chunk borders therefore receive the
  -- exact same values and cannot split into view-dependent wedges.
  return function(x, z)
    local x0 = math.floor(x)
    local z0 = math.floor(z)
    local tx = x - x0
    local tz = z - z0
    local e00, s00 = sample(x0, z0)
    local e10, s10 = sample(x0 + 1, z0)
    local e01, s01 = sample(x0, z0 + 1)
    local e11, s11 = sample(x0 + 1, z0 + 1)
    local e0 = e00 + (e10 - e00) * tx
    local e1 = e01 + (e11 - e01) * tx
    local s0 = s00 + (s10 - s00) * tx
    local s1 = s01 + (s11 - s01) * tx
    return e0 + (e1 - e0) * tz, s0 + (s1 - s0) * tz
  end
end

local function uploadTerrainChunkMesh(entry, vertices, options)
  options = options or {}
  local mesh = uploadTerrainMesh(vertices)
  if options.dielectricVertices and #options.dielectricVertices > 0 then
    mesh.dielectricMesh = uploadTerrainMesh(options.dielectricVertices)
  end
  local waterVertices = effects.waterChunkVertices(
    entry.chunk, entry.offsetX, entry.offsetZ, WATER_LEVEL, blocks.water, blocks.water_still,
    WATER_NEAR_TESSELLATION, createWaterWaveSampler(options.world)
  )
  if #waterVertices > 0 then
    mesh.waterMesh = uploadMesh(waterVertices)
  end
  mesh.chunkX = entry.chunkX
  mesh.chunkZ = entry.chunkZ
  mesh.bounds = terrainChunkBounds(entry)
  mesh.provisionalLight = options.provisionalLight or false
  mesh.lightRevision = options.lightRevision
  entry.hasMesh = true
  entry.hasGPUBuffer = true
  entry.isUploaded = true
  entry.renderReady = true
  entry.lightQuality = mesh.provisionalLight and "provisional" or "complete"
  return mesh
end

local function releaseTerrainMesh(mesh)
  if not mesh then return end
  rendering.release(mesh.dielectricMesh)
  rendering.release(mesh.waterMesh)
  rendering.release(mesh)
end

local function replaceTerrainMesh(terrainMeshes, key, mesh)
  releaseTerrainMesh(terrainMeshes[key])
  terrainMeshes[key] = mesh
end

local function releaseTerrainMeshes(terrainMeshes)
  for key, mesh in pairs(terrainMeshes) do
    releaseTerrainMesh(mesh)
    terrainMeshes[key] = nil
  end
end

local function createDistantTerrain()
  return DistantTerrain.new({
    radius = DISTANT_CHUNK_RADIUS,
    generationSteps = DISTANT_GENERATION_STEPS,
    buildBudget = DISTANT_BUILD_BUDGET,
    frameBudgetMs = DISTANT_FRAME_BUDGET_MS,
    ringBudget = DISTANT_RING_BUDGET,
    maxHeight = TERRAIN_MAX_H,
    waterId = blocks.water,
    stillWaterId = blocks.water_still,
    now = glfw.glfwGetTime,
    waveDataAt = createWaterWaveSampler(),
    upload = function(record, vertices, waterVertices, bounds, step)
      local mesh = uploadTerrainMesh(vertices)
      if #waterVertices > 0 then mesh.waterMesh = uploadMesh(waterVertices) end
      mesh.chunkX = record.chunkX
      mesh.chunkZ = record.chunkZ
      mesh.bounds = bounds
      mesh.distantLod = true
      mesh.lodStep = step
      return mesh
    end,
    release = releaseTerrainMesh
  })
end

local function uploadSkyMesh()
  local vertices = {
    -1, -1, 0, 0,0,1, 1,1,1, 0,0,
     3, -1, 0, 0,0,1, 1,1,1, 1,0,
    -1,  3, 0, 0,0,1, 1,1,1, 0,1
  }

  return uploadMesh(vertices)
end

local function appendCloudFace(vertices, x0, y0, z0, x1, y1, z1, nx, ny, nz, color)
  local r, g, b = color[1], color[2], color[3]
  local face

  if ny == 1 then
    face = {
      x0,y1,z1, nx,ny,nz, r,g,b, 0,1,
      x1,y1,z1, nx,ny,nz, r,g,b, 1,1,
      x1,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x1,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x0,y1,z0, nx,ny,nz, r,g,b, 0,0,
      x0,y1,z1, nx,ny,nz, r,g,b, 0,1
    }
  elseif ny == -1 then
    face = {
      x0,y0,z0, nx,ny,nz, r,g,b, 0,1,
      x1,y0,z0, nx,ny,nz, r,g,b, 1,1,
      x1,y0,z1, nx,ny,nz, r,g,b, 1,0,
      x1,y0,z1, nx,ny,nz, r,g,b, 1,0,
      x0,y0,z1, nx,ny,nz, r,g,b, 0,0,
      x0,y0,z0, nx,ny,nz, r,g,b, 0,1
    }
  elseif nx == 1 then
    face = {
      x1,y0,z1, nx,ny,nz, r,g,b, 0,1,
      x1,y0,z0, nx,ny,nz, r,g,b, 1,1,
      x1,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x1,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x1,y1,z1, nx,ny,nz, r,g,b, 0,0,
      x1,y0,z1, nx,ny,nz, r,g,b, 0,1
    }
  elseif nx == -1 then
    face = {
      x0,y0,z0, nx,ny,nz, r,g,b, 0,1,
      x0,y0,z1, nx,ny,nz, r,g,b, 1,1,
      x0,y1,z1, nx,ny,nz, r,g,b, 1,0,
      x0,y1,z1, nx,ny,nz, r,g,b, 1,0,
      x0,y1,z0, nx,ny,nz, r,g,b, 0,0,
      x0,y0,z0, nx,ny,nz, r,g,b, 0,1
    }
  elseif nz == 1 then
    face = {
      x0,y0,z1, nx,ny,nz, r,g,b, 0,1,
      x1,y0,z1, nx,ny,nz, r,g,b, 1,1,
      x1,y1,z1, nx,ny,nz, r,g,b, 1,0,
      x1,y1,z1, nx,ny,nz, r,g,b, 1,0,
      x0,y1,z1, nx,ny,nz, r,g,b, 0,0,
      x0,y0,z1, nx,ny,nz, r,g,b, 0,1
    }
  else
    face = {
      x1,y0,z0, nx,ny,nz, r,g,b, 0,1,
      x0,y0,z0, nx,ny,nz, r,g,b, 1,1,
      x0,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x0,y1,z0, nx,ny,nz, r,g,b, 1,0,
      x1,y1,z0, nx,ny,nz, r,g,b, 0,0,
      x1,y0,z0, nx,ny,nz, r,g,b, 0,1
    }
  end

  for i = 1, #face do
    vertices[#vertices + 1] = face[i]
  end
end

local function createCloudMesh(path)
  local img = texture.loadPng(path)
  if not img then
    error("Failed to load cloud texture: " .. path)
  end

  local cells = CLOUD_MESH_CELLS
  local filled = {}
  local function sampleValue(x, z)
    local sx = x % img.w
    local sz = z % img.h
    local idx = (sz * img.w + sx) * 4
    local r = img.data[idx] / 255.0
    local g = img.data[idx + 1] / 255.0
    local b = img.data[idx + 2] / 255.0
    local a = img.data[idx + 3] / 255.0
    return math.max(r, g, b) * a
  end

  local function sampleFilled(x, z)
    local center = sampleValue(x, z)
    local neighbors = 0.0
    for dx = -1, 1 do
      for dz = -1, 1 do
        neighbors = neighbors + sampleValue(x + dx, z + dz)
      end
    end
    neighbors = neighbors / 9.0
    return center > 0.26 or (center > 0.12 and neighbors > 0.22)
  end

  for x = 0, cells - 1 do
    filled[x] = {}
    for z = 0, cells - 1 do
      filled[x][z] = sampleFilled(x, z)
    end
  end

  local function isFilled(x, z)
    if x < 0 or x >= cells or z < 0 or z >= cells then
      return false
    end
    return filled[x][z]
  end

  local vertices = {}
  local half = cells * CLOUD_CELL_SIZE * 0.5
  for x = 0, cells - 1 do
    for z = 0, cells - 1 do
      if filled[x][z] then
        local x0 = x * CLOUD_CELL_SIZE - half
        local z0 = z * CLOUD_CELL_SIZE - half
        local x1 = x0 + CLOUD_CELL_SIZE
        local z1 = z0 + CLOUD_CELL_SIZE
        local variation = 0.96 + ((x * 37 + z * 17) % 9) * 0.005
        appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, 0, 1, 0, {variation, variation, variation})
        appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, 0, -1, 0, {0.72, 0.76, 0.82})
        if not isFilled(x + 1, z) then appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, 1, 0, 0, {0.84, 0.87, 0.92}) end
        if not isFilled(x - 1, z) then appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, -1, 0, 0, {0.84, 0.87, 0.92}) end
        if not isFilled(x, z + 1) then appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, 0, 0, 1, {0.84, 0.87, 0.92}) end
        if not isFilled(x, z - 1) then appendCloudFace(vertices, x0, CLOUD_BOTTOM, z0, x1, CLOUD_TOP, z1, 0, 0, -1, {0.84, 0.87, 0.92}) end
      end
    end
  end

  return uploadMesh(vertices)
end

local function createTextureAtlas()
  local atlas = texture.createAtlas()
  blocks.initTextures(atlas)
  require("items").initTextures(atlas)

  local atlasTex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, atlasTex)
  gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
  local maxMipLevel = atlas:getMaxMipLevel()
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
    maxMipLevel > 0 and GL_NEAREST_MIPMAP_LINEAR or GL_NEAREST)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, maxMipLevel)
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, atlas.w, atlas.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas.pixels)
  if maxMipLevel > 0 then
    gl.glGenerateMipmap(GL_TEXTURE_2D)
  end

  return atlasTex
end

local function createImageTexture(path, nearest, repeatWrap)
  local img = texture.loadPng(path)
  if not img then
    error("Failed to load texture: " .. path)
  end

  local tex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, tex)
  gl.glBindTexture(GL_TEXTURE_2D, tex[0])
  local filter = nearest and GL_NEAREST or GL_LINEAR
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
  local wrap = repeatWrap and GL_REPEAT or GL_CLAMP_TO_EDGE
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap)
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img.w, img.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img.data)

  return tex
end

-- Samplers for meshing one chunk. Both are bound to the 3x3 chunk neighbourhood
-- so the mesher can cull boundary faces against real neighbours and light their
-- corners correctly. Provisional light is only used before the world has
-- finished lighting; it forces dark cells bright so a chunk can be shown early.
local function meshOptions(world, entry, provisionalLight, yieldStep)
  local light = world:skyLightSampler(entry.chunkX, entry.chunkZ)

  if provisionalLight then
    local base = light
    light = function(x, y, z)
      local level = base(x, y, z)
      if level <= 0 and y >= 0 then
        return 15
      end
      return level
    end
  end

  return {
    skyLightAt = light,
    blockAt = world:blockSampler(entry.chunkX, entry.chunkZ),
    yieldStep = yieldStep
  }
end

local function createTerrainMesh(entry, world)
  local provisionalLight = not world:lightingReady()
  local vertices, dielectricVertices = voxel.meshChunk(
    entry.chunk, world.maxHeight, entry.offsetX, entry.offsetZ,
    meshOptions(world, entry, provisionalLight)
  )
  return uploadTerrainChunkMesh(entry, vertices, {
    dielectricVertices = dielectricVertices,
    provisionalLight = provisionalLight,
    lightRevision = world.lightRevision,
    world = world
  })
end

local function createTerrainMeshes(world)
  local meshes = {}

  world:eachChunk(function(chunk, entry)
    replaceTerrainMesh(meshes, World.chunkKey(entry.chunkX, entry.chunkZ), createTerrainMesh(entry, world))
  end)

  return meshes
end

local function meshEntryForItem(item)
  return item.entry or item
end

local function ensureTerrainMeshThread(world, item)
  if item.meshThread then
    return
  end

  local entry = meshEntryForItem(item)
  if item.provisionalLight == nil then
    item.provisionalLight = not world:lightingReady()
  end
  local provisionalLight = item.provisionalLight
  item.meshThread = coroutine.create(function()
    item.vertices, item.dielectricVertices = voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetZ,
      meshOptions(world, entry, provisionalLight, function()
        coroutine.yield(false)
      end))
    return true
  end)
end

local function stepTerrainMeshItem(world, item)
  ensureTerrainMeshThread(world, item)

  local ok, err = coroutine.resume(item.meshThread)
  if not ok then
    error(err)
  end

  return coroutine.status(item.meshThread) == "dead" and item.vertices ~= nil
end

local function randomWorldSeed()
  local clock = math.floor(os.clock() * 1000000)
  local seed = (os.time() * 1103515245 + clock * 12345) % 2147483647
  seed = math.floor(seed)
  return seed ~= 0 and seed or 1
end

local function createWorldLoadingJob(config)
  config.worldId = worldProfiles.id(config.worldId)
  local worldProfile = worldProfiles.get(config.worldId)
  local seed = tonumber(config.seed) or randomWorldSeed()
  local selectedRenderRadius = math.max(4, math.min(128,
    math.floor(tonumber(config.renderDistance) or DISTANT_CHUNK_RADIUS)))
  local chunkRenderRadius = math.min(CHUNK_RENDER_RADIUS, selectedRenderRadius)
  local save = config.existingWorld or saves.createWorld({
    worldName = config.worldName,
    gameMode = config.gameMode,
    generatorType = config.generatorType,
    worldId = config.worldId,
    seed = seed,
    generateStructures = config.generateStructures,
    allowCheats = config.allowCheats,
    bonusChest = config.bonusChest
  })
  local savedPlayer = config.existingWorld and saves.loadPlayer(save) or nil
  terrain.setWorldProfile(config.worldId)
  terrain.setSeed(seed)
  local preferredX = config.spawnX or DEFAULT_SPAWN_X
  local preferredZ = config.spawnZ or DEFAULT_SPAWN_Z
  local savedPosition = savedPlayer and savedPlayer.camera and savedPlayer.camera.position
  local hasSavedPosition = type(savedPosition) == "table" and
    tonumber(savedPosition[1]) ~= nil and tonumber(savedPosition[3]) ~= nil
  if hasSavedPosition then
    preferredX = tonumber(savedPosition[1])
    preferredZ = tonumber(savedPosition[3])
  end
  local spawnX, spawnZ, spawnColumn
  if hasSavedPosition then
    spawnX, spawnZ = preferredX, preferredZ
  elseif config.generatorType == "superflat" then
    spawnX, spawnZ = preferredX, preferredZ
  else
    spawnX, spawnZ, spawnColumn = terrain.findSafeSpawn(preferredX, preferredZ, TERRAIN_MAX_H)
  end
  if spawnColumn then
    print(string.format("Spawn: %s at %.1f, %.1f (ground %d)",
      tostring(spawnColumn.biome), spawnX, spawnZ, spawnColumn.height))
  end
  local plan = spawnLoading.createPlan({
    centerChunkX = World.chunkCoord(spawnX),
    centerChunkZ = World.chunkCoord(spawnZ),
    requiredRadius = math.min(chunkRenderRadius, LOADING_REQUIRED_RADIUS),
    haloRadius = math.min(chunkRenderRadius, LOADING_HALO_RADIUS)
  })
  local world = World.new({
    chunkRadius = chunkRenderRadius,
    maxHeight = TERRAIN_MAX_H,
    generatorType = config.generatorType,
    worldId = config.worldId,
    seed = seed,
    deferInitialChunks = true
  })

  return {
    config = config,
    save = save,
    savedPlayer = savedPlayer,
    world = world,
    terrainMeshes = {},
    plan = plan,
    coords = plan.coords,
    spawnX = spawnX,
    spawnZ = spawnZ,
    chunkIndex = 1,
    chunkJob = nil,
    centerEntry = nil,
    spawnMeshItem = nil,
    spawnMeshComplete = false,
    generatedChunks = 0,
    lightingStarted = false,
    streamingEntries = nil,
    title = "Generating level",
    message = "Building spawn terrain",
    progress = 0.0,
    seed = seed,
    worldProfile = worldProfile
  }
end

local function stepWorldLoadingJob(job)
  local chunkBudget = LOADING_CHUNK_BUDGET
  local meshBudget = LOADING_MESH_BUDGET

  while chunkBudget > 0 and job.chunkIndex <= #job.coords do
    if not job.chunkJob then
      local coord = job.coords[job.chunkIndex]
      job.chunkJob = job.world:createChunkJob(coord.chunkX, coord.chunkZ)
    end

    local ok, err = coroutine.resume(job.chunkJob.thread)
    if not ok then
      error(err)
    end

    if coroutine.status(job.chunkJob.thread) == "dead" then
      local entry = job.chunkJob.entry
      if entry then
        job.generatedChunks = job.generatedChunks + 1
        if spawnLoading.isCenterChunk(job.plan, entry.chunkX, entry.chunkZ) then
          job.centerEntry = entry
        end
      end
      job.chunkJob = nil
      job.chunkIndex = job.chunkIndex + 1
    end

    chunkBudget = chunkBudget - 1
  end

  if job.chunkIndex > #job.coords then
    job.lightingStarted = true
    job.world:stepLightingJob(LOADING_LIGHTING_STEP_BUDGET)
  end

  if job.chunkIndex > #job.coords and job.world:lightingReady() then
    job.centerEntry = job.centerEntry or spawnLoading.centerEntry(job.plan, job.world)
    if job.centerEntry and not job.spawnMeshItem then
      job.spawnMeshItem = {
        chunkX = job.centerEntry.chunkX,
        chunkZ = job.centerEntry.chunkZ,
        entry = job.centerEntry
      }
    end

    while meshBudget > 0 and job.spawnMeshItem and not job.spawnMeshComplete do
      local item = job.spawnMeshItem
      if stepTerrainMeshItem(job.world, item) then
        local entry = item.entry
        replaceTerrainMesh(job.terrainMeshes, World.chunkKey(entry.chunkX, entry.chunkZ), uploadTerrainChunkMesh(entry, item.vertices, {
          provisionalLight = item.provisionalLight,
          lightRevision = job.world.lightRevision,
          world = job.world
        }))
        item.vertices = nil
        item.meshThread = nil
        item.provisionalLight = nil
        job.spawnMeshComplete = true
      end
      meshBudget = meshBudget - 1
    end
  end

  job.message = spawnLoading.message(job.plan, job)
  job.progress = spawnLoading.progress(job.plan, job)
  if spawnLoading.isSpawnPlayable(job.plan, job.world, job.terrainMeshes) then
    job.progress = 1.0
    job.message = "Joining world"
    job.streamingEntries = spawnLoading.streamingMeshQueue(job.plan, job.world, job.terrainMeshes)
    return true
  end

  return false
end

local function pendingChunkCoords(item)
  if item.entry then
    return item.entry.chunkX, item.entry.chunkZ
  end
  return item.chunkX, item.chunkZ
end

-- `urgent` marks work the player is waiting to see. The queue is processed from
-- the front, so without this a remesh caused by placing a block queues behind
-- every pending chunk generation -- up to CHUNK_QUEUE_BACKLOG of them, seconds
-- of work -- and the edit stays invisible until streaming catches up.
local function queueChunkRemesh(pendingEntries, entry, urgent)
  if not entry then
    return
  end

  local key = World.chunkKey(entry.chunkX, entry.chunkZ)
  for i = 1, #pendingEntries do
    local chunkX, chunkZ = pendingChunkCoords(pendingEntries[i])
    if chunkX and chunkZ and World.chunkKey(chunkX, chunkZ) == key then
      local item = pendingEntries[i]
      item.entry = item.entry or entry
      item.rebuild = true
      if urgent and i > 1 then
        table.remove(pendingEntries, i)
        table.insert(pendingEntries, 1, item)
      end
      return
    end
  end

  local item = {
    chunkX = entry.chunkX,
    chunkZ = entry.chunkZ,
    entry = entry,
    rebuild = true
  }

  if urgent then
    table.insert(pendingEntries, 1, item)
  else
    pendingEntries[#pendingEntries + 1] = item
  end
end

local function queueProvisionalLightRemeshes(world, terrainMeshes, pendingEntries)
  for key, mesh in pairs(terrainMeshes) do
    if mesh and mesh.provisionalLight then
      local entry = world.chunks[key]
      if entry then
        queueChunkRemesh(pendingEntries, entry)
      end
    end
  end
end

-- The incremental light update records every chunk it wrote into. Remesh those
-- and nothing else.
local function queueLightTouchedRemeshes(world, pendingEntries, urgent)
  local touched = world:drainLightTouched()
  local queued = 0

  for _, entry in pairs(touched) do
    if entry.hasMesh then
      queueChunkRemesh(pendingEntries, entry, urgent)
      queued = queued + 1
    end
  end

  return queued
end

local function queueTerrainMeshes(world, pendingEntries, x, z, budget, priority, externallyPending)
  budget = budget or CHUNK_QUEUE_BUDGET
  priority = priority or {}
  local centerChunkX = World.chunkCoord(x)
  local centerChunkZ = World.chunkCoord(z)
  local predictedChunkX = World.chunkCoord(priority.predictedX or x)
  local predictedChunkZ = World.chunkCoord(priority.predictedZ or z)
  local forwardX = priority.forwardX or 0.0
  local forwardZ = priority.forwardZ or 0.0
  local coords = {}
  local queued = {}

  for i = 1, #pendingEntries do
    local chunkX, chunkZ = pendingChunkCoords(pendingEntries[i])
    if chunkX and chunkZ then
      queued[World.chunkKey(chunkX, chunkZ)] = true
    end
  end

  for chunkX = centerChunkX - world.chunkRadius, centerChunkX + world.chunkRadius do
    for chunkZ = centerChunkZ - world.chunkRadius, centerChunkZ + world.chunkRadius do
      local key = World.chunkKey(chunkX, chunkZ)
      if not world.chunks[key] and not queued[key] and
          not (externallyPending and externallyPending(chunkX, chunkZ)) then
        coords[#coords + 1] = {chunkX = chunkX, chunkZ = chunkZ}
      end
    end
  end

  table.sort(coords, function(a, b)
    local adx = a.chunkX - centerChunkX
    local adz = a.chunkZ - centerChunkZ
    local bdx = b.chunkX - centerChunkX
    local bdz = b.chunkZ - centerChunkZ
    local apx = a.chunkX - predictedChunkX
    local apz = a.chunkZ - predictedChunkZ
    local bpx = b.chunkX - predictedChunkX
    local bpz = b.chunkZ - predictedChunkZ
    local ad = adx * adx + adz * adz + (apx * apx + apz * apz) * 0.65
    local bd = bdx * bdx + bdz * bdz + (bpx * bpx + bpz * bpz) * 0.65

    local al = math.sqrt(adx * adx + adz * adz)
    local bl = math.sqrt(bdx * bdx + bdz * bdz)
    if al > 0.0 then
      ad = ad - ((adx / al) * forwardX + (adz / al) * forwardZ) * 3.0
    end
    if bl > 0.0 then
      bd = bd - ((bdx / bl) * forwardX + (bdz / bl) * forwardZ) * 3.0
    end

    if ad == bd then
      return a.chunkX == b.chunkX and a.chunkZ < b.chunkZ or a.chunkX < b.chunkX
    end
    return ad < bd
  end)

  local created = 0
  for i = 1, #coords do
    if created >= budget then
      break
    end
    local coord = coords[i]
    pendingEntries[#pendingEntries + 1] = world:createChunkJob(coord.chunkX, coord.chunkZ)
    created = created + 1
  end
end

local function processTerrainMeshQueue(world, terrainMeshes, pendingEntries, budget)
  budget = budget or TERRAIN_WORK_BUDGET
  local processed = 0
  local deadline = glfw.glfwGetTime() + TERRAIN_FRAME_BUDGET
  local lightingWasReady = world:lightingReady()
  local stats = {
    budget = budget,
    budgetMs = TERRAIN_FRAME_BUDGET * 1000.0,
    elapsedMs = 0,
    timeSliced = false,
    processed = 0,
    chunkSteps = 0,
    meshSteps = 0,
    meshUploads = 0,
    syncUploads = 0,
    dropped = 0,
    lightingBudget = 0,
    lightingReadyBefore = lightingWasReady,
    lightingReadyAfter = lightingWasReady
  }

  while processed < budget and #pendingEntries > 0 do
    local item = pendingEntries[1]
    if item.thread and not item.entry then
      local ok, err = coroutine.resume(item.thread)
      if not ok then
        error(err)
      end
      processed = processed + 1

      if coroutine.status(item.thread) == "dead" and not item.entry then
        table.remove(pendingEntries, 1)
        stats.dropped = stats.dropped + 1
        break
      end
      stats.chunkSteps = stats.chunkSteps + 1
    elseif item.entry then
      local completed = stepTerrainMeshItem(world, item)
      processed = processed + 1
      stats.meshSteps = stats.meshSteps + 1

      if completed then
        replaceTerrainMesh(terrainMeshes, World.chunkKey(item.entry.chunkX, item.entry.chunkZ), uploadTerrainChunkMesh(item.entry, item.vertices, {
          dielectricVertices = item.dielectricVertices,
          provisionalLight = item.provisionalLight,
          lightRevision = world.lightRevision,
          world = world
        }))
        stats.meshUploads = stats.meshUploads + 1
        item.vertices = nil
        item.dielectricVertices = nil
        item.meshThread = nil
        item.provisionalLight = nil
        table.remove(pendingEntries, 1)
        break
      end
    else
      local entry = table.remove(pendingEntries, 1)
      replaceTerrainMesh(terrainMeshes, World.chunkKey(entry.chunkX, entry.chunkZ), createTerrainMesh(entry, world))
      processed = processed + 1
      stats.syncUploads = stats.syncUploads + 1
      break
    end

    -- Checked after the body so at least one step always runs; otherwise a
    -- frame that is already over budget would never make progress.
    if glfw.glfwGetTime() >= deadline then
      stats.timeSliced = true
      break
    end
  end

  stats.elapsedMs = (glfw.glfwGetTime() - (deadline - TERRAIN_FRAME_BUDGET)) * 1000.0

  stats.processed = processed
  if world.lightDirty or world.lightingJob then
    stats.lightingBudget = LIGHTING_STEP_BUDGET
    local lightingReady = world:stepLightingJob(LIGHTING_STEP_BUDGET)
    if lightingReady and not lightingWasReady then
      queueProvisionalLightRemeshes(world, terrainMeshes, pendingEntries)
    end
    stats.lightingReadyAfter = lightingReady
  end

  -- Newly generated chunks light themselves and can spill into a neighbour that
  -- is already meshed; pick those up here.
  stats.lightRemeshes = queueLightTouchedRemeshes(world, pendingEntries)

  return stats
end

local function pruneTerrainMeshes(world, terrainMeshes, pendingEntries, x, z)
  local centerChunkX = World.chunkCoord(x)
  local centerChunkZ = World.chunkCoord(z)
  local keepRadius = world.chunkRadius + 1

  for key, entry in pairs(world.chunks) do
    if math.abs(entry.chunkX - centerChunkX) > keepRadius or math.abs(entry.chunkZ - centerChunkZ) > keepRadius then
      world.chunks[key] = nil
      if world.lightTouched then world.lightTouched[key] = nil end
      releaseTerrainMesh(terrainMeshes[key])
      terrainMeshes[key] = nil
    end
  end

  local i = 1
  while i <= #pendingEntries do
    local entry = pendingEntries[i]
    local chunkX, chunkZ = pendingChunkCoords(entry)
    if chunkX and chunkZ and (math.abs(chunkX - centerChunkX) > keepRadius or math.abs(chunkZ - centerChunkZ) > keepRadius) then
      table.remove(pendingEntries, i)
    else
      i = i + 1
    end
  end
end

local function rebuildChunkMesh(world, pendingEntries, chunkX, chunkZ, urgent)
  local key = World.chunkKey(chunkX, chunkZ)
  local entry = world.chunks[key]
  if entry then
    queueChunkRemesh(pendingEntries, entry, urgent)
  end
end

-- Called when the player places or breaks a block, so everything here is urgent:
-- the block data (and its collision) has already changed and the mesh is the
-- only thing left before the edit becomes visible.
local function rebuildBlockChunkMeshes(world, pendingEntries, x, z)
  local _, _, chunkX, chunkZ = world:localBlockCoord(x, z)
  rebuildChunkMesh(world, pendingEntries, chunkX, chunkZ, true)

  -- Neighbour geometry never depends on this chunk (voxel.lua treats anything
  -- outside 0..15 as air), so the only reason to touch a neighbour is light,
  -- and the update tells us exactly which ones changed.
  queueLightTouchedRemeshes(world, pendingEntries, true)
end

local function rebuildChangedBlockMeshes(world,pendingEntries,changed)
  local chunks={}
  for _,p in ipairs(changed or {}) do
    local _,_,cx,cz=world:localBlockCoord(p.x,p.z)
    chunks[cx..":"..cz]={x=cx,z=cz}
  end
  for _,chunk in pairs(chunks) do rebuildChunkMesh(world,pendingEntries,chunk.x,chunk.z,true) end
  queueLightTouchedRemeshes(world,pendingEntries,true)
end

local function createCharacterMesh()
  local player = character.createPlayer({8, 6, 8})
  return uploadMesh(player:createMesh())
end

local function releaseDroppedItemMeshes(meshes)
  for item, mesh in pairs(meshes) do
    if mesh then rendering.release(mesh) end
    meshes[item] = nil
  end
end

local function drawDroppedItems(manager, meshes, modelLocation, identityModel)
  for _, entity in ipairs(manager.items) do
    local mesh = meshes[entity.item]
    if mesh == nil then
      local vertices = DroppedItems.meshVertices(entity.item)
      mesh = #vertices > 0 and uploadTerrainMesh(vertices) or false
      meshes[entity.item] = mesh
    end
    if mesh then
      local rotation = entity.rotation or {0.0, 0.0, 0.0}
      local sx, cx = math.sin(rotation[1]), math.cos(rotation[1])
      local sy, cy = math.sin(rotation[2]), math.cos(rotation[2])
      local sz, cz = math.sin(rotation[3]), math.cos(rotation[3])
      local transform = {
        cz*cy, sz*cy, -sy, 0,
        cz*sy*sx-sz*cx, sz*sy*sx+cz*cx, cy*sx, 0,
        cz*sy*cx+sz*sx, sz*sy*cx-cz*sx, cy*cx, 0,
        entity.position[1], entity.position[2], entity.position[3], 1
      }
      gl.glUniformMatrix4fv(modelLocation, 1, 0, ffi.new("float[16]", transform))
      rendering.draw(mesh)
    end
  end
  gl.glUniformMatrix4fv(modelLocation, 1, 0, ffi.new("float[16]", identityModel))
end


local function releaseFallingTreeMeshes(meshes)
  for id,mesh in pairs(meshes) do if mesh then rendering.release(mesh) end meshes[id]=nil end
end

local function drawFallingTrees(manager,meshes,modelLocation,identityModel)
  for _,tree in ipairs(manager.trees) do
    local mesh=meshes[tree.id]
    if mesh==nil then mesh=#tree.vertices>0 and uploadTerrainMesh(tree.vertices) or false meshes[tree.id]=mesh end
    if mesh then
      gl.glUniformMatrix4fv(modelLocation,1,0,ffi.new("float[16]",manager:model(tree)))
      rendering.draw(mesh)
    end
  end
  gl.glUniformMatrix4fv(modelLocation,1,0,ffi.new("float[16]",identityModel))
end

local function drawSky(skyShader, skyMesh, locations, moonTexture, playerCamera, sunDir, sky, time, worldProfile)
  local forward = playerCamera:getFront()
  local worldUp = {0.0, 1.0, 0.0}
  local right = math3d.normalize(math3d.cross(forward, worldUp))
  local up = math3d.normalize(math3d.cross(right, forward))

  gl.glDisable(GL_DEPTH_TEST)
  gl.glUseProgram(skyShader)
  gl.glUniform3f(locations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(locations.time, time, 0.0, 0.0)
  gl.glUniform3f(locations.cameraForward, forward[1], forward[2], forward[3])
  gl.glUniform3f(locations.cameraRight, right[1], right[2], right[3])
  gl.glUniform3f(locations.cameraUp, up[1], up[2], up[3])
  gl.glUniform3f(locations.cameraPosition, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
  gl.glUniform3f(locations.cameraProjection, windowWidth / windowHeight * math.tan(CAMERA_FOV / 2), math.tan(CAMERA_FOV / 2), 0.0)
  local profileSky = (worldProfile or worldProfiles.get("earth")).sky
  local profileAtmosphere = (worldProfile or worldProfiles.get("earth")).atmosphere
  gl.glUniform3f(locations.skyTuning, graphics.atmosphere.skyExposure, graphics.atmosphere.cloudDensity, graphics.atmosphere.sunGlare)
  gl.glUniform3f(locations.skyParams,
    (SKY.scatterStrength or 1.0) * (profileSky.scatterStrengthScale or 1.0),
    profileAtmosphere.moonAmount or 0.0,
    (SKY.sunIntensity or 22.0) * (profileSky.sunIntensityScale or 1.0))
  gl.glUniform3f(locations.sunDisc,
    (SKY.sunAngularRadius or 0.012) * (profileSky.sunAngularScale or 1.0),
    (SKY.sunDiscBrightness or 9.0) * (profileSky.sunDiscScale or 1.0), 0.0)
  gl.glUniform3f(locations.scatteringPlanet,
    profileSky.planetRadiusMeters, profileSky.atmosphereHeightMeters, terrain.SEA_LEVEL - 1.0)
  gl.glUniform3f(locations.scatteringScale,
    profileSky.rayleighScaleHeightMeters, profileSky.dustScaleHeightMeters, profileSky.dustAnisotropy)
  gl.glUniform3f(locations.scatteringRayleigh,
    profileSky.rayleighBeta[1], profileSky.rayleighBeta[2], profileSky.rayleighBeta[3])
  gl.glUniform3f(locations.scatteringDust,
    profileSky.dustBeta[1], profileSky.dustBeta[2], profileSky.dustBeta[3])
  gl.glUniform3f(locations.aureoleColor,
    profileSky.aureoleColor[1], profileSky.aureoleColor[2], profileSky.aureoleColor[3])
  gl.glUniform3f(locations.aureoleParams,
    profileSky.aureoleFocus or 420.0, profileSky.aureoleStrength or 0.16, 0.0)
  gl.glUniform3f(locations.fogColor, sky.fogColor[1], sky.fogColor[2], sky.fogColor[3])
  gl.glActiveTexture(GL_TEXTURE2)
  gl.glBindTexture(GL_TEXTURE_2D, moonTexture[0])
  rendering.draw(skyMesh)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glEnable(GL_DEPTH_TEST)
end

local function drawClouds(cloudShader, cloudMesh, locations, playerCamera, view, projection, time, sky)
  local drift = time * 0.55
  local span = CLOUD_MESH_CELLS * CLOUD_CELL_SIZE
  local offsetX = math.floor((playerCamera.position[1] + drift) / span + 0.5) * span
  local offsetZ = math.floor((playerCamera.position[3] + drift * 0.12) / span + 0.5) * span

  gl.glUseProgram(cloudShader)
  gl.glUniformMatrix4fv(locations.projection, 1, 0, ffi.new("float[16]", projection))
  gl.glUniformMatrix4fv(locations.view, 1, 0, ffi.new("float[16]", view))
  gl.glUniform3f(locations.offset, offsetX - drift, 0.0, offsetZ - drift * 0.12)
  gl.glUniform1f(locations.alpha, CLOUD_ALPHA)
  gl.glUniform3f(locations.tint, sky.cloudColor[1], sky.cloudColor[2], sky.cloudColor[3])

  -- Cloud cells are closed boxes wound counter-clockwise outwards, and shared
  -- side walls are not emitted. Always cull their back faces: from outside this
  -- leaves one visible surface per pixel, and from inside a cloud it correctly
  -- hides the box interior instead of exposing a second translucent shell.
  gl.glEnable(GL_CULL_FACE)
  gl.glCullFace(GL_BACK)

  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  -- Keep the nearest cloud surface in the scene depth texture. Besides stopping
  -- translucent shells from stacking, this gives volumetric composition the
  -- cloud's real distance instead of treating it as infinitely far sky.
  gl.glDepthMask(1)
  rendering.draw(cloudMesh)
  gl.glDisable(GL_BLEND)
  gl.glDisable(GL_CULL_FACE)
end

local function visibleTerrainMeshes(terrainMeshes, frustum, centerChunkX, centerChunkZ, radius)
  local visible = {}
  for _, mesh in pairs(terrainMeshes) do
    if mesh then
      local inRadius = not centerChunkX or
        math.max(math.abs(mesh.chunkX - centerChunkX), math.abs(mesh.chunkZ - centerChunkZ)) <= radius
      if inRadius and (not mesh.bounds or math3d.aabbInFrustum(frustum, mesh.bounds)) then
        visible[#visible + 1] = mesh
      end
    end
  end
  return visible
end

local function appendMeshes(target, source)
  for i = 1, #source do target[#target + 1] = source[i] end
  return target
end

local function visibleDielectricMeshes(visibleTerrain)
  local visible = {}
  for i = 1, #visibleTerrain do
    local dielectricMesh = visibleTerrain[i].dielectricMesh
    if dielectricMesh and dielectricMesh.count > 0 then
      visible[#visible + 1] = dielectricMesh
    end
  end
  return visible
end

local function visibleWaterMeshes(visibleTerrain)
  local visible = {}
  for i = 1, #visibleTerrain do
    local waterMesh = visibleTerrain[i].waterMesh
    if waterMesh and waterMesh.count > 0 then
      visible[#visible + 1] = waterMesh
    end
  end
  return visible
end

local function formatNumber(value, decimals)
  return string.format("%." .. tostring(decimals or 1) .. "f", tonumber(value) or 0.0)
end

local function formatBytes(bytes)
  bytes = tonumber(bytes) or 0
  if bytes >= 1024 * 1024 then
    return formatNumber(bytes / (1024 * 1024), 1) .. " MB"
  end
  return formatNumber(bytes / 1024, 1) .. " KB"
end

local function blockDebugName(id)
  if not id or id == 0 then
    return "minecraft:air"
  end

  local def = blocks.list[id]
  local name = def and (def.key or def.name) or ("unknown_" .. tostring(id))
  if not string.find(name, ":", 1, true) then
    name = "minecraft:" .. name
  end
  return name
end

local function cameraFacingName(yaw)
  local normalized = ((yaw or 0.0) % 360.0 + 360.0) % 360.0
  if normalized >= 45.0 and normalized < 135.0 then
    return "south (+Z)"
  end
  if normalized >= 135.0 and normalized < 225.0 then
    return "west (-X)"
  end
  if normalized >= 225.0 and normalized < 315.0 then
    return "north (-Z)"
  end
  return "east (+X)"
end

local function collectChunkStats(world, pendingEntries)
  local stats = {
    loaded = 0,
    terrain = 0,
    collision = 0,
    serverReady = 0,
    light = 0,
    mesh = 0,
    gpu = 0,
    uploaded = 0,
    renderReady = 0,
    pending = #pendingEntries,
    pendingGenerate = 0,
    pendingMesh = 0,
    pendingRemesh = 0
  }

  for _, entry in pairs(world.chunks) do
    stats.loaded = stats.loaded + 1
    if entry.hasTerrain then stats.terrain = stats.terrain + 1 end
    if entry.hasCollision then stats.collision = stats.collision + 1 end
    if entry.serverReady then stats.serverReady = stats.serverReady + 1 end
    if entry.hasInitialLight then stats.light = stats.light + 1 end
    if entry.hasMesh then stats.mesh = stats.mesh + 1 end
    if entry.hasGPUBuffer then stats.gpu = stats.gpu + 1 end
    if entry.isUploaded then stats.uploaded = stats.uploaded + 1 end
    if entry.renderReady then stats.renderReady = stats.renderReady + 1 end
  end

  for i = 1, #pendingEntries do
    local item = pendingEntries[i]
    if item.thread and not item.entry then
      stats.pendingGenerate = stats.pendingGenerate + 1
    elseif item.rebuild then
      stats.pendingRemesh = stats.pendingRemesh + 1
    else
      stats.pendingMesh = stats.pendingMesh + 1
    end
  end

  return stats
end

local function collectMeshStats(terrainMeshes, visibleMeshes)
  local stats = {
    uploaded = 0,
    visible = #visibleMeshes,
    provisional = 0,
    totalVertices = 0,
    visibleVertices = 0,
    bytes = 0
  }

  for _, mesh in pairs(terrainMeshes) do
    if mesh then
      stats.uploaded = stats.uploaded + 1
      stats.totalVertices = stats.totalVertices + (mesh.count or 0)
      if mesh.provisionalLight then
        stats.provisional = stats.provisional + 1
      end
    end
  end

  for i = 1, #visibleMeshes do
    stats.visibleVertices = stats.visibleVertices + (visibleMeshes[i].count or 0)
  end

  stats.bytes = stats.totalVertices * TERRAIN_VERTEX_STRIDE_FLOATS * 4
  return stats
end

local function updateDebugFrameStats(state, dt)
  state.debugFrames = state.debugFrames + 1
  state.debugFrameAccumulator = state.debugFrameAccumulator + dt
  state.debugLastFrameMs = dt * 1000.0

  if state.debugFrameAccumulator >= 0.5 then
    state.debugFps = state.debugFrames / math.max(0.001, state.debugFrameAccumulator)
    state.debugFrameMs = state.debugFrameAccumulator / math.max(1, state.debugFrames) * 1000.0
    state.debugFrames = 0
    state.debugFrameAccumulator = 0.0
  end
end

local function buildDebugInfo(world, terrainMeshes, visibleMeshes, pendingEntries, playerCamera, state, currentTime, queueStats, sky, sunDir)
  queueStats = queueStats or {}
  sky = sky or {}
  sunDir = sunDir or {0.0, 1.0, 0.0}
  local pos = playerCamera.position
  local feetY = pos[2] - (playerCamera.eyeHeight or 1.62)
  local blockX = math.floor(pos[1])
  local blockY = math.floor(feetY)
  local blockZ = math.floor(pos[3])
  local eyeBlockY = math.floor(pos[2])
  local chunkX = World.chunkCoord(blockX)
  local chunkZ = World.chunkCoord(blockZ)
  local localX = blockX - chunkX * 16
  local localZ = blockZ - chunkZ * 16
  local biomeName = terrain.biomeAt(blockX, blockZ)
  local generation = terrain.debugFieldsAt(blockX, blockZ, TERRAIN_MAX_H)
  local target = world:raycast(pos, playerCamera:getFront(), playerCamera.reach or 6.0)
  local targetLine = "Looking at: none"
  if target then
    targetLine = string.format(
      "Looking at: %s (%d %d %d)",
      blockDebugName(target.id),
      target.x,
      target.y,
      target.z
    )
  end

  local chunkStats = collectChunkStats(world, pendingEntries)
  local meshStats = collectMeshStats(terrainMeshes, visibleMeshes)
  local standingOn = world:blockAt(blockX, blockY - 1, blockZ)
  local insideBlock = world:blockAt(blockX, eyeBlockY, blockZ)
  local speed = math.sqrt(
    (playerCamera.velocity[1] or 0.0) * (playerCamera.velocity[1] or 0.0) +
    (playerCamera.velocity[2] or 0.0) * (playerCamera.velocity[2] or 0.0) +
    (playerCamera.velocity[3] or 0.0) * (playerCamera.velocity[3] or 0.0)
  )
  local memMb = collectgarbage("count") / 1024.0
  local runtime = (_G.jit and jit.version) or _VERSION
  local queueLine = string.format(
    "Queue: %d pending (%d gen, %d mesh, %d remesh)",
    chunkStats.pending,
    chunkStats.pendingGenerate,
    chunkStats.pendingMesh,
    chunkStats.pendingRemesh
  )
  local frameWorkLine = string.format(
    "Frame work: %.1f/%.1f ms%s, %d/%d steps, %d uploads",
    queueStats.elapsedMs or 0.0,
    queueStats.budgetMs or 0.0,
    queueStats.timeSliced and " (capped)" or "",
    queueStats.processed or 0,
    queueStats.budget or TERRAIN_WORK_BUDGET,
    (queueStats.meshUploads or 0) + (queueStats.syncUploads or 0)
  )
  local distant = queueStats.distant or {}
  local distantLine = string.format(
    "Distant LOD: square %d, ring %d/%d, %d queued, %d builds",
    distant.radius or state.renderDistance or 0,
    distant.scheduledThrough or 0,
    distant.radius or state.renderDistance or 0,
    distant.queued or 0,
    distant.built or 0
  )

  local leftLines = {
    string.format("MineLua 1.0.0 (%s)", runtime),
    string.format("%d fps (%s ms avg, %s ms last)", math.floor((state.debugFps or 0.0) + 0.5), formatNumber(state.debugFrameMs or 0.0, 1), formatNumber(state.debugLastFrameMs or 0.0, 1)),
    string.format("C: %d/%d chunks, V: %d verts", meshStats.visible, meshStats.uploaded, math.floor(meshStats.visibleVertices + 0.5)),
    queueLine,
    frameWorkLine,
    distantLine,
    string.format("XYZ: %s / %s / %s", formatNumber(pos[1], 3), formatNumber(feetY, 3), formatNumber(pos[3], 3)),
    string.format("Eye: %s / %s / %s", formatNumber(pos[1], 3), formatNumber(pos[2], 3), formatNumber(pos[3], 3)),
    string.format("Block: %d %d %d", blockX, blockY, blockZ),
    string.format("Chunk: %d %d in %d %d %d", chunkX, chunkZ, localX, math.floor(feetY) % 16, localZ),
    string.format("Facing: %s (yaw %s / pitch %s)", cameraFacingName(playerCamera.yaw), formatNumber(playerCamera.yaw, 1), formatNumber(playerCamera.pitch, 1)),
    string.format("Biome: minecraft:%s", tostring(biomeName or "unknown")),
    string.format("Light: sky %d, daylight %s, moon %s", world:skyLightAt(blockX, eyeBlockY, blockZ), formatNumber(sky.daylight or 0.0, 2), formatNumber(sky.moonAmount or 0.0, 2)),
    string.format("Standing on: %s", blockDebugName(standingOn)),
    string.format("Inside: %s", blockDebugName(insideBlock)),
    targetLine
  }

  local rightLines = {
    string.format("Display: %dx%d", windowWidth, windowHeight),
    string.format("Mem: %s", formatNumber(memMb, 1) .. " MB"),
    string.format("World seed: %s", tostring(world.seed or "?")),
    string.format("World: %s", world.worldProfile and world.worldProfile.name or "Earth"),
    string.format("Generator: %s", tostring(world.generatorType or "default")),
    string.format("Landform: %s / geology: %s", tostring(generation.landform), tostring(generation.geology)),
    string.format("Climate: T %s, M %s, rain %s", formatNumber(generation.temperature, 2), formatNumber(generation.moisture, 2), formatNumber(generation.rainfall, 2)),
    string.format("World fields: continent %s, mountain %s", formatNumber(generation.continentalness, 2), formatNumber(generation.mountainPotential, 2)),
    string.format("Erosion %s, drainage %s, river %s", formatNumber(generation.erosion, 2), formatNumber(generation.drainage, 2), formatNumber(generation.riverNetwork, 2)),
    string.format("Hydrology: %s / coast: %s", tostring(generation.waterKind or "dry"), tostring(generation.coastType or "inland")),
    string.format("Server chunks: %d loaded / %d ready / %d collision", chunkStats.loaded, chunkStats.serverReady, chunkStats.collision),
    string.format("Lighting: %d lit / dirty %s / job %s / rev %d", chunkStats.light, tostring(world.lightDirty == true), tostring(world.lightingJob ~= nil), world.lightRevision or 0),
    string.format("Render chunks: %d mesh / %d gpu / %d ready", chunkStats.mesh, chunkStats.gpu, chunkStats.renderReady),
    string.format("Provisional meshes: %d", meshStats.provisional),
    string.format("Terrain GPU: %s, %d verts", formatBytes(meshStats.bytes), math.floor(meshStats.totalVertices + 0.5)),
    string.format("Budget: terrain %d, queue %d, backlog %d", TERRAIN_WORK_BUDGET, CHUNK_QUEUE_BUDGET, CHUNK_QUEUE_BACKLOG),
    string.format("Spawn load: %dx%d required, %dx%d halo", LOADING_REQUIRED_RADIUS * 2 + 1, LOADING_REQUIRED_RADIUS * 2 + 1, LOADING_HALO_RADIUS * 2 + 1, LOADING_HALO_RADIUS * 2 + 1),
    string.format("Lighting budget: stream %d, load %d", LIGHTING_STEP_BUDGET, LOADING_LIGHTING_STEP_BUDGET),
    string.format("Render radius: %d full / %d square range, far %.0f", world.chunkRadius, state.renderDistance, CAMERA_FAR),
    string.format("Velocity: %s / %s / %s", formatNumber(playerCamera.velocity[1] or 0.0, 2), formatNumber(playerCamera.velocity[2] or 0.0, 2), formatNumber(playerCamera.velocity[3] or 0.0, 2)),
    string.format("Speed: %s m/s", formatNumber(speed, 2)),
    string.format("Mode: %s, flying %s, grounded %s", tostring(state.worldGameMode or "?"), tostring(playerCamera.flying == true), tostring(playerCamera.grounded == true)),
    string.format("Sun dir: %s / %s / %s", formatNumber(sunDir[1], 2), formatNumber(sunDir[2], 2), formatNumber(sunDir[3], 2)),
    "F3: hide debug screen"
  }

  return {
    leftLines = leftLines,
    rightLines = rightLines,
    key = table.concat(leftLines, "\31") .. "\30" .. table.concat(rightLines, "\31")
  }
end

local function updateViewportAndProjection(locP)
  gl.glViewport(0, 0, windowWidth, windowHeight)
  local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, CAMERA_NEAR, CAMERA_FAR)
  gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", projection))
end

local function refreshDrawableSize(window, state)
  local width = ffi.new("int[1]")
  local height = ffi.new("int[1]")
  glfw.glfwGetFramebufferSize(window, width, height)

  local w = math.max(1, tonumber(width[0]))
  local h = math.max(1, tonumber(height[0]))
  if w == windowWidth and h == windowHeight then
    return false
  end

  windowWidth = w
  windowHeight = h
  if state and not state.fullscreen then
    state.windowW = w
    state.windowH = h
  end

  return true
end

local function createDisplayState()
  return {
    fullscreen = false,
    f11WasDown = false,
    f3WasDown = false,
    f4WasDown = false,
    escapeWasDown = false,
    breakWasDown = false,
    breakTarget = nil,
    breakProgress = 0.0,
    handSwing = 0.0,
    handSwinging = false,
    handSwingStyle = "quick",
    -- Smoothed turn rates and a walk phase for the held model's sway.
    heldMotion = {lookX = 0.0, lookY = 0.0, bob = 0.0, walkPhase = 0.0, yaw = nil, pitch = nil},
    placeWasDown = false,
    dropWasDown = false,
    menuClickWasDown = false,
    activeMenuSlider = nil,
    debugScreen = false,
    devMenuOpen = false,
    debugInfo = nil,
    debugSampleTimer = 0.0,
    debugFrames = 0,
    debugFrameAccumulator = 0.0,
    debugFps = 0.0,
    debugFrameMs = 0.0,
    debugLastFrameMs = 0.0,
    lastQueueStats = nil,
    -- game.autoStartWorld skips the menus and drops straight into a generated
    -- world. Only a scripted smoke run sets it, so a launch from the command
    -- line exercises worldgen, meshing and the HUD instead of the title screen.
    screen = game.autoStartWorld and "loading" or "main",
    cursorMode = nil,
    menuMouseX = -1,
    menuMouseY = -1,
    worldGameMode = "survival",
    worldGeneratorType = "default",
    worldId = "earth",
    worldNameText = "New World",
    worldNamePristine = true,
    worldSeedText = "",
    generateStructures = true,
    allowCheats = false,
    bonusChest = false,
    renderDistance = math.max(4, math.min(128, math.floor(tonumber(DISTANT_CHUNK_RADIUS) or 24))),
    savedWorlds = {},
    selectedWorldIndex = nil,
    pendingDeleteWorld = nil,
    deleteWorldRequested = nil,
    worldListPage = 1,
    worldListVersion = 0,
    createTextKeyWasDown = {},
    hasWorld = false,
    menuParentScreen = nil,
    currentWorldSave = nil,
    pendingNewWorldConfig = game.autoStartWorld and {
      gameMode = "creative",
      generatorType = "default",
      seed = tonumber(game.autoStartWorld) or 1,
      worldName = "Smoke Test",
      spawnAltitudeMeters = 0.0
    } or nil,
    loadingJob = nil,
    pendingTerrainEntries = {},
    selectedSlot = 1,
    hotbarScroll = 0.0,
    inventory = Inventory.new("survival"),
    inventoryVersion = 1,
    inventoryWasDown = false,
    inventoryClickWasDown = false,
    creativeTab = "building",
    creativeFiltered = Inventory.catalog(),
    hotbarBlocks = {
      blocks.grass,
      blocks.dirt,
      blocks.stone,
      blocks.sand,
      blocks.ice,
      blocks.glass,
      blocks.oak_planks,
      blocks.oak_log,
      blocks.oak_leaves
    },
    windowX = 100,
    windowY = 100,
    windowW = WINDOW_W,
    windowH = WINDOW_H
  }
end

local function playerOptionsForGameMode(gameMode, worldProfile)
  local options = {}
  for key, value in pairs(graphics.player) do
    options[key] = value
  end

  worldProfile = worldProfile or worldProfiles.get("earth")
  options.gravity = (options.gravity or 19.5) * (worldProfile.gravityScale or 1.0)

  if gameMode == "creative" then
    options.flying = true
    options.allowFlight = true
    options.reach = math.max(options.reach or 6.0, 8.0)
  else
    options.flying = false
    options.allowFlight = false
  end

  return options
end

local function playerSnapshot(state, playerCamera)
  return {
    camera = playerCamera:saveState(),
    inventory = state.inventory:saveState()
  }
end

local function saveCurrentPlayer(state, playerCamera)
  if not state or not playerCamera or not state.inventory or
      not state.currentWorldSave or not state.currentWorldSave.path then
    return false
  end

  local ok, err = pcall(saves.savePlayer, state.currentWorldSave, playerSnapshot(state, playerCamera))
  if not ok then
    io.stderr:write("Unable to save player data: " .. tostring(err) .. "\n")
  end
  return ok
end

local function restorePlayer(state, playerCamera, savedPlayer)
  if type(savedPlayer) ~= "table" then return false end

  if type(savedPlayer.camera) == "table" then
    playerCamera:restoreState(savedPlayer.camera)
  end
  if type(savedPlayer.inventory) == "table" then
    state.inventory:restoreState(savedPlayer.inventory)
  end

  state.selectedSlot = state.inventory:normalizeSelected()
  return true
end

local function syncCursorMode(window, state, playerCamera)
  local target = (state.screen or state.devMenuOpen) and glfw.GLFW_CURSOR_NORMAL or glfw.GLFW_CURSOR_DISABLED
  if state.cursorMode ~= target then
    glfw.glfwSetInputMode(window, glfw.GLFW_CURSOR, target)
    state.cursorMode = target
    if target == glfw.GLFW_CURSOR_DISABLED and playerCamera then
      playerCamera.firstMouse = true
    end
  end
end

local function setFullscreen(window, state, enabled, locP)
  if state.fullscreen == enabled then
    return
  end

  if enabled then
    local xpos = ffi.new("int[1]")
    local ypos = ffi.new("int[1]")
    local width = ffi.new("int[1]")
    local height = ffi.new("int[1]")
    glfw.glfwGetWindowPos(window, xpos, ypos)
    glfw.glfwGetWindowSize(window, width, height)

    state.windowX = xpos[0]
    state.windowY = ypos[0]
    state.windowW = width[0]
    state.windowH = height[0]

    local monitor = glfw.glfwGetPrimaryMonitor()
    local mode = glfw.glfwGetVideoMode(monitor)
    windowWidth = mode.width
    windowHeight = mode.height
    glfw.glfwSetWindowMonitor(window, monitor, 0, 0, windowWidth, windowHeight, mode.refreshRate)
  else
    windowWidth = state.windowW
    windowHeight = state.windowH
    glfw.glfwSetWindowMonitor(window, nil, state.windowX, state.windowY, windowWidth, windowHeight, 0)
  end

  state.fullscreen = enabled
  updateViewportAndProjection(locP)
end

local function handleUiCommand(window, command, playerCamera, state)
  if command == "quit_game" then
    glfw.glfwSetWindowShouldClose(window, 1)
  elseif command == "quit_to_title" then
    saveCurrentPlayer(state, playerCamera)
    state.currentWorldSave = nil
  elseif command == "started_world" or command == "resume" then
    if playerCamera then
      playerCamera.firstMouse = true
    end
  end
end

local function updateWorldCreationTextInput(window, state)
  if state.screen ~= "create_world" then
    state.createTextKeyWasDown = {}
    return
  end

  local previous = state.createTextKeyWasDown or {}
  local current = {}
  local editingSeed = state.moreWorldOptions == true
  local text = editingSeed and (state.worldSeedText or "") or (state.worldNameText or "New World")
  local limit = editingSeed and 19 or 32

  local function appendKey(key, character)
    local down = glfw.glfwGetKey(window, key) == glfw.GLFW_PRESS
    current[key] = down
    if down and not previous[key] and #text < limit then
      if not editingSeed and state.worldNamePristine then
        text = ""
        state.worldNamePristine = false
      end
      text = text .. character
    end
  end

  if editingSeed then
    for digit = 0, 9 do appendKey(48 + digit, tostring(digit)) end
    local minusDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_MINUS) == glfw.GLFW_PRESS
    current.minus = minusDown
    if minusDown and not previous.minus and text == "" then text = "-" end
  else
    local shift = glfw.glfwGetKey(window, glfw.GLFW_KEY_LEFT_SHIFT) == glfw.GLFW_PRESS or
      glfw.glfwGetKey(window, 344) == glfw.GLFW_PRESS
    for code = 65, 90 do appendKey(code, string.char(shift and code or (code + 32))) end
    for digit = 0, 9 do appendKey(48 + digit, tostring(digit)) end
    appendKey(glfw.GLFW_KEY_SPACE, " ")
    appendKey(glfw.GLFW_KEY_MINUS, shift and "_" or "-")
  end

  local backspaceDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_BACKSPACE) == glfw.GLFW_PRESS
  current.backspace = backspaceDown
  if backspaceDown and not previous.backspace then
    if not editingSeed and state.worldNamePristine then
      text = ""
      state.worldNamePristine = false
    else
      text = text:sub(1, -2)
    end
  end

  if editingSeed then state.worldSeedText = text else state.worldNameText = text end
  state.createTextKeyWasDown = current
end

function game.refreshSavedWorldList(state)
  local selected = state.savedWorlds and state.savedWorlds[state.selectedWorldIndex or 0]
  local selectedPath = selected and selected.path
  state.savedWorlds = saves.listWorlds()
  state.selectedWorldIndex = #state.savedWorlds > 0 and 1 or nil
  if selectedPath then
    for index, entry in ipairs(state.savedWorlds) do
      if entry.path == selectedPath then state.selectedWorldIndex = index break end
    end
  end
  state.worldListPage = 1
  state.worldListVersion = (state.worldListVersion or 0) + 1
  state.refreshWorldListRequested = false
end

local function closeInventory(state, playerCamera)
  if state.inventory.cursor then
    if state.screen ~= "creative_inventory" then
      state.inventory:add(state.inventory.cursor.item, state.inventory.cursor.count)
    end
    state.inventory.cursor = nil
  end
  state.inventory:returnCraftingItems()
  state.inventory:setCraftingGridSize(2)
  state.inventoryLeftDrag = nil
  state.inventoryRightDragSeen = nil
  state.inventoryClickWasDown = false
  state.inventoryRightWasDown = false
  state.screen = nil
  state.inventoryVersion = (state.inventoryVersion or 0) + 1
  if playerCamera then playerCamera.firstMouse = true end
end

local function updateFullscreenInput(window, state, locP, playerCamera, devMenu)
  local f11Down = glfw.glfwGetKey(window, glfw.GLFW_KEY_F11) == glfw.GLFW_PRESS
  local escapeDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_ESCAPE) == glfw.GLFW_PRESS

  if f11Down and not state.f11WasDown then
    setFullscreen(window, state, not state.fullscreen, locP)
  end

  if escapeDown and not state.escapeWasDown and state.fullscreen then
    setFullscreen(window, state, false, locP)
  elseif escapeDown and not state.escapeWasDown and state.devMenuOpen then
    devMenu:setOpen(false)
    state.devMenuOpen = false
    if playerCamera then playerCamera.firstMouse = true end
  elseif escapeDown and not state.escapeWasDown then
    local wasScreen = state.screen
    if wasScreen == "inventory" or wasScreen == "creative_inventory" or wasScreen == "crafting_table" or wasScreen == "furnace" then
      closeInventory(state, playerCamera)
    else
      uiFlow.back(state)
    end
    if wasScreen and not state.screen and playerCamera then
      playerCamera.firstMouse = true
    end
  end

  state.f11WasDown = f11Down
  state.escapeWasDown = escapeDown
end

local function updateDevMenuInput(window, state, devMenu)
  local f4Down = glfw.glfwGetKey(window, glfw.GLFW_KEY_F4) == glfw.GLFW_PRESS
  if f4Down and not state.f4WasDown and state.hasWorld then
    devMenu:toggle()
    state.devMenuOpen = devMenu:isOpen()
  end
  state.f4WasDown = f4Down
end

local function updateDebugInput(window, state)
  local f3Down = glfw.glfwGetKey(window, glfw.GLFW_KEY_F3) == glfw.GLFW_PRESS
  if f3Down and not state.f3WasDown then
    state.debugScreen = not state.debugScreen
    state.debugInfo = nil
    state.debugSampleTimer = 999.0
  end
  state.f3WasDown = f3Down
end

local function refreshCreativeFilter(state)
  local query = (state.inventory.search or ""):lower()
  local filtered = {}
  for _, item in ipairs(Inventory.catalog()) do
    local definition = blocks.mapping[item]
    local label = definition and definition.name and definition.name:lower() or item
    if query == "" or item:find(query, 1, true) or label:find(query, 1, true) then
      filtered[#filtered + 1] = item
    end
  end
  state.creativeFiltered = filtered
end

local function updateInventoryInput(window, state, playerCamera)
  if not state.hasWorld or state.devMenuOpen then return end

  local inventoryDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_E) == glfw.GLFW_PRESS
  if inventoryDown and not state.inventoryWasDown then
    if state.screen == "inventory" or state.screen == "creative_inventory" or state.screen == "crafting_table" or state.screen == "furnace" then
      closeInventory(state, playerCamera)
    elseif not state.screen then
      state.inventory:setCraftingGridSize(2)
      state.screen = state.worldGameMode == "creative" and "creative_inventory" or "inventory"
      refreshCreativeFilter(state)
    end
  end
  state.inventoryWasDown = inventoryDown

  if state.screen ~= "inventory" and state.screen ~= "creative_inventory" and state.screen ~= "crafting_table" and state.screen ~= "furnace" then
    return
  end

  local xpos, ypos = ffi.new("double[1]"), ffi.new("double[1]")
  local clientWidth, clientHeight = ffi.new("int[1]"), ffi.new("int[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)
  glfw.glfwGetWindowSize(window, clientWidth, clientHeight)
  state.menuMouseX = tonumber(xpos[0]) * windowWidth / math.max(1, tonumber(clientWidth[0]))
  state.menuMouseY = tonumber(ypos[0]) * windowHeight / math.max(1, tonumber(clientHeight[0]))

  local target = hud.inventorySlotAt(
    state.screen, windowWidth, windowHeight, state.menuMouseX, state.menuMouseY, state
  )
  local leftDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
  local rightDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_RIGHT) == glfw.GLFW_PRESS
  local shiftDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_LEFT_SHIFT) == glfw.GLFW_PRESS or
    glfw.glfwGetKey(window, 344) == glfw.GLFW_PRESS

  if leftDown then
    if not state.inventoryClickWasDown then
      local clickKey = target and (target.kind .. ":" .. tostring(target.index or target.item or target.tab)) or nil
      local clickTime = glfw.glfwGetTime()
      local doubleClick = clickKey and clickKey == state.inventoryLastClickKey and
        clickTime - (state.inventoryLastClickTime or -math.huge) <= 0.25
      if target and target.kind == "craft" and state.inventory.cursor and not shiftDown then
        state.inventoryLeftDrag = {kind = "craft", indices = {target.index}, seen = {[target.index] = true}}
      elseif target then
        if target.kind == "slot" then
          if doubleClick and state.inventory.cursor then
            state.inventory:collectToCursor()
          else
            local pickedUp = not state.inventory.cursor and state.inventory:get(target.index) ~= nil
            if pickedUp then state.inventory:swapOrMerge(target.index) end
            state.inventoryLeftDrag = {
              kind = "slot", indices = {target.index}, seen = {[target.index] = true}, pickedUp = pickedUp
            }
          end
        elseif target.kind == "craft" then
          state.inventory:swapCraft(target.index)
        elseif target.kind == "furnace_input" or target.kind == "furnace_fuel" or target.kind == "furnace_output" then
          state.inventory:swapFurnace(target.kind)
        elseif target.kind == "result" then
          if shiftDown then state.inventory:craftAll() else state.inventory:takeCraftResult() end
        elseif target.kind == "creative_tab" then
          state.creativeTab = target.tab
          refreshCreativeFilter(state)
        elseif target.kind == "creative" and target.item then
          state.inventory.cursor = {item = target.item, count = 64}
        end
        state.inventoryVersion = state.inventoryVersion + 1
      end
      state.inventoryLastClickKey = clickKey
      state.inventoryLastClickTime = clickTime
    elseif state.inventoryLeftDrag and target and target.kind == state.inventoryLeftDrag.kind and
        not state.inventoryLeftDrag.seen[target.index] then
      state.inventoryLeftDrag.seen[target.index] = true
      state.inventoryLeftDrag.indices[#state.inventoryLeftDrag.indices + 1] = target.index
    end
  elseif state.inventoryLeftDrag then
    local drag = state.inventoryLeftDrag
    local indices = state.inventoryLeftDrag.indices
    if drag.kind == "slot" then
      if #indices > 1 then
        state.inventory:distributeSlots(indices)
      elseif not drag.pickedUp then
        state.inventory:swapOrMerge(indices[1])
      end
    elseif #indices > 1 then
      state.inventory:distributeCraft(indices)
    else
      state.inventory:swapCraft(indices[1])
    end
    state.inventoryLeftDrag = nil
    state.inventoryVersion = state.inventoryVersion + 1
  end
  state.inventoryClickWasDown = leftDown

  if rightDown and not leftDown then
    if not state.inventoryRightWasDown or not state.inventoryRightDragSeen then
      state.inventoryRightDragSeen = {}
    end
    if target and (target.kind == "craft" or target.kind == "slot" or
        target.kind == "furnace_input" or target.kind == "furnace_fuel" or target.kind == "furnace_output") then
      local dragKey = target.kind .. ":" .. target.index
      if not state.inventoryRightDragSeen[dragKey] then
        state.inventoryRightDragSeen[dragKey] = true
        local changed
        if target.kind == "craft" then
          changed = state.inventory:rightClickCraft(target.index)
        elseif target.kind:sub(1,8)=="furnace_" then
          changed = state.inventory:rightClickFurnace(target.kind)
        else
          changed = state.inventory:rightClickSlot(target.index)
        end
        if changed then
          state.inventoryVersion = state.inventoryVersion + 1
        end
      end
    end
  else
    state.inventoryRightDragSeen = nil
  end
  state.inventoryRightWasDown = rightDown
end

local function updateMenuInput(window, state, playerCamera)
  if state.devMenuOpen then
    state.menuClickWasDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
    state.activeMenuSlider = nil
    return
  end
  if not state.screen then
    state.menuClickWasDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
    state.activeMenuSlider = nil
    return
  end
  if state.screen == "inventory" or state.screen == "creative_inventory" or state.screen == "crafting_table" or state.screen == "furnace" then
    return
  end

  if state.refreshWorldListRequested then game.refreshSavedWorldList(state) end
  updateWorldCreationTextInput(window, state)

  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  local clientWidth = ffi.new("int[1]")
  local clientHeight = ffi.new("int[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)
  glfw.glfwGetWindowSize(window, clientWidth, clientHeight)
  state.menuMouseX = tonumber(xpos[0]) * windowWidth / math.max(1, tonumber(clientWidth[0]))
  state.menuMouseY = tonumber(ypos[0]) * windowHeight / math.max(1, tonumber(clientHeight[0]))

  local clickDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
  if clickDown then
    local slider, value = hud.menuSliderValueAt(
      state.screen, windowWidth, windowHeight, state.menuMouseX, state.menuMouseY,
      state, state.activeMenuSlider
    )
    if slider then
      state.activeMenuSlider = slider
      uiFlow.applySlider(state, slider, value)
    elseif not state.menuClickWasDown then
      local action = hud.menuButtonAt(state.screen, windowWidth, windowHeight, state.menuMouseX, state.menuMouseY, state)
      local command = uiFlow.applyAction(state, action)
      if state.deleteWorldRequested then
        local worldToDelete = state.deleteWorldRequested
        state.deleteWorldRequested = nil
        local deleted, deleteError = saves.deleteWorld(worldToDelete)
        if deleted then
          state.statusMessage = "Deleted " .. tostring(worldToDelete.worldName or worldToDelete.folderName)
        else
          state.statusMessage = "Could not delete world: " .. tostring(deleteError or "unknown error")
        end
        state.refreshWorldListRequested = true
      end
      if state.refreshWorldListRequested then game.refreshSavedWorldList(state) end
      handleUiCommand(window, command, playerCamera, state)
    end
  else
    state.activeMenuSlider = nil
  end

  state.menuClickWasDown = clickDown
end

local function updateBlockEditInput(window, state, world, pendingEntries, playerCamera, droppedItems, fallingTrees, dt)
  local Mining=require("mining")
  local FallingTrees=require("falling_trees")
  local breakDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
  local placeDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_RIGHT) == glfw.GLFW_PRESS

  local slotKeys = {
    glfw.GLFW_KEY_1,
    glfw.GLFW_KEY_2,
    glfw.GLFW_KEY_3,
    glfw.GLFW_KEY_4,
    glfw.GLFW_KEY_5,
    glfw.GLFW_KEY_6,
    glfw.GLFW_KEY_7,
    glfw.GLFW_KEY_8,
    glfw.GLFW_KEY_9
  }

  local scrollDelta = state.hotbarScroll or 0.0
  local scrollSteps = scrollDelta > 0 and math.floor(scrollDelta) or math.ceil(scrollDelta)
  if scrollSteps ~= 0 then
    state.selectedSlot = ((state.selectedSlot - 1 - scrollSteps) % Inventory.HOTBAR_SIZE) + 1
    state.inventory.selected = state.selectedSlot
    state.hotbarScroll = scrollDelta - scrollSteps
  end

  for i = 1, #slotKeys do
    if glfw.glfwGetKey(window, slotKeys[i]) == glfw.GLFW_PRESS then
      state.selectedSlot = i
      state.inventory.selected = i
    end
  end

  -- The swing runs before the break loop so a chop can bite at the moment the
  -- animation says the blade arrives, rather than on the button press.
  local heldStack=state.inventory.slots[state.selectedSlot]
  local landedBlow=heldItem.updateSwing(state, dt,
    breakDown or (placeDown and not state.placeWasDown),
    heldItem.isHeavy(Mining.tool(heldStack and heldStack.item)))

  if breakDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    if hit then
      local definition = blocks.list[hit.id]
      local targetKey=hit.x..":"..hit.y..":"..hit.z
      if state.breakTarget~=targetKey then
        state.breakTarget=targetKey
        state.breakProgress=0
      end
      local held=heldStack
      local broke=Mining.advanceBreak(state,definition,held and held.item,state.worldGameMode,dt,landedBlow)
      state.breakTargetPosition={x=hit.x,y=hit.y,z=hit.z}
      if broke and (state.worldGameMode~="creative" or not state.breakWasDown) then
        local tree,changed
        local canHarvest=state.worldGameMode=="creative" or Mining.canHarvest(definition,held and held.item)
        if FallingTrees.isLog(definition) and canHarvest then tree,changed=fallingTrees:start(world,hit.x,hit.y,hit.z,playerCamera:getFront()) end
        if not tree then changed=worldInteraction.breakBlock(world, hit.x, hit.y, hit.z) end
        rebuildChangedBlockMeshes(world,pendingEntries,changed)
        if #changed > 0 and not tree and state.worldGameMode ~= "creative" and definition and Mining.canHarvest(definition,held and held.item) then
          local drop = Mining.drop(definition, held and held.item)
          if drop then droppedItems:spawn(drop.item, drop.count,
            {hit.x + 0.5, hit.y + 0.55, hit.z + 0.5},
            {(math.random() - 0.5) * 1.4, 2.2, (math.random() - 0.5) * 1.4}, 0.35) end
        end
        state.breakTarget=nil
        state.breakTargetPosition=nil state.breakDuration=nil
        state.breakProgress=0
      end
    else
      state.breakTarget=nil state.breakTargetPosition=nil state.breakDuration=nil state.breakProgress=0
    end
  else
    state.breakTarget=nil state.breakTargetPosition=nil state.breakDuration=nil state.breakProgress=0
  end

  if placeDown and not state.placeWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    if hit and hit.id == blocks.crafting_table then
      state.inventory:setCraftingGridSize(3)
      state.screen = "crafting_table"
      state.inventoryVersion = state.inventoryVersion + 1
    elseif hit and hit.id == blocks.furnace then
      state.inventory:returnCraftingItems()
      state.inventory:setCraftingGridSize(2)
      state.screen = "furnace"
      state.inventoryVersion = state.inventoryVersion + 1
    else
      local stack = state.inventory.slots[state.selectedSlot]
      local blockId = state.inventory:blockIdFor(stack)
      local target = worldInteraction.placeFromHit(world, hit, blockId)
      if target then
        rebuildBlockChunkMeshes(world, pendingEntries, target.x, target.z)
        state.inventory:consumeSelected(1)
        state.inventoryVersion = state.inventoryVersion + 1
      end
    end
  end

  local dropDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_Q) == glfw.GLFW_PRESS
  if dropDown and not state.dropWasDown and state.worldGameMode ~= "creative" then
    local removed = state.inventory:removeAt(state.selectedSlot, 1)
    if removed then
      local front = playerCamera:getFront()
      droppedItems:spawn(removed.item, removed.count, {
        playerCamera.position[1] + front[1] * 0.8,
        playerCamera.position[2] - 0.25,
        playerCamera.position[3] + front[3] * 0.8
      }, {front[1] * 4.0, front[2] * 4.0 + 2.0, front[3] * 4.0}, 1.0)
      state.inventoryVersion = state.inventoryVersion + 1
    end
  end

  state.breakWasDown = breakDown
  state.placeWasDown = placeDown
  state.dropWasDown = dropDown
end

local function initWindow()
  if glfw.glfwInit() == 0 then
    error("Failed to init GLFW")
  end

  glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4)
  glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6)
  glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE)

  local window = glfw.glfwCreateWindow(WINDOW_W, WINDOW_H, "MineLua", nil, nil)
  if window == nil then
    error("Failed to create an OpenGL 4.6 Core window; update the graphics driver or use a GPU that supports OpenGL 4.6")
  end

  glfw.glfwMakeContextCurrent(window)
  -- With vsync on, every frame reports the refresh interval regardless of how
  -- much work it actually did, which hides the real headroom. Turn it off to
  -- measure true frame cost.
  glfw.glfwSwapInterval(VSYNC_ENABLED and 1 or 0)
  glfw.glfwSetInputMode(window, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_NORMAL)

  return window
end

-- Read the default framebuffer back to a PPM. Scripted runs use this instead
-- of a screenshot key, which no headless launch can press.
function game.captureFrame(path, width, height)
  local pixels = ffi.new("unsigned char[?]", width * height * 3)
  gl.glPixelStorei(0x0D05, 1) -- GL_PACK_ALIGNMENT
  gl.glReadPixels(0, 0, width, height, 0x1907, 0x1401, pixels) -- GL_RGB, GL_UNSIGNED_BYTE
  local file = io.open(path, "wb")
  if not file then return false end
  file:write(string.format("P6\n%d %d\n255\n", width, height))
  -- OpenGL hands back the bottom row first; PPM wants the top row first.
  local stride = width * 3
  for row = height - 1, 0, -1 do
    file:write(ffi.string(pixels + row * stride, stride))
  end
  file:close()
  return true
end

function game.run()
  local ok, err = pcall(function()
    local window = initWindow()

    GL.loadModernGL()
    print("GL_VERSION:", ffi.string(gl.glGetString(0x1F02)))

    gl.glEnable(GL_DEPTH_TEST)
    gl.glDepthFunc(GL_LESS)
    gl.glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS)
    local devMenu = DevMenu.new()
    local runtimeAtmosphereSettings = {}
    local previewAtmosphereSettings = {}
    local activeWorldProfile = worldProfiles.get("earth")
    updateRuntimeAtmosphereSettings(runtimeAtmosphereSettings, 1.0, activeWorldProfile)
    updateRuntimeAtmosphereSettings(previewAtmosphereSettings, 0.0, activeWorldProfile)

    local atlasTex = createTextureAtlas()
    local moonTexture = createImageTexture("assets/textures/environment/moon_phases.png", true)
    local underwaterOverlayTexture = createImageTexture("assets/textures/blocks/water_overlay.png", false, true)
    effects.miningOverlay = require("mining_overlay").create()
    local world = World.new({
      chunkRadius = CHUNK_RENDER_RADIUS,
      maxHeight = TERRAIN_MAX_H,
      generatorType = "default",
      worldId = "earth",
      seed = graphics.terrainGeneration.seed or 1,
      deferInitialChunks = true
    })
    local terrainMeshes = {}
    local droppedItems = DroppedItems.new()
    local droppedItemMeshes = {}
    local fallingTrees = require("falling_trees").new()
    local fallingTreeMeshes = {}
    local distantTerrain = createDistantTerrain()
    local currentWaterLevel = WATER_LEVEL
    local characterMesh = graphics.player.showDebugBody and createCharacterMesh() or nil
    local skyMesh = uploadSkyMesh()
    local cloudMesh = createCloudMesh("assets/textures/environment/clouds.png")
    local shadowMap = effects.createShadowMap(SHADOW_MAP_SIZE)
    local sceneTarget = effects.createSceneTarget(windowWidth, windowHeight)
    local waterBackgroundTarget = effects.createSceneTarget(windowWidth, windowHeight)
    local volumetricFog = effects.createVolumetricFog(FOG_GRID_WIDTH, FOG_GRID_HEIGHT, FOG_GRID_DEPTH)
    local ocean = effects.createOceanSimulation(graphics.water)

    local shader = createShaderProgram()
    local shadowShader = effects.createShadowShader()
    local skyShader = createSkyShaderProgram()
    local cloudShader = createCloudShaderProgram()
    local dielectricShader = effects.createDielectricShader()
    local waterShader = effects.createWaterShader()
    local atmospherePostShader = effects.createAtmospherePostShader()
    local volumetricFogShaders = effects.createVolumetricFogShaders(FOG_GRID_WIDTH, FOG_GRID_HEIGHT, FOG_GRID_DEPTH)
    local worldgenPreviewShader = createWorldgenPreviewShader()
    local hudOverlay = hud.create()
    gl.glUseProgram(shader)

    local locP = gl.glGetUniformLocation(shader, "uProjection")
    local locV = gl.glGetUniformLocation(shader, "uView")
    local locM = gl.glGetUniformLocation(shader, "uModel")
    local locLight = gl.glGetUniformLocation(shader, "lightDir")
    local locViewPos = gl.glGetUniformLocation(shader, "viewPos")
    local locTex = gl.glGetUniformLocation(shader, "tex0")
    local locTime = gl.glGetUniformLocation(shader, "time")

    local locShadowMap = gl.glGetUniformLocation(shader, "shadowMap")
    local locAmbientColor = gl.glGetUniformLocation(shader, "ambientColor")
    local locLightColor = gl.glGetUniformLocation(shader, "lightColor")
    local locMoonLightColor = gl.glGetUniformLocation(shader, "moonLightColor")
    local locLightingParams = gl.glGetUniformLocation(shader, "lightingParams")
    local locFaceLight = gl.glGetUniformLocation(shader, "faceLight")
    local locExposure = gl.glGetUniformLocation(shader, "exposure")
    local locShadowStrength = gl.glGetUniformLocation(shader, "shadowStrength")
    local locLightSpaceMatrix = gl.glGetUniformLocation(shader, "lightSpaceMatrix")
    local locTerrainWaterLevel = gl.glGetUniformLocation(shader, "waterLevel")
    local locTerrainWaterNormalMap = gl.glGetUniformLocation(shader, "waterNormalMap")
    local locTerrainWaterCascadeSizes = gl.glGetUniformLocation(shader, "waterCascadeSizes")
    local locTerrainWaterNormalWeights = gl.glGetUniformLocation(shader, "waterNormalWeights")
    local locTerrainCausticStrength = gl.glGetUniformLocation(shader, "causticStrength")
    local shadowLocations = {
      model = gl.glGetUniformLocation(shadowShader, "uModel"),
      lightSpaceMatrix = gl.glGetUniformLocation(shadowShader, "lightSpaceMatrix"),
      tex0 = gl.glGetUniformLocation(shadowShader, "tex0")
    }
    local skyLocations = {
      sunDir = gl.glGetUniformLocation(skyShader, "sunDir"),
      time = gl.glGetUniformLocation(skyShader, "time"),
      cameraForward = gl.glGetUniformLocation(skyShader, "cameraForward"),
      cameraRight = gl.glGetUniformLocation(skyShader, "cameraRight"),
      cameraUp = gl.glGetUniformLocation(skyShader, "cameraUp"),
      cameraPosition = gl.glGetUniformLocation(skyShader, "cameraPosition"),
      cameraProjection = gl.glGetUniformLocation(skyShader, "cameraProjection"),
      skyTuning = gl.glGetUniformLocation(skyShader, "skyTuning"),
      skyParams = gl.glGetUniformLocation(skyShader, "skyParams"),
      fogColor = gl.glGetUniformLocation(skyShader, "fogColor"),
      moonTex = gl.glGetUniformLocation(skyShader, "moonTex"),
      sunDisc = gl.glGetUniformLocation(skyShader, "sunDisc"),
      scatteringPlanet = gl.glGetUniformLocation(skyShader, "scatteringPlanet"),
      scatteringScale = gl.glGetUniformLocation(skyShader, "scatteringScale"),
      scatteringRayleigh = gl.glGetUniformLocation(skyShader, "scatteringRayleigh"),
      scatteringDust = gl.glGetUniformLocation(skyShader, "scatteringDust"),
      aureoleColor = gl.glGetUniformLocation(skyShader, "aureoleColor"),
      aureoleParams = gl.glGetUniformLocation(skyShader, "aureoleParams")
    }
    local cloudLocations = {
      projection = gl.glGetUniformLocation(cloudShader, "uProjection"),
      view = gl.glGetUniformLocation(cloudShader, "uView"),
      offset = gl.glGetUniformLocation(cloudShader, "cloudOffset"),
      alpha = gl.glGetUniformLocation(cloudShader, "cloudAlpha"),
      tint = gl.glGetUniformLocation(cloudShader, "cloudTint")
    }
    local dielectricLocations = {
      projection = gl.glGetUniformLocation(dielectricShader, "uProjection"),
      view = gl.glGetUniformLocation(dielectricShader, "uView"),
      model = gl.glGetUniformLocation(dielectricShader, "uModel"),
      viewPos = gl.glGetUniformLocation(dielectricShader, "viewPos"),
      sunDir = gl.glGetUniformLocation(dielectricShader, "sunDir"),
      fogColor = gl.glGetUniformLocation(dielectricShader, "fogColor"),
      skyZenithColor = gl.glGetUniformLocation(dielectricShader, "skyZenithColor"),
      lightColor = gl.glGetUniformLocation(dielectricShader, "lightColor"),
      viewportSize = gl.glGetUniformLocation(dielectricShader, "viewportSize"),
      clipPlanes = gl.glGetUniformLocation(dielectricShader, "clipPlanes"),
      iceOptics = gl.glGetUniformLocation(dielectricShader, "iceOptics"),
      glassOptics = gl.glGetUniformLocation(dielectricShader, "glassOptics"),
      iceAbsorption = gl.glGetUniformLocation(dielectricShader, "iceAbsorption"),
      glassAbsorption = gl.glGetUniformLocation(dielectricShader, "glassAbsorption"),
      tex0 = gl.glGetUniformLocation(dielectricShader, "tex0"),
      sceneColor = gl.glGetUniformLocation(dielectricShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(dielectricShader, "sceneDepth")
    }
    local worldgenPreviewLocations = {
      projection = gl.glGetUniformLocation(worldgenPreviewShader, "uProjection"),
      view = gl.glGetUniformLocation(worldgenPreviewShader, "uView"),
      lightDir = gl.glGetUniformLocation(worldgenPreviewShader, "lightDir")
    }
    local waterLocations = {
      projection = gl.glGetUniformLocation(waterShader, "uProjection"),
      view = gl.glGetUniformLocation(waterShader, "uView"),
      waterLevel = gl.glGetUniformLocation(waterShader, "waterLevel"),
      viewPos = gl.glGetUniformLocation(waterShader, "viewPos"),
      sunDir = gl.glGetUniformLocation(waterShader, "sunDir"),
      fogColor = gl.glGetUniformLocation(waterShader, "fogColor"),
      lightColor = gl.glGetUniformLocation(waterShader, "lightColor"),
      skyZenithColor = gl.glGetUniformLocation(waterShader, "skyZenithColor"),
      cascadeSizes = gl.glGetUniformLocation(waterShader, "cascadeSizes"),
      displacementWeights = gl.glGetUniformLocation(waterShader, "displacementWeights"),
      normalWeights = gl.glGetUniformLocation(waterShader, "normalWeights"),
      openWaterWaveBoost = gl.glGetUniformLocation(waterShader, "openWaterWaveBoost"),
      viewportSize = gl.glGetUniformLocation(waterShader, "viewportSize"),
      clipPlanes = gl.glGetUniformLocation(waterShader, "clipPlanes"),
      time = gl.glGetUniformLocation(waterShader, "time"),
      refractionStrength = gl.glGetUniformLocation(waterShader, "refractionStrength"),
      absorption = gl.glGetUniformLocation(waterShader, "absorption"),
      displacementMap0 = gl.glGetUniformLocation(waterShader, "displacementMap0"),
      displacementMap1 = gl.glGetUniformLocation(waterShader, "displacementMap1"),
      displacementMap2 = gl.glGetUniformLocation(waterShader, "displacementMap2"),
      normalMap0 = gl.glGetUniformLocation(waterShader, "normalMap0"),
      normalMap1 = gl.glGetUniformLocation(waterShader, "normalMap1"),
      normalMap2 = gl.glGetUniformLocation(waterShader, "normalMap2"),
      sceneColor = gl.glGetUniformLocation(waterShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(waterShader, "sceneDepth")
    }
    local atmospherePostLocations = {
      sceneColor = gl.glGetUniformLocation(atmospherePostShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(atmospherePostShader, "sceneDepth"),
      underwaterOverlay = gl.glGetUniformLocation(atmospherePostShader, "underwaterOverlay"),
      fogVolume = gl.glGetUniformLocation(atmospherePostShader, "fogVolume"),
      cameraPosition = gl.glGetUniformLocation(atmospherePostShader, "cameraPosition"),
      cameraForward = gl.glGetUniformLocation(atmospherePostShader, "cameraForward"),
      cameraRight = gl.glGetUniformLocation(atmospherePostShader, "cameraRight"),
      cameraUp = gl.glGetUniformLocation(atmospherePostShader, "cameraUp"),
      cameraProjection = gl.glGetUniformLocation(atmospherePostShader, "cameraProjection"),
      depthParams = gl.glGetUniformLocation(atmospherePostShader, "depthParams"),
      volumeParams = gl.glGetUniformLocation(atmospherePostShader, "volumeParams"),
      blurAmount = gl.glGetUniformLocation(atmospherePostShader, "blurAmount"),
      time = gl.glGetUniformLocation(atmospherePostShader, "time"),
      bloomTexture = gl.glGetUniformLocation(atmospherePostShader, "bloomTexture"),
      gradeParams = gl.glGetUniformLocation(atmospherePostShader, "gradeParams"),
      tonemapParams = gl.glGetUniformLocation(atmospherePostShader, "tonemapParams")
    }

    local bloomShaders = {
      down = effects.createBloomDownShader(),
      up = effects.createBloomUpShader()
    }
    bloomShaders.downLoc = {
      source = gl.glGetUniformLocation(bloomShaders.down, "source"),
      texelSize = gl.glGetUniformLocation(bloomShaders.down, "texelSize"),
      prefilter = gl.glGetUniformLocation(bloomShaders.down, "prefilter"),
      clampMax = gl.glGetUniformLocation(bloomShaders.down, "clampMax")
    }
    bloomShaders.upLoc = {
      source = gl.glGetUniformLocation(bloomShaders.up, "source"),
      texelSize = gl.glGetUniformLocation(bloomShaders.up, "texelSize"),
      radius = gl.glGetUniformLocation(bloomShaders.up, "radius")
    }
    local bloomChain = effects.createBloomChain(windowWidth, windowHeight, POST.bloomLevels or 6)

    local model = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}

    updateViewportAndProjection(locP)
    gl.glUniformMatrix4fv(locM, 1, 0, ffi.new("float[16]", model))
    gl.glUniform1i(locTex, 0)
    gl.glUniform1i(locShadowMap, 1)
    gl.glUniform1i(locTerrainWaterNormalMap, 2)
    gl.glUseProgram(skyShader)
    gl.glUniform1i(skyLocations.moonTex, 2)
    gl.glUseProgram(shader)
    gl.glUniform3f(locFaceLight, graphics.terrain.topLight, graphics.terrain.sideLight, graphics.terrain.bottomLight)
    gl.glUniform1f(locExposure, graphics.terrain.exposure)

    local playerCamera = camera.new(playerOptionsForGameMode("survival", activeWorldProfile))
    playerCamera:placeAtSpawn(world, playerCamera.position[1], playerCamera.position[3])
    local worldgenPreviewCamera = camera.new({position = {0.0, 900.0, 0.0}, yaw = 45.0, pitch = -54.0})
    local worldgenPreviewState = {
      centerX = playerCamera.position[1],
      centerZ = playerCamera.position[3],
      yaw = 45.0,
      distance = 980.0
    }
    local worldgenPreviewMesh = nil
    local displayState = createDisplayState()
    local scrollCallback = ffi.cast("GLFWscrollfun", function(_, _, yoffset)
      displayState.hotbarScroll = displayState.hotbarScroll + tonumber(yoffset)
    end)
    displayState.scrollCallback = scrollCallback
    glfw.glfwSetScrollCallback(window, scrollCallback)
    local lastTime = glfw.glfwGetTime()
    local lastPlayerSaveTime = lastTime

    while glfw.glfwWindowShouldClose(window) == 0 do
      local currentTime = glfw.glfwGetTime()
      local dt = currentTime - lastTime
      lastTime = currentTime

      updateDebugFrameStats(displayState, dt)
      updateDevMenuInput(window, displayState, devMenu)
      updateFullscreenInput(window, displayState, locP, playerCamera, devMenu)
      updateDebugInput(window, displayState)
      devMenu:processExportRequest()
      if devMenu:consumePreviewRebuildRequest() then
        worldgenPreviewMesh = rebuildWorldgenPreview(
          worldgenPreviewMesh,
          devMenu:stagedGenerationSettings(),
          world.seed,
          worldgenPreviewState.centerX,
          worldgenPreviewState.centerZ
        )
        worldgenPreviewState.meshCenterX = worldgenPreviewState.centerX
        worldgenPreviewState.meshCenterZ = worldgenPreviewState.centerZ
      end
      if devMenu:consumeRegenerateRequest() and displayState.hasWorld and world.generatorType ~= "superflat" then
        devMenu:commitGenerationChanges(graphics.terrainGeneration)
        terrain.refreshGenerationSettings()
        releaseTerrainMeshes(terrainMeshes)
        distantTerrain:clear()
        terrainMeshes = {}
        displayState.pendingTerrainEntries = {}
        world.seed = graphics.terrainGeneration.seed
        world:clearGeneratedChunks()
        terrain.setSeed(world.seed)
        devMenu:setPreviewMode(false)
        displayState.debugInfo = nil
        displayState.debugSampleTimer = 999.0
      end
      refreshDrawableSize(window, displayState)
      updateInventoryInput(window, displayState, playerCamera)
      if displayState.inventory and displayState.inventory:updateSmelting(dt) then
        displayState.inventoryVersion=(displayState.inventoryVersion or 0)+1
      end
      updateMenuInput(window, displayState, playerCamera)
      distantTerrain:setRadius(displayState.renderDistance)
      world.chunkRadius = math.min(CHUNK_RENDER_RADIUS, displayState.renderDistance)
      local renderedLoadingFrame = false
      if displayState.pendingNewWorldConfig then
        local config = displayState.pendingNewWorldConfig
        displayState.pendingNewWorldConfig = nil
        displayState.loadingJob = createWorldLoadingJob(config)
      end
      if displayState.loadingJob then
        local job = displayState.loadingJob
        local done = stepWorldLoadingJob(job)
        if done then
          releaseTerrainMeshes(terrainMeshes)
          distantTerrain:clear()
          world = job.world
          activeWorldProfile = job.worldProfile
          terrainMeshes = job.terrainMeshes
          displayState.currentWorldSave = job.save
          if job.config.generatorType == "superflat" or not activeWorldProfile.hasSurfaceWater then
            currentWaterLevel = nil
          else
            currentWaterLevel = WATER_LEVEL
          end
          playerCamera = camera.new(playerOptionsForGameMode(job.config.gameMode, activeWorldProfile))
          playerCamera:placeAtSpawn(world, job.spawnX, job.spawnZ)
          displayState.worldGameMode = job.config.gameMode
          displayState.inventory = Inventory.new(job.config.gameMode)
          displayState.selectedSlot = 1
          restorePlayer(displayState, playerCamera, job.savedPlayer)
          if game.startHold then
            displayState.inventory.slots[1] = {item = game.startHold, count = 1}
            displayState.inventory.selected = 1
            displayState.selectedSlot = 1
          end
          -- Physics belongs to the selected world, not to an old camera
          -- snapshot. This also lets profile upgrades correct existing saves.
          playerCamera.gravity = (graphics.player.gravity or 19.5) *
            (activeWorldProfile.gravityScale or 1.0)
          displayState.inventoryVersion = displayState.inventoryVersion + 1
          playerCamera.firstMouse = true
          refreshCreativeFilter(displayState)
          displayState.worldGeneratorType = job.config.generatorType
          displayState.worldId = activeWorldProfile.id
          devMenu:setGenerationSeed(job.seed)
          worldgenPreviewState.centerX = playerCamera.position[1]
          worldgenPreviewState.centerZ = playerCamera.position[3]
          displayState.hasWorld = true
          displayState.screen = nil
          displayState.loadingJob = nil
          displayState.pendingTerrainEntries = job.streamingEntries or {}
          droppedItems:clear()
          fallingTrees:clear()
          releaseFallingTreeMeshes(fallingTreeMeshes)
          lastPlayerSaveTime = currentTime
        else
          syncCursorMode(window, displayState, playerCamera)
          gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
          gl.glViewport(0, 0, windowWidth, windowHeight)
          gl.glClearColor(0.0, 0.0, 0.0, 1.0)
          gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
          hudOverlay:drawLoading(windowWidth, windowHeight, job)
          glfw.glfwSwapBuffers(window)
          glfw.glfwPollEvents()
          renderedLoadingFrame = true
        end
      end
      if not renderedLoadingFrame and displayState.screen and not displayState.hasWorld then
        syncCursorMode(window, displayState, playerCamera)
        gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
        gl.glViewport(0, 0, windowWidth, windowHeight)
        gl.glClearColor(0.0, 0.0, 0.0, 1.0)
        gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
        hudOverlay:drawMenu(windowWidth, windowHeight, displayState.screen, displayState.menuMouseX, displayState.menuMouseY, displayState, currentTime)
        glfw.glfwSwapBuffers(window)
        glfw.glfwPollEvents()
        renderedLoadingFrame = true
      end
      if not renderedLoadingFrame then
        syncCursorMode(window, displayState, playerCamera)
        local previewMode = devMenu:isPreviewMode() and worldgenPreviewMesh ~= nil
        local queueStats = {
          budget = TERRAIN_WORK_BUDGET,
          processed = 0,
          chunkSteps = 0,
          meshSteps = 0,
          meshUploads = 0,
          syncUploads = 0,
          dropped = 0,
          lightingBudget = 0
        }
        local distantStats = nil
        if not previewMode then
          if displayState.hasWorld then
            distantStats = distantTerrain:update(
              world, terrainMeshes, displayState.pendingTerrainEntries,
              playerCamera.position[1], playerCamera.position[3]
            )
            queueStats.distant = distantStats
          end
          pruneTerrainMeshes(world, terrainMeshes, displayState.pendingTerrainEntries, playerCamera.position[1], playerCamera.position[3])
          if #displayState.pendingTerrainEntries < CHUNK_QUEUE_BACKLOG then
            local streamForward = playerCamera:getHorizontalFront()
            queueTerrainMeshes(
              world,
              displayState.pendingTerrainEntries,
              playerCamera.position[1],
              playerCamera.position[3],
              math.min(CHUNK_QUEUE_BUDGET, CHUNK_QUEUE_BACKLOG - #displayState.pendingTerrainEntries),
              {
                predictedX = playerCamera.position[1] + (playerCamera.velocity and playerCamera.velocity[1] or 0.0) * 1.5,
                predictedZ = playerCamera.position[3] + (playerCamera.velocity and playerCamera.velocity[3] or 0.0) * 1.5,
                forwardX = streamForward[1],
                forwardZ = streamForward[3]
              },
              function(chunkX, chunkZ) return distantTerrain:isPending(chunkX, chunkZ) end
            )
          end
          if #displayState.pendingTerrainEntries > 0 or world.lightDirty or world.lightingJob then
            queueStats = processTerrainMeshQueue(world, terrainMeshes, displayState.pendingTerrainEntries, TERRAIN_WORK_BUDGET)
            queueStats.distant = distantStats
          end
        end
        displayState.lastQueueStats = queueStats
        if displayState.hasWorld and not previewMode then
          local pickedUp = droppedItems:update(dt, world, playerCamera.position, displayState.inventory)
          if pickedUp > 0 then
            displayState.inventoryVersion = displayState.inventoryVersion + 1
          end
          for _,tree in ipairs(fallingTrees:update(dt)) do
            local mesh=fallingTreeMeshes[tree.id]
            if mesh then rendering.release(mesh) fallingTreeMeshes[tree.id]=nil end
            if displayState.worldGameMode~="creative" then
              droppedItems:spawn(tree.drop,tree.logCount,{tree.pivot[1]+tree.direction[1]*2,tree.pivot[2]+.3,tree.pivot[3]+tree.direction[3]*2},{0,2,0},.35)
            end
          end
        end
        if previewMode then
          updateWorldgenPreviewCamera(worldgenPreviewState, worldgenPreviewCamera, window, dt, not devMenu:wantsMouse())
          local meshCenterX = worldgenPreviewState.meshCenterX or worldgenPreviewState.centerX
          local meshCenterZ = worldgenPreviewState.meshCenterZ or worldgenPreviewState.centerZ
          if math.abs(worldgenPreviewState.centerX - meshCenterX) > 520.0 or
             math.abs(worldgenPreviewState.centerZ - meshCenterZ) > 520.0 then
            worldgenPreviewMesh = rebuildWorldgenPreview(
              worldgenPreviewMesh,
              devMenu:stagedGenerationSettings(),
              world.seed,
              worldgenPreviewState.centerX,
              worldgenPreviewState.centerZ
            )
            worldgenPreviewState.meshCenterX = worldgenPreviewState.centerX
            worldgenPreviewState.meshCenterZ = worldgenPreviewState.centerZ
          end
        elseif not displayState.screen and not displayState.devMenuOpen then
          playerCamera:update(dt, window, world)
          heldItem.updateMotion(displayState.heldMotion, playerCamera, dt)
          updateBlockEditInput(window, displayState, world, displayState.pendingTerrainEntries, playerCamera, droppedItems, fallingTrees, dt)
        else
          displayState.hotbarScroll = 0.0
        end
        if displayState.hasWorld and currentTime - lastPlayerSaveTime >= PLAYER_AUTOSAVE_INTERVAL then
          saveCurrentPlayer(displayState, playerCamera)
          lastPlayerSaveTime = currentTime
        end
        local worldCycleSpeed = SUN_CYCLE_SPEED / (activeWorldProfile.dayLengthScale or 1.0)
        devMenu:setNaturalTimeOfDay(timeOfDayForSimulationTime(currentTime, worldCycleSpeed))
        local atmosphereTime = currentTime
        if game.forceTimeOfDay then
          atmosphereTime = simulationTimeForTimeOfDay(game.forceTimeOfDay, worldCycleSpeed)
        end
        if devMenu:usesTimeOverride() then
          atmosphereTime = simulationTimeForTimeOfDay(devMenu:timeOfDay(), worldCycleSpeed)
        end
        updateRuntimeAtmosphereSettings(runtimeAtmosphereSettings, devMenu:fogStrength(), activeWorldProfile)

        local sunDir = math3d.normalize(atmosphere.sunDirection(atmosphereTime, worldCycleSpeed))
        local sky = atmosphere.forSun(sunDir, FOG_START, FOG_END, activeWorldProfile)
        local activeCamera = previewMode and worldgenPreviewCamera or playerCamera
        local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, CAMERA_NEAR, CAMERA_FAR)
        local view = math3d.lookAt(activeCamera.position, activeCamera:getCenter(), {0, 1, 0})
        local frustum = math3d.frustumPlanes(math3d.multiplyMat4(projection, view))
        local centerChunkX = World.chunkCoord(activeCamera.position[1])
        local centerChunkZ = World.chunkCoord(activeCamera.position[3])
        local visibleNearMeshes = previewMode and {} or visibleTerrainMeshes(
          terrainMeshes, frustum, centerChunkX, centerChunkZ, world.chunkRadius
        )
        local visibleMeshes = appendMeshes({}, visibleNearMeshes)
        if not previewMode then
          appendMeshes(visibleMeshes, distantTerrain:visible(
            frustum, math3d.aabbInFrustum, centerChunkX, centerChunkZ, world.chunkRadius
          ))
        end
        local visibleDielectrics = previewMode and {} or visibleDielectricMeshes(visibleNearMeshes)
        local visibleWater = previewMode and {} or visibleWaterMeshes(visibleMeshes)
        if displayState.debugScreen and not displayState.screen and not previewMode then
          displayState.debugSampleTimer = displayState.debugSampleTimer + dt
          if not displayState.debugInfo or displayState.debugSampleTimer >= 0.25 then
            displayState.debugInfo = buildDebugInfo(
              world,
              terrainMeshes,
              visibleMeshes,
              displayState.pendingTerrainEntries,
              playerCamera,
              displayState,
              currentTime,
              queueStats,
              sky,
              sunDir
            )
            displayState.debugSampleTimer = 0.0
          end
        elseif not displayState.debugScreen then
          displayState.debugInfo = nil
        end
        local lightSpaceMatrix = effects.lightSpaceMatrix(activeCamera.position, sunDir, TERRAIN_MAX_H, SHADOW_DISTANCE, SHADOW_NEAR, SHADOW_FAR)
        if not previewMode then
          effects.renderShadowPass(shadowShader, shadowMap, shadowLocations, visibleNearMeshes, characterMesh, lightSpaceMatrix, model, SHADOW_MAP_SIZE, windowWidth, windowHeight, atlasTex)
        end
        effects.renderVolumetricFog(volumetricFog, volumetricFogShaders, activeCamera, sunDir, sky, CAMERA_FOV, windowWidth, windowHeight, currentWaterLevel or WATER_LEVEL, previewMode and previewAtmosphereSettings or runtimeAtmosphereSettings, shadowMap, lightSpaceMatrix)
        if not previewMode and currentWaterLevel and #visibleWater > 0 then
          -- Terrain caustics and the surface must read the same current FFT field.
          effects.updateOceanSimulation(ocean, dt)
        end

        sceneTarget = effects.ensureSceneTarget(sceneTarget, windowWidth, windowHeight)
        waterBackgroundTarget = effects.ensureSceneTarget(waterBackgroundTarget, windowWidth, windowHeight)
        bloomChain = effects.ensureBloomChain(bloomChain, windowWidth, windowHeight, POST.bloomLevels or 6)
        gl.glBindFramebuffer(GL_FRAMEBUFFER, sceneTarget.framebuffer[0])
        gl.glViewport(0, 0, windowWidth, windowHeight)

        gl.glUseProgram(shader)
        gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", projection))
        gl.glUniformMatrix4fv(locV, 1, 0, ffi.new("float[16]", view))
        gl.glUniformMatrix4fv(locLightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
        gl.glUniform3f(locViewPos, activeCamera.position[1], activeCamera.position[2], activeCamera.position[3])
        gl.glUniform3f(locLight, -sunDir[1], -sunDir[2], -sunDir[3])
        gl.glUniform1f(locTime, currentTime)
        gl.glUniform3f(locAmbientColor, sky.ambient[1], sky.ambient[2], sky.ambient[3])
        gl.glUniform3f(locLightColor, sky.lightColor[1], sky.lightColor[2], sky.lightColor[3])
        gl.glUniform3f(locMoonLightColor, sky.moonLightColor[1], sky.moonLightColor[2], sky.moonLightColor[3])
        gl.glUniform3f(locLightingParams, sky.daylight, sky.moonAmount, sky.ambientFloor)
        gl.glUniform1f(locShadowStrength, sky.shadowStrength)
        gl.glUniform1f(locTerrainWaterLevel, previewMode and -1000.0 or (currentWaterLevel or -1000.0))
        gl.glUniform3f(locTerrainWaterCascadeSizes,
          ocean.cascadeSizes[1], ocean.cascadeSizes[2], ocean.cascadeSizes[3])
        gl.glUniform3f(locTerrainWaterNormalWeights,
          ocean.normalWeights[1], ocean.normalWeights[2], ocean.normalWeights[3])
        gl.glUniform1f(locTerrainCausticStrength, graphics.water.causticStrength or 0.42)

        gl.glClearColor(sky.fogColor[1], sky.fogColor[2], sky.fogColor[3], 1.0)
        gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
        drawSky(skyShader, skyMesh, skyLocations, moonTexture, activeCamera, sunDir, sky, currentTime,
          activeWorldProfile)
        gl.glClear(GL_DEPTH_BUFFER_BIT)

        if previewMode then
          gl.glUseProgram(worldgenPreviewShader)
          gl.glUniformMatrix4fv(worldgenPreviewLocations.projection, 1, 0, ffi.new("float[16]", projection))
          gl.glUniformMatrix4fv(worldgenPreviewLocations.view, 1, 0, ffi.new("float[16]", view))
          gl.glUniform3f(worldgenPreviewLocations.lightDir, sunDir[1], sunDir[2], sunDir[3])
          rendering.draw(worldgenPreviewMesh)
        else
          gl.glUseProgram(shader)
          gl.glActiveTexture(GL_TEXTURE0)
          gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
          gl.glActiveTexture(GL_TEXTURE1)
          gl.glBindTexture(GL_TEXTURE_2D, shadowMap.depthTexture[0])
          gl.glActiveTexture(GL_TEXTURE2)
          gl.glBindTexture(GL_TEXTURE_2D, ocean.normalTexture)
          gl.glActiveTexture(GL_TEXTURE0)
          for _, mesh in ipairs(visibleMeshes) do
            rendering.draw(mesh)
          end
          if characterMesh then
            rendering.draw(characterMesh)
          end
          drawDroppedItems(droppedItems, droppedItemMeshes, locM, model)
          drawFallingTrees(fallingTrees,fallingTreeMeshes,locM,model)
          effects.miningOverlay:draw(displayState,projection,view)
          if #visibleDielectrics > 0 then
            effects.copySceneTarget(sceneTarget, waterBackgroundTarget)
            effects.drawDielectrics(
              dielectricShader, visibleDielectrics, dielectricLocations, playerCamera,
              view, projection, sunDir, sky, waterBackgroundTarget,
              windowWidth, windowHeight, CAMERA_NEAR, CAMERA_FAR,
              atlasTex, graphics.dielectrics, model
            )
          end
          if activeWorldProfile.hasClouds then
            drawClouds(cloudShader, cloudMesh, cloudLocations, playerCamera, view, projection, currentTime, sky)
          end
          if currentWaterLevel and #visibleWater > 0 then
            effects.copySceneTarget(sceneTarget, waterBackgroundTarget)
            effects.drawWater(
              waterShader, visibleWater, waterLocations, playerCamera, view, projection, sunDir, sky,
              currentWaterLevel, ocean, waterBackgroundTarget, windowWidth, windowHeight,
              currentTime, CAMERA_NEAR, CAMERA_FAR
            )
          end
        end

        -- Bloom reads the HDR scene before it is graded, so anything brighter
        -- than the threshold bleeds. Runs at half resolution downward, so the
        -- whole chain costs about as much as one full-resolution pass.
        local bloomTexture = nil
        if POST.bloom ~= false then
          bloomTexture = effects.renderBloom(bloomShaders, bloomChain, sceneTarget.colorTexture[0], skyMesh, {
            threshold = POST.bloomThreshold or 0.70,
            softKnee = POST.bloomSoftKnee or 0.60,
            radius = POST.bloomRadius or 1.0,
            clampMax = POST.bloomClamp or 12.0
          })
        end

        gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
        gl.glViewport(0, 0, windowWidth, windowHeight)
        effects.drawAtmospherePost(atmospherePostShader, skyMesh, atmospherePostLocations, sceneTarget, activeCamera, CAMERA_FOV, windowWidth, windowHeight, CAMERA_NEAR, CAMERA_FAR, previewMode and -1000.0 or (currentWaterLevel or -1000.0), previewMode and previewAtmosphereSettings or runtimeAtmosphereSettings, displayState.screen == "pause" and 1.15 or 0.0, underwaterOverlayTexture, currentTime, bloomTexture, POST, volumetricFog)
        if displayState.screen == "inventory" or displayState.screen == "creative_inventory" or displayState.screen == "crafting_table" or displayState.screen == "furnace" then
          hudOverlay:drawInventory(windowWidth, windowHeight, displayState.screen, displayState,
            displayState.menuMouseX, displayState.menuMouseY, {id = atlasTex}, currentTime)
        elseif displayState.screen then
          hudOverlay:drawMenu(windowWidth, windowHeight, displayState.screen, displayState.menuMouseX, displayState.menuMouseY, displayState, currentTime)
        elseif not previewMode then
          -- The held model is camera-relative, but its light remains anchored
          -- to the world. Transform the sun into view space and sample the
          -- player's local skylight so caves, night, and water affect it too.
          local heldLightDir={
            view[1]*sunDir[1]+view[5]*sunDir[2]+view[9]*sunDir[3],
            view[2]*sunDir[1]+view[6]*sunDir[2]+view[10]*sunDir[3],
            view[3]*sunDir[1]+view[7]*sunDir[2]+view[11]*sunDir[3]
          }
          local heldLocalLight=world:skyLightAt(
            math.floor(playerCamera.position[1]),math.floor(playerCamera.position[2]),
            math.floor(playerCamera.position[3]))/15
          hudOverlay:draw(windowWidth, windowHeight, currentTime, displayState.selectedSlot, displayState,
            {id = atlasTex},{
              ambient=sky.ambient,
              sunColor=sky.lightColor,
              moonColor=sky.moonLightColor,
              ambientFloor=sky.ambientFloor,
              lightDir=heldLightDir,
              localLight=heldLocalLight,
              underwater=currentWaterLevel and playerCamera.position[2]<currentWaterLevel,
              heldTransform=devMenu:heldItemTransform(),
              heldMotion=displayState.viewBobbing == false and {lookX=displayState.heldMotion.lookX,lookY=displayState.heldMotion.lookY} or displayState.heldMotion
            })
          if displayState.debugScreen and displayState.debugInfo then
            hudOverlay:drawDebug(windowWidth, windowHeight, displayState.debugInfo)
          end
        end
        devMenu:draw(window, windowWidth, windowHeight, dt)
        displayState.devMenuOpen = devMenu:isOpen()

        if game.screenshotSchedule and #game.screenshotSchedule > 0 then
          local due = game.screenshotSchedule[1]
          if currentTime >= due.at then
            table.remove(game.screenshotSchedule, 1)
            if game.captureFrame(due.path, windowWidth, windowHeight) then
              print(string.format("Captured %s at %.1f s", due.path, currentTime))
            else
              print("Failed to write " .. due.path)
            end
            if #game.screenshotSchedule == 0 and game.exitAfterScreenshots then
              glfw.glfwSetWindowShouldClose(window, 1)
            end
          end
        end

        glfw.glfwSwapBuffers(window)
        glfw.glfwPollEvents()
      end
    end

    saveCurrentPlayer(displayState, playerCamera)
    effects.releaseBloomChain(bloomChain)
    effects.releaseVolumetricFog(volumetricFog, volumetricFogShaders)
    effects.releaseOceanSimulation(ocean)
    effects.releaseSceneTarget(waterBackgroundTarget)
    effects.releaseSceneTarget(sceneTarget)
    devMenu:release()
    rendering.release(worldgenPreviewMesh)
    releaseDroppedItemMeshes(droppedItemMeshes)
    releaseFallingTreeMeshes(fallingTreeMeshes)
    releaseTerrainMeshes(terrainMeshes)
    distantTerrain:clear()
    rendering.release(characterMesh)
    effects.miningOverlay:release()
    rendering.release(skyMesh)
    rendering.release(cloudMesh)
    hudOverlay:release()
  end)

  glfw.glfwTerminate()

  if not ok then
    error(err)
  end
end

return game
