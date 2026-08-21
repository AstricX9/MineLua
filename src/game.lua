local ffi = require("ffi")
local glfw = require("glfw")
local GL = require("gl")
local atmosphere = require("atmosphere")
local blocks = require("blocks")
local camera = require("camera")
local character = require("character")
local effects = require("render_effects")
local graphics = require("graphics_settings")
local hud = require("hud")
local math3d = require("math3d")
local rendering = require("rendering")
local saves = require("saves")
local shaderModule = require("shader")
local spawnLoading = require("spawn_loading")
local terrain = require("terrain")
local texture = require("texture")
local uiFlow = require("ui_flow")
local voxel = require("voxel")
local World = require("world")
local worldInteraction = require("world_interaction")

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
local GL_NEAREST = 0x2600
local GL_RGBA = 0x1908
local GL_UNSIGNED_BYTE = 0x1401
local GL_ARRAY_BUFFER = 0x8892
local GL_STATIC_DRAW = 0x88E4
local GL_FLOAT = 0x1406
local GL_TEXTURE0 = 0x84C0
local GL_TEXTURE1 = 0x84C1
local GL_TEXTURE2 = 0x84C2
local GL_TEXTURE3 = 0x84C3
local GL_TEXTURE4 = 0x84C4
local GL_TEXTURE5 = 0x84C5
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

local WINDOW_W = graphics.window.width
local WINDOW_H = graphics.window.height
local windowWidth = WINDOW_W
local windowHeight = WINDOW_H
local CAMERA_FOV = math.rad(graphics.window.fovDegrees)
-- Set graphics.window.vsync = false (data/settings.json) to uncap the frame rate
-- and have the debug screen report real frame cost instead of the refresh rate.
local VSYNC_ENABLED = graphics.window.vsync ~= false
local CAMERA_NEAR = 0.1
local CAMERA_FAR = math.max(graphics.world.visualDistance or 4096.0, 4096.0)
local TERRAIN_MAX_H = graphics.world.terrainMaxHeight
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
local WATER_RADIUS = math.min(graphics.water.radius, (CHUNK_RENDER_RADIUS + 0.5) * 16.0)
local CLOUD_CELL_SIZE = 12.0
local CLOUD_MESH_CELLS = 256
local CLOUD_BOTTOM = graphics.atmosphere.cloudBottom or 132.0
local CLOUD_TOP = graphics.atmosphere.cloudTop or (CLOUD_BOTTOM + 4.0)
local CLOUD_ALPHA = 0.76
local PERFORMANCE = graphics.performance or {}
local POST = graphics.post or {}
local SKY = graphics.sky or {}
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

local function createShaderProgram()
  local vertSource = [[
#version 330 core
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
#version 330 core
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
#version 330 core
layout (location = 0) in vec3 aPos;
out vec2 vUv;
void main() {
  vUv = aPos.xy * 0.5 + 0.5;
  gl_Position = vec4(aPos.xy, 0.0, 1.0);
}
]]

  local fragSource = [[
#version 330 core
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
uniform sampler2D sunTex;
uniform sampler2D cloudTex;

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
const float PLANET_RADIUS = 6371000.0;
const float ATMOSPHERE_RADIUS = 6471000.0;
const float RAYLEIGH_SCALE_H = 8000.0;
const float MIE_SCALE_H = 1200.0;
// Bruneton's coefficients at 680/550/440 nm, per metre.
const vec3 RAYLEIGH_BETA = vec3(5.802e-6, 13.558e-6, 33.100e-6);
const float MIE_BETA = 21.0e-6;
const float MIE_G = 0.758;
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
  vec3 origin = vec3(0.0, PLANET_RADIUS + observerAltitude, 0.0);

  float rayLength = raySphereFar(origin, rayDir, ATMOSPHERE_RADIUS);
  if (rayLength <= 0.0) return vec3(0.0);

  // Looking down into the planet: stop at the surface.
  float groundHit = raySphereNear(origin, rayDir, PLANET_RADIUS);
  if (groundHit > 0.0) rayLength = min(rayLength, groundHit);

  float mu = dot(rayDir, sunDirection);
  float phaseRayleigh = 3.0 / (16.0 * PI_SKY) * (1.0 + mu * mu);
  float g2 = MIE_G * MIE_G;
  float phaseMie = 3.0 / (8.0 * PI_SKY) * ((1.0 - g2) * (1.0 + mu * mu)) /
                   ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * MIE_G * mu, 1e-4), 1.5));

  float stepSize = rayLength / float(SCATTER_VIEW_SAMPLES);
  float travelled = 0.0;
  float opticalDepthR = 0.0;
  float opticalDepthM = 0.0;
  vec3 accumR = vec3(0.0);
  vec3 accumM = vec3(0.0);

  for (int i = 0; i < SCATTER_VIEW_SAMPLES; i++) {
    vec3 samplePos = origin + rayDir * (travelled + stepSize * 0.5);
    float height = length(samplePos) - PLANET_RADIUS;

    float densityR = exp(-height / RAYLEIGH_SCALE_H) * stepSize;
    float densityM = exp(-height / MIE_SCALE_H) * stepSize;
    opticalDepthR += densityR;
    opticalDepthM += densityM;

    // second march: how much air the sunlight crossed to reach this sample
    float lightLength = raySphereFar(samplePos, sunDirection, ATMOSPHERE_RADIUS);
    float lightStep = lightLength / float(SCATTER_LIGHT_SAMPLES);
    float lightTravelled = 0.0;
    float lightDepthR = 0.0;
    float lightDepthM = 0.0;
    bool occluded = false;

    for (int j = 0; j < SCATTER_LIGHT_SAMPLES; j++) {
      vec3 lightPos = samplePos + sunDirection * (lightTravelled + lightStep * 0.5);
      float lightHeight = length(lightPos) - PLANET_RADIUS;
      if (lightHeight < 0.0) { occluded = true; break; }
      lightDepthR += exp(-lightHeight / RAYLEIGH_SCALE_H) * lightStep;
      lightDepthM += exp(-lightHeight / MIE_SCALE_H) * lightStep;
      lightTravelled += lightStep;
    }

    if (!occluded) {
      vec3 tau = RAYLEIGH_BETA * (opticalDepthR + lightDepthR) +
                 MIE_BETA * 1.1 * (opticalDepthM + lightDepthM);
      vec3 transmittance = exp(-tau);
      accumR += transmittance * densityR;
      accumM += transmittance * densityM;
    }

    travelled += stepSize;
  }

  return sunIntensity * (accumR * RAYLEIGH_BETA * phaseRayleigh + accumM * MIE_BETA * phaseMie);
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
  float observerAltitude = max(cameraPosition.y - 62.0, 1.0);
  vec3 scattered = atmosphericScattering(skyPos, sun, observerAltitude, skyParams.z);
  vec3 nightSky = mix(vec3(0.060, 0.095, 0.150), vec3(0.015, 0.028, 0.080), altitude);
  vec3 color = nightSky * nightAmount + scattered * skyParams.x;

  float moonVisible = smoothstep(-0.06, 0.08, moon.y) * nightAmount;
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

  float sunAmount = max(dot(skyPos, sun), 0.0);
  vec3 sunTint = mix(vec3(1.0, 0.58, 0.28), vec3(1.0, 0.96, 0.82), dayAmount);
  vec3 sunBasisUp = abs(sun.y) > 0.96 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
  vec3 sunRight = normalize(cross(sunBasisUp, sun));
  vec3 sunUp = normalize(cross(sun, sunRight));
  vec2 sunUv = vec2(dot(skyPos, sunRight), dot(skyPos, sunUp)) / 0.044;
  vec2 sunSampleUv = sunUv * 0.5 + 0.5;
  vec4 sunTextureColor = texture(sunTex, sunSampleUv);
  float sunSquare = step(max(abs(sunUv.x), abs(sunUv.y)), 1.0);
  float sunLuma = max(max(sunTextureColor.r, sunTextureColor.g), sunTextureColor.b);
  float sunImageMask = sunTextureColor.a * sunSquare * smoothstep(0.025, 0.11, sunLuma);
  color += sunTint * pow(sunAmount, 420.0) * 0.16 * max(dayAmount, 0.15) * skyTuning.z;
  color = mix(color, sunTextureColor.rgb * sunTint * 1.18, sunImageMask * smoothstep(-0.06, 0.08, sun.y) * skyTuning.z);

  color += vec3(0.82, 0.88, 1.0) * stars(pos) * nightAmount * smoothstep(0.0, 0.18, pos.y);
  color = mix(color, vec3(0.98, 0.38, 0.18), horizonWarmth * smoothstep(0.0, 0.12, skyPos.y) * 0.15);
  color += noise(skyPos * 1000.0) * 0.006;
  color = vec3(1.0) - exp(-color * skyTuning.x);
  color = pow(color, vec3(1.08));
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
#version 330 core
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
#version 330 core
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

local function uploadTerrainChunkMesh(entry, vertices, options)
  options = options or {}
  local mesh = uploadTerrainMesh(vertices)
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

local function replaceTerrainMesh(terrainMeshes, key, mesh)
  rendering.release(terrainMeshes[key])
  terrainMeshes[key] = mesh
end

local function releaseTerrainMeshes(terrainMeshes)
  for key, mesh in pairs(terrainMeshes) do
    rendering.release(mesh)
    terrainMeshes[key] = nil
  end
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

  local atlasTex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, atlasTex)
  gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, atlas.w, atlas.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, atlas.pixels)

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
  return uploadTerrainChunkMesh(entry, voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetZ,
    meshOptions(world, entry, provisionalLight)), {
    provisionalLight = provisionalLight,
    lightRevision = world.lightRevision
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
    item.vertices = voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetZ,
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
  local seed = tonumber(config.seed) or randomWorldSeed()
  local spawnX = config.spawnX or DEFAULT_SPAWN_X
  local spawnZ = config.spawnZ or DEFAULT_SPAWN_Z
  local plan = spawnLoading.createPlan({
    centerChunkX = World.chunkCoord(spawnX),
    centerChunkZ = World.chunkCoord(spawnZ),
    requiredRadius = math.min(CHUNK_RENDER_RADIUS, LOADING_REQUIRED_RADIUS),
    haloRadius = math.min(CHUNK_RENDER_RADIUS, LOADING_HALO_RADIUS)
  })
  local save = saves.createWorld({
    worldName = config.worldName,
    gameMode = config.gameMode,
    generatorType = config.generatorType,
    seed = seed
  })

  local world = World.new({
    chunkRadius = CHUNK_RENDER_RADIUS,
    maxHeight = TERRAIN_MAX_H,
    generatorType = config.generatorType,
    seed = seed,
    deferInitialChunks = true
  })

  return {
    config = config,
    save = save,
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
    seed = seed
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
          lightRevision = job.world.lightRevision
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

local function queueTerrainMeshes(world, pendingEntries, x, z, budget, priority)
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
      if not world.chunks[key] and not queued[key] then
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
          provisionalLight = item.provisionalLight,
          lightRevision = world.lightRevision
        }))
        stats.meshUploads = stats.meshUploads + 1
        item.vertices = nil
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
      rendering.release(terrainMeshes[key])
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

local function createCharacterMesh()
  local player = character.createPlayer({8, 6, 8})
  return uploadMesh(player:createMesh())
end

local function drawSky(skyShader, skyMesh, locations, moonTexture, sunTexture, cloudTexture, playerCamera, sunDir, sky, time)
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
  gl.glUniform3f(locations.skyTuning, graphics.atmosphere.skyExposure, graphics.atmosphere.cloudDensity, graphics.atmosphere.sunGlare)
  gl.glUniform3f(locations.skyParams, SKY.scatterStrength or 1.0, 0.0, SKY.sunIntensity or 22.0)
  gl.glUniform3f(locations.fogColor, sky.fogColor[1], sky.fogColor[2], sky.fogColor[3])
  gl.glActiveTexture(GL_TEXTURE2)
  gl.glBindTexture(GL_TEXTURE_2D, moonTexture[0])
  gl.glActiveTexture(GL_TEXTURE4)
  gl.glBindTexture(GL_TEXTURE_2D, sunTexture[0])
  gl.glActiveTexture(GL_TEXTURE5)
  gl.glBindTexture(GL_TEXTURE_2D, cloudTexture[0])
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

  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  rendering.draw(cloudMesh)
  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
end

local function visibleTerrainMeshes(terrainMeshes, frustum)
  local visible = {}
  for _, mesh in pairs(terrainMeshes) do
    if mesh and (not mesh.bounds or math3d.aabbInFrustum(frustum, mesh.bounds)) then
      visible[#visible + 1] = mesh
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

  local leftLines = {
    string.format("MineLua 1.0.0 (%s)", runtime),
    string.format("%d fps (%s ms avg, %s ms last)", math.floor((state.debugFps or 0.0) + 0.5), formatNumber(state.debugFrameMs or 0.0, 1), formatNumber(state.debugLastFrameMs or 0.0, 1)),
    string.format("C: %d/%d chunks, V: %d verts", meshStats.visible, meshStats.uploaded, math.floor(meshStats.visibleVertices + 0.5)),
    queueLine,
    frameWorkLine,
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
    string.format("Generator: %s", tostring(world.generatorType or "default")),
    string.format("Server chunks: %d loaded / %d ready / %d collision", chunkStats.loaded, chunkStats.serverReady, chunkStats.collision),
    string.format("Lighting: %d lit / dirty %s / job %s / rev %d", chunkStats.light, tostring(world.lightDirty == true), tostring(world.lightingJob ~= nil), world.lightRevision or 0),
    string.format("Render chunks: %d mesh / %d gpu / %d ready", chunkStats.mesh, chunkStats.gpu, chunkStats.renderReady),
    string.format("Provisional meshes: %d", meshStats.provisional),
    string.format("Terrain GPU: %s, %d verts", formatBytes(meshStats.bytes), math.floor(meshStats.totalVertices + 0.5)),
    string.format("Budget: terrain %d, queue %d, backlog %d", TERRAIN_WORK_BUDGET, CHUNK_QUEUE_BUDGET, CHUNK_QUEUE_BACKLOG),
    string.format("Spawn load: %dx%d required, %dx%d halo", LOADING_REQUIRED_RADIUS * 2 + 1, LOADING_REQUIRED_RADIUS * 2 + 1, LOADING_HALO_RADIUS * 2 + 1, LOADING_HALO_RADIUS * 2 + 1),
    string.format("Lighting budget: stream %d, load %d", LIGHTING_STEP_BUDGET, LOADING_LIGHTING_STEP_BUDGET),
    string.format("Render radius: %d chunks, far %.0f", CHUNK_RENDER_RADIUS, CAMERA_FAR),
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
    escapeWasDown = false,
    breakWasDown = false,
    placeWasDown = false,
    menuClickWasDown = false,
    debugScreen = false,
    debugInfo = nil,
    debugSampleTimer = 0.0,
    debugFrames = 0,
    debugFrameAccumulator = 0.0,
    debugFps = 0.0,
    debugFrameMs = 0.0,
    debugLastFrameMs = 0.0,
    lastQueueStats = nil,
    screen = "main",
    cursorMode = nil,
    menuMouseX = -1,
    menuMouseY = -1,
    worldGameMode = "survival",
    worldGeneratorType = "default",
    hasWorld = false,
    menuParentScreen = nil,
    currentWorldSave = nil,
    pendingNewWorldConfig = nil,
    loadingJob = nil,
    pendingTerrainEntries = {},
    selectedSlot = 1,
    hotbarBlocks = {
      blocks.grass,
      blocks.dirt,
      blocks.stone,
      blocks.sand,
      blocks.gravel or blocks.cobblestone,
      blocks.sandstone or blocks.cobblestone,
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

local function playerOptionsForGameMode(gameMode)
  local options = {}
  for key, value in pairs(graphics.player) do
    options[key] = value
  end

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

local function syncCursorMode(window, state, playerCamera)
  local target = state.screen and glfw.GLFW_CURSOR_NORMAL or glfw.GLFW_CURSOR_DISABLED
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

local function handleUiCommand(window, command, playerCamera)
  if command == "quit_game" then
    glfw.glfwSetWindowShouldClose(window, 1)
  elseif command == "started_world" or command == "resume" then
    if playerCamera then
      playerCamera.firstMouse = true
    end
  end
end

local function updateFullscreenInput(window, state, locP, playerCamera)
  local f11Down = glfw.glfwGetKey(window, glfw.GLFW_KEY_F11) == glfw.GLFW_PRESS
  local escapeDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_ESCAPE) == glfw.GLFW_PRESS

  if f11Down and not state.f11WasDown then
    setFullscreen(window, state, not state.fullscreen, locP)
  end

  if escapeDown and not state.escapeWasDown and state.fullscreen then
    setFullscreen(window, state, false, locP)
  elseif escapeDown and not state.escapeWasDown then
    local wasScreen = state.screen
    uiFlow.back(state)
    if wasScreen and not state.screen and playerCamera then
      playerCamera.firstMouse = true
    end
  end

  state.f11WasDown = f11Down
  state.escapeWasDown = escapeDown
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

local function updateMenuInput(window, state, playerCamera)
  if not state.screen then
    state.menuClickWasDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
    return
  end

  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  local clientWidth = ffi.new("int[1]")
  local clientHeight = ffi.new("int[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)
  glfw.glfwGetWindowSize(window, clientWidth, clientHeight)
  state.menuMouseX = tonumber(xpos[0]) * windowWidth / math.max(1, tonumber(clientWidth[0]))
  state.menuMouseY = tonumber(ypos[0]) * windowHeight / math.max(1, tonumber(clientHeight[0]))

  local clickDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
  if clickDown and not state.menuClickWasDown then
    local action = hud.menuButtonAt(state.screen, windowWidth, windowHeight, state.menuMouseX, state.menuMouseY, state)
    handleUiCommand(window, uiFlow.applyAction(state, action), playerCamera)
  end

  state.menuClickWasDown = clickDown
end

local function updateBlockEditInput(window, state, world, pendingEntries, playerCamera)
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

  for i = 1, #slotKeys do
    if glfw.glfwGetKey(window, slotKeys[i]) == glfw.GLFW_PRESS then
      state.selectedSlot = i
    end
  end

  if breakDown and not state.breakWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    if hit then
      worldInteraction.breakBlock(world, hit.x, hit.y, hit.z)
      rebuildBlockChunkMeshes(world, pendingEntries, hit.x, hit.z)
    end
  end

  if placeDown and not state.placeWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    local blockId = state.hotbarBlocks[state.selectedSlot]
    local target = worldInteraction.placeFromHit(world, hit, blockId)
    if target then
      rebuildBlockChunkMeshes(world, pendingEntries, target.x, target.z)
    end
  end

  state.breakWasDown = breakDown
  state.placeWasDown = placeDown
end

local function initWindow()
  if glfw.glfwInit() == 0 then
    error("Failed to init GLFW")
  end

  glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3)
  glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3)
  glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE)

  local window = glfw.glfwCreateWindow(WINDOW_W, WINDOW_H, "MineLua", nil, nil)
  if window == nil then
    error("Failed to create window")
  end

  glfw.glfwMakeContextCurrent(window)
  -- With vsync on, every frame reports the refresh interval regardless of how
  -- much work it actually did, which hides the real headroom. Turn it off to
  -- measure true frame cost.
  glfw.glfwSwapInterval(VSYNC_ENABLED and 1 or 0)
  glfw.glfwSetInputMode(window, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_NORMAL)

  return window
end

function game.run()
  local ok, err = pcall(function()
    local window = initWindow()

    GL.loadModernGL()
    print("GL_VERSION:", ffi.string(gl.glGetString(0x1F02)))

    gl.glEnable(GL_DEPTH_TEST)
    gl.glDepthFunc(GL_LESS)
    gl.glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS)

    local atlasTex = createTextureAtlas()
    local moonTexture = createImageTexture("assets/textures/environment/moon_phases.png", true)
    local sunTexture = createImageTexture("assets/textures/environment/sun.png", true)
    local cloudTexture = createImageTexture("assets/textures/environment/clouds.png", true, true)
    local waterTexture = createImageTexture("assets/textures/blocks/water_flow.png", true, true)
    local underwaterOverlayTexture = createImageTexture("assets/textures/blocks/water_overlay.png", false, true)
    local world = World.new({
      chunkRadius = CHUNK_RENDER_RADIUS,
      maxHeight = TERRAIN_MAX_H,
      generatorType = "default",
      seed = graphics.terrainGeneration.seed or 1,
      deferInitialChunks = true
    })
    local terrainMeshes = {}
    local currentWaterLevel = WATER_LEVEL
    local characterMesh = graphics.player.showDebugBody and createCharacterMesh() or nil
    local skyMesh = uploadSkyMesh()
    local cloudMesh = createCloudMesh("assets/textures/environment/clouds.png")
    local waterMesh = uploadMesh(effects.waterVertices(WATER_RADIUS))
    local shadowMap = effects.createShadowMap(SHADOW_MAP_SIZE)
    local sceneTarget = effects.createSceneTarget(windowWidth, windowHeight)

    local shader = createShaderProgram()
    local shadowShader = effects.createShadowShader()
    local skyShader = createSkyShaderProgram()
    local cloudShader = createCloudShaderProgram()
    local waterShader = effects.createWaterShader()
    local atmospherePostShader = effects.createAtmospherePostShader()
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
      sunTex = gl.glGetUniformLocation(skyShader, "sunTex"),
      cloudTex = gl.glGetUniformLocation(skyShader, "cloudTex")
    }
    local cloudLocations = {
      projection = gl.glGetUniformLocation(cloudShader, "uProjection"),
      view = gl.glGetUniformLocation(cloudShader, "uView"),
      offset = gl.glGetUniformLocation(cloudShader, "cloudOffset"),
      alpha = gl.glGetUniformLocation(cloudShader, "cloudAlpha"),
      tint = gl.glGetUniformLocation(cloudShader, "cloudTint")
    }
    local waterLocations = {
      projection = gl.glGetUniformLocation(waterShader, "uProjection"),
      view = gl.glGetUniformLocation(waterShader, "uView"),
      waterCenter = gl.glGetUniformLocation(waterShader, "waterCenter"),
      waterLevel = gl.glGetUniformLocation(waterShader, "waterLevel"),
      viewPos = gl.glGetUniformLocation(waterShader, "viewPos"),
      sunDir = gl.glGetUniformLocation(waterShader, "sunDir"),
      fogColor = gl.glGetUniformLocation(waterShader, "fogColor"),
      fogParams = gl.glGetUniformLocation(waterShader, "fogParams"),
      lightColor = gl.glGetUniformLocation(waterShader, "lightColor"),
      skyZenithColor = gl.glGetUniformLocation(waterShader, "skyZenithColor"),
      time = gl.glGetUniformLocation(waterShader, "time"),
      waterTex = gl.glGetUniformLocation(waterShader, "waterTex")
    }
    local atmospherePostLocations = {
      sceneColor = gl.glGetUniformLocation(atmospherePostShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(atmospherePostShader, "sceneDepth"),
      underwaterOverlay = gl.glGetUniformLocation(atmospherePostShader, "underwaterOverlay"),
      cameraPosition = gl.glGetUniformLocation(atmospherePostShader, "cameraPosition"),
      cameraForward = gl.glGetUniformLocation(atmospherePostShader, "cameraForward"),
      cameraRight = gl.glGetUniformLocation(atmospherePostShader, "cameraRight"),
      cameraUp = gl.glGetUniformLocation(atmospherePostShader, "cameraUp"),
      cameraProjection = gl.glGetUniformLocation(atmospherePostShader, "cameraProjection"),
      sunDir = gl.glGetUniformLocation(atmospherePostShader, "sunDir"),
      fogColor = gl.glGetUniformLocation(atmospherePostShader, "fogColor"),
      fogParams = gl.glGetUniformLocation(atmospherePostShader, "fogParams"),
      skyZenithColor = gl.glGetUniformLocation(atmospherePostShader, "skyZenithColor"),
      lightColor = gl.glGetUniformLocation(atmospherePostShader, "lightColor"),
      depthParams = gl.glGetUniformLocation(atmospherePostShader, "depthParams"),
      atmosphereParams = gl.glGetUniformLocation(atmospherePostShader, "atmosphereParams"),
      scatterParams = gl.glGetUniformLocation(atmospherePostShader, "scatterParams"),
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
    gl.glUseProgram(skyShader)
    gl.glUniform1i(skyLocations.moonTex, 2)
    gl.glUniform1i(skyLocations.sunTex, 4)
    gl.glUniform1i(skyLocations.cloudTex, 5)
    gl.glUseProgram(shader)
    gl.glUniform3f(locFaceLight, graphics.terrain.topLight, graphics.terrain.sideLight, graphics.terrain.bottomLight)
    gl.glUniform1f(locExposure, graphics.terrain.exposure)

    local playerCamera = camera.new(playerOptionsForGameMode("survival"))
    playerCamera:placeAtSpawn(world, playerCamera.position[1], playerCamera.position[3])
    local displayState = createDisplayState()
    local lastTime = glfw.glfwGetTime()

    while glfw.glfwWindowShouldClose(window) == 0 do
      local currentTime = glfw.glfwGetTime()
      local dt = currentTime - lastTime
      lastTime = currentTime

      updateDebugFrameStats(displayState, dt)
      updateFullscreenInput(window, displayState, locP, playerCamera)
      updateDebugInput(window, displayState)
      refreshDrawableSize(window, displayState)
      updateMenuInput(window, displayState, playerCamera)
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
          world = job.world
          terrainMeshes = job.terrainMeshes
          displayState.currentWorldSave = job.save
          currentWaterLevel = job.config.generatorType == "superflat" and nil or WATER_LEVEL
          playerCamera = camera.new(playerOptionsForGameMode(job.config.gameMode))
          playerCamera:placeAtSpawn(world, job.spawnX, job.spawnZ)
          playerCamera.firstMouse = true
          displayState.selectedSlot = 1
          displayState.worldGameMode = job.config.gameMode
          displayState.worldGeneratorType = job.config.generatorType
          displayState.hasWorld = true
          displayState.screen = nil
          displayState.loadingJob = nil
          displayState.pendingTerrainEntries = job.streamingEntries or {}
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
            }
          )
        end
        if #displayState.pendingTerrainEntries > 0 or world.lightDirty or world.lightingJob then
          queueStats = processTerrainMeshQueue(world, terrainMeshes, displayState.pendingTerrainEntries, TERRAIN_WORK_BUDGET)
        end
        displayState.lastQueueStats = queueStats
        if not displayState.screen then
          playerCamera:update(dt, window, world)
          updateBlockEditInput(window, displayState, world, displayState.pendingTerrainEntries, playerCamera)
        end
        local sunDir = math3d.normalize(atmosphere.sunDirection(currentTime, SUN_CYCLE_SPEED))
        local sky = atmosphere.forSun(sunDir, FOG_START, FOG_END)
        local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, CAMERA_NEAR, CAMERA_FAR)
        local view = math3d.lookAt(playerCamera.position, playerCamera:getCenter(), {0, 1, 0})
        local frustum = math3d.frustumPlanes(math3d.multiplyMat4(projection, view))
        local visibleMeshes = visibleTerrainMeshes(terrainMeshes, frustum)
        if displayState.debugScreen and not displayState.screen then
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
        local lightSpaceMatrix = effects.lightSpaceMatrix(playerCamera.position, sunDir, TERRAIN_MAX_H, SHADOW_DISTANCE, SHADOW_NEAR, SHADOW_FAR)
        effects.renderShadowPass(shadowShader, shadowMap, shadowLocations, visibleMeshes, characterMesh, lightSpaceMatrix, model, SHADOW_MAP_SIZE, windowWidth, windowHeight, atlasTex)

        sceneTarget = effects.ensureSceneTarget(sceneTarget, windowWidth, windowHeight)
        bloomChain = effects.ensureBloomChain(bloomChain, windowWidth, windowHeight, POST.bloomLevels or 6)
        gl.glBindFramebuffer(GL_FRAMEBUFFER, sceneTarget.framebuffer[0])
        gl.glViewport(0, 0, windowWidth, windowHeight)

        gl.glUseProgram(shader)
        gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", projection))
        gl.glUniformMatrix4fv(locV, 1, 0, ffi.new("float[16]", view))
        gl.glUniformMatrix4fv(locLightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
        gl.glUniform3f(locViewPos, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
        gl.glUniform3f(locLight, -sunDir[1], -sunDir[2], -sunDir[3])
        gl.glUniform1f(locTime, currentTime)
        gl.glUniform3f(locAmbientColor, sky.ambient[1], sky.ambient[2], sky.ambient[3])
        gl.glUniform3f(locLightColor, sky.lightColor[1], sky.lightColor[2], sky.lightColor[3])
        gl.glUniform3f(locMoonLightColor, sky.moonLightColor[1], sky.moonLightColor[2], sky.moonLightColor[3])
        gl.glUniform3f(locLightingParams, sky.daylight, sky.moonAmount, sky.ambientFloor)
        gl.glUniform1f(locShadowStrength, sky.shadowStrength)

        gl.glClearColor(sky.fogColor[1], sky.fogColor[2], sky.fogColor[3], 1.0)
        gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
        drawSky(skyShader, skyMesh, skyLocations, moonTexture, sunTexture, cloudTexture, playerCamera, sunDir, sky, currentTime)
        gl.glClear(GL_DEPTH_BUFFER_BIT)

        gl.glUseProgram(shader)
        gl.glActiveTexture(GL_TEXTURE0)
        gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
        gl.glActiveTexture(GL_TEXTURE1)
        gl.glBindTexture(GL_TEXTURE_2D, shadowMap.depthTexture[0])
        gl.glActiveTexture(GL_TEXTURE0)
        for _, mesh in ipairs(visibleMeshes) do
          rendering.draw(mesh)
        end
        if characterMesh then
          rendering.draw(characterMesh)
        end
        drawClouds(cloudShader, cloudMesh, cloudLocations, playerCamera, view, projection, currentTime, sky)
        if currentWaterLevel then
          effects.drawWater(waterShader, waterMesh, waterLocations, playerCamera, view, projection, sunDir, sky, currentTime, currentWaterLevel, waterTexture)
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
        effects.drawAtmospherePost(atmospherePostShader, skyMesh, atmospherePostLocations, sceneTarget, playerCamera, sunDir, sky, CAMERA_FOV, windowWidth, windowHeight, CAMERA_NEAR, CAMERA_FAR, currentWaterLevel or -1000.0, graphics.atmosphere, displayState.screen == "pause" and 1.15 or 0.0, underwaterOverlayTexture, currentTime, bloomTexture, POST)
        if displayState.screen then
          hudOverlay:drawMenu(windowWidth, windowHeight, displayState.screen, displayState.menuMouseX, displayState.menuMouseY, displayState, currentTime)
        else
          hudOverlay:draw(windowWidth, windowHeight, currentTime, displayState.selectedSlot)
          if displayState.debugScreen and displayState.debugInfo then
            hudOverlay:drawDebug(windowWidth, windowHeight, displayState.debugInfo)
          end
        end

        glfw.glfwSwapBuffers(window)
        glfw.glfwPollEvents()
      end
    end

    effects.releaseBloomChain(bloomChain)
    releaseTerrainMeshes(terrainMeshes)
    rendering.release(characterMesh)
    rendering.release(skyMesh)
    rendering.release(cloudMesh)
    rendering.release(waterMesh)
    hudOverlay:release()
  end)

  glfw.glfwTerminate()

  if not ok then
    error(err)
  end
end

return game
