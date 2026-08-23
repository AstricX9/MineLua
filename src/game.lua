local ffi = require("ffi")
local glfw = require("glfw")
local GL = require("gl")
local atmosphere = require("atmosphere")
local blocks = require("blocks")
local camera = require("camera")
local Celestial = require("celestial")
local character = require("character")
local DevMenu = require("dev_menu")
local effects = require("render_effects")
local graphics = require("graphics_settings")
local hud = require("hud")
local Inventory = require("inventory")
local math3d = require("math3d")
local Planet = require("planet")
local planetVisuals = require("planet_visuals")
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
local WATER_NEAR_TESSELLATION = graphics.water.nearTessellation or 2
local FAR_WATER_CHUNK_RADIUS = graphics.water.farChunkRadius or 18
local FAR_WATER_COVERAGE_SUBDIVISIONS = graphics.water.farCoverageSubdivisions or 4
local FAR_WATER_TILE_SUBDIVISIONS = graphics.water.farTileSubdivisions or 8
local FAR_WATER_BUILD_BUDGET = graphics.water.farBuildBudget or 8
local FAR_WATER_FRAME_BUDGET = (graphics.water.farBuildBudgetMs or 2.0) / 1000.0
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
local BASE_POST_EXPOSURE = POST.exposure or 1.0
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
local TWO_PI = math.pi * 2.0

-- The sky is no longer a vector swept around by a tuning constant. The planet
-- turns, and the sun direction is read out of that rotation in body
-- coordinates. atmosphere.sunCycleSpeed is left in the settings file for the
-- flat worldgen preview, which has no planet to turn.
local celestial = Celestial.new(graphics.celestial)

local function updateRuntimeAtmosphereSettings(runtime, strength)
  for key, value in pairs(graphics.atmosphere) do
    runtime[key] = value
  end

  strength = math.max(0.0, math.min(strength or 1.0, 3.0))
  runtime.heightFogDensity = (graphics.atmosphere.heightFogDensity or 0.0045) * strength
  runtime.horizonFog = (graphics.atmosphere.horizonFog or 0.24) * strength
  runtime.distanceFogDensity = (graphics.atmosphere.distanceFogDensity or 0.0015) * strength
  runtime.airScatter = (graphics.atmosphere.airScatter or 0.12) * strength

  local authoredOpacity = graphics.atmosphere.fogMaxOpacity or graphics.atmosphere.maxFogAmount or 0.82
  runtime.fogMaxOpacity = 1.0 - ((1.0 - authoredOpacity) ^ strength)
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
uniform vec3 viewPos;
uniform vec3 planetUp;
uniform vec4 foliageParams; // grass cull start/end, leaf wind distance, strength

float plantHash(vec2 cell) {
  return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec3 localPosition = aPos;
  vec3 worldPosition = vec3(uModel * vec4(localPosition, 1.0));
  if (aInfo.x > 0.5) {
    bool isGrass = aInfo.x > 1.5;
    vec3 upAxis=normalize(planetUp);
    vec3 referenceAxis=abs(upAxis.y)<0.85?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0);
    vec3 tangentX=normalize(cross(referenceAxis,upAxis));
    vec3 tangentZ=normalize(cross(upAxis,tangentX));
    vec2 plantCell=floor(vec2(dot(worldPosition,tangentX),dot(worldPosition,tangentZ)))+vec2(0.5);
    vec2 cameraCell=vec2(dot(viewPos,tangentX),dot(viewPos,tangentZ));
    float cameraDistance=length(plantCell-cameraCell);

    // Stable per-block thinning avoids a hard circular cutoff and removes the
    // distant grass triangles before rasterization. Leaves retain silhouettes.
    if (isGrass) {
      float visibility = 1.0 - smoothstep(foliageParams.x, foliageParams.y, cameraDistance);
      if (plantHash(plantCell) > visibility) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return;
      }
    }

    float animationEnd = isGrass ? foliageParams.x : foliageParams.z;
    float distanceFade = 1.0 - smoothstep(animationEnd * 0.58, animationEnd, cameraDistance);
    float anchor = pow(clamp(aInfo.y, 0.0, 1.0), 1.35) * distanceFade;

    // Three spatial/temporal scales make coherent gusts carry smaller lateral
    // turbulence and tip flutter instead of every plant rocking in lockstep.
    vec2 windDirection = normalize(vec2(0.88, 0.34));
    vec2 crossWind = vec2(-windDirection.y, windDirection.x);
    float gust = 0.58 + 0.42 * sin(time * 0.43 + dot(plantCell, vec2(0.018, -0.014)));
    gust = gust * gust * (3.0 - 2.0 * gust);
    float mainWave=sin(time*1.35+dot(plantCell,vec2(0.24,0.17)));
    float turbulence=sin(time*2.65+dot(plantCell,vec2(-0.53,0.71))+mainWave*0.7);
    float flutter=sin(time*5.2+dot(plantCell,vec2(1.71,-1.27)));
    float strength = (isGrass ? 0.105 : 0.038) * foliageParams.w;
    vec2 bend = windDirection * (mainWave * (0.55 + gust * 0.62) + flutter * 0.12)
      + crossWind * turbulence * 0.22;
    worldPosition+=(tangentX*bend.x+tangentZ*bend.y)*strength*anchor;
    worldPosition-=upAxis*abs(mainWave)*strength*anchor*(isGrass?0.10:0.04);
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
uniform vec3 planetUp;
uniform float exposure;
uniform float shadowStrength;
uniform float useVoxelLight;
uniform float smoothLighting;
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
  float radialFacing=dot(normal,normalize(planetUp));
  if(radialFacing>0.9)return 1.00;
  if(radialFacing< -0.9)return 0.50;
  return 0.72+0.08*abs(normal.x);
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

vec4 causticSurface(vec2 surfacePosition) {
  vec4 wave0 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.x + vec2(0.17, 0.61));
  vec4 wave1 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.y + vec2(0.73, 0.29));
  vec4 wave2 = texture(waterNormalMap, surfacePosition / waterCascadeSizes.z + vec2(0.41, 0.83));
  vec3 waveNormal = normalize(
    wave0.xyz * waterNormalWeights.x +
    wave1.xyz * waterNormalWeights.y +
    wave2.xyz * waterNormalWeights.z
  );
  return vec4(waveNormal, min(wave0.a, min(wave1.a, wave2.a)));
}

float voxelCaustics(vec3 worldPosition, vec3 surfaceNormal, vec3 sunlight) {
  float waterDepth = waterLevel - worldPosition.y;
  if (waterDepth <= 0.02 || sunlight.y <= 0.015) return 0.0;

  // Start with the flat-surface Snell solution, then perform one correction
  // toward the surface point whose refracted solar ray actually reaches this
  // voxel. This is a compact backward ray-tracing approximation.
  const float AIR_TO_WATER = 1.0 / 1.333;
  vec3 flatRay = refract(-sunlight, vec3(0.0, 1.0, 0.0), AIR_TO_WATER);
  vec2 surfacePosition = worldPosition.xz - flatRay.xz *
    (waterDepth / max(-flatRay.y, 0.08));

  vec4 surfaceData = causticSurface(surfacePosition);
  vec3 transmitted = refract(-sunlight, surfaceData.xyz, AIR_TO_WATER);
  vec2 landing = surfacePosition + transmitted.xz *
    (waterDepth / max(-transmitted.y, 0.08));
  surfacePosition -= (landing - worldPosition.xz) * 0.72;

  surfaceData = causticSurface(surfacePosition);
  transmitted = refract(-sunlight, surfaceData.xyz, AIR_TO_WATER);
  landing = surfacePosition + transmitted.xz *
    (waterDepth / max(-transmitted.y, 0.08));

  float missDistance = length(landing - worldPosition.xz);
  float beamRadius = 0.16 + waterDepth * 0.012 + fwidth(missDistance) * 1.5;
  float beam = exp(-0.5 * (missDistance * missDistance) /
    max(beamRadius * beamRadius, 1.0e-4));

  // The FFT displacement Jacobian is a cheap flux-density estimate: compressed
  // surface patches cover less receiver area and therefore become brighter.
  float jacobian = clamp(surfaceData.a, 0.16, 1.65);
  float fluxDensity = clamp(0.16 + max(1.0 / jacobian - 1.0, 0.0) * 1.65, 0.0, 2.6);
  float focusing = beam * fluxDensity;

  float depthFade = exp(-waterDepth * 0.052);
  float daylight = smoothstep(0.015, 0.22, sunlight.y);
  float receiving = 0.18 + 0.82 * max(dot(surfaceNormal, -transmitted), 0.0);
  return clamp(focusing * depthFade * daylight * receiving, 0.0, 1.35);
}

void main() {
  float material = vInfo.x;
  bool isLeaf = material > 0.5 && material < 1.5;
  // Terrain is intentionally rendered without global back-face culling. Flip
  // normals for a visible reverse face so alpha-cut leaves remain lit like a
  // thin two-sided surface instead of turning into dark or glowing cardboard.
  vec3 geometricNormal = gl_FrontFacing ? vNormal : -vNormal;
  vec3 norm = normalize(geometricNormal);
  if (material > 1.5) {
    norm = normalize(mix(norm, vec3(0.0, 1.0, 0.0), 0.65));
  } else if (material > 0.5) {
    norm = normalize(mix(norm, vec3(0.0, 1.0, 0.0), 0.35));
  }
  vec3 light = normalize(-lightDir);
  float diff = max(dot(norm, light), 0.0);
  vec4 texColor = texture(tex0, vTexCoord);
  vec3 viewDirection = normalize(viewPos - vFragPos);
  float surfaceAlpha = texColor.a;
  if (isLeaf) {
    // Beer-Lambert optical thickness for a thin leaf sheet. The dedicated
    // foliage pass composites this alpha back-to-front without writing depth.
    if (texColor.a < 0.5) discard;
    vec3 sheetNormal = normalize(geometricNormal);
    float viewCosine = max(abs(dot(sheetNormal, viewDirection)), 0.20);
    float cameraDistance = length(viewPos - vFragPos);
    // The texel cutout supplies the visible gaps. Covered texels represent a
    // cluster of real leaflets, so they should be nearly opaque rather than a
    // pane of green glass. Retain only a restrained 2-8% transmission, with
    // grazing and distant foliage becoming denser to preserve silhouettes.
    float denseAtDistance = smoothstep(18.0, 92.0, cameraDistance);
    float grazing = 1.0 - viewCosine;
    float leafCoverage = mix(0.92, 0.985, max(grazing, denseAtDistance));
    surfaceAlpha *= leafCoverage;
  } else if (texColor.a < 0.5) {
    discard;
  }
  vec3 albedo = srgbToLinear(texColor.rgb) * srgbToLinear(vColor);

  // Zero is a valid fully-dark terrain light value. Non-terrain meshes do not
  // carry aInfo, so the draw call explicitly disables voxel lighting for them.
  float voxelLight = mix(1.0, clamp(vInfo.z, 0.0, 1.0), useVoxelLight * smoothLighting);
  if (material > 0.5) {
    voxelLight = max(voxelLight, 0.34);
  }

  float sunDiffuse = material > 1.5 ? mix(0.88, 1.0, diff) : mix(0.68, 1.0, diff);
  float faceShadeValue = fixedFaceShade(normalize(geometricNormal), material);
  float shadowAmount = shadowAt(norm, light, diff) * shadowStrength;
  float shadowVisibility = mix(1.0, 0.45, clamp(shadowAmount, 0.0, 1.0));
  float daylight = lightingParams.x;
  float ambientFloor = lightingParams.z;

  vec3 skyContribution = ambientColor * voxelLight;
  vec3 sunContribution = lightColor * faceShadeValue * sunDiffuse * shadowVisibility * voxelLight;
  vec3 moonContribution = moonLightColor * mix(0.76, 1.0, max(dot(norm, -light), 0.0)) * faceShadeValue * voxelLight;
  vec3 totalLight = skyContribution + sunContribution + moonContribution;
  if (isLeaf) {
    // A compact thin-leaf BTDF approximation: light arriving behind the sheet
    // is forward-scattered toward the viewer and tinted by the leaf albedo.
    vec3 sheetNormal = normalize(geometricNormal);
    float backLighting = max(dot(-sheetNormal, light), 0.0);
    float forwardScatter = pow(max(dot(viewDirection, -light), 0.0), 4.0);
    float transmission = backLighting * (0.20 + 0.42 * forwardScatter)
      * mix(0.60, 1.0, shadowVisibility) * daylight;
    totalLight += lightColor * vec3(0.62, 1.00, 0.42) * transmission * voxelLight;
  }
  float solidAO = material < 0.5 ? clamp(vInfo.y, 0.45, 1.0) : 1.0;
  solidAO = mix(1.0, solidAO, smoothLighting);
  float shapedAmbientFloor = ambientFloor * mix(0.68, 1.0, solidAO)
    * mix(0.74, 1.0, faceShadeValue);
  totalLight = max(totalLight, vec3(shapedAmbientFloor));

  vec3 litColor = albedo * totalLight * exposure;
  if (isLeaf) {
    vec3 halfVector = normalize(light + viewDirection);
    float leafSpecular = pow(max(dot(norm, halfVector), 0.0), 24.0)
      * 0.065 * daylight * shadowVisibility;
    litColor += lightColor * leafSpecular * voxelLight;
  }
  float caustic = voxelCaustics(vFragPos, norm, light) * daylight * shadowVisibility * voxelLight;
  vec3 causticColor = srgbToLinear(vec3(0.52, 0.90, 1.0));
  litColor += albedo * lightColor * causticColor * caustic * causticStrength;
  vec3 finalColor = linearToSrgb(litColor);
  float luminance = dot(finalColor, vec3(0.2126, 0.7152, 0.0722));
  float nightSaturation = mix(0.55, 1.0, daylight);
  finalColor = mix(vec3(luminance), finalColor, nightSaturation);
  FragColor = vec4(finalColor, surfaceAlpha);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function createPlanetWaterShader()
  local vertex=[[
#version 460 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
out vec3 vPosition;
out vec3 vNormal;
uniform mat4 uProjection;
uniform mat4 uView;
void main(){vPosition=aPos;vNormal=normalize(aNormal);gl_Position=uProjection*uView*vec4(aPos,1.0);}
]]
  local fragment=[[
#version 460 core
in vec3 vPosition;
in vec3 vNormal;
out vec4 FragColor;
uniform vec3 viewPos;
uniform vec3 sunDir;
uniform vec3 waterColor;
void main(){
  vec3 V=normalize(viewPos-vPosition);
  vec3 N=normalize(vNormal);
  float fresnel=0.03+0.72*pow(1.0-max(dot(N,V),0.0),5.0);
  float sparkle=pow(max(dot(reflect(-normalize(sunDir),N),V),0.0),96.0);
  vec3 deep=waterColor*0.48;
  vec3 sky=vec3(0.36,0.66,0.86);
  vec3 color=mix(deep,sky,fresnel)+vec3(1.0,0.88,0.62)*sparkle*0.85;
  FragColor=vec4(color,0.78);
}
]]
  return shaderModule.fromSource(vertex,fragment)
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
uniform vec3 planetUp;
uniform float observerAltitude;
uniform vec3 cloudParams; // bottom altitude, top altitude, density
// Spin angle of the planet. The voxel world is the body frame, so the stars
// have to be counter-rotated by it or they would be nailed to the ground.
uniform float skyRotation;

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

vec2 raySphereRoots(vec3 origin, vec3 dir, float radius) {
  float b = dot(origin, dir);
  float c = dot(origin, origin) - radius * radius;
  float d = b * b - c;
  if (d < 0.0) return vec2(1.0, -1.0);
  float h = sqrt(d);
  return vec2(-b - h, -b + h);
}

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

vec3 atmosphericScattering(vec3 origin, vec3 rayDir, vec3 sunDirection, float sunIntensity) {
  vec2 atmosphereHit = raySphereRoots(origin, rayDir, ATMOSPHERE_RADIUS);
  float rayStart = max(atmosphereHit.x, 0.0);
  float rayEnd = atmosphereHit.y;
  if (rayEnd <= rayStart) return vec3(0.0);

  // Looking down into the planet: stop at the surface.
  float groundHit = raySphereNear(origin, rayDir, PLANET_RADIUS);
  if (groundHit > rayStart) rayEnd = min(rayEnd, groundHit);
  float rayLength = rayEnd - rayStart;
  if (rayLength <= 0.0) return vec3(0.0);

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
    vec3 samplePos = origin + rayDir * (rayStart + travelled + stepSize * 0.5);
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

// Transmittance from the observer to the top of the atmosphere. The scattering
// march already computes this for the light rays it traces; the sun disc needs
// it along the view ray instead, so that the same air that turns the sky red at
// dusk dims and reddens the disc itself rather than a tint being authored for
// it. Returns black once the ray meets the planet, which is what makes the sun
// set instead of sitting on the horizon.
vec3 sunTransmittance(vec3 origin, vec3 rayDir) {
  vec2 atmosphereHit = raySphereRoots(origin, rayDir, ATMOSPHERE_RADIUS);
  float rayStart = max(atmosphereHit.x, 0.0);
  float rayEnd = atmosphereHit.y;
  if (rayEnd <= rayStart) return vec3(0.0);
  float groundHit = raySphereNear(origin, rayDir, PLANET_RADIUS);
  if (groundHit > rayStart && groundHit < rayEnd) return vec3(0.0);
  float rayLength = rayEnd - rayStart;

  float stepSize = rayLength / float(SCATTER_LIGHT_SAMPLES);
  float travelled = 0.0;
  float depthR = 0.0;
  float depthM = 0.0;

  for (int i = 0; i < SCATTER_LIGHT_SAMPLES; i++) {
    vec3 samplePos = origin + rayDir * (rayStart + travelled + stepSize * 0.5);
    float height = max(length(samplePos) - PLANET_RADIUS, 0.0);
    depthR += exp(-height / RAYLEIGH_SCALE_H) * stepSize;
    depthM += exp(-height / MIE_SCALE_H) * stepSize;
    travelled += stepSize;
  }

  return exp(-(RAYLEIGH_BETA * depthR + MIE_BETA * 1.1 * depthM));
}

// A render-only cloud shell.  It is sampled in true planet-centred 3D space,
// so it has no flat plane, longitude seam, or polar singularity.  Voxel terrain
// still owns collision; this layer is free to curve smoothly and the long
// grazing path naturally thickens toward the horizon.
//
// The march is clipped to the shell itself. Spreading ten steps over the whole
// atmosphere put about six of them inside a 2.4 km layer looking straight up
// and one or two near the horizon, and with the old extinction constant a
// vertical column accumulated roughly 0.05 alpha -- which is why the sky came
// out clean. Every step now lands in the layer, so twenty-four of them resolve
// individual clouds instead of a wash.

// fbm sums five unnormalised octaves of noise in [0,1], so it clusters near
// 0.52 with a standard deviation around 0.15 rather than filling its range.
// Rescaling here is what lets the coverage threshold below mean something.
//
// Three octaves rather than five: the cloud march samples this three times a
// step, twenty-four steps a pixel, at full resolution. Measured at 2560x1369,
// the layer cost 6.8 ms a frame -- clouds on 83 fps against 180 fps off. The
// two octaves dropped here sit below a kilometre in a field whose smallest
// meaningful feature is the wisp term, so they cost frame time without
// changing what the sky looks like.
float cloudField(vec3 p) {
  float f = noise(p) / 2.0;
  p = cloudMatrix * p * 1.1;
  f += noise(p) / 4.0;
  p = cloudMatrix * p * 1.2;
  f += noise(p) / 6.0;
  // Same centre and spread as the five-octave form, so the coverage numbers
  // below did not have to be retuned.
  return clamp(0.5 + (f - 0.4583) * 1.55, 0.0, 1.0);
}

vec4 sphericalCloudLayer(vec3 origin, vec3 rayDir, vec3 sunDirection, float seconds) {
  if (cloudParams.z <= 0.001) return vec4(0.0);
  float bottomRadius = PLANET_RADIUS + cloudParams.x;
  float topRadius = PLANET_RADIUS + max(cloudParams.y, cloudParams.x + 1.0);
  float thickness = topRadius - bottomRadius;

  vec2 outerHit = raySphereRoots(origin, rayDir, topRadius);
  if (outerHit.y <= 0.0 || outerHit.y <= outerHit.x) return vec4(0.0);
  float rayStart = max(outerHit.x, 0.0);
  float rayEnd = outerHit.y;

  // The inner sphere is a hole in the shell. Depending on where the observer
  // is, it either ends the segment (we are outside it, looking in) or starts it
  // (we are inside it, looking out).
  vec2 innerHit = raySphereRoots(origin, rayDir, bottomRadius);
  if (innerHit.y > innerHit.x) {
    if (innerHit.x > rayStart) rayEnd = min(rayEnd, innerHit.x);
    else if (innerHit.y > rayStart) rayStart = max(rayStart, innerHit.y);
  }

  float groundHit = raySphereNear(origin, rayDir, PLANET_RADIUS);
  if (groundHit > 0.0) rayEnd = min(rayEnd, groundHit);
  if (rayEnd <= rayStart) return vec4(0.0);

  const int CLOUD_STEPS = 18;
  float stepLength = (rayEnd - rayStart) / float(CLOUD_STEPS);
  vec3 drift = vec3(seconds * 0.0018, seconds * 0.00035, -seconds * 0.0011);

  // Extinction per metre. A 600 m thick column at full density reaches an
  // optical depth of about 2.4, which reads as solid without the whole sky
  // going flat white the moment coverage rises.
  const float EXTINCTION = 0.0060;

  float sunUp = clamp(dot(normalize(origin), sunDirection), -1.0, 1.0);
  float daylight = smoothstep(-0.18, 0.10, sunUp);
  float forwardScatter = pow(max(dot(rayDir, sunDirection), 0.0), 14.0);

  vec3 litColor = mix(vec3(0.62, 0.66, 0.78), vec3(1.00, 0.98, 0.94), daylight);
  vec3 shadeColor = mix(vec3(0.05, 0.07, 0.12), vec3(0.55, 0.60, 0.71), daylight);

  vec3 accumulated = vec3(0.0);
  float transmittance = 1.0;

  for (int i = 0; i < CLOUD_STEPS; i++) {
    if (transmittance < 0.015) break;
    vec3 samplePos = origin + rayDir * (rayStart + (float(i) + 0.5) * stepLength);
    float radius = length(samplePos);
    float layer = clamp((radius - bottomRadius) / thickness, 0.0, 1.0);

    vec3 radialNormal = samplePos / radius;
    // Wavelengths matter more than amplitudes here. The shape field used to run
    // at about 21 km and the weather field at 700 km, so the entire visible sky
    // sat inside a fraction of one cell: it was uniformly clouded or uniformly
    // clear, and from the ground that reads as no clouds at all. A cumulus
    // field is cells a few kilometres apart, which is the scale below.
    float weather = cloudField(radialNormal * 120.0 + drift * 0.02); // ~50 km systems
    float shape = cloudField(samplePos * 0.00026 + drift * 0.8);     // ~3.8 km cells
    float wisps = cloudField(samplePos * 0.0011 + drift * 2.2);      // ~0.9 km detail

    // Coverage is what the weather pattern asks for; the shape and wisp fields
    // decide which parts of that pattern actually condense.
    float coverage = clamp(cloudParams.z * 0.32 + (weather - 0.5) * 0.50, 0.0, 0.85);
    float field = shape * 0.72 + wisps * 0.28;
    // A narrow threshold is what gives a cloud an edge. The wide ramp this
    // replaced spread every cloud across more than a standard deviation of the
    // field, so the sky came out as haze with no shapes in it.
    float strength = smoothstep(1.0 - coverage, 1.0 - coverage + 0.10, field);
    // Flat-bottomed, rounded-topped, and taller where the field is stronger --
    // cumulus, rather than a slab of fog filling the shell.
    float topLimit = 0.22 + strength * 0.78;
    float verticalShape = smoothstep(0.0, 0.10, layer) *
      (1.0 - smoothstep(topLimit * 0.5, topLimit, layer));
    float density = strength * verticalShape;

    if (density > 0.001) {
      // Depth of cloud between this sample and the top of the layer along the
      // sun ray, without a second march: the slant factor is the only thing a
      // light march would add that matters at this scale.
      float slant = max(dot(radialNormal, sunDirection), 0.12);
      float lightDepth = (1.0 - layer) * thickness / slant;
      float lightTransmit = exp(-density * lightDepth * EXTINCTION * 0.42);
      // Powder: light that scattered forward through a thin edge, which is what
      // makes cloud rims glow instead of turning grey.
      float powder = 1.0 - exp(-density * 5.0);

      vec3 cloudColor = mix(shadeColor, litColor, lightTransmit * powder);
      cloudColor += vec3(1.0, 0.90, 0.72) * forwardScatter * lightTransmit * 0.55 * daylight;

      float alpha = 1.0 - exp(-density * stepLength * EXTINCTION);
      accumulated += transmittance * cloudColor * alpha;
      transmittance *= 1.0 - alpha;
    }
  }

  return vec4(accumulated, 1.0 - transmittance);
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
  vec3 radialUp = normalize(planetUp);
  vec3 observer = radialUp * (PLANET_RADIUS + max(observerAltitude, 0.0));
  float rayElevation = dot(pos, radialUp);
  float sunElevation = dot(sun, radialUp);
  float moonElevation = dot(moon, radialUp);
  float dayAmount = smoothstep(-0.08, 0.22, sunElevation);
  float nightAmount = 1.0 - smoothstep(-0.18, 0.08, sunElevation);
  float spaceAmount = smoothstep(70000.0, 115000.0, observerAltitude);
  float horizonWarmth = 1.0 - smoothstep(-0.03, 0.34, abs(sunElevation));
  float skyMask = smoothstep(-0.08, 0.08, rayElevation);
  vec3 skyPos = normalize(pos + radialUp * max(0.015 - rayElevation, 0.0));

  float altitude = smoothstep(0.0, 0.92, dot(skyPos, radialUp));

  // The physical model produces daylight only; it correctly falls to black once
  // the sun is below the horizon, so the authored night sky sits underneath it
  // rather than being cross-faded against it.
  vec3 scattered = atmosphericScattering(observer, pos, sun, skyParams.z);
  vec3 nightSky = mix(vec3(0.060, 0.095, 0.150), vec3(0.015, 0.028, 0.080), altitude);
  vec3 color = nightSky * nightAmount + scattered * skyParams.x;

  float moonVisible = smoothstep(-0.06, 0.08, moonElevation) * nightAmount;
  vec3 fallbackAxis = abs(radialUp.x) < 0.8 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
  vec3 moonBasisUp = abs(moonElevation) > 0.96 ? normalize(cross(radialUp, fallbackAxis)) : radialUp;
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
  vec3 sunTint = mix(vec3(1.0, 0.58, 0.28), vec3(1.0, 0.96, 0.82), dayAmount);
  color += sunTint * pow(sunAmount, 420.0) * 0.16 * max(dayAmount, 0.15) * skyTuning.z;

  float starCos = cos(skyRotation);
  float starSin = sin(skyRotation);
  vec3 starDir = vec3(pos.x * starCos + pos.z * starSin, pos.y, -pos.x * starSin + pos.z * starCos);
  color += vec3(0.82, 0.88, 1.0) * stars(starDir) * max(nightAmount, spaceAmount) * mix(smoothstep(0.0, 0.18, rayElevation), 1.0, spaceAmount);
  color = mix(color, vec3(0.98, 0.38, 0.18), horizonWarmth * smoothstep(0.0, 0.12, dot(skyPos, radialUp)) * 0.15);
  color += noise(skyPos * 1000.0) * 0.006;
  vec4 cloud = sphericalCloudLayer(observer, pos, sun, time.x);
  color = color * (1.0 - cloud.a) + cloud.rgb;
  color = vec3(1.0) - exp(-color * skyTuning.x);
  color = pow(color, vec3(1.08));

  // The sun itself is a real sphere drawn in its own pass, so what is left to
  // do here is report how much of it survives the cloud deck. That goes into
  // alpha, and the sun pass multiplies itself by it.
  color = mix(fogColor, color, skyMask);
  FragColor = vec4(color, 1.0 - cloud.a);
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

local function createOrbitalPlanetShader()
  local vertex = [[
#version 460 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
out vec3 vNormal;
out vec3 vColor;
out vec3 vPosition;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 planetOffset;
void main(){
  vPosition=aPos+planetOffset;
  vNormal=normalize(aNormal);
  vColor=aColor;
  gl_Position=uProjection*uView*vec4(vPosition,1.0);
}
]]
  local fragment = [[
#version 460 core
in vec3 vNormal;
in vec3 vColor;
in vec3 vPosition;
out vec4 FragColor;
uniform vec3 sunDir;
uniform vec3 viewPos;
void main(){
  vec3 N=normalize(vNormal);
  vec3 V=normalize(viewPos-vPosition);
  float daylight=max(dot(N,normalize(sunDir)),0.0);
  float twilight=smoothstep(-0.18,0.08,dot(N,normalize(sunDir)));
  vec3 surface=vColor*(0.055+daylight*0.95)*mix(vec3(0.28,0.36,0.52),vec3(1.0),twilight);
  float limb=pow(1.0-max(dot(N,V),0.0),4.0);
  surface+=vec3(0.10,0.34,0.72)*limb*(0.18+twilight*0.42);
  FragColor=vec4(surface,1.0);
}
]]
  return shaderModule.fromSource(vertex,fragment)
end

local function createOrbitalCloudShader()
  local vertex = [[
#version 460 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
out vec3 vDirection;
out vec3 vPosition;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 planetOffset;
void main(){
  vDirection=normalize(aNormal);
  vPosition=aPos+planetOffset;
  gl_Position=uProjection*uView*vec4(vPosition,1.0);
}
]]
  local fragment = [[
#version 460 core
in vec3 vDirection;
in vec3 vPosition;
out vec4 FragColor;
uniform vec3 sunDir;
uniform vec3 viewPos;
uniform float time;
float hash(vec3 p){p=fract(p*0.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z);}
float noise(vec3 p){
  vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
  return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void main(){
  vec3 drift=vec3(time*0.004,time*0.001,-time*0.002);
  float n=noise(vDirection*18.0+drift)*0.62+noise(vDirection*43.0-drift*0.7)*0.38;
  float alpha=smoothstep(0.54,0.72,n)*0.82;
  if(alpha<0.015) discard;
  float light=0.30+0.70*max(dot(normalize(vDirection),normalize(sunDir)),0.0);
  float silver=pow(1.0-max(dot(normalize(vDirection),normalize(viewPos-vPosition)),0.0),3.0);
  vec3 color=mix(vec3(0.34,0.39,0.48),vec3(0.96,0.98,1.0),light)+vec3(0.20,0.35,0.62)*silver*0.22;
  FragColor=vec4(color,alpha);
}
]]
  return shaderModule.fromSource(vertex,fragment)
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
  frozenShore = {0.72, 0.77, 0.76}
}

local function worldgenPreviewVertices(centerX, centerZ, extent, resolution)
  local vertices = {}
  local side = resolution + 1
  local step = extent / resolution
  local originX = math.floor((centerX - extent * 0.5) / step) * step
  local originZ = math.floor((centerZ - extent * 0.5) / step) * step
  local heights = {}
  local colors = {}

  for z = 0, resolution do
    for x = 0, resolution do
      local worldX = originX + x * step
      local worldZ = originZ + z * step
      local rawHeight = terrain.heightAt(worldX, worldZ, TERRAIN_MAX_H)
      local index = z * side + x + 1
      local localWaterLevel = terrain.waterSurfaceAt(worldX, worldZ)
      local underwater = localWaterLevel and rawHeight < localWaterLevel
      heights[index] = underwater and (localWaterLevel - 0.35) or rawHeight
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
  local origin = entry.renderOrigin or {0,0,0}
  return {
    minX = entry.offsetX - origin[1],
    minY = entry.offsetY - origin[2],
    minZ = entry.offsetZ - origin[3],
    maxX = entry.offsetX - origin[1] + 16,
    maxY = entry.offsetY - origin[2] + 16,
    maxZ = entry.offsetZ - origin[3] + 16
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

  local function isWater(id)
    return id == blocks.water or (blocks.water_still and id == blocks.water_still)
  end

  local function depthFactorAt(cellX, cellZ)
    local key = cellX .. "," .. cellZ
    local cached = depthSamples[key]
    if cached ~= nil then return cached end

    local depth = 4
    local surfaceY = terrain.waterSurfaceAt(cellX, cellZ)
    if not surfaceY then
      depthSamples[key] = 0.0
      return 0.0
    end
    surfaceY = math.floor(surfaceY)
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

  local function smoothBand(edge0, edge1, value)
    local t = saturate((value - edge0) / math.max(edge1 - edge0, 0.0001))
    return t * t * (3.0 - 2.0 * t)
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

      local shoreX, shoreZ, breaker = 0.0, 0.0, 0.0
      if world then
        -- The bathymetry gradient is the coastline-domain direction: depth
        -- increases offshore, so its negative points in the travel direction
        -- of a breaking wave. Sampling symmetrically makes this continuous at
        -- chunk boundaries and avoids any camera-dependent shoreline lookup.
        local gradientX = vertexDepthFactor(x + 1, z) - vertexDepthFactor(x - 1, z)
        local gradientZ = vertexDepthFactor(x, z + 1) - vertexDepthFactor(x, z - 1)
        local gradientLength = math.sqrt(gradientX * gradientX + gradientZ * gradientZ)
        if gradientLength > 0.012 then
          shoreX = -gradientX / gradientLength
          shoreZ = -gradientZ / gradientLength
          local entersBreakZone = smoothBand(0.10, 0.38, depthFactor)
          local leavesBreakZone = smoothBand(0.68, 0.98, depthFactor)
          local oceanEnergy = smoothBand(0.56, 0.90, exposure)
          breaker = entersBreakZone * (1.0 - leavesBreakZone) * oceanEnergy
        end
      end

      value = {exposure, shore, shoreX, shoreZ, breaker}
      samples[key] = value
    end
    return value[1], value[2], value[3], value[4], value[5]
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
    local e00, s00, x00, d00, b00 = sample(x0, z0)
    local e10, s10, x10, d10, b10 = sample(x0 + 1, z0)
    local e01, s01, x01, d01, b01 = sample(x0, z0 + 1)
    local e11, s11, x11, d11, b11 = sample(x0 + 1, z0 + 1)
    local function bilerp(v00, v10, v01, v11)
      local a = v00 + (v10 - v00) * tx
      local b = v01 + (v11 - v01) * tx
      return a + (b - a) * tz
    end
    return bilerp(e00, e10, e01, e11), bilerp(s00, s10, s01, s11),
      bilerp(x00, x10, x01, x11), bilerp(d00, d10, d01, d11),
      bilerp(b00, b10, b01, b11)
  end
end

local PLANET_WATER_FACE_CORNERS={
  {{1,0,1},{1,0,0},{1,1,0},{1,1,1}},{{0,0,0},{0,0,1},{0,1,1},{0,1,0}},
  {{0,1,1},{1,1,1},{1,1,0},{0,1,0}},{{0,0,0},{1,0,0},{1,0,1},{0,0,1}},
  {{0,0,1},{1,0,1},{1,1,1},{0,1,1}},{{1,0,0},{0,0,0},{0,1,0},{1,1,0}}
}
local PLANET_WATER_ORDER={1,2,3,3,4,1}

local function planetWaterChunkVertices(entry,world)
  local vertices={} local planet=world.planet local origin=world.renderOrigin
  local waterId,stillId=blocks.water,blocks.water_still
  if not waterId and not stillId then return vertices end
  local directions={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
  local function isWater(id) return id==waterId or (stillId and id==stillId) end
  local function appendVertex(gx,gy,gz,targetRadius)
    local rx,ry,rz=gx-planet.center[1],gy-planet.center[2],gz-planet.center[3]
    local length=math.sqrt(rx*rx+ry*ry+rz*rz)
    local nx,ny,nz=rx/length,ry/length,rz/length
    targetRadius=targetRadius or planet.seaLevelRadiusVoxels
    gx=planet.center[1]+nx*targetRadius-origin[1]
    gy=planet.center[2]+ny*targetRadius-origin[2]
    gz=planet.center[3]+nz*targetRadius-origin[3]
    local n=#vertices
    vertices[n+1]=gx vertices[n+2]=gy vertices[n+3]=gz
    vertices[n+4]=nx vertices[n+5]=ny vertices[n+6]=nz
    vertices[n+7]=1 vertices[n+8]=1 vertices[n+9]=1
    vertices[n+10]=0 vertices[n+11]=0
  end
  for x=0,15 do for y=0,15 do for z=0,15 do
    if isWater(entry.chunk:getBlock(x,y,z)) then
      local wx,wy,wz=entry.offsetX+x,entry.offsetY+y,entry.offsetZ+z
      local ux,uy,uz=planet:dominantUpStep({wx+0.5,wy+0.5,wz+0.5})
      if not isWater(world:blockAt(wx+ux,wy+uy,wz+uz)) then
        local waterSample=terrain.surfaceAtPosition(wx+0.5,wy+0.5,wz+0.5,planet)
        local targetRadius=waterSample.waterSurfaceRadiusVoxels or planet.seaLevelRadiusVoxels
        local dir=ux==1 and 1 or (ux==-1 and 2 or (uy==1 and 3 or (uy==-1 and 4 or (uz==1 and 5 or 6))))
        local corners=PLANET_WATER_FACE_CORNERS[dir]
        for i=1,6 do local c=corners[PLANET_WATER_ORDER[i]] appendVertex(wx+c[1],wy+c[2],wz+c[3],targetRadius) end
      end
    end
  end end end
  return vertices
end


local function uploadTerrainChunkMesh(entry, vertices, options)
  options = options or {}
  entry.renderOrigin = options.world and options.world.renderOrigin or entry.renderOrigin or {0,0,0}
  local renderCenter={entry.offsetX-entry.renderOrigin[1]+8,entry.offsetY-entry.renderOrigin[2]+8,entry.offsetZ-entry.renderOrigin[3]+8}
  local mesh = uploadTerrainMesh(vertices)
  if options.iceVertices and #options.iceVertices > 0 then
    mesh.iceMesh = uploadTerrainMesh(options.iceVertices)
  end
  if options.leafVertices and #options.leafVertices > 0 then
    mesh.leafMesh = uploadTerrainMesh(options.leafVertices)
    mesh.leafMesh.chunkX = entry.chunkX
    mesh.leafMesh.chunkY = entry.chunkY
    mesh.leafMesh.chunkZ = entry.chunkZ
    mesh.leafMesh.renderCenter=renderCenter
  end
  if options.world then
    local waterVertices=planetWaterChunkVertices(entry,options.world)
    if #waterVertices>0 then mesh.waterMesh=uploadMesh(waterVertices) end
  end
  mesh.chunkX = entry.chunkX
  mesh.chunkY = entry.chunkY
  mesh.chunkZ = entry.chunkZ
  mesh.renderCenter=renderCenter
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
  rendering.release(mesh.iceMesh)
  rendering.release(mesh.leafMesh)
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

-- Starts the spherical voxel world: a GridWorld the physics collides against
-- and a GridRuntime that keeps it generated and meshed around the player.
--
-- Hangs off the module table because this file is at Lua's 200-local ceiling.
function game.startGridWorld(world, playerCamera, terrainMeshes, radius)
  local GridWorld = require("grid_world")
  local GridRuntime = require("grid_runtime")
  local planet = world.planet
  local gridWorld = GridWorld.new(planet, world.seed)

  local runtime = GridRuntime.new(gridWorld, {
    radius = radius or 5,
    renderOrigin = world.renderOrigin,
    upload = function(key, vertices, leaves)
      releaseTerrainMesh(terrainMeshes[key])
      local mesh = #vertices > 0 and uploadTerrainMesh(vertices) or nil
      if leaves and #leaves > 0 then
        -- The leaf pass reads this off the terrain mesh, so an all-leaf chunk
        -- still needs a carrier even when it has no opaque geometry of its own.
        mesh = mesh or {count = 0, vao = nil}
        mesh.leafMesh = uploadTerrainMesh(leaves)
      end
      terrainMeshes[key] = mesh
    end,
    release = function(key)
      releaseTerrainMesh(terrainMeshes[key])
      terrainMeshes[key] = nil
    end
  })

  -- Stand the player on the grid terrain before anything else: the Cartesian
  -- surface under them can sit a metre away from it, which would drop them
  -- into the ground or leave them hanging.
  local up = planet:localUp(playerCamera.position)
  local surfaceRadius = gridWorld:surfaceRadius(up[1], up[2], up[3])
  local standRadius = surfaceRadius + playerCamera.eyeHeight + 1.0
  playerCamera.position = {
    planet.center[1] + up[1] * standRadius,
    planet.center[2] + up[2] * standRadius,
    planet.center[3] + up[3] * standRadius
  }
  playerCamera.velocity = {0, 0, 0}
  playerCamera.radialVelocity, playerCamera.velocityY = 0, 0
  playerCamera.grounded = false

  -- Load the ground under their feet synchronously, so they do not spawn into
  -- an unloaded hole and fall.
  runtime:refocus(playerCamera.position)
  for _ = 1, 9 do
    if runtime:ready() then break end
    runtime:update(playerCamera.position)
  end

  return gridWorld, runtime
end

-- Break or place a block on the spherical grid.
function game.updateGridEditInput(window, state, runtime, playerCamera, dt)
  state.gridEdit = state.gridEdit or {attack = false, use = false, cooldown = 0.0}
  local edit = state.gridEdit
  edit.cooldown = math.max(0.0, edit.cooldown - dt)

  local attack = playerCamera:controlDown(window, "attack", "MOUSE1")
  local use = playerCamera:controlDown(window, "use", "MOUSE2")
  local wantsBreak = attack and (not edit.attack or edit.cooldown <= 0.0)
  local wantsPlace = use and not edit.use
  edit.attack, edit.use = attack, use
  if not (wantsBreak or wantsPlace) then return end

  local origin = playerCamera.position
  local hit = runtime.world:raycast(origin, playerCamera:getFront(), playerCamera.reach or 6.0)
  if not hit then return end

  if wantsBreak then
    if runtime:setBlock(hit.face, hit.column, hit.row, hit.layer, blocks.air or 0) then
      edit.cooldown = 0.22
      state.stats.blocksMined = (state.stats.blocksMined or 0) + 1
    end
  elseif wantsPlace and hit.previous then
    local slot = state.inventory and state.inventory:selectedItem()
    local id = slot and slot.id
    if id and id ~= 0 then
      local previous = hit.previous
      if runtime:setBlock(previous.face, previous.column, previous.row, previous.layer, id) then
        state.stats.blocksPlaced = (state.stats.blocksPlaced or 0) + 1
      end
    end
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

-- A real spherical sun, not a screen-space disc.
--
-- The geometry is a unit sphere; the draw call scales it to the angular radius
-- the real sun subtends from one astronomical unit (0.00465 rad, about half a
-- degree across) at whatever distance keeps it inside the current frustum.
-- Because the pass runs with depth testing off, that distance is free to be
-- chosen for numerical comfort rather than realism -- a sphere at 1.5e11 m has
-- no representable position in a float vertex buffer.
local sunPass = {}

function sunPass.uploadMesh(segments, rings)
  segments, rings = segments or 32, rings or 16
  local vertices = {}

  local function push(latitude, longitude)
    local c = math.cos(latitude)
    local x, y, z = c * math.cos(longitude), math.sin(latitude), c * math.sin(longitude)
    local n = #vertices
    vertices[n + 1], vertices[n + 2], vertices[n + 3] = x, y, z
    vertices[n + 4], vertices[n + 5], vertices[n + 6] = x, y, z
    vertices[n + 7], vertices[n + 8], vertices[n + 9] = 1.0, 1.0, 1.0
    vertices[n + 10] = longitude / (math.pi * 2.0)
    vertices[n + 11] = latitude / math.pi + 0.5
  end

  for ring = 0, rings - 1 do
    local lat0 = -math.pi * 0.5 + math.pi * (ring / rings)
    local lat1 = -math.pi * 0.5 + math.pi * ((ring + 1) / rings)
    for segment = 0, segments - 1 do
      local lon0 = math.pi * 2.0 * (segment / segments)
      local lon1 = math.pi * 2.0 * ((segment + 1) / segments)
      push(lat0, lon0) push(lat1, lon0) push(lat1, lon1)
      push(lat1, lon1) push(lat0, lon1) push(lat0, lon0)
    end
  end

  return uploadMesh(vertices)
end

function sunPass.createShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
out vec3 vNormal;
out vec3 vWorldPos;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 sunCenter;
uniform float sunRadius;
void main() {
  vNormal = normalize(aPos);
  vWorldPos = sunCenter + vNormal * sunRadius;
  gl_Position = uProjection * uView * vec4(vWorldPos, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec3 vNormal;
in vec3 vWorldPos;
out vec4 FragColor;
uniform vec3 viewPos;
uniform vec3 sunRadiance;   // brightness already multiplied by atmospheric transmittance
void main() {
  // Linear limb darkening. mu is the cosine of the angle between the surface
  // normal and the line of sight, so it runs from 1 at the centre of the disc
  // to 0 at the limb. The coefficients are the solar values near 610, 550 and
  // 470 nm: red is darkened least, which is why the rim runs warm without a
  // tint being painted on.
  vec3 toViewer = normalize(viewPos - vWorldPos);
  float mu = clamp(dot(normalize(vNormal), toViewer), 0.0, 1.0);
  vec3 limb = vec3(1.0) - vec3(0.397, 0.503, 0.652) * (1.0 - mu);
  // Soften the very edge so a coarse sphere does not show its silhouette
  // polygons at this size.
  float edge = smoothstep(0.0, 0.06, mu);
  FragColor = vec4(sunRadiance * limb * edge, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

-- Draws the sun into the scene target. The pass is additive, so the sky it sits
-- on shows through the limb, and it is modulated by the destination alpha,
-- which the sky shader filled with how much of it survives the cloud deck.
function sunPass.draw(sunShader, sunMesh, locations, view, projection, viewPosition,
    sunDir, distance, radius, radiance)
  if radiance[1] + radiance[2] + radiance[3] <= 0.0005 then return end
  local GL_ZERO, GL_ONE, GL_DST_ALPHA = 0x0000, 0x0001, 0x0304
  gl.glUseProgram(sunShader)
  gl.glUniformMatrix4fv(locations.projection, 1, 0, ffi.new("float[16]", projection))
  gl.glUniformMatrix4fv(locations.view, 1, 0, ffi.new("float[16]", view))
  gl.glUniform3f(locations.center,
    viewPosition[1] + sunDir[1] * distance,
    viewPosition[2] + sunDir[2] * distance,
    viewPosition[3] + sunDir[3] * distance)
  gl.glUniform1f(locations.radius, radius)
  gl.glUniform3f(locations.viewPos, viewPosition[1], viewPosition[2], viewPosition[3])
  gl.glUniform3f(locations.radiance, radiance[1], radiance[2], radiance[3])

  gl.glDisable(GL_DEPTH_TEST)
  gl.glDepthMask(0)
  gl.glEnable(GL_BLEND)
  -- Colour is added on top of the sky and scaled by the cloud transmittance the
  -- sky left in alpha; alpha itself is passed through untouched. Where the
  -- target has no alpha this degrades to a plain additive blend, which is the
  -- sun simply never being hidden rather than anything breaking.
  gl.glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE, GL_ZERO, GL_ONE)
  rendering.draw(sunMesh)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDisable(GL_BLEND)
  gl.glDepthMask(1)
  gl.glEnable(GL_DEPTH_TEST)
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
  local light = world:skyLightSampler(entry.chunkX, entry.chunkY, entry.chunkZ)

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
    blockAt = world:blockSampler(entry.chunkX, entry.chunkY, entry.chunkZ),
    renderOrigin = world.renderOrigin,
    planet = world.planet,
    yieldStep = yieldStep
  }
end

local function createTerrainMesh(entry, world)
  local provisionalLight = not world:lightingReady()
  local vertices, iceVertices, leafVertices = voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetY, entry.offsetZ,
    meshOptions(world, entry, provisionalLight))
  return uploadTerrainChunkMesh(entry, vertices, {
    iceVertices = iceVertices,
    leafVertices = leafVertices,
    provisionalLight = provisionalLight,
    lightRevision = world.lightRevision,
    world = world
  })
end

local function createTerrainMeshes(world)
  local meshes = {}

  world:eachChunk(function(chunk, entry)
    replaceTerrainMesh(meshes, World.chunkKey(entry.chunkX, entry.chunkY, entry.chunkZ), createTerrainMesh(entry, world))
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
  item.meshRevision = entry.meshRevision or 0
  if item.provisionalLight == nil then
    item.provisionalLight = not world:lightingReady()
  end
  local provisionalLight = item.provisionalLight
  item.meshThread = coroutine.create(function()
    item.vertices, item.iceVertices, item.leafVertices = voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetY, entry.offsetZ,
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

  if coroutine.status(item.meshThread) == "dead" and item.vertices ~= nil then
    local entry = meshEntryForItem(item)
    if item.meshRevision ~= (entry.meshRevision or 0) then
      item.vertices = nil
      item.iceVertices = nil
      item.leafVertices = nil
      item.meshThread = nil
      item.provisionalLight = nil
      item.meshRevision = nil
      return false
    end
    return true
  end

  return false
end

local function randomWorldSeed()
  local clock = math.floor(os.clock() * 1000000)
  local seed = (os.time() * 1103515245 + clock * 12345) % 2147483647
  seed = math.floor(seed)
  return seed ~= 0 and seed or 1
end

local function findPlanetSpawnDirection(planet, preferred)
  preferred = math3d.normalize(preferred or {0.0, 0.0, 1.0})
  local first = terrain.surfaceAtDirection(preferred, planet)
  if first.land > 0.50 and first.elevationMeters > planet.seaLevelOffsetMeters + 1.5 then
    return preferred
  end

  -- Deterministic Fibonacci coverage finds the nearest viable land direction
  -- without introducing longitude seams or assuming that +Z happens to be a
  -- continent for every seed.
  local best, bestScore
  local golden = math.pi * (3.0 - math.sqrt(5.0))
  for i = 0, 255 do
    local y = 1.0 - (i + 0.5) * (2.0 / 256.0)
    local radius = math.sqrt(math.max(0.0, 1.0 - y * y))
    local angle = i * golden
    local direction = {math.cos(angle) * radius, y, math.sin(angle) * radius}
    local sample = terrain.surfaceAtDirection(direction, planet)
    if sample.land > 0.50 and sample.elevationMeters > planet.seaLevelOffsetMeters + 1.5 then
      local proximity = math3d.dot(direction, preferred)
      local score = proximity * 100.0 + math.min(sample.elevationMeters, 48.0) * 0.08 - sample.mountain * 4.0
      if not bestScore or score > bestScore then best, bestScore = direction, score end
    end
  end
  return best or preferred
end

local function createWorldLoadingJob(config)
  local seed = tonumber(config.seed) or randomWorldSeed()
  local world = World.new({
    chunkRadius = graphics.world.chunkLoadRadius,
    chunkRadiusVertical = graphics.world.chunkLoadRadiusVertical,
    maxHeight = TERRAIN_MAX_H,
    generatorType = config.generatorType,
    seed = seed,
    planet = graphics.planet,
    deferInitialChunks = true
  })
  local spawnDirection = findPlanetSpawnDirection(world.planet, config.spawnDirection or {0.0, 0.0, 1.0})
  world.spawnDirection = spawnDirection
  world.spawnAltitudeMeters = math.max(0.0, tonumber(config.spawnAltitudeMeters) or 0.0)
  local spawnOffsetVoxels = (graphics.player.eyeHeight or 1.62) + 1.0 + world.spawnAltitudeMeters / world.planet.voxelSizeMeters
  local spawnPosition = world:surfacePosition(spawnDirection, spawnOffsetVoxels)
  world.renderOrigin=world.planet:snappedRenderOrigin(spawnPosition)
  local plan = spawnLoading.createPlan({
    centerChunkX = World.chunkCoord(spawnPosition[1]),
    centerChunkY = World.chunkCoord(spawnPosition[2]),
    centerChunkZ = World.chunkCoord(spawnPosition[3]),
    requiredRadius = math.min(CHUNK_RENDER_RADIUS, LOADING_REQUIRED_RADIUS),
    haloRadius = math.min(CHUNK_RENDER_RADIUS, LOADING_HALO_RADIUS)
  })
  local save = saves.createWorld({
    worldName = config.worldName,
    gameMode = config.gameMode,
    generatorType = config.generatorType,
    seed = seed
  })

  return {
    config = config,
    save = save,
    world = world,
    terrainMeshes = {},
    plan = plan,
    coords = plan.coords,
    spawnPosition = spawnPosition,
    spawnDirection = spawnDirection,
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
      job.chunkJob = job.world:createChunkJob(coord.chunkX, coord.chunkY, coord.chunkZ)
    end

    local ok, err = coroutine.resume(job.chunkJob.thread)
    if not ok then
      error(err)
    end

    if coroutine.status(job.chunkJob.thread) == "dead" then
      local entry = job.chunkJob.entry
      if entry then
        job.generatedChunks = job.generatedChunks + 1
        if spawnLoading.isCenterChunk(job.plan, entry.chunkX, entry.chunkY, entry.chunkZ) then
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
        chunkY = job.centerEntry.chunkY,
        chunkZ = job.centerEntry.chunkZ,
        entry = job.centerEntry
      }
    end

    while meshBudget > 0 and job.spawnMeshItem and not job.spawnMeshComplete do
      local item = job.spawnMeshItem
      if stepTerrainMeshItem(job.world, item) then
        local entry = item.entry
        replaceTerrainMesh(job.terrainMeshes, World.chunkKey(entry.chunkX, entry.chunkY, entry.chunkZ), uploadTerrainChunkMesh(entry, item.vertices, {
          iceVertices = item.iceVertices,
          leafVertices = item.leafVertices,
          provisionalLight = item.provisionalLight,
          lightRevision = job.world.lightRevision,
          world = job.world
        }))
        item.vertices = nil
        item.iceVertices = nil
        item.leafVertices = nil
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
    return item.entry.chunkX, item.entry.chunkY, item.entry.chunkZ
  end
  return item.chunkX, item.chunkY, item.chunkZ
end

-- `urgent` marks work the player is waiting to see. The queue is processed from
-- the front, so without this a remesh caused by placing a block queues behind
-- every pending chunk generation -- up to CHUNK_QUEUE_BACKLOG of them, seconds
-- of work -- and the edit stays invisible until streaming catches up.
local function queueChunkRemesh(pendingEntries, entry, urgent)
  if not entry then
    return
  end

  local key = World.chunkKey(entry.chunkX, entry.chunkY, entry.chunkZ)
  for i = 1, #pendingEntries do
    local chunkX, chunkY, chunkZ = pendingChunkCoords(pendingEntries[i])
    if chunkX and chunkY and chunkZ and World.chunkKey(chunkX, chunkY, chunkZ) == key then
      local item = pendingEntries[i]
      item.entry = item.entry or entry
      item.rebuild = true
      -- A meshing coroutine reads the live chunk over several frames. Once an
      -- edit arrives, continuing it would mix pre/post-edit slices and its
      -- eventual upload would consume this rebuild request. Restart cleanly.
      if item.meshThread then
        item.vertices = nil
        item.iceVertices = nil
        item.leafVertices = nil
        item.meshThread = nil
        item.provisionalLight = nil
        item.meshRevision = nil
      end
      if urgent and i > 1 then
        table.remove(pendingEntries, i)
        table.insert(pendingEntries, 1, item)
      end
      return
    end
  end

  local item = {
    chunkX = entry.chunkX,
    chunkY = entry.chunkY,
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

local function queueTerrainMeshes(world, pendingEntries, x, y, z, budget, priority)
  budget = budget or CHUNK_QUEUE_BUDGET
  priority = priority or {}
  local centerChunkX,centerChunkY,centerChunkZ=World.chunkCoord(x),World.chunkCoord(y),World.chunkCoord(z)
  local predictedChunkX=World.chunkCoord(priority.predictedX or x)
  local predictedChunkY=World.chunkCoord(priority.predictedY or y)
  local predictedChunkZ=World.chunkCoord(priority.predictedZ or z)
  local forwardX,forwardY,forwardZ=priority.forwardX or 0,priority.forwardY or 0,priority.forwardZ or 0
  local coords=world:chunkCoordsAroundBlock(x,y,z,world.chunkRadius)
  local queued = {}

  for i = 1, #pendingEntries do
    local chunkX,chunkY,chunkZ=pendingChunkCoords(pendingEntries[i])
    if chunkX and chunkY and chunkZ then
      queued[World.chunkKey(chunkX,chunkY,chunkZ)] = true
    end
  end

  table.sort(coords, function(a, b)
    local adx,ady,adz=a.chunkX-centerChunkX,a.chunkY-centerChunkY,a.chunkZ-centerChunkZ
    local bdx,bdy,bdz=b.chunkX-centerChunkX,b.chunkY-centerChunkY,b.chunkZ-centerChunkZ
    local apx,apy,apz=a.chunkX-predictedChunkX,a.chunkY-predictedChunkY,a.chunkZ-predictedChunkZ
    local bpx,bpy,bpz=b.chunkX-predictedChunkX,b.chunkY-predictedChunkY,b.chunkZ-predictedChunkZ
    local ad=adx*adx+ady*ady+adz*adz+(apx*apx+apy*apy+apz*apz)*0.65
    local bd=bdx*bdx+bdy*bdy+bdz*bdz+(bpx*bpx+bpy*bpy+bpz*bpz)*0.65
    local al,bl=math.sqrt(adx*adx+ady*ady+adz*adz),math.sqrt(bdx*bdx+bdy*bdy+bdz*bdz)
    if al > 0.0 then
      ad=ad-((adx/al)*forwardX+(ady/al)*forwardY+(adz/al)*forwardZ)*3
    end
    if bl > 0.0 then
      bd=bd-((bdx/bl)*forwardX+(bdy/bl)*forwardY+(bdz/bl)*forwardZ)*3
    end
    if ad==bd then return a.chunkX==b.chunkX and (a.chunkY==b.chunkY and a.chunkZ<b.chunkZ or a.chunkY<b.chunkY) or a.chunkX<b.chunkX end
    return ad < bd
  end)

  local created = 0
  for i = 1, #coords do
    if created >= budget then
      break
    end
    local coord = coords[i]
    local key=World.chunkKey(coord.chunkX,coord.chunkY,coord.chunkZ)
    if not world.chunks[key] and not queued[key] then
      pendingEntries[#pendingEntries + 1] = world:createChunkJob(coord.chunkX,coord.chunkY,coord.chunkZ)
      created=created+1
    end
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
        replaceTerrainMesh(terrainMeshes, World.chunkKey(item.entry.chunkX, item.entry.chunkY, item.entry.chunkZ), uploadTerrainChunkMesh(item.entry, item.vertices, {
          iceVertices = item.iceVertices,
          leafVertices = item.leafVertices,
          provisionalLight = item.provisionalLight,
          lightRevision = world.lightRevision,
          world = world
        }))
        stats.meshUploads = stats.meshUploads + 1
        item.vertices = nil
        item.iceVertices = nil
        item.leafVertices = nil
        item.meshThread = nil
        item.provisionalLight = nil
        table.remove(pendingEntries, 1)
        break
      end
    else
      local entry = table.remove(pendingEntries, 1)
      replaceTerrainMesh(terrainMeshes, World.chunkKey(entry.chunkX, entry.chunkY, entry.chunkZ), createTerrainMesh(entry, world))
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

local function pruneTerrainMeshes(world, terrainMeshes, pendingEntries, x, y, z)
  local centerChunkX,centerChunkY,centerChunkZ=World.chunkCoord(x),World.chunkCoord(y),World.chunkCoord(z)
  -- Eviction has to use the same ellipsoid the streamer fills, with one chunk
  -- of hysteresis. A sphere here would either throw away chunks that were just
  -- generated or hold on to a shell of them that can never be seen.
  local up = world.planet:localUp({x, y, z})
  local keepRadius = world.chunkRadius + 1
  local keepVertical = (world.chunkRadiusVertical or world.chunkRadius) + 1

  if (graphics.world.sphericalVoxels ~= false) then return end
  for key, entry in pairs(world.chunks) do
    local dx,dy,dz=entry.chunkX-centerChunkX,entry.chunkY-centerChunkY,entry.chunkZ-centerChunkZ
    if world:chunkRegionScore(dx,dy,dz,up,keepRadius,keepVertical)>1.0 then
      world.chunks[key] = nil
      releaseTerrainMesh(terrainMeshes[key])
      terrainMeshes[key] = nil
    end
  end

  local i = 1
  while i <= #pendingEntries do
    local entry = pendingEntries[i]
    local chunkX,chunkY,chunkZ=pendingChunkCoords(entry)
    local dx,dy,dz=(chunkX or centerChunkX)-centerChunkX,(chunkY or centerChunkY)-centerChunkY,(chunkZ or centerChunkZ)-centerChunkZ
    if chunkX and chunkY and chunkZ and
        world:chunkRegionScore(dx,dy,dz,up,keepRadius,keepVertical)>1.0 then
      table.remove(pendingEntries, i)
    else
      i = i + 1
    end
  end
end

local function rebuildChunkMesh(world, pendingEntries, chunkX, chunkY, chunkZ, urgent)
  local key = World.chunkKey(chunkX, chunkY, chunkZ)
  local entry = world.chunks[key]
  if entry then
    queueChunkRemesh(pendingEntries, entry, urgent)
  end
end

-- Called when the player places or breaks a block, so everything here is urgent:
-- the block data (and its collision) has already changed and the mesh is the
-- only thing left before the edit becomes visible.
local function rebuildBlockChunkMeshes(world, pendingEntries, x, y, z)
  local localX,localY,localZ,chunkX,chunkY,chunkZ=world:localBlockCoord(x,y,z)
  local minDX = localX == 0 and -1 or 0
  local maxDX = localX == 15 and 1 or 0
  local minDY = localY == 0 and -1 or 0
  local maxDY = localY == 15 and 1 or 0
  local minDZ = localZ == 0 and -1 or 0
  local maxDZ = localZ == 15 and 1 or 0

  -- Boundary faces, their corner AO, and smooth vertex lighting sample the
  -- neighbouring chunk. Include diagonal neighbours for corner edits.
  for dz = minDZ, maxDZ do
    for dy = minDY, maxDY do
      for dx = minDX, maxDX do
        rebuildChunkMesh(world,pendingEntries,chunkX+dx,chunkY+dy,chunkZ+dz,true)
      end
    end
  end

  queueLightTouchedRemeshes(world, pendingEntries, true)
end

local function createCharacterMesh()
  local player = character.createPlayer({8, 6, 8}, {skinPath=graphics.player.skinPath,model=graphics.player.skinModel})
  return uploadMesh(player:createMesh())
end

local function drawSky(skyShader, skyMesh, locations, moonTexture, playerCamera, sunDir, sky, time, cloudsEnabled, skyRotation)
  local forward = playerCamera:getFront()
  local worldUp = playerCamera.getLocalUp and playerCamera:getLocalUp() or {0.0, 1.0, 0.0}
  local absolutePosition = playerCamera.absolutePosition or playerCamera.position
  local observerAltitude = math.max(absolutePosition[2] - 62.0, 1.0)
  if playerCamera.planet then observerAltitude = math.max(playerCamera.planet:altitudeMeters(absolutePosition), 0.0) end
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
  gl.glUniform3f(locations.sunDisc, SKY.sunAngularRadius or 0.012, SKY.sunDiscBrightness or 9.0, 0.0)
  gl.glUniform3f(locations.fogColor, sky.fogColor[1], sky.fogColor[2], sky.fogColor[3])
  gl.glUniform3f(locations.planetUp, worldUp[1], worldUp[2], worldUp[3])
  gl.glUniform1f(locations.observerAltitude, observerAltitude)
  gl.glUniform1f(locations.skyRotation, skyRotation or 0.0)
  gl.glUniform3f(locations.cloudParams, CLOUD_BOTTOM, CLOUD_TOP, cloudsEnabled == false and 0.0 or (graphics.atmosphere.cloudDensity or 1.0))
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

local function visibleTerrainMeshes(terrainMeshes, frustum)
  local visible = {}
  for _, mesh in pairs(terrainMeshes) do
    if mesh and (not mesh.bounds or math3d.aabbInFrustum(frustum, mesh.bounds)) then
      visible[#visible + 1] = mesh
    end
  end
  return visible
end

local function visibleIceMeshes(visibleTerrain)
  local visible = {}
  for i = 1, #visibleTerrain do
    local iceMesh = visibleTerrain[i].iceMesh
    if iceMesh and iceMesh.count > 0 then
      visible[#visible + 1] = iceMesh
    end
  end
  return visible
end

local function visibleLeafMeshes(visibleTerrain, cameraPosition)
  local visible = {}
  for i = 1, #visibleTerrain do
    local leafMesh = visibleTerrain[i].leafMesh
    if leafMesh and leafMesh.count > 0 then
      visible[#visible + 1] = leafMesh
    end
  end
  -- Standard alpha compositing needs far surfaces first. Chunk sorting is
  -- coarse, but leaf blocks within a chunk use the same material and dense
  -- crowns hide the small residual ordering error.
  table.sort(visible, function(a, b)
    local ac=a.renderCenter or {0,0,0} local bc=b.renderCenter or {0,0,0}
    local ax,ay,az=ac[1]-cameraPosition[1],ac[2]-cameraPosition[2],ac[3]-cameraPosition[3]
    local bx,by,bz=bc[1]-cameraPosition[1],bc[2]-cameraPosition[2],bc[3]-cameraPosition[3]
    return ax*ax+ay*ay+az*az > bx*bx+by*by+bz*bz
  end)
  return visible
end

local function visibleWaterMeshes(visibleTerrain, farWaterMeshes, terrainMeshes, frustum)
  local visible = {}
  for i = 1, #visibleTerrain do
    local waterMesh = visibleTerrain[i].waterMesh
    if waterMesh and waterMesh.count > 0 then
      visible[#visible + 1] = waterMesh
    end
  end
  for key, waterMesh in pairs(farWaterMeshes or {}) do
    if waterMesh and not terrainMeshes[key] and
        (not waterMesh.bounds or math3d.aabbInFrustum(frustum, waterMesh.bounds)) then
      visible[#visible + 1] = waterMesh
    end
  end
  return visible
end

local function releaseFarWaterMeshes(farWaterMeshes, state)
  for key, mesh in pairs(farWaterMeshes) do
    if mesh then rendering.release(mesh) end
    farWaterMeshes[key] = nil
  end
  state.centerChunkX = nil
  state.centerChunkZ = nil
  state.queue = {}
  state.queueIndex = 1
end

local function refreshFarWaterQueue(farWaterMeshes, state, terrainMeshes, centerChunkX, centerChunkZ, innerRadius)
  local keepRadius = FAR_WATER_CHUNK_RADIUS + 2
  for key, mesh in pairs(farWaterMeshes) do
    local chunkX, chunkZ
    if mesh then
      chunkX, chunkZ = mesh.chunkX, mesh.chunkZ
    else
      chunkX, chunkZ = key:match("^(-?%d+),(-?%d+)$")
      chunkX, chunkZ = tonumber(chunkX), tonumber(chunkZ)
    end
    if not chunkX or math.abs(chunkX - centerChunkX) > keepRadius or
        math.abs(chunkZ - centerChunkZ) > keepRadius then
      if mesh then rendering.release(mesh) end
      farWaterMeshes[key] = nil
    end
  end

  local queue = {}
  for dz = -FAR_WATER_CHUNK_RADIUS, FAR_WATER_CHUNK_RADIUS do
    for dx = -FAR_WATER_CHUNK_RADIUS, FAR_WATER_CHUNK_RADIUS do
      local distance = math.max(math.abs(dx), math.abs(dz))
      if distance > innerRadius then
        local chunkX = centerChunkX + dx
        local chunkZ = centerChunkZ + dz
        local key = World.chunkKey(chunkX, chunkZ)
        if farWaterMeshes[key] == nil and not terrainMeshes[key] then
          queue[#queue + 1] = {
            chunkX = chunkX,
            chunkZ = chunkZ,
            distanceSquared = dx * dx + dz * dz
          }
        end
      end
    end
  end
  table.sort(queue, function(a, b) return a.distanceSquared < b.distanceSquared end)
  state.queue = queue
  state.queueIndex = 1
  state.centerChunkX = centerChunkX
  state.centerChunkZ = centerChunkZ
end

local function updateFarWaterMeshes(farWaterMeshes, state, terrainMeshes, world, x, z)
  local centerChunkX = World.chunkCoord(x)
  local centerChunkZ = World.chunkCoord(z)
  if centerChunkX ~= state.centerChunkX or centerChunkZ ~= state.centerChunkZ then
    refreshFarWaterQueue(
      farWaterMeshes, state, terrainMeshes, centerChunkX, centerChunkZ, world.chunkRadius
    )
  end

  local built = 0
  local deadline = glfw.glfwGetTime() + FAR_WATER_FRAME_BUDGET
  while built < FAR_WATER_BUILD_BUDGET and state.queueIndex <= #state.queue and
      (built == 0 or glfw.glfwGetTime() < deadline) do
    local coord = state.queue[state.queueIndex]
    state.queueIndex = state.queueIndex + 1
    local key = World.chunkKey(coord.chunkX, coord.chunkZ)
    if farWaterMeshes[key] == nil and not terrainMeshes[key] then
      local offsetX = coord.chunkX * 16
      local offsetZ = coord.chunkZ * 16
      local vertices = effects.waterTileVertices(
        offsetX, offsetZ, 16.0, FAR_WATER_COVERAGE_SUBDIVISIONS,
        function(sampleX, sampleZ)
          if terrain.biomeAt(sampleX, sampleZ) ~= "ocean" then return false end
          return terrain.heightAt(sampleX, sampleZ, TERRAIN_MAX_H, true) < WATER_LEVEL
        end,
        FAR_WATER_TILE_SUBDIVISIONS,
        createWaterWaveSampler(),
        WATER_LEVEL
      )
      if #vertices > 0 then
        local mesh = uploadMesh(vertices)
        mesh.chunkX = coord.chunkX
        mesh.chunkZ = coord.chunkZ
        mesh.bounds = {
          minX = offsetX,
          minY = WATER_LEVEL - 5.0,
          minZ = offsetZ,
          maxX = offsetX + 16.0,
          maxY = WATER_LEVEL + 5.0,
          maxZ = offsetZ + 16.0
        }
        farWaterMeshes[key] = mesh
      else
        -- false is a cached dry/non-ocean tile; nil means it has not been built.
        farWaterMeshes[key] = false
      end
      built = built + 1
    end
  end
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
        + (mesh.leafMesh and mesh.leafMesh.count or 0)
        + (mesh.iceMesh and mesh.iceMesh.count or 0)
      if mesh.provisionalLight then
        stats.provisional = stats.provisional + 1
      end
    end
  end

  for i = 1, #visibleMeshes do
    local mesh=visibleMeshes[i]
    stats.visibleVertices = stats.visibleVertices + (mesh.count or 0)
      + (mesh.leafMesh and mesh.leafMesh.count or 0)
      + (mesh.iceMesh and mesh.iceMesh.count or 0)
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

local function buildDebugInfo(world, terrainMeshes, visibleMeshes, pendingEntries, playerCamera, state, currentTime, queueStats, sky, sunDir, gridWorld)
  queueStats = queueStats or {}
  sky = sky or {}
  sunDir = sunDir or {0.0, 1.0, 0.0}
  local pos = playerCamera.position
  local localUp=world.planet:localUp(pos)
  local localDown={-localUp[1],-localUp[2],-localUp[3]}
  local eyeHeight=playerCamera.eyeHeight or 1.62
  local feet={pos[1]-localUp[1]*eyeHeight,pos[2]-localUp[2]*eyeHeight,pos[3]-localUp[3]*eyeHeight}
  local blockX,blockY,blockZ=math.floor(feet[1]),math.floor(feet[2]),math.floor(feet[3])
  local eyeBlockX,eyeBlockY,eyeBlockZ=math.floor(pos[1]),math.floor(pos[2]),math.floor(pos[3])
  local chunkX = World.chunkCoord(blockX)
  local chunkY = World.chunkCoord(blockY)
  local chunkZ = World.chunkCoord(blockZ)
  local localX = blockX - chunkX * 16
  local localY = blockY - chunkY * 16
  local localZ = blockZ - chunkZ * 16
  local biomeName=terrain.biomeAtPosition(feet[1],feet[2],feet[3],world.planet)
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
  local ux,uy,uz=world.planet:dominantUpStep(feet)
  local standingOn=world:blockAt(blockX-ux,blockY-uy,blockZ-uz)
  local insideBlock=world:blockAt(eyeBlockX,eyeBlockY,eyeBlockZ)
  local playerRadius=world.planet:distanceVoxels(pos)*world.planet.voxelSizeMeters
  local altitude=world.planet:altitudeMeters(pos)
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
    string.format("XYZ: %s / %s / %s",formatNumber(feet[1],3),formatNumber(feet[2],3),formatNumber(feet[3],3)),
    string.format("Eye: %s / %s / %s", formatNumber(pos[1], 3), formatNumber(pos[2], 3), formatNumber(pos[3], 3)),
    string.format("Block: %d %d %d", blockX, blockY, blockZ),
    string.format("Chunk: %d %d %d in %d %d %d",chunkX,chunkY,chunkZ,localX,localY,localZ),
    -- Which voxel topology is actually underfoot. Without this the two are
    -- indistinguishable in game, and the only clue is a line printed to the
    -- console at load.
    gridWorld
      and string.format("Voxels: spherical grid, %d chunks loaded", gridWorld:chunkCount())
      or "Voxels: Cartesian lattice",
    string.format("Planet radius: %.0f m",world.planet.radiusMeters),
    string.format("Player radius: %.3f m",playerRadius),
    string.format("Radial altitude: %.3f m",altitude),
    string.format("Local up: %.4f / %.4f / %.4f",localUp[1],localUp[2],localUp[3]),
    string.format("Gravity: %.4f / %.4f / %.4f",localDown[1]*world.planet.gravityAcceleration,localDown[2]*world.planet.gravityAcceleration,localDown[3]*world.planet.gravityAcceleration),
    string.format("Facing: %s (yaw %s / pitch %s)", cameraFacingName(playerCamera.yaw), formatNumber(playerCamera.yaw, 1), formatNumber(playerCamera.pitch, 1)),
    string.format("Biome: minecraft:%s", tostring(biomeName or "unknown")),
    string.format("Light: sky %d, daylight %s, moon %s",world:skyLightAt(eyeBlockX,eyeBlockY,eyeBlockZ),formatNumber(sky.daylight or 0,2),formatNumber(sky.moonAmount or 0,2)),
    string.format("Standing on: %s", blockDebugName(standingOn)),
    string.format("Inside: %s", blockDebugName(insideBlock)),
    targetLine
  }

  local rightLines = {
    string.format("Display: %dx%d", windowWidth, windowHeight),
    string.format("Mem: %s", formatNumber(memMb, 1) .. " MB"),
    string.format("World seed: %s", tostring(world.seed or "?")),
    string.format("Sea radius: %.0f m",world.planet.seaLevelRadiusVoxels*world.planet.voxelSizeMeters),
    string.format("Voxel size: %.3f m",world.planet.voxelSizeMeters),
    string.format("Render origin: %.0f / %.0f / %.0f",world.renderOrigin[1],world.renderOrigin[2],world.renderOrigin[3]),
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
    string.format("Planet visual LOD: %s",world.visualLod:levelForPosition(pos)),
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
    placeWasDown = false,
    pickWasDown = false,
    menuClickWasDown = false,
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
    screen = game.autoStartWorld and "loading" or "main",
    cursorMode = nil,
    menuMouseX = -1,
    menuMouseY = -1,
    worldGameMode = "survival",
    worldGeneratorType = "default",
    hasWorld = false,
    menuParentScreen = nil,
    musicVolume = 100,
    soundVolume = 100,
    invertMouse = false,
    sensitivity = 100,
    fovDegrees = graphics.window.fovDegrees or 70,
    difficulty = "Normal",
    graphicsMode = "Fancy",
    renderDistance = CHUNK_RENDER_RADIUS,
    smoothLighting = true,
    vsync = VSYNC_ENABLED,
    anaglyph = false,
    viewBobbing = true,
    guiScale = 0,
    brightness = 100,
    clouds = true,
    bloom = POST.bloom ~= false,
    particles = "All",
    controlBindings = {
      attack = "MOUSE1", use = "MOUSE2", pick = "MOUSE3",
      forward = "W", back = "S", left = "A", right = "D",
      jump = "SPACE", sneak = "CTRL", inventory = "E", drop = "Q"
    },
    stats = {blocksMined = 0, blocksPlaced = 0, distance = 0.0, playTime = 0.0},
    seedKeyWasDown = {},
    currentWorldSave = nil,
    -- game.autoStartWorld skips the menus and drops straight into a generated
    -- world. Nothing but a headless smoke run should set it: it exists so a
    -- 30 second launch exercises world generation, meshing, the sky and the
    -- sun pass instead of stopping at the title screen.
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
    inventory = Inventory.new("survival"),
    inventoryVersion = 1,
    creativeTab = "building",
    health = 20,
    hunger = 20,
    saturation = 5,
    exhaustion = 0,
    armor = 0,
    handSwing = 0,
    tutorialTime = 0,
    windowX = 100,
    windowY = 100,
    windowW = WINDOW_W,
    windowH = WINDOW_H
  }
end

local function playerOptionsForGameMode(gameMode, state)
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

  if state then
    options.mouseSensitivity = (graphics.player.mouseSensitivity or 0.085) * (state.sensitivity or 100) / 100
    options.invertMouse = state.invertMouse == true
    options.controlBindings = state.controlBindings
  end

  return options
end


-- Frame capture for the headless smoke run. A rendering change cannot honestly
-- be called an improvement without looking at it, and the game window is not
-- reachable from a script, so the back buffer is written out as a binary PPM
-- just before it would be swapped. PPM because it needs no encoder: a nine
-- byte header and rows of RGB.
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

local function applyMenuRuntimeState(window, state, playerCamera, world)
  CAMERA_FOV = math.rad(state.fovDegrees or graphics.window.fovDegrees or 70)
  CHUNK_RENDER_RADIUS = state.renderDistance or graphics.world.chunkRenderRadius or 8
  VSYNC_ENABLED = state.vsync ~= false
  glfw.glfwSwapInterval(VSYNC_ENABLED and 1 or 0)
  hud.setGuiScale(state.guiScale)
  POST.exposure = BASE_POST_EXPOSURE * (state.brightness or 100) / 100
  POST.anaglyph = state.anaglyph == true

  if world then
    world.chunkRadius = graphics.world.chunkLoadRadius
    world.chunkRadiusVertical = graphics.world.chunkLoadRadiusVertical
  end
  if playerCamera then
    playerCamera.mouseSensitivity = (graphics.player.mouseSensitivity or 0.085) * (state.sensitivity or 100) / 100
    playerCamera.invertMouse = state.invertMouse == true
    playerCamera.controlBindings = state.controlBindings or playerCamera.controlBindings
  end
end

local function handleUiCommand(window, command, playerCamera, state, world, locP)
  if command == "quit_game" then
    glfw.glfwSetWindowShouldClose(window, 1)
  elseif command == "toggle_fullscreen" then
    setFullscreen(window, state, not state.fullscreen, locP)
  elseif command == "started_world" or command == "resume" then
    if playerCamera then
      playerCamera.firstMouse = true
    end
  end
end

local function updateSeedTextInput(window, state)
  if state.screen ~= "create_world" or not state.moreWorldOptions then
    state.seedKeyWasDown = {}
    return
  end

  local previous = state.seedKeyWasDown or {}
  local current = {}
  local text = state.worldSeedText or ""
  for digit = 0, 9 do
    local key = 48 + digit
    local down = glfw.glfwGetKey(window, key) == glfw.GLFW_PRESS
    current[key] = down
    if down and not previous[key] and #text < 19 then
      text = text .. tostring(digit)
    end
  end

  local minusDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_MINUS) == glfw.GLFW_PRESS
  current.minus = minusDown
  if minusDown and not previous.minus and text == "" then text = "-" end

  local backspaceDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_BACKSPACE) == glfw.GLFW_PRESS
  current.backspace = backspaceDown
  if backspaceDown and not previous.backspace then text = text:sub(1, -2) end

  state.worldSeedText = text
  state.seedKeyWasDown = current
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
    uiFlow.back(state)
    if (wasScreen=="inventory" or wasScreen=="creative_inventory") and not state.screen and state.inventory.cursor then
      state.inventory:add(state.inventory.cursor.item,state.inventory.cursor.count)
      state.inventory.cursor=nil
      state.inventoryVersion=state.inventoryVersion+1
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
  local tab = state.creativeTab or "building"
  local filtered = {}
  for _, item in ipairs(Inventory.catalog()) do
    local definition = blocks.mapping[item]
    local label = ((definition and definition.name) or item):lower()
    local properties = definition and definition.properties or {}
    local categoryMatch = false
    if tab == "search" then
      categoryMatch = true
    elseif tab == "nature" then
      categoryMatch = properties.leaves or properties.cutout or item == "grass" or item == "dirt" or
        item == "sand" or item == "red_sand" or item == "clay" or item == "snow" or
        item == "ice" or item == "packed_ice"
    elseif tab == "materials" then
      categoryMatch = item:find("_ore",1,true) ~= nil or item:find("_log",1,true) ~= nil or
        item == "clay" or item == "gravel" or item == "sand"
    elseif tab == "redstone" then
      categoryMatch = item:find("redstone",1,true) ~= nil or item == "crafting_table"
    else
      categoryMatch = properties.solid and not properties.leaves and not properties.cutout
    end
    local searchMatch = tab ~= "search" or query == "" or item:find(query, 1, true) or label:find(query, 1, true)
    if categoryMatch and searchMatch then
      filtered[#filtered + 1] = item
    end
  end
  state.creativeFiltered = filtered
end

local function closeInventory(state, playerCamera)
  if state.inventory.cursor then
    -- Creative catalog stacks are virtual. Closing the menu discards the
    -- cursor copy instead of duplicating it into the survival inventory.
    if state.screen ~= "creative_inventory" then
      state.inventory:add(state.inventory.cursor.item, state.inventory.cursor.count)
    end
    state.inventory.cursor = nil
  end
  state.screen = nil
  state.inventoryVersion = state.inventoryVersion + 1
  if playerCamera then playerCamera.firstMouse = true end
end

local function updateInventoryInput(window, state, playerCamera)
  if not state.hasWorld or state.devMenuOpen then return end
  local inventoryDown = playerCamera:controlDown(window, "inventory", "E")
  if inventoryDown and not state.inventoryWasDown then
    if state.screen == "inventory" or state.screen == "creative_inventory" then
      closeInventory(state, playerCamera)
    elseif not state.screen then
      state.screen = state.worldGameMode == "creative" and "creative_inventory" or "inventory"
      refreshCreativeFilter(state)
    end
  end
  state.inventoryWasDown = inventoryDown

  if state.screen ~= "inventory" and state.screen ~= "creative_inventory" then return end
  local xpos,ypos=ffi.new("double[1]"),ffi.new("double[1]")
  local clientWidth,clientHeight=ffi.new("int[1]"),ffi.new("int[1]")
  glfw.glfwGetCursorPos(window,xpos,ypos)
  glfw.glfwGetWindowSize(window,clientWidth,clientHeight)
  state.menuMouseX=tonumber(xpos[0])*windowWidth/math.max(1,tonumber(clientWidth[0]))
  state.menuMouseY=tonumber(ypos[0])*windowHeight/math.max(1,tonumber(clientHeight[0]))

  if state.screen == "creative_inventory" and state.creativeTab == "search" then
    state.inventoryTextWasDown = state.inventoryTextWasDown or {}
    local current = {}
    for code=65,90 do
      local down=glfw.glfwGetKey(window,code)==glfw.GLFW_PRESS
      current[code]=down
      if down and not state.inventoryTextWasDown[code] and #(state.inventory.search or "")<24 then
        state.inventory.search=(state.inventory.search or "")..string.char(code+32)
        refreshCreativeFilter(state)
      end
    end
    local back=glfw.glfwGetKey(window,glfw.GLFW_KEY_BACKSPACE)==glfw.GLFW_PRESS
    current.back=back
    if back and not state.inventoryTextWasDown.back then
      state.inventory.search=(state.inventory.search or ""):sub(1,-2)
      refreshCreativeFilter(state)
    end
    state.inventoryTextWasDown=current
  end

  local click=glfw.glfwGetMouseButton(window,glfw.GLFW_MOUSE_BUTTON_LEFT)==glfw.GLFW_PRESS
  if click and not state.inventoryClickWasDown then
    local target=hud.inventorySlotAt(state.screen,windowWidth,windowHeight,state.menuMouseX,state.menuMouseY,state)
    if target then
      if target.kind=="slot" then state.inventory:swapOrMerge(target.index)
      elseif target.kind=="craft" then state.inventory:swapCraft(target.index)
      elseif target.kind=="result" then state.inventory:takeCraftResult()
      elseif target.kind=="creative_tab" then
        state.creativeTab=target.tab
        refreshCreativeFilter(state)
      elseif target.kind=="creative" and target.item then
        -- Match the native creative workflow: selecting a catalog entry picks
        -- up a full stack, which can then be placed into any hotbar slot.
        state.inventory.cursor={item=target.item,count=64}
      end
      state.inventoryVersion=state.inventoryVersion+1
    end
  end
  state.inventoryClickWasDown=click
end

local function updateMenuInput(window, state, playerCamera, world, locP)
  if state.devMenuOpen then
    state.menuClickWasDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
    return
  end
  if not state.screen then
    state.menuClickWasDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS
    return
  end
  if state.screen == "inventory" or state.screen == "creative_inventory" then return end

  updateSeedTextInput(window, state)

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
    local command = uiFlow.applyAction(state, action)
    applyMenuRuntimeState(window, state, playerCamera, world)
    handleUiCommand(window, command, playerCamera, state, world, locP)
  end

  state.menuClickWasDown = clickDown
end

local function updateBlockEditInput(window, state, world, pendingEntries, playerCamera, dt)
  local breakDown = playerCamera:controlDown(window, "attack", "MOUSE1")
  local placeDown = playerCamera:controlDown(window, "use", "MOUSE2")
  local pickDown = playerCamera:controlDown(window, "pick", "MOUSE3")

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
      state.inventory.selected = i
    end
  end

  if breakDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    if hit then
      local hitDefinition = blocks.list[hit.id]
      local key=hit.x..","..hit.y..","..hit.z
      if state.breakTarget~=key then state.breakTarget=key state.breakProgress=0 end
      local name=hitDefinition and hitDefinition.key or ""
      local breakTime=0.35
      if name:find("stone") or name:find("ore") or name=="cobblestone" then breakTime=0.95
      elseif name:find("log") or name:find("planks") or name=="crafting_table" then breakTime=0.58
      elseif name:find("leaves") or name:find("grass") then breakTime=0.16 end
      state.breakProgress=(state.breakProgress or 0)+(dt or 0)
      local ready=state.worldGameMode=="creative" and not state.breakWasDown or state.breakProgress>=breakTime
      if ready then
        local changed = worldInteraction.breakBlock(world, hit.x, hit.y, hit.z)
        rebuildBlockChunkMeshes(world,pendingEntries,hit.x,hit.y,hit.z)
        if #changed > 0 then
          state.stats.blocksMined = state.stats.blocksMined + 1
          if state.worldGameMode ~= "creative" and hitDefinition and hitDefinition.key then
            local properties = hitDefinition.properties or {}
            state.inventory:add(properties.drop or hitDefinition.key, 1)
            state.inventoryVersion = state.inventoryVersion + 1
          end
        end
        state.breakProgress,state.breakTarget=0,nil
      end
      if state.handSwing==0 then state.handSwing=0.01 end
    end
  else
    state.breakProgress,state.breakTarget=0,nil
  end

  if placeDown and not state.placeWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    local stack = state.inventory.slots[state.selectedSlot]
    local blockId = state.inventory:blockIdFor(stack)
    local target = worldInteraction.placeFromHit(world, hit, blockId)
    if target then
      rebuildBlockChunkMeshes(world,pendingEntries,target.x,target.y,target.z)
      state.stats.blocksPlaced = state.stats.blocksPlaced + 1
      state.inventory:consumeSelected(1)
      state.inventoryVersion = state.inventoryVersion + 1
      state.handSwing = 0.01
    end
  end

  if pickDown and not state.pickWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), playerCamera.reach or graphics.player.reach or 6.0)
    if hit then
      local definition = blocks.list[hit.id]
      local found = definition and state.inventory:pickBlock(definition.key)
      if found and found <= 9 then state.selectedSlot = found end
      state.inventoryVersion = state.inventoryVersion + 1
    end
  end

  local dropDown = playerCamera:controlDown(window, "drop", "Q")
  if dropDown and not state.dropWasDown then
    if state.inventory:removeAt(state.selectedSlot, 1) then
      state.inventoryVersion = state.inventoryVersion + 1
      state.handSwing = 0.01
    end
  end

  state.breakWasDown = breakDown
  state.placeWasDown = placeDown
  state.pickWasDown = pickDown
  state.dropWasDown = dropDown
end

local function updateSurvival(state, playerCamera, world, dt, travelled, landedVelocity)
  if state.worldGameMode == "creative" then
    state.health, state.hunger = 20, 20
    return
  end
  state.exhaustion = (state.exhaustion or 0) + (travelled or 0) * 0.12
  while state.exhaustion >= 4 do
    state.exhaustion = state.exhaustion - 4
    if state.saturation > 0 then state.saturation = math.max(0,state.saturation-1)
    else state.hunger = math.max(0,state.hunger-1) end
  end
  if landedVelocity and landedVelocity < -11 then
    state.health = math.max(0,state.health-math.max(1,math.floor((-landedVelocity-10)*0.8)))
  end
  state.survivalTimer = (state.survivalTimer or 0) + dt
  if state.hunger >= 18 and state.health < 20 and state.survivalTimer >= 4 then
    state.health = math.min(20,state.health+1) state.exhaustion=state.exhaustion+1 state.survivalTimer=0
  elseif state.hunger <= 0 and state.survivalTimer >= 4 and state.difficulty ~= "Peaceful" then
    state.health = math.max(0,state.health-1) state.survivalTimer=0
  elseif state.difficulty == "Peaceful" then
    state.hunger=20
    if state.survivalTimer>=1 and state.health<20 then state.health=math.min(20,state.health+1) state.survivalTimer=0 end
  end
  if state.health <= 0 then
    playerCamera:placeAtSpawn(world,playerCamera.position[1],playerCamera.position[3])
    state.health,state.hunger,state.saturation,state.exhaustion=20,20,5,0
  end
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
    updateRuntimeAtmosphereSettings(runtimeAtmosphereSettings, 1.0)
    updateRuntimeAtmosphereSettings(previewAtmosphereSettings, 0.0)

    local atlasTex = createTextureAtlas()
    local moonTexture = createImageTexture("assets/textures/environment/moon_phases.png", true)
    local underwaterOverlayTexture = createImageTexture("assets/textures/blocks/water_overlay.png", false, true)
    local world = World.new({
      chunkRadius = graphics.world.chunkLoadRadius,
      chunkRadiusVertical = graphics.world.chunkLoadRadiusVertical,
      maxHeight = TERRAIN_MAX_H,
      generatorType = "default",
      seed = graphics.terrainGeneration.seed or 1,
      planet = graphics.planet,
      deferInitialChunks = true
    })
    local terrainMeshes = {}
    local farWaterMeshes = {}
    local farWaterState = {queue = {}, queueIndex = 1}
    local currentWaterLevel = nil
    local characterMesh = graphics.player.showDebugBody and createCharacterMesh() or nil
    local characterSkinTexture = characterMesh and createImageTexture(graphics.player.skinPath or character.DEFAULT_SKIN, true) or nil
    local skyMesh = uploadSkyMesh()
    local sunMesh = sunPass.uploadMesh()
    local smokeFrames, smokeElapsed, smokeTotal = 0, 0.0, 0.0
    local gridWorld, gridRuntime = nil, nil
    if game.openDevMenu then devMenu:openNavigation() end
    local cloudMesh = createCloudMesh("assets/textures/environment/clouds.png")
    local orbitalPlanetMesh = nil
    local orbitalCloudMesh = nil
    local shadowMap = effects.createShadowMap(SHADOW_MAP_SIZE)
    local sceneTarget = effects.createSceneTarget(windowWidth, windowHeight)
    local waterBackgroundTarget = effects.createSceneTarget(windowWidth, windowHeight)
    local volumetricFog = effects.createVolumetricFog(FOG_GRID_WIDTH, FOG_GRID_HEIGHT, FOG_GRID_DEPTH)
    local ocean = effects.createOceanSimulation(graphics.water)

    local shader = createShaderProgram()
    local shadowShader = effects.createShadowShader()
    local iceShader = effects.createIceShader()
    local skyShader = createSkyShaderProgram()
    local sunShader = sunPass.createShader()
    local cloudShader = createCloudShaderProgram()
    local orbitalPlanetShader = createOrbitalPlanetShader()
    local orbitalCloudShader = createOrbitalCloudShader()
    local waterShader = effects.createWaterShader()
    local planetWaterShader=createPlanetWaterShader()
    local atmospherePostShader = effects.createAtmospherePostShader()
    local volumetricFogShaders = effects.createVolumetricFogShaders(FOG_GRID_WIDTH, FOG_GRID_HEIGHT, FOG_GRID_DEPTH)
    local worldgenPreviewShader = createWorldgenPreviewShader()
    local hudOverlay = hud.create(graphics.player.skinPath)
    gl.glUseProgram(shader)

    local locP = gl.glGetUniformLocation(shader, "uProjection")
    local locV = gl.glGetUniformLocation(shader, "uView")
    local locM = gl.glGetUniformLocation(shader, "uModel")
    local locLight = gl.glGetUniformLocation(shader, "lightDir")
    local locViewPos = gl.glGetUniformLocation(shader, "viewPos")
    local locTex = gl.glGetUniformLocation(shader, "tex0")
    local locTime = gl.glGetUniformLocation(shader, "time")
    local locFoliageParams = gl.glGetUniformLocation(shader, "foliageParams")
    local locPlanetUp=gl.glGetUniformLocation(shader,"planetUp")

    local locShadowMap = gl.glGetUniformLocation(shader, "shadowMap")
    local locAmbientColor = gl.glGetUniformLocation(shader, "ambientColor")
    local locLightColor = gl.glGetUniformLocation(shader, "lightColor")
    local locMoonLightColor = gl.glGetUniformLocation(shader, "moonLightColor")
    local locLightingParams = gl.glGetUniformLocation(shader, "lightingParams")
    local locFaceLight = gl.glGetUniformLocation(shader, "faceLight")
    local locExposure = gl.glGetUniformLocation(shader, "exposure")
    local locShadowStrength = gl.glGetUniformLocation(shader, "shadowStrength")
    local locUseVoxelLight = gl.glGetUniformLocation(shader, "useVoxelLight")
    local locSmoothLighting = gl.glGetUniformLocation(shader, "smoothLighting")
    local locLightSpaceMatrix = gl.glGetUniformLocation(shader, "lightSpaceMatrix")
    local locTerrainWaterLevel = gl.glGetUniformLocation(shader, "waterLevel")
    local locTerrainWaterNormalMap = gl.glGetUniformLocation(shader, "waterNormalMap")
    local locTerrainWaterCascadeSizes = gl.glGetUniformLocation(shader, "waterCascadeSizes")
    local locTerrainWaterNormalWeights = gl.glGetUniformLocation(shader, "waterNormalWeights")
    local locTerrainCausticStrength = gl.glGetUniformLocation(shader, "causticStrength")
    local shadowLocations = {
      model = gl.glGetUniformLocation(shadowShader, "uModel"),
      lightSpaceMatrix = gl.glGetUniformLocation(shadowShader, "lightSpaceMatrix"),
      tex0 = gl.glGetUniformLocation(shadowShader, "tex0"),
      viewPos = gl.glGetUniformLocation(shadowShader, "viewPos"),
      time = gl.glGetUniformLocation(shadowShader, "time"),
      foliageParams = gl.glGetUniformLocation(shadowShader, "foliageParams")
    }
    local iceLocations = {
      projection = gl.glGetUniformLocation(iceShader, "uProjection"),
      view = gl.glGetUniformLocation(iceShader, "uView"),
      model = gl.glGetUniformLocation(iceShader, "uModel"),
      viewPos = gl.glGetUniformLocation(iceShader, "viewPos"),
      sunDir = gl.glGetUniformLocation(iceShader, "sunDir"),
      fogColor = gl.glGetUniformLocation(iceShader, "fogColor"),
      skyZenithColor = gl.glGetUniformLocation(iceShader, "skyZenithColor"),
      lightColor = gl.glGetUniformLocation(iceShader, "lightColor"),
      viewportSize = gl.glGetUniformLocation(iceShader, "viewportSize"),
      clipPlanes = gl.glGetUniformLocation(iceShader, "clipPlanes"),
      absorption = gl.glGetUniformLocation(iceShader, "absorption"),
      iceParams = gl.glGetUniformLocation(iceShader, "iceParams"),
      tex0 = gl.glGetUniformLocation(iceShader, "tex0"),
      sceneColor = gl.glGetUniformLocation(iceShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(iceShader, "sceneDepth")
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
      planetUp = gl.glGetUniformLocation(skyShader, "planetUp"),
      observerAltitude = gl.glGetUniformLocation(skyShader, "observerAltitude"),
      cloudParams = gl.glGetUniformLocation(skyShader, "cloudParams"),
      skyRotation = gl.glGetUniformLocation(skyShader, "skyRotation")
    }
    local sunLocations = {
      projection = gl.glGetUniformLocation(sunShader, "uProjection"),
      view = gl.glGetUniformLocation(sunShader, "uView"),
      center = gl.glGetUniformLocation(sunShader, "sunCenter"),
      radius = gl.glGetUniformLocation(sunShader, "sunRadius"),
      viewPos = gl.glGetUniformLocation(sunShader, "viewPos"),
      radiance = gl.glGetUniformLocation(sunShader, "sunRadiance")
    }
    local cloudLocations = {
      projection = gl.glGetUniformLocation(cloudShader, "uProjection"),
      view = gl.glGetUniformLocation(cloudShader, "uView"),
      offset = gl.glGetUniformLocation(cloudShader, "cloudOffset"),
      alpha = gl.glGetUniformLocation(cloudShader, "cloudAlpha"),
      tint = gl.glGetUniformLocation(cloudShader, "cloudTint")
    }
    local orbitalPlanetLocations = {
      projection = gl.glGetUniformLocation(orbitalPlanetShader, "uProjection"),
      view = gl.glGetUniformLocation(orbitalPlanetShader, "uView"),
      offset = gl.glGetUniformLocation(orbitalPlanetShader, "planetOffset"),
      sunDir = gl.glGetUniformLocation(orbitalPlanetShader, "sunDir"),
      viewPos = gl.glGetUniformLocation(orbitalPlanetShader, "viewPos")
    }
    local orbitalCloudLocations = {
      projection = gl.glGetUniformLocation(orbitalCloudShader, "uProjection"),
      view = gl.glGetUniformLocation(orbitalCloudShader, "uView"),
      offset = gl.glGetUniformLocation(orbitalCloudShader, "planetOffset"),
      sunDir = gl.glGetUniformLocation(orbitalCloudShader, "sunDir"),
      viewPos = gl.glGetUniformLocation(orbitalCloudShader, "viewPos"),
      time = gl.glGetUniformLocation(orbitalCloudShader, "time")
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
      breakerParams = gl.glGetUniformLocation(waterShader, "breakerParams"),
      viewportSize = gl.glGetUniformLocation(waterShader, "viewportSize"),
      clipPlanes = gl.glGetUniformLocation(waterShader, "clipPlanes"),
      time = gl.glGetUniformLocation(waterShader, "time"),
      refractionStrength = gl.glGetUniformLocation(waterShader, "refractionStrength"),
      snellParams = gl.glGetUniformLocation(waterShader, "snellParams"),
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
    local planetWaterLocations={
      projection=gl.glGetUniformLocation(planetWaterShader,"uProjection"),
      view=gl.glGetUniformLocation(planetWaterShader,"uView"),
      viewPos=gl.glGetUniformLocation(planetWaterShader,"viewPos"),
      sunDir=gl.glGetUniformLocation(planetWaterShader,"sunDir"),
      waterColor=gl.glGetUniformLocation(planetWaterShader,"waterColor")
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
      tonemapParams = gl.glGetUniformLocation(atmospherePostShader, "tonemapParams"),
      anaglyphAmount = gl.glGetUniformLocation(atmospherePostShader, "anaglyphAmount")
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

    local displayState = createDisplayState()
    local playerCamera = camera.new(playerOptionsForGameMode("survival", displayState))
    playerCamera:placeAtSpawn(world, playerCamera.position[1], playerCamera.position[3])
    local worldgenPreviewCamera = camera.new({position = {0.0, 900.0, 0.0}, yaw = 45.0, pitch = -54.0})
    local worldgenPreviewState = {
      centerX = playerCamera.position[1],
      centerZ = playerCamera.position[3],
      yaw = 45.0,
      distance = 980.0
    }
    local worldgenPreviewMesh = nil
    applyMenuRuntimeState(window, displayState, playerCamera, world)
    local lastTime = glfw.glfwGetTime()

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
        releaseFarWaterMeshes(farWaterMeshes, farWaterState)
        rendering.release(orbitalPlanetMesh)
        rendering.release(orbitalCloudMesh)
        orbitalPlanetMesh, orbitalCloudMesh = nil, nil
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
      updateMenuInput(window, displayState, playerCamera, world, locP)
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
          releaseFarWaterMeshes(farWaterMeshes, farWaterState)
          rendering.release(orbitalPlanetMesh)
          rendering.release(orbitalCloudMesh)
          orbitalPlanetMesh, orbitalCloudMesh = nil, nil
          world = job.world
          terrainMeshes = job.terrainMeshes
          displayState.currentWorldSave = job.save
          currentWaterLevel = nil
          playerCamera = camera.new(playerOptionsForGameMode(job.config.gameMode, displayState))
          playerCamera:placeAtSpawn(world, job.spawnDirection)
          playerCamera.firstMouse = true
          displayState.selectedSlot = 1
          displayState.worldGameMode = job.config.gameMode
          displayState.inventory = Inventory.new(job.config.gameMode)
          displayState.inventory.selected = 1
          displayState.inventoryVersion = displayState.inventoryVersion + 1
          displayState.health, displayState.hunger, displayState.saturation = 20, 20, 5
          displayState.exhaustion, displayState.handSwing = 0, 0
          displayState.tutorialTime = 0
          refreshCreativeFilter(displayState)
          displayState.worldGeneratorType = job.config.generatorType
          devMenu:setGenerationSeed(job.seed)
          worldgenPreviewState.centerX = playerCamera.position[1]
          worldgenPreviewState.centerZ = playerCamera.position[3]
          displayState.hasWorld = true
          displayState.screen = nil
          displayState.loadingJob = nil
          displayState.pendingTerrainEntries = job.streamingEntries or {}
          if game.startTeleport then
            playerCamera:teleportTo(world, game.startTeleport[1], game.startTeleport[2], game.startTeleport[3])
            playerCamera.allowFlight, playerCamera.flying = true, true
            world:updateRenderOrigin(playerCamera.position)
          end
          if (graphics.world.sphericalVoxels ~= false) then
            local started = glfw.glfwGetTime()
            releaseTerrainMeshes(terrainMeshes)
            terrainMeshes = {}
            gridWorld, gridRuntime = game.startGridWorld(
              world, playerCamera, terrainMeshes, graphics.world.gridLoadRadius)
            print(string.format("Spherical voxel world: %d chunks around spawn in %.2f s",
              gridWorld:chunkCount(), glfw.glfwGetTime() - started))
          end
          if game.autoStartWorld then
            local latitude, longitude, altitude = playerCamera:geodeticPosition()
            local sample = terrain.surfaceAtPosition(
              playerCamera.position[1], playerCamera.position[2], playerCamera.position[3], world.planet)
            print(string.format(
              "World ready: seed %s, %.4f lat, %.4f lon, %.1f m, %s, ground %.1f m, solar time %.2f h",
              tostring(job.seed), latitude, longitude, altitude, sample.biome,
              sample.elevationMeters, celestial:timeOfDayHours(playerCamera.position, world.planet.center)))
          end
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
        if not previewMode then
          if world:updateRenderOrigin(playerCamera.position) then
            if gridRuntime then
              -- The grid runtime owns these meshes. Wiping the table here would
              -- also rebind it, and the runtime's upload closure still holds
              -- the old one -- so every later mesh would land in an orphaned
              -- table and never be drawn again. Let the runtime rebuild in
              -- place instead, all at once so nothing shows at a stale origin.
              gridRuntime:setRenderOrigin(world.renderOrigin)
              gridRuntime:rebuildDirty()
            else
              releaseTerrainMeshes(terrainMeshes)
              terrainMeshes={}
              displayState.pendingTerrainEntries={}
              world:eachChunk(function(_,entry) entry.hasMesh=false entry.hasGPUBuffer=false entry.isUploaded=false entry.renderReady=false end)
            end
          end
          if gridRuntime then
            gridRuntime:update(playerCamera.position)
          end
          local streamVoxelWorld=world.visualLod:levelForPosition(playerCamera.position)=="voxel"
            and not devMenu:freezesStreaming() and not gridRuntime
          if streamVoxelWorld then
            pruneTerrainMeshes(world,terrainMeshes,displayState.pendingTerrainEntries,playerCamera.position[1],playerCamera.position[2],playerCamera.position[3])
            if #displayState.pendingTerrainEntries < CHUNK_QUEUE_BACKLOG then
            local streamForward = playerCamera:getHorizontalFront()
            queueTerrainMeshes(
              world,
              displayState.pendingTerrainEntries,
              playerCamera.position[1],
              playerCamera.position[2],
              playerCamera.position[3],
              math.min(CHUNK_QUEUE_BUDGET, CHUNK_QUEUE_BACKLOG - #displayState.pendingTerrainEntries),
              {
                predictedX = playerCamera.position[1] + (playerCamera.velocity and playerCamera.velocity[1] or 0.0) * 1.5,
                predictedY = playerCamera.position[2] + (playerCamera.velocity and playerCamera.velocity[2] or 0.0) * 1.5,
                predictedZ = playerCamera.position[3] + (playerCamera.velocity and playerCamera.velocity[3] or 0.0) * 1.5,
                forwardX = streamForward[1],
                forwardY = streamForward[2],
                forwardZ = streamForward[3]
              }
            )
            end
            if #displayState.pendingTerrainEntries > 0 or world.lightDirty or world.lightingJob then
              queueStats = processTerrainMeshQueue(world, terrainMeshes, displayState.pendingTerrainEntries, TERRAIN_WORK_BUDGET)
            end
          end
          if displayState.hasWorld and currentWaterLevel then
            updateFarWaterMeshes(
              farWaterMeshes, farWaterState, terrainMeshes, world,
              playerCamera.position[1], playerCamera.position[3]
            )
          end
        end
        displayState.lastQueueStats = queueStats
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
          local previousX = playerCamera.position[1]
          local previousY = playerCamera.position[2]
          local previousZ = playerCamera.position[3]
          local wasGrounded = playerCamera.grounded
          local fallingVelocity = playerCamera.velocityY or 0
          playerCamera:update(dt, window, gridWorld or world)
          if gridRuntime then
            game.updateGridEditInput(window, displayState, gridRuntime, playerCamera, dt)
          else
            updateBlockEditInput(window, displayState, world, displayState.pendingTerrainEntries, playerCamera, dt)
          end
          local dx = playerCamera.position[1] - previousX
          local dy = playerCamera.position[2] - previousY
          local dz = playerCamera.position[3] - previousZ
          displayState.stats.distance = displayState.stats.distance + math.sqrt(dx * dx + dy * dy + dz * dz)
          displayState.stats.playTime = displayState.stats.playTime + dt
          displayState.tutorialTime = (displayState.tutorialTime or 0) + dt
          local travelled=math.sqrt(dx*dx+dy*dy+dz*dz)
          updateSurvival(displayState,playerCamera,world,dt,travelled,(not wasGrounded and playerCamera.grounded) and fallingVelocity or nil)
        end
        if displayState.handSwing and displayState.handSwing > 0 then
          displayState.handSwing = displayState.handSwing + dt * 3.8
          if displayState.handSwing >= 1 then displayState.handSwing = 0 end
        end
        -- Developer navigation. Walking a planet at 5 m/s inside a loaded ball
        -- roughly 100 m across is not exploration, so the dev menu owns a fast
        -- no-clip flight, a coordinate jump, and a switch that stops chunk
        -- streaming while you cross the map.
        if not previewMode then
          local wantsFlight = devMenu:flyEnabled()
          if wantsFlight and not playerCamera.flying then
            playerCamera.allowFlight = true
            playerCamera.flying = true
            playerCamera.radialVelocity, playerCamera.velocityY = 0.0, 0.0
            playerCamera.grounded = false
          elseif not wantsFlight and playerCamera.devFlightActive then
            playerCamera.flying = false
          end
          playerCamera.devFlightActive = wantsFlight
          playerCamera.noclip = wantsFlight
          playerCamera.flySpeedMultiplier = devMenu:flySpeedMultiplier()

          devMenu:setCurrentLocation(playerCamera:geodeticPosition())
          devMenu:consumeCaptureRequest()
          local latitude, longitude, altitude = devMenu:consumeTeleportRequest()
          if latitude then
            playerCamera:teleportTo(world, latitude, longitude, altitude)
            -- Everything cached is relative to the old render origin, and the
            -- jump is far larger than the origin grid, so drop it all rather
            -- than let stale meshes float around the new position.
            releaseTerrainMeshes(terrainMeshes)
            terrainMeshes = {}
            displayState.pendingTerrainEntries = {}
            world:updateRenderOrigin(playerCamera.position)
            world:eachChunk(function(_, entry)
              entry.hasMesh = false entry.hasGPUBuffer = false
              entry.isUploaded = false entry.renderReady = false
            end)
          end
        end

        -- Solar time is read at the player, so the dev menu asking for noon puts
        -- the sun over their head rather than over a fixed prime meridian.
        celestial:setTimeScale(devMenu:timeScale())
        celestial:advance(dt)
        local solarObserver = playerCamera.position
        local planetCentre = world.planet and world.planet.center or nil
        celestial:clearTimeOverride()
        devMenu:setNaturalTimeOfDay(celestial:timeOfDayHours(solarObserver, planetCentre))
        if devMenu:usesTimeOverride() then
          celestial:overrideTimeOfDay(devMenu:timeOfDay(), solarObserver, planetCentre)
        elseif game.forceTimeOfDay then
          celestial:overrideTimeOfDay(game.forceTimeOfDay, solarObserver, planetCentre)
        end
        updateRuntimeAtmosphereSettings(runtimeAtmosphereSettings, devMenu:fogStrength())

        local sunDir = celestial:sunDirection()
        local skyRotation = celestial:rotationAngle()
        -- Smoke-run camera aiming, so a capture can look at the sky and the sun
        -- rather than wherever spawn happened to face.
        -- Smoke-run autopilot: walks tangentially at a fixed speed. Needed to
        -- reproduce anything that only happens once the player has travelled,
        -- which includes every render-origin change.
        if game.autoWalk and not previewMode then
          local up = playerCamera:getLocalUp()
          local forward = playerCamera:getHorizontalFront()
          local advance = game.autoWalk * dt
          local moved = {
            playerCamera.position[1] + forward[1] * advance,
            playerCamera.position[2] + forward[2] * advance,
            playerCamera.position[3] + forward[3] * advance
          }
          playerCamera.position = moved
          playerCamera.velocity = {forward[1] * game.autoWalk, forward[2] * game.autoWalk, forward[3] * game.autoWalk}
        end

        if game.lookAt == "sun" and not previewMode then
          local up = playerCamera:getLocalUp()
          local elevation = math.max(-1.0, math.min(1.0,
            sunDir[1]*up[1] + sunDir[2]*up[2] + sunDir[3]*up[3]))
          local tx = sunDir[1] - up[1]*elevation
          local ty = sunDir[2] - up[2]*elevation
          local tz = sunDir[3] - up[3]*elevation
          -- At the zenith the sun has no horizontal bearing at all, and
          -- normalising the zero vector would put a NaN through the view
          -- matrix. Keep the heading and just look up.
          if tx*tx + ty*ty + tz*tz > 1e-8 then
            playerCamera.heading = math3d.normalize({tx, ty, tz})
          end
          playerCamera.pitch = math.deg(math.asin(elevation)) * 0.6
        end
        local sky = atmosphere.forSun(sunDir, FOG_START, FOG_END,
          previewMode and {0.0, 1.0, 0.0} or playerCamera:getLocalUp())
        local activeCamera = previewMode and worldgenPreviewCamera or playerCamera
        local radialAltitude = previewMode and 0.0 or world.planet:altitudeMeters(activeCamera.position)
        local frameNear, frameFar = CAMERA_NEAR, CAMERA_FAR
        if not previewMode and radialAltitude > 1000.0 then
          frameNear = math.max(1.0, math.min(1000.0, radialAltitude * 0.0005))
          frameFar = math.max(CAMERA_FAR, world.planet.diameterVoxels + radialAltitude / world.planet.voxelSizeMeters + 200000.0)
          if not orbitalPlanetMesh then
            terrain.setSeed(world.seed)
            orbitalPlanetMesh = uploadMesh(planetVisuals.buildSurfaceVertices(world, 128, 64))
            local cloudAltitude = ((CLOUD_BOTTOM + CLOUD_TOP) * 0.5)
            orbitalCloudMesh = uploadMesh(planetVisuals.buildShellVertices(world.planet, cloudAltitude, 128, 64))
          end
        end
        local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, frameNear, frameFar)
        local viewPosition = previewMode and activeCamera.position or world:toRenderPosition(activeCamera.position)
        local activeFront=activeCamera:getFront()
        local viewCenter = previewMode and activeCamera:getCenter() or {viewPosition[1]+activeFront[1],viewPosition[2]+activeFront[2],viewPosition[3]+activeFront[3]}
        if not previewMode and displayState.viewBobbing ~= false and playerCamera.grounded then
          local horizontalSpeed = math.sqrt(
            playerCamera.velocity[1] * playerCamera.velocity[1] +
            playerCamera.velocity[3] * playerCamera.velocity[3]
          )
          local bobAmount = math.min(horizontalSpeed / math.max(playerCamera.walkSpeed, 0.1), 1.5)
          local bob = math.sin(currentTime * 11.0) * 0.035 * bobAmount
          local bobUp=playerCamera:getLocalUp()
          viewPosition={viewPosition[1]+bobUp[1]*bob,viewPosition[2]+bobUp[2]*bob,viewPosition[3]+bobUp[3]*bob}
          viewCenter={viewCenter[1]+bobUp[1]*bob,viewCenter[2]+bobUp[2]*bob,viewCenter[3]+bobUp[3]*bob}
        end
        local view = math3d.lookAt(viewPosition,viewCenter,previewMode and {0,1,0} or activeCamera:getLocalUp())
        local renderCamera=activeCamera
        if not previewMode then
          renderCamera=setmetatable({position=viewPosition,absolutePosition=activeCamera.position},{__index=activeCamera})
          renderCamera.getFront=function() return activeCamera:getFront() end
          renderCamera.getLocalUp=function() return activeCamera:getLocalUp() end
          renderCamera.getCenter=function() local f=activeCamera:getFront() return {viewPosition[1]+f[1],viewPosition[2]+f[2],viewPosition[3]+f[3]} end
        end
        local frustum = math3d.frustumPlanes(math3d.multiplyMat4(projection, view))
        local visibleMeshes = previewMode and {} or visibleTerrainMeshes(terrainMeshes, frustum)
        local visibleLeaves = previewMode and {} or visibleLeafMeshes(visibleMeshes,viewPosition)
        local visibleIce = previewMode and {} or visibleIceMeshes(visibleMeshes)
        local visibleWater = previewMode and {} or visibleWaterMeshes(
          visibleMeshes, farWaterMeshes, terrainMeshes, frustum
        )
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
              sunDir,
              gridWorld
            )
            displayState.debugSampleTimer = 0.0
          end
        elseif not displayState.debugScreen then
          displayState.debugInfo = nil
        end
        local lightSpaceMatrix=effects.lightSpaceMatrix(viewPosition,sunDir,TERRAIN_MAX_H,SHADOW_DISTANCE,SHADOW_NEAR,SHADOW_FAR,previewMode and {0,1,0} or activeCamera:getLocalUp())
        if not previewMode then
          effects.renderShadowPass(shadowShader, shadowMap, shadowLocations, visibleMeshes, characterMesh, lightSpaceMatrix, model, SHADOW_MAP_SIZE, windowWidth, windowHeight, atlasTex,
            viewPosition,currentTime,graphics.terrain)
        end
        effects.renderVolumetricFog(volumetricFog,volumetricFogShaders,renderCamera,sunDir,sky,CAMERA_FOV,windowWidth,windowHeight,currentWaterLevel or -1000.0,previewMode and previewAtmosphereSettings or runtimeAtmosphereSettings,shadowMap,lightSpaceMatrix)
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
        gl.glUniform3f(locViewPos,viewPosition[1],viewPosition[2],viewPosition[3])
        gl.glUniform3f(locLight, -sunDir[1], -sunDir[2], -sunDir[3])
        gl.glUniform1f(locTime, currentTime)
        gl.glUniform4f(locFoliageParams,
          graphics.terrain.grassCullStart or 64.0,
          graphics.terrain.grassCullEnd or 104.0,
          graphics.terrain.leafWindDistance or 112.0,
          graphics.terrain.foliageWindStrength or 1.0)
        local shaderUp=previewMode and {0,1,0} or activeCamera:getLocalUp()
        gl.glUniform3f(locPlanetUp,shaderUp[1],shaderUp[2],shaderUp[3])
        gl.glUniform3f(locAmbientColor, sky.ambient[1], sky.ambient[2], sky.ambient[3])
        gl.glUniform3f(locLightColor, sky.lightColor[1], sky.lightColor[2], sky.lightColor[3])
        gl.glUniform3f(locMoonLightColor, sky.moonLightColor[1], sky.moonLightColor[2], sky.moonLightColor[3])
        gl.glUniform3f(locLightingParams, sky.daylight, sky.moonAmount, sky.ambientFloor)
        gl.glUniform1f(locShadowStrength, sky.shadowStrength)
        gl.glUniform1f(locSmoothLighting, displayState.smoothLighting == false and 0.0 or 1.0)
        gl.glUniform1f(locTerrainWaterLevel, previewMode and -1000.0 or (currentWaterLevel or -1000.0))
        gl.glUniform3f(locTerrainWaterCascadeSizes,
          ocean.cascadeSizes[1], ocean.cascadeSizes[2], ocean.cascadeSizes[3])
        gl.glUniform3f(locTerrainWaterNormalWeights,
          ocean.normalWeights[1], ocean.normalWeights[2], ocean.normalWeights[3])
        gl.glUniform1f(locTerrainCausticStrength, graphics.water.causticStrength or 0.42)

        gl.glClearColor(sky.fogColor[1], sky.fogColor[2], sky.fogColor[3], 1.0)
        gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
        drawSky(skyShader,skyMesh,skyLocations,moonTexture,renderCamera,sunDir,sky,currentTime,displayState.clouds,skyRotation)
        -- The sun sphere goes on top of the sky and under everything else, so
        -- it is drawn before the depth buffer is cleared for world geometry.
        do
          local observerAltitude = previewMode and 0.0 or math.max(radialAltitude, 0.0)
          local sunUp = previewMode and {0,1,0} or activeCamera:getLocalUp()
          local elevation = sunDir[1]*sunUp[1] + sunDir[2]*sunUp[2] + sunDir[3]*sunUp[3]
          local transmittance = atmosphere.sunTransmittance(observerAltitude, elevation)
          local brightness = graphics.celestial.sunBrightness or 24.0
          local sunDistance = frameNear * 500.0
          local sunRadius = sunDistance * math.tan(celestial:sunAngularRadius())
            * (graphics.celestial.sunSizeScale or 1.0)
          sunPass.draw(sunShader,sunMesh,sunLocations,view,projection,viewPosition,sunDir,
            sunDistance,sunRadius,
            {transmittance[1]*brightness,transmittance[2]*brightness,transmittance[3]*brightness})
        end
        gl.glClear(GL_DEPTH_BUFFER_BIT)

        if not previewMode and radialAltitude > 1000.0 and orbitalPlanetMesh then
          local planetOffset={
            world.planet.center[1]-world.renderOrigin[1],
            world.planet.center[2]-world.renderOrigin[2],
            world.planet.center[3]-world.renderOrigin[3]
          }
          gl.glEnable(GL_CULL_FACE)
          gl.glCullFace(GL_BACK)
          gl.glUseProgram(orbitalPlanetShader)
          gl.glUniformMatrix4fv(orbitalPlanetLocations.projection,1,0,ffi.new("float[16]",projection))
          gl.glUniformMatrix4fv(orbitalPlanetLocations.view,1,0,ffi.new("float[16]",view))
          gl.glUniform3f(orbitalPlanetLocations.offset,planetOffset[1],planetOffset[2],planetOffset[3])
          gl.glUniform3f(orbitalPlanetLocations.sunDir,sunDir[1],sunDir[2],sunDir[3])
          gl.glUniform3f(orbitalPlanetLocations.viewPos,viewPosition[1],viewPosition[2],viewPosition[3])
          rendering.draw(orbitalPlanetMesh)
          if displayState.clouds ~= false and orbitalCloudMesh then
            gl.glUseProgram(orbitalCloudShader)
            gl.glUniformMatrix4fv(orbitalCloudLocations.projection,1,0,ffi.new("float[16]",projection))
            gl.glUniformMatrix4fv(orbitalCloudLocations.view,1,0,ffi.new("float[16]",view))
            gl.glUniform3f(orbitalCloudLocations.offset,planetOffset[1],planetOffset[2],planetOffset[3])
            gl.glUniform3f(orbitalCloudLocations.sunDir,sunDir[1],sunDir[2],sunDir[3])
            gl.glUniform3f(orbitalCloudLocations.viewPos,viewPosition[1],viewPosition[2],viewPosition[3])
            gl.glUniform1f(orbitalCloudLocations.time,currentTime)
            gl.glEnable(GL_BLEND)
            gl.glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA)
            gl.glDepthMask(0)
            rendering.draw(orbitalCloudMesh)
            gl.glDepthMask(1)
            gl.glDisable(GL_BLEND)
          end
          gl.glDisable(GL_CULL_FACE)
        end

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
          gl.glUniform1f(locUseVoxelLight, 1.0)
          for _, mesh in ipairs(visibleMeshes) do
            rendering.draw(mesh)
          end
          if characterMesh then
            gl.glUniform1f(locUseVoxelLight, 0.0)
            gl.glBindTexture(GL_TEXTURE_2D, characterSkinTexture[0])
            rendering.draw(characterMesh)
            gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
          end
          if displayState.clouds ~= false and displayState.graphicsMode ~= "Fast" and not world.planet then
            drawClouds(cloudShader,cloudMesh,cloudLocations,renderCamera,view,projection,currentTime,sky)
          end
          if #visibleIce > 0 then
            effects.copySceneTarget(sceneTarget, waterBackgroundTarget)
            effects.drawIce(
              iceShader,visibleIce,iceLocations,renderCamera,view,projection,sunDir,sky,
              waterBackgroundTarget, windowWidth, windowHeight, frameNear, frameFar,
              atlasTex, graphics.ice, model
            )
          end
          if #visibleWater>0 then
            gl.glUseProgram(planetWaterShader)
            gl.glUniformMatrix4fv(planetWaterLocations.projection,1,0,ffi.new("float[16]",projection))
            gl.glUniformMatrix4fv(planetWaterLocations.view,1,0,ffi.new("float[16]",view))
            gl.glUniform3f(planetWaterLocations.viewPos,viewPosition[1],viewPosition[2],viewPosition[3])
            gl.glUniform3f(planetWaterLocations.sunDir,sunDir[1],sunDir[2],sunDir[3])
            gl.glUniform3f(planetWaterLocations.waterColor,0.055,0.31,0.48)
            gl.glEnable(GL_BLEND)
            gl.glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA)
            gl.glDepthMask(0)
            for _,waterMesh in ipairs(visibleWater) do rendering.draw(waterMesh) end
            gl.glDepthMask(1)
            gl.glDisable(GL_BLEND)
          end
          -- Foliage is the final world-space translucent pass. Clouds, ice and
          -- water have already written depth, so leaves behind them fail depth
          -- testing while nearby leaves blend correctly over their surfaces.
          if #visibleLeaves > 0 then
            gl.glUseProgram(shader)
            gl.glActiveTexture(GL_TEXTURE0)
            gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
            gl.glActiveTexture(GL_TEXTURE1)
            gl.glBindTexture(GL_TEXTURE_2D, shadowMap.depthTexture[0])
            gl.glActiveTexture(GL_TEXTURE2)
            gl.glBindTexture(GL_TEXTURE_2D, ocean.normalTexture)
            gl.glActiveTexture(GL_TEXTURE0)
            gl.glUniform1f(locUseVoxelLight, 1.0)
            gl.glEnable(GL_BLEND)
            gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
            gl.glDepthMask(0)
            for _, leafMesh in ipairs(visibleLeaves) do
              rendering.draw(leafMesh)
            end
            gl.glDepthMask(1)
            gl.glDisable(GL_BLEND)
          end
        end

        -- Bloom reads the HDR scene before it is graded, so anything brighter
        -- than the threshold bleeds. Runs at half resolution downward, so the
        -- whole chain costs about as much as one full-resolution pass.
        local bloomTexture = nil
        if displayState.bloom ~= false and displayState.graphicsMode ~= "Fast" then
          bloomTexture = effects.renderBloom(bloomShaders, bloomChain, sceneTarget.colorTexture[0], skyMesh, {
            threshold = POST.bloomThreshold or 0.70,
            softKnee = POST.bloomSoftKnee or 0.60,
            radius = POST.bloomRadius or 1.0,
            clampMax = POST.bloomClamp or 12.0
          })
        end

        gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
        gl.glViewport(0, 0, windowWidth, windowHeight)
        local postWaterLevel = -1000.0
        if not previewMode and currentWaterLevel and world then
          local cameraX = math.floor(activeCamera.position[1])
          local cameraY = math.floor(activeCamera.position[2])
          local cameraZ = math.floor(activeCamera.position[3])
          local cameraBlock = world:blockAt(cameraX, cameraY, cameraZ)
          if cameraBlock == blocks.water or (blocks.water_still and cameraBlock == blocks.water_still) then
            local localSurface = terrain.waterSurfaceAt(cameraX, cameraZ)
            if localSurface then
              postWaterLevel = localSurface + (WATER_LEVEL - terrain.SEA_LEVEL)
            end
          end
        end
        effects.drawAtmospherePost(atmospherePostShader, skyMesh, atmospherePostLocations, sceneTarget, renderCamera, CAMERA_FOV, windowWidth, windowHeight, frameNear, frameFar, postWaterLevel, previewMode and previewAtmosphereSettings or runtimeAtmosphereSettings, displayState.screen == "pause" and 1.15 or 0.0, underwaterOverlayTexture, currentTime, bloomTexture, POST, volumetricFog)
        if displayState.screen == "inventory" or displayState.screen == "creative_inventory" then
          hudOverlay:drawInventory(windowWidth,windowHeight,displayState.screen,displayState,displayState.menuMouseX,displayState.menuMouseY,{id=atlasTex})
        elseif displayState.screen then
          hudOverlay:drawMenu(windowWidth, windowHeight, displayState.screen, displayState.menuMouseX, displayState.menuMouseY, displayState, currentTime)
        elseif not previewMode then
          hudOverlay:draw(windowWidth, windowHeight, currentTime, displayState.selectedSlot, displayState, {id=atlasTex})
          if displayState.debugScreen and displayState.debugInfo then
            hudOverlay:drawDebug(windowWidth, windowHeight, displayState.debugInfo)
          end
        end
        devMenu:draw(window, windowWidth, windowHeight, dt)
        displayState.devMenuOpen = devMenu:isOpen()

        if game.screenshotSchedule and #game.screenshotSchedule > 0 then
          local due = game.screenshotSchedule[1]
          if smokeTotal >= due.at then
            table.remove(game.screenshotSchedule, 1)
            if game.captureFrame(due.path, windowWidth, windowHeight) then
              print(string.format("Captured %s at %.1f s, solar %.2f h", due.path, smokeTotal,
                celestial:timeOfDayHours(playerCamera.position, world.planet.center)))
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

        smokeTotal = smokeTotal + dt
        -- Smoke-run telemetry. The headless launch cannot press F3, so the
        -- numbers that would be on the debug screen are printed instead.
        if game.autoStartWorld then
          smokeFrames = smokeFrames + 1
          smokeElapsed = smokeElapsed + dt
          if smokeElapsed >= 5.0 then
            local pending = #displayState.pendingTerrainEntries
            local resident = 0
            for _ in pairs(world.chunks) do resident = resident + 1 end
            print(string.format(
              "  %5.1f fps  grid %4d chunks %4d meshed %4d pending  drawn %3d  alt %7.2f m",
              smokeFrames / smokeElapsed,
              gridWorld and gridWorld:chunkCount() or resident,
              gridRuntime and (function()
                local n = 0
                for _, v in pairs(gridRuntime.meshed) do if v then n = n + 1 end end
                return n
              end)() or 0,
              gridRuntime and (#gridRuntime.pending - gridRuntime.pendingIndex + 1) or pending,
              #visibleMeshes,
              world.planet:altitudeMeters(playerCamera.position)))
            smokeFrames, smokeElapsed = 0, 0.0
          end
        end
      end
    end

    effects.releaseBloomChain(bloomChain)
    effects.releaseVolumetricFog(volumetricFog, volumetricFogShaders)
    effects.releaseOceanSimulation(ocean)
    effects.releaseSceneTarget(waterBackgroundTarget)
    effects.releaseSceneTarget(sceneTarget)
    devMenu:release()
    rendering.release(worldgenPreviewMesh)
    rendering.release(orbitalPlanetMesh)
    rendering.release(orbitalCloudMesh)
    releaseTerrainMeshes(terrainMeshes)
    releaseFarWaterMeshes(farWaterMeshes, farWaterState)
    rendering.release(characterMesh)
    rendering.release(skyMesh)
    rendering.release(sunMesh)
    rendering.release(cloudMesh)
    hudOverlay:release()
  end)

  glfw.glfwTerminate()

  if not ok then
    error(err)
  end
end

return game
