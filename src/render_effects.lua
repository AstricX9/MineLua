local ffi = require("ffi")
local GL = require("gl")
local math3d = require("math3d")
local rendering = require("rendering")
local shaderModule = require("shader")

local effects = {}

local gl = GL.gl

local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_TEXTURE0 = 0x84C0
local GL_TEXTURE1 = 0x84C1
local GL_TEXTURE2 = 0x84C2
local GL_TEXTURE3 = 0x84C3
local GL_TEXTURE4 = 0x84C4
local GL_TEXTURE5 = 0x84C5
local GL_TEXTURE_2D = 0x0DE1
local GL_TEXTURE_3D = 0x806F
local GL_TEXTURE_MIN_FILTER = 0x2801
local GL_TEXTURE_MAG_FILTER = 0x2800
local GL_TEXTURE_WRAP_S = 0x2802
local GL_TEXTURE_WRAP_T = 0x2803
local GL_TEXTURE_WRAP_R = 0x8072
local GL_LINEAR = 0x2601
local GL_NEAREST = 0x2600
local GL_RGBA = 0x1908
local GL_RG = 0x8227
local GL_RED = 0x1903
local GL_R32F = 0x822E
local GL_RG32F = 0x8230
local GL_RGBA32F = 0x8814
local GL_CLAMP_TO_EDGE = 0x812F
local GL_REPEAT = 0x2901
local GL_DEPTH_COMPONENT = 0x1902
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_UNSIGNED_INT = 0x1405
local GL_UNSIGNED_BYTE = 0x1401
local GL_FRAMEBUFFER = 0x8D40
local GL_READ_FRAMEBUFFER = 0x8CA8
local GL_DRAW_FRAMEBUFFER = 0x8CA9
local GL_COLOR_ATTACHMENT0 = 0x8CE0
local GL_DEPTH_ATTACHMENT = 0x8D00
local GL_FRAMEBUFFER_COMPLETE = 0x8CD5
local GL_NONE = 0
local GL_POLYGON_OFFSET_FILL = 0x8037
local GL_DEPTH_TEST = 0x0B71
local GL_BLEND = 0x0BE2
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303
local GL_RGBA16F = 0x881A
local GL_FLOAT = 0x1406
local GL_TRUE = 1
local GL_READ_ONLY = 0x88B8
local GL_WRITE_ONLY = 0x88B9
local GL_SHADER_IMAGE_ACCESS_BARRIER_BIT = 0x00000020
local GL_TEXTURE_FETCH_BARRIER_BIT = 0x00000008
local GL_ONE = 1
local GL_COLOR_BUFFER_BIT = 0x00004000
local GL_LINEAR_MIPMAP_LINEAR = 0x2703

function effects.createShadowShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 3) in vec2 aTexCoord;
out vec2 vTexCoord;
uniform mat4 uModel;
uniform mat4 lightSpaceMatrix;
void main() {
  vTexCoord = aTexCoord;
  gl_Position = lightSpaceMatrix * uModel * vec4(aPos, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec2 vTexCoord;
uniform sampler2D tex0;
void main() {
  if (texture(tex0, vTexCoord).a < 0.5) discard;
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createDielectricShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;
layout (location = 4) in vec3 aInfo;
out vec3 vWorldPos;
out vec3 vNormal;
out vec2 vTexCoord;
out vec3 vColor;
out float vMaterial;
out float vThickness;
out float vVoxelLight;
uniform mat4 uProjection;
uniform mat4 uView;
uniform mat4 uModel;
void main() {
  vec4 worldPosition = uModel * vec4(aPos, 1.0);
  vWorldPos = worldPosition.xyz;
  vNormal = mat3(transpose(inverse(uModel))) * aNormal;
  vTexCoord = aTexCoord;
  vColor = aColor;
  vMaterial = aInfo.x;
  vThickness = aInfo.y;
  vVoxelLight = aInfo.z;
  gl_Position = uProjection * uView * worldPosition;
}
]]

  local fragSource = [[
#version 460 core
in vec3 vWorldPos;
in vec3 vNormal;
in vec2 vTexCoord;
in vec3 vColor;
in float vMaterial;
in float vThickness;
in float vVoxelLight;
out vec4 FragColor;
uniform mat4 uView;
uniform vec3 viewPos;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform vec3 skyZenithColor;
uniform vec3 lightColor;
uniform vec2 viewportSize;
uniform vec2 clipPlanes;
uniform vec4 iceOptics;   // IOR, roughness, refraction, cloudiness
uniform vec4 glassOptics; // IOR, roughness, refraction, cloudiness
uniform vec3 iceAbsorption;
uniform vec3 glassAbsorption;
uniform sampler2D tex0;
uniform sampler2D sceneColor;
uniform sampler2D sceneDepth;

const float PI = 3.14159265359;

float linearDepth(float rawDepth) {
  float z = rawDepth * 2.0 - 1.0;
  return (2.0 * clipPlanes.x * clipPlanes.y) /
    (clipPlanes.y + clipPlanes.x - z * (clipPlanes.y - clipPlanes.x));
}

float dielectricFresnel(float cosThetaI, float etaI, float etaT) {
  cosThetaI = clamp(cosThetaI, 0.0, 1.0);
  float eta = etaI / etaT;
  float sinThetaTSquared = eta * eta * max(1.0 - cosThetaI * cosThetaI, 0.0);
  float cosThetaT = sqrt(max(1.0 - sinThetaTSquared, 0.0));
  float parallel = (etaT * cosThetaI - etaI * cosThetaT) /
    max(etaT * cosThetaI + etaI * cosThetaT, 1.0e-5);
  float perpendicular = (etaI * cosThetaI - etaT * cosThetaT) /
    max(etaI * cosThetaI + etaT * cosThetaT, 1.0e-5);
  return 0.5 * (parallel * parallel + perpendicular * perpendicular);
}

float distributionGGX(float nDotH, float roughness) {
  float a2 = roughness * roughness;
  a2 *= a2;
  float d = nDotH * nDotH * (a2 - 1.0) + 1.0;
  return a2 / max(PI * d * d, 1.0e-5);
}

float geometrySmith(float nDotV, float nDotL, float roughness) {
  float k = roughness + 1.0;
  k = k * k * 0.125;
  float gv = nDotV / mix(nDotV, 1.0, k);
  float gl = nDotL / mix(nDotL, 1.0, k);
  return gv * gl;
}

vec3 skyRadiance(vec3 direction) {
  direction = normalize(direction);
  float altitude = smoothstep(0.0, 0.88, max(direction.y, 0.0));
  vec3 sky = mix(fogColor, skyZenithColor, altitude);
  float sunDisc = smoothstep(cos(0.020), cos(0.010), dot(direction, normalize(sunDir)));
  return sky + lightColor * sunDisc * 2.1;
}

void main() {
  bool isGlass = vMaterial > 3.5;
  vec4 optics = isGlass ? glassOptics : iceOptics;
  vec3 absorption = isGlass ? glassAbsorption : iceAbsorption;
  vec4 surfaceTexture = texture(tex0, vTexCoord);
  float textureLight = dot(surfaceTexture.rgb, vec3(0.2126, 0.7152, 0.0722));
  float textureDetail = isGlass
    ? clamp(1.0 - surfaceTexture.a, 0.0, 1.0)
    : smoothstep(0.60, 0.96, textureLight);

  vec3 normal = normalize(vNormal);
  vec3 viewDirection = normalize(viewPos - vWorldPos);
  if (dot(normal, viewDirection) < 0.0) normal = -normal;
  float nDotV = max(dot(normal, viewDirection), 0.025);
  float pathLength = clamp(max(vThickness, 1.0) / nDotV, 0.65, 18.0);

  vec2 screenUv = gl_FragCoord.xy / viewportSize;
  float surfaceDepth = linearDepth(gl_FragCoord.z);
  vec3 viewNormal = normalize(mat3(uView) * normal);
  vec2 textureSlope = vec2(dFdx(textureLight), dFdy(textureLight));
  vec2 distortedUv = screenUv + viewNormal.xy * optics.z * (0.40 + pathLength * 0.075)
    + textureSlope * optics.z * (isGlass ? 0.10 : 0.34);
  distortedUv = clamp(distortedUv, vec2(0.002), vec2(0.998));
  float distortedDepth = linearDepth(texture(sceneDepth, distortedUv).r);
  if (distortedDepth < surfaceDepth + 0.04) distortedUv = screenUv;

  vec3 transmittedScene = texture(sceneColor, distortedUv).rgb;
  vec3 transmittance = exp(-absorption * pathLength);
  float cloudiness = clamp(optics.w + textureDetail * (isGlass ? 0.08 : 0.22), 0.0, 1.0);
  vec3 scatterColor = isGlass ? vec3(0.82, 0.91, 0.96) : vec3(0.30, 0.64, 0.82);
  vec3 refracted = transmittedScene * transmittance + scatterColor * (1.0 - transmittance);
  refracted = mix(refracted, scatterColor * (0.70 + 0.30 * vVoxelLight), cloudiness * 0.20);

  float fresnel = dielectricFresnel(nDotV, 1.0, optics.x);
  vec3 reflectionDirection = reflect(-viewDirection, normal);
  vec3 reflected = skyRadiance(reflectionDirection);

  vec3 lightDirection = normalize(sunDir);
  vec3 halfVector = normalize(lightDirection + viewDirection);
  float nDotL = max(dot(normal, lightDirection), 0.0);
  float nDotH = max(dot(normal, halfVector), 0.0);
  float roughness = clamp(optics.y + textureDetail * (isGlass ? 0.025 : 0.18), 0.025, 0.62);
  float microfacet = distributionGGX(nDotH, roughness) *
    geometrySmith(nDotV, nDotL, roughness) * fresnel /
    max(4.0 * nDotV * max(nDotL, 0.001), 0.001);

  vec3 color = mix(refracted, reflected, clamp(fresnel + cloudiness * 0.035, 0.0, 0.96));
  color += lightColor * microfacet * nDotL;
  color *= mix(0.76, 1.0, clamp(vVoxelLight, 0.0, 1.0));
  color *= mix(vec3(1.0), surfaceTexture.rgb, isGlass ? 0.035 : 0.16);
  FragColor = vec4(color * vColor, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createWaterShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 3) in vec2 aWaveData;
out vec3 vWorldPos;
out float vWaveExposure;
out float vShoreDistance;
out float vSurfaceLevel;
uniform mat4 uProjection;
uniform mat4 uView;
uniform float waterLevel;
uniform vec3 cascadeSizes;
uniform vec3 displacementWeights;
uniform float openWaterWaveBoost;
uniform sampler2D displacementMap0;
uniform sampler2D displacementMap1;
uniform sampler2D displacementMap2;

void main() {
  vec3 basePosition = vec3(aPos.x, aPos.y, aPos.z);
  vSurfaceLevel = aPos.y;
  // Wave fetch and shoreline damping are baked from continuous world-space
  // terrain signals. Unlike screen-depth probes these values cannot change as
  // the camera turns or as an occluder crosses the projected sample position.
  float exposure = clamp(aWaveData.x, 0.0, 1.0);
  float shoreDistance = clamp(aWaveData.y, 0.0, 1.0);

  // Short waves survive in enclosed water, while swell needs a long open fetch.
  // The final boost makes fully open ocean the strongest water in the scene.
  vec3 bodyScale = vec3(
    mix(0.24, 1.0, exposure),
    mix(0.08, 1.0, exposure * exposure),
    mix(0.015, 1.0, exposure * exposure * exposure)
  );
  bodyScale *= mix(1.0, openWaterWaveBoost, smoothstep(0.72, 1.0, exposure));
  bodyScale *= mix(0.025, 1.0, shoreDistance);

  vec3 displacement = texture(displacementMap0, basePosition.xz / cascadeSizes.x + vec2(0.17, 0.61)).rgb * displacementWeights.x * bodyScale.x;
  displacement += texture(displacementMap1, basePosition.xz / cascadeSizes.y + vec2(0.73, 0.29)).rgb * displacementWeights.y * bodyScale.y;
  displacement += texture(displacementMap2, basePosition.xz / cascadeSizes.z + vec2(0.41, 0.83)).rgb * displacementWeights.z * bodyScale.z;
  vec3 worldPos = basePosition + displacement;
  vWorldPos = worldPos;
  vWaveExposure = exposure;
  vShoreDistance = shoreDistance;
  gl_Position = uProjection * uView * vec4(worldPos, 1.0);
}
]]

  local fragSource = [[
#version 460 core
in vec3 vWorldPos;
in float vWaveExposure;
in float vShoreDistance;
in float vSurfaceLevel;
out vec4 FragColor;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 viewPos;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform vec3 lightColor;
uniform vec3 skyZenithColor;
uniform vec3 cascadeSizes;
uniform vec3 normalWeights;
uniform vec2 viewportSize;
uniform vec2 clipPlanes;
uniform float waterLevel;
uniform float time;
uniform float refractionStrength;
uniform float openWaterWaveBoost;
uniform vec3 absorption;
uniform sampler2D normalMap0;
uniform sampler2D normalMap1;
uniform sampler2D normalMap2;
uniform sampler2D sceneColor;
uniform sampler2D sceneDepth;
uniform sampler2D cloudShadowMap;
uniform vec4 cloudShadow;    // xy = sheet origin in world, z = 1 / sheet span, w = cloud base
uniform float cloudShadowStrength;

const float PI = 3.14159265359;

float linearDepth(float rawDepth) {
  float z = rawDepth * 2.0 - 1.0;
  return (2.0 * clipPlanes.x * clipPlanes.y) /
    (clipPlanes.y + clipPlanes.x - z * (clipPlanes.y - clipPlanes.x));
}

float edgeFade(vec2 uv) {
  vec2 edge = min(uv, 1.0 - uv);
  return smoothstep(0.0, 0.08, min(edge.x, edge.y));
}

vec3 traceReflection(vec3 origin, vec3 direction, out float confidence) {
  vec3 samplePosition = origin + direction * 0.45;
  float travel = 0.55;
  vec2 lastUv = vec2(-1.0);
  confidence = 0.0;

  for (int stepIndex = 0; stepIndex < 24; ++stepIndex) {
    samplePosition += direction * travel;
    travel *= 1.19;
    vec4 clip = uProjection * uView * vec4(samplePosition, 1.0);
    if (clip.w <= 0.0) break;
    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
    if (any(lessThanEqual(uv, vec2(0.002))) || any(greaterThanEqual(uv, vec2(0.998)))) break;
    lastUv = uv;

    float rawSceneDepth = texture(sceneDepth, uv).r;
    if (rawSceneDepth < 0.9998) {
      float rayDepth = -(uView * vec4(samplePosition, 1.0)).z;
      float surfaceDepth = linearDepth(rawSceneDepth);
      float separation = rayDepth - surfaceDepth;
      if (separation > -0.12 && separation < max(0.75, travel * 0.65)) {
        confidence = edgeFade(uv) * (1.0 - float(stepIndex) / 32.0);
        return texture(sceneColor, uv).rgb;
      }
    }
  }

  // A reflected sky ray has no depth hit. Its final screen projection still
  // provides the correct local sky/cloud colour when it remains on screen.
  if (lastUv.x >= 0.0) {
    confidence = edgeFade(lastUv) * 0.58;
    return texture(sceneColor, lastUv).rgb;
  }
  return vec3(0.0);
}

float distributionGGX(float nDotH, float roughness) {
  float a2 = roughness * roughness;
  a2 *= a2;
  float d = nDotH * nDotH * (a2 - 1.0) + 1.0;
  return a2 / max(PI * d * d, 1.0e-5);
}

float geometrySmith(float nDotV, float nDotL, float roughness) {
  float k = (roughness + 1.0);
  k = k * k * 0.125;
  float gv = nDotV / mix(nDotV, 1.0, k);
  float gl = nDotL / mix(nDotL, 1.0, k);
  return gv * gl;
}

void main() {
  vec4 gradient0 = texture(normalMap0, vWorldPos.xz / cascadeSizes.x + vec2(0.17, 0.61));
  vec4 gradient1 = texture(normalMap1, vWorldPos.xz / cascadeSizes.y + vec2(0.73, 0.29));
  vec4 gradient2 = texture(normalMap2, vWorldPos.xz / cascadeSizes.z + vec2(0.41, 0.83));

  float exposure = clamp(vWaveExposure, 0.0, 1.0);
  float normalBoost = mix(1.0, openWaterWaveBoost, smoothstep(0.72, 1.0, exposure));
  vec3 bodyScale = vec3(
    mix(0.30, 1.0, exposure),
    mix(0.12, 1.0, exposure * exposure),
    mix(0.02, 1.0, exposure * exposure * exposure)
  ) * normalBoost;
  bodyScale *= mix(0.18, 1.0, vShoreDistance);

  vec2 slope = gradient0.xz / max(gradient0.y, 0.18) * normalWeights.x * bodyScale.x;
  slope += gradient1.xz / max(gradient1.y, 0.18) * normalWeights.y * bodyScale.y;
  slope += gradient2.xz / max(gradient2.y, 0.18) * normalWeights.z * bodyScale.z;

  // Short directional ripples fill the frequency gap below the smallest FFT
  // cascade. Keeping these in the normal only avoids geometric shimmer.
  vec2 p = vWorldPos.xz;
  vec2 d0 = normalize(vec2(0.82, 0.57));
  vec2 d1 = normalize(vec2(-0.31, 0.95));
  vec2 d2 = normalize(vec2(0.98, -0.18));
  // Even a sheltered river or lake remains alive with wind-driven capillary
  // ripples; openness only increases their amplitude slightly.
  float rippleScale = mix(0.72, 1.12, exposure) * mix(0.55, 1.0, vShoreDistance);
  slope += d0 * cos(dot(p, d0) * 2.3 + time * 2.1) * 0.030 * rippleScale;
  slope += d1 * cos(dot(p, d1) * 3.7 + time * 2.8) * 0.018 * rippleScale;
  slope += d2 * cos(dot(p, d2) * 5.1 + time * 3.6) * 0.010 * rippleScale;

  vec3 interfaceNormal = normalize(vec3(slope.x, 1.0, slope.y));
  bool underwater = viewPos.y < vSurfaceLevel;
  vec3 viewDir = normalize(viewPos - vWorldPos);
  vec3 normal = interfaceNormal;
  if (dot(normal, viewDir) < 0.0) normal = -normal;
  float nDotV = max(dot(normal, viewDir), 0.001);
  float fresnel = 0.0200187 + (1.0 - 0.0200187) * pow(1.0 - nDotV, 5.0);

  // From water to air, rays beyond 48.6 degrees cannot leave the water and
  // reflect internally. The animated interface normal bends the critical cone,
  // producing the moving circular boundary of Snell's window without a mask.
  if (underwater) {
    const float WATER_IOR = 1.333;
    float criticalCosine = sqrt(1.0 - 1.0 / (WATER_IOR * WATER_IOR));
    float snellWindow = smoothstep(criticalCosine - 0.022, criticalCosine + 0.022, nDotV);
    fresnel = mix(1.0, fresnel, snellWindow);
  }

  vec2 screenUv = gl_FragCoord.xy / viewportSize;
  float waterViewDepth = linearDepth(gl_FragCoord.z);
  float rawBackgroundDepth = texture(sceneDepth, screenUv).r;
  float backgroundDepth = linearDepth(rawBackgroundDepth);
  float waterThickness = rawBackgroundDepth >= 0.9998 ? 48.0 : max(backgroundDepth - waterViewDepth, 0.0);
  if (underwater) waterThickness = length(viewPos - vWorldPos);

  vec2 distortedUv = screenUv + normal.xz * refractionStrength *
    (0.22 + min(waterThickness * 0.10, 1.0));
  distortedUv = clamp(distortedUv, vec2(0.002), vec2(0.998));
  float distortedDepth = linearDepth(texture(sceneDepth, distortedUv).r);
  if (distortedDepth < waterViewDepth + 0.05) distortedUv = screenUv;

  vec3 transmittedScene = texture(sceneColor, distortedUv).rgb;
  vec3 transmittance = exp(-absorption * min(waterThickness, 48.0));
  vec3 waterScatter = mix(vec3(0.008, 0.075, 0.105), vec3(0.015, 0.235, 0.270),
    clamp(sunDir.y * 0.7 + 0.35, 0.0, 1.0));
  vec3 refracted = transmittedScene * transmittance + waterScatter * (1.0 - transmittance);

  vec3 reflectionDirection = reflect(-viewDir, normal);
  float horizon = pow(1.0 - clamp(reflectionDirection.y, 0.0, 1.0), 2.0);
  vec3 skyFallback = mix(skyZenithColor, fogColor, horizon);
  float reflectionConfidence = 0.0;
  vec3 screenReflection = traceReflection(vWorldPos + normal * 0.12, reflectionDirection, reflectionConfidence);
  vec3 reflected = mix(skyFallback, screenReflection, reflectionConfidence);
  if (underwater) {
    vec3 internalReflection = mix(vec3(0.012, 0.085, 0.135), waterScatter, 0.62);
    reflected = mix(internalReflection, screenReflection, reflectionConfidence);
  }

  float jacobian = min(gradient0.a, min(gradient1.a, gradient2.a));
  float foldingFoam = (1.0 - smoothstep(0.18, 0.72, jacobian)) *
    smoothstep(0.48, 0.90, exposure);
  float shoreFoam = (1.0 - smoothstep(0.18, 1.65, waterThickness)) *
    step(rawBackgroundDepth, 0.9998);
  float foam = clamp(foldingFoam * 0.82 + shoreFoam * 0.48, 0.0, 1.0);

  vec3 lightDirection = normalize(sunDir);
  vec3 halfVector = normalize(viewDir + lightDirection);
  float nDotL = max(dot(normal, lightDirection), 0.0);
  float nDotH = max(dot(normal, halfVector), 0.0);
  float roughness = mix(0.065, 0.18, foam);
  float directSpecular = distributionGGX(nDotH, roughness) *
    geometrySmith(nDotV, nDotL, roughness) * fresnel /
    max(4.0 * nDotV * nDotL, 0.01);

  // The sun glitter on open water is the most obvious thing a passing cloud
  // takes away, and the terrain under the same cloud has already lost its
  // direct light. Reading the same mask the same way keeps the shadow
  // continuous where the water meets the shore.
  float cloudShade = 1.0;
  if (cloudShadowStrength > 0.0) {
    float elevation = smoothstep(0.05, 0.25, lightDirection.y);
    float travel = (cloudShadow.w - vWorldPos.y) / max(lightDirection.y, 1e-3);
    if (elevation > 0.0 && travel > 0.0) {
      vec2 hit = vWorldPos.xz + lightDirection.xz * travel;
      float coverage = texture(cloudShadowMap, (hit - cloudShadow.xy) * cloudShadow.z).r;
      cloudShade = 1.0 - coverage * cloudShadowStrength * elevation;
    }
  }

  vec3 color = mix(refracted, reflected, fresnel);
  color += lightColor * directSpecular * nDotL * 2.2 * cloudShade;
  color = mix(color, vec3(0.72, 0.82, 0.84) * max(lightColor, vec3(0.35)), foam * 0.72);
  FragColor = vec4(color, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function oceanShaderSource(source, resolution)
  return source
    :gsub("@RESOLUTION@", tostring(resolution))
    :gsub("@HALF_RESOLUTION@", tostring(math.floor(resolution / 2)))
end

function effects.createOceanSimulation(settings)
  settings = settings or {}
  local resolution = settings.fftResolution or 256
  local power = 1
  local stages = 0
  while power < resolution do
    power = power * 2
    stages = stages + 1
  end
  if power ~= resolution or resolution < 16 or resolution > 1024 then
    error("Water FFT resolution must be a power of two between 16 and 1024")
  end

  local oceanSize = settings.fftOceanSize or 256.0
  local windSpeed = settings.windSpeed or 14.142135
  local windAngle = math.rad(settings.windAngleDegrees or 45.0)
  local windX = math.cos(windAngle) * windSpeed
  local windY = math.sin(windAngle) * windSpeed
  local textureIds = ffi.new("GLuint[6]")
  gl.glGenTextures(6, textureIds)

  -- h0 carries the random complex Gaussian field. Phase therefore begins at
  -- zero and advances only by the physical dispersion relation.
  local phaseData = ffi.new("float[?]", resolution * resolution)

  local function initializeTexture(index, internalFormat, format, data, filter)
    gl.glBindTexture(GL_TEXTURE_2D, textureIds[index])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, resolution, resolution, 0, format, GL_FLOAT, data)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
  end

  initializeTexture(0, GL_RG32F, GL_RG, nil, GL_NEAREST)
  initializeTexture(1, GL_R32F, GL_RED, phaseData, GL_NEAREST)
  initializeTexture(2, GL_R32F, GL_RED, nil, GL_NEAREST)
  initializeTexture(3, GL_RGBA32F, GL_RGBA, nil, GL_LINEAR)
  initializeTexture(4, GL_RGBA32F, GL_RGBA, nil, GL_LINEAR)
  initializeTexture(5, GL_RGBA32F, GL_RGBA, nil, GL_LINEAR)
  gl.glBindTexture(GL_TEXTURE_2D, 0)

  local initialSource = oceanShaderSource([[
#version 460 core
layout (local_size_x = 16, local_size_y = 16) in;
layout (binding = 0, rg32f) uniform writeonly image2D initialSpectrum;
uniform float oceanSize;
uniform vec2 wind;
const int RESOLUTION = @RESOLUTION@;
const float PI = 3.14159265359;
const float G = 9.81;
const float KM = 370.0;
const float CM = 0.23;
float square(float x) { return x * x; }
float omega(float k) { return sqrt(G * k * (1.0 + (k * k) / (KM * KM))); }
uint hashUint(uint x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  return x ^ (x >> 16);
}
float random01(uvec2 p, uint stream) {
  uint h = hashUint(p.x + hashUint(p.y + stream * 0x9e3779b9u));
  return (float(h) + 0.5) / 4294967296.0;
}
vec2 gaussian(uvec2 p) {
  float u1 = max(random01(p, 1u), 1.0e-7);
  float u2 = random01(p, 2u);
  float radius = sqrt(-2.0 * log(u1));
  float angle = 2.0 * PI * u2;
  return radius * vec2(cos(angle), sin(angle));
}
void main() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(coord, ivec2(RESOLUTION)))) return;
  float n = coord.x < RESOLUTION / 2 ? float(coord.x) : float(coord.x - RESOLUTION);
  float m = coord.y < RESOLUTION / 2 ? float(coord.y) : float(coord.y - RESOLUTION);
  vec2 waveVector = 2.0 * PI * vec2(n, m) / oceanSize;
  float k = length(waveVector);
  if (k < 1.0e-6) { imageStore(initialSpectrum, coord, vec4(0.0)); return; }

  float U10 = max(length(wind), 0.1);
  float Omega = 0.84;
  float kp = G * square(Omega / U10);
  float c = omega(k) / k;
  float cp = omega(kp) / kp;
  float Lpm = exp(-1.25 * square(kp / k));
  float sigma = 0.08 * (1.0 + 4.0 * pow(Omega, -3.0));
  float Gamma = exp(-square(sqrt(k / kp) - 1.0) / (2.0 * square(sigma)));
  float Fp = Lpm * pow(1.7, Gamma) * exp(-Omega / sqrt(10.0) * (sqrt(k / kp) - 1.0));
  float Bl = 0.5 * (0.006 * sqrt(Omega)) * cp / c * Fp;
  float z0 = 0.000037 * square(U10) / G * pow(U10 / cp, 0.9);
  float uStar = 0.41 * U10 / log(10.0 / max(z0, 1.0e-6));
  float alphaM = 0.01 * (uStar < CM ? 1.0 + log(max(uStar / CM, 1.0e-6)) : 1.0 + 3.0 * log(uStar / CM));
  float Bh = 0.5 * alphaM * CM / c * exp(-0.25 * square(k / KM - 1.0)) * Lpm;
  float delta = tanh(log(2.0) / 4.0 + 4.0 * pow(c / cp, 2.5) + 0.13 * uStar / CM * pow(CM / c, 2.5));
  float cosPhi = dot(normalize(wind), normalize(waveVector));
  float spectrum = (Bl + Bh) * (1.0 + delta * (2.0 * cosPhi * cosPhi - 1.0)) /
    (2.0 * PI * pow(k, 4.0));
  float dk = 2.0 * PI / oceanSize;
  vec2 h0 = gaussian(uvec2(coord)) * sqrt(max(spectrum, 0.0) * 0.5) * dk;
  imageStore(initialSpectrum, coord, vec4(h0, 0.0, 0.0));
}
]], resolution)

  local phaseSource = oceanShaderSource([[
#version 460 core
layout (local_size_x = 16, local_size_y = 16) in;
layout (binding = 0, r32f) uniform readonly image2D phaseInput;
layout (binding = 1, r32f) uniform writeonly image2D phaseOutput;
uniform float deltaTime;
uniform float oceanSize;
const int RESOLUTION = @RESOLUTION@;
const float PI = 3.14159265359;
const float G = 9.81;
const float KM = 370.0;
float omega(float k) { return sqrt(G * k * (1.0 + (k * k) / (KM * KM))); }
void main() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(coord, ivec2(RESOLUTION)))) return;
  float n = coord.x < RESOLUTION / 2 ? float(coord.x) : float(coord.x - RESOLUTION);
  float m = coord.y < RESOLUTION / 2 ? float(coord.y) : float(coord.y - RESOLUTION);
  float k = length(2.0 * PI * vec2(n, m) / oceanSize);
  float phase = mod(imageLoad(phaseInput, coord).r + omega(k) * deltaTime, 2.0 * PI);
  imageStore(phaseOutput, coord, vec4(phase, 0.0, 0.0, 0.0));
}
]], resolution)

  local spectrumSource = oceanShaderSource([[
#version 460 core
layout (local_size_x = 16, local_size_y = 16) in;
layout (binding = 0, r32f) uniform readonly image2D phases;
layout (binding = 1, rg32f) uniform readonly image2D initialSpectrum;
layout (binding = 2, rgba32f) uniform writeonly image2D spectrumOutput;
uniform float oceanSize;
uniform float choppiness;
const int RESOLUTION = @RESOLUTION@;
const float PI = 3.14159265359;
vec2 complexMultiply(vec2 a, vec2 b) { return vec2(a.x*b.x-a.y*b.y, a.y*b.x+a.x*b.y); }
vec2 multiplyByI(vec2 z) { return vec2(-z.y, z.x); }
void main() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(coord, ivec2(RESOLUTION)))) return;
  float n = coord.x < RESOLUTION / 2 ? float(coord.x) : float(coord.x - RESOLUTION);
  float m = coord.y < RESOLUTION / 2 ? float(coord.y) : float(coord.y - RESOLUTION);
  vec2 waveVector = 2.0 * PI * vec2(n, m) / oceanSize;
  float k = length(waveVector);
  if (k < 1.0e-6) { imageStore(spectrumOutput, coord, vec4(0.0)); return; }
  float phase = imageLoad(phases, coord).r;
  vec2 phaseVector = vec2(cos(phase), sin(phase));
  ivec2 mirror = (ivec2(RESOLUTION) - coord) % RESOLUTION;
  vec2 h0 = imageLoad(initialSpectrum, coord).rg;
  vec2 mirroredH0 = imageLoad(initialSpectrum, mirror).rg;
  vec2 h0Star = vec2(mirroredH0.x, -mirroredH0.y);
  vec2 h = complexMultiply(h0, phaseVector) + complexMultiply(h0Star, vec2(phaseVector.x, -phaseVector.y));
  vec2 hX = -multiplyByI(h * waveVector.x / k) * choppiness;
  vec2 hZ = -multiplyByI(h * waveVector.y / k) * choppiness;
  imageStore(spectrumOutput, coord, vec4(hX + multiplyByI(h), hZ));
}
]], resolution)

  local fftSource = oceanShaderSource([[
#version 460 core
layout (local_size_x = @HALF_RESOLUTION@) in;
layout (binding = 0, rgba32f) uniform readonly image2D fftInput;
layout (binding = 1, rgba32f) uniform writeonly image2D fftOutput;
uniform int subsequenceCount;
uniform int vertical;
const int RESOLUTION = @RESOLUTION@;
const float PI = 3.14159265358979323846;
vec2 complexMultiply(vec2 a, vec2 b) { return vec2(a.x*b.x-a.y*b.y, a.y*b.x+a.x*b.y); }
vec4 butterfly(vec2 a, vec2 b, vec2 twiddle) {
  vec2 t = complexMultiply(twiddle, b);
  return vec4(a + t, a - t);
}
void main() {
  int lane = int(gl_LocalInvocationID.x);
  int line = int(gl_WorkGroupID.x);
  ivec2 aCoord = vertical == 1 ? ivec2(line, lane) : ivec2(lane, line);
  ivec2 bCoord = vertical == 1 ? ivec2(line, lane + RESOLUTION / 2) : ivec2(lane + RESOLUTION / 2, line);
  int inIndex = lane & (subsequenceCount - 1);
  int outIndex = ((lane - inIndex) << 1) + inIndex;
  float angle = -PI * float(inIndex) / float(subsequenceCount);
  vec2 twiddle = vec2(cos(angle), sin(angle));
  vec4 a = imageLoad(fftInput, aCoord);
  vec4 b = imageLoad(fftInput, bCoord);
  vec4 result0 = butterfly(a.xy, b.xy, twiddle);
  vec4 result1 = butterfly(a.zw, b.zw, twiddle);
  ivec2 out0 = vertical == 1 ? ivec2(line, outIndex) : ivec2(outIndex, line);
  ivec2 out1 = vertical == 1 ? ivec2(line, outIndex + subsequenceCount) : ivec2(outIndex + subsequenceCount, line);
  imageStore(fftOutput, out0, vec4(result0.xy, result1.xy));
  imageStore(fftOutput, out1, vec4(result0.zw, result1.zw));
}
]], resolution)

  local normalSource = oceanShaderSource([[
#version 460 core
layout (local_size_x = 16, local_size_y = 16) in;
layout (binding = 0, rgba32f) uniform readonly image2D displacementMap;
layout (binding = 1, rgba32f) uniform writeonly image2D normalMap;
uniform float oceanSize;
uniform float displacementScale;
const int RESOLUTION = @RESOLUTION@;
ivec2 wrapped(ivec2 p) { return (p + RESOLUTION) % RESOLUTION; }
vec3 displacement(ivec2 p) { return imageLoad(displacementMap, wrapped(p)).xyz * displacementScale; }
void main() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(coord, ivec2(RESOLUTION)))) return;
  float texelSize = oceanSize / float(RESOLUTION);
  vec3 center = displacement(coord);
  vec3 dispRight = displacement(coord + ivec2(1, 0));
  vec3 dispLeft = displacement(coord - ivec2(1, 0));
  vec3 dispTop = displacement(coord - ivec2(0, 1));
  vec3 dispBottom = displacement(coord + ivec2(0, 1));
  vec3 right = vec3(texelSize, 0.0, 0.0) + dispRight - center;
  vec3 left = vec3(-texelSize, 0.0, 0.0) + dispLeft - center;
  vec3 top = vec3(0.0, 0.0, -texelSize) + dispTop - center;
  vec3 bottom = vec3(0.0, 0.0, texelSize) + dispBottom - center;
  vec3 normal = normalize(cross(right, top) + cross(top, left) + cross(left, bottom) + cross(bottom, right));
  vec2 dDx = (dispRight.xz - dispLeft.xz) / (2.0 * texelSize);
  vec2 dDz = (dispBottom.xz - dispTop.xz) / (2.0 * texelSize);
  float jacobian = (1.0 + dDx.x) * (1.0 + dDz.y) - dDx.y * dDz.x;
  imageStore(normalMap, coord, vec4(normal, jacobian));
}
]], resolution)

  local programs = {
    initial = shaderModule.fromComputeSource(initialSource),
    phase = shaderModule.fromComputeSource(phaseSource),
    spectrum = shaderModule.fromComputeSource(spectrumSource),
    fft = shaderModule.fromComputeSource(fftSource),
    normal = shaderModule.fromComputeSource(normalSource)
  }
  local locations = {
    initial = {
      oceanSize = gl.glGetUniformLocation(programs.initial, "oceanSize"),
      wind = gl.glGetUniformLocation(programs.initial, "wind")
    },
    phase = {
      deltaTime = gl.glGetUniformLocation(programs.phase, "deltaTime"),
      oceanSize = gl.glGetUniformLocation(programs.phase, "oceanSize")
    },
    spectrum = {
      oceanSize = gl.glGetUniformLocation(programs.spectrum, "oceanSize"),
      choppiness = gl.glGetUniformLocation(programs.spectrum, "choppiness")
    },
    fft = {
      subsequenceCount = gl.glGetUniformLocation(programs.fft, "subsequenceCount"),
      vertical = gl.glGetUniformLocation(programs.fft, "vertical")
    },
    normal = {
      oceanSize = gl.glGetUniformLocation(programs.normal, "oceanSize"),
      displacementScale = gl.glGetUniformLocation(programs.normal, "displacementScale")
    }
  }

  gl.glUseProgram(programs.initial)
  gl.glUniform1f(locations.initial.oceanSize, oceanSize)
  gl.glUniform2f(locations.initial.wind, windX, windY)
  gl.glBindImageTexture(0, textureIds[0], 0, 0, 0, GL_WRITE_ONLY, GL_RG32F)
  gl.glDispatchCompute(math.ceil(resolution / 16), math.ceil(resolution / 16), 1)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)

  return {
    resolution = resolution,
    stages = stages,
    oceanSize = oceanSize,
    displacementScale = settings.displacementScale or (resolution / oceanSize),
    choppiness = settings.choppiness or 0.88,
    phaseIndex = 1,
    textures = textureIds,
    initialSpectrum = textureIds[0],
    phaseTextures = {textureIds[1], textureIds[2]},
    spectrumTexture = textureIds[3],
    tempTexture = textureIds[4],
    normalTexture = textureIds[5],
    displacementTexture = textureIds[3],
    cascadeSizes = settings.cascadeSizes or {36.0, 144.0, 576.0},
    displacementWeights = settings.cascadeDisplacementWeights or {0.075, 0.16, 0.40},
    normalWeights = settings.cascadeNormalWeights or {0.48, 0.29, 0.16},
    openWaterWaveBoost = settings.openWaterWaveBoost or 1.08,
    refractionStrength = settings.refractionStrength or 0.014,
    absorption = settings.absorption or {0.16, 0.055, 0.026},
    programs = programs,
    locations = locations
  }
end

function effects.updateOceanSimulation(ocean, deltaTime)
  local resolution = ocean.resolution
  local programs = ocean.programs
  local locations = ocean.locations
  local readPhaseIndex = ocean.phaseIndex
  local writePhaseIndex = readPhaseIndex == 1 and 2 or 1

  gl.glUseProgram(programs.phase)
  gl.glUniform1f(locations.phase.deltaTime, math.min(deltaTime or 0.0, 0.05))
  gl.glUniform1f(locations.phase.oceanSize, ocean.oceanSize)
  gl.glBindImageTexture(0, ocean.phaseTextures[readPhaseIndex], 0, 0, 0, GL_READ_ONLY, GL_R32F)
  gl.glBindImageTexture(1, ocean.phaseTextures[writePhaseIndex], 0, 0, 0, GL_WRITE_ONLY, GL_R32F)
  gl.glDispatchCompute(math.ceil(resolution / 16), math.ceil(resolution / 16), 1)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)
  ocean.phaseIndex = writePhaseIndex

  gl.glUseProgram(programs.spectrum)
  gl.glUniform1f(locations.spectrum.oceanSize, ocean.oceanSize)
  gl.glUniform1f(locations.spectrum.choppiness, ocean.choppiness)
  gl.glBindImageTexture(0, ocean.phaseTextures[writePhaseIndex], 0, 0, 0, GL_READ_ONLY, GL_R32F)
  gl.glBindImageTexture(1, ocean.initialSpectrum, 0, 0, 0, GL_READ_ONLY, GL_RG32F)
  gl.glBindImageTexture(2, ocean.spectrumTexture, 0, 0, 0, GL_WRITE_ONLY, GL_RGBA32F)
  gl.glDispatchCompute(math.ceil(resolution / 16), math.ceil(resolution / 16), 1)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)

  gl.glUseProgram(programs.fft)
  local inputTexture = ocean.spectrumTexture
  local outputTexture = ocean.tempTexture
  for direction = 0, 1 do
    gl.glUniform1i(locations.fft.vertical, direction)
    local subsequenceCount = 1
    for _ = 1, ocean.stages do
      gl.glUniform1i(locations.fft.subsequenceCount, subsequenceCount)
      gl.glBindImageTexture(0, inputTexture, 0, 0, 0, GL_READ_ONLY, GL_RGBA32F)
      gl.glBindImageTexture(1, outputTexture, 0, 0, 0, GL_WRITE_ONLY, GL_RGBA32F)
      gl.glDispatchCompute(resolution, 1, 1)
      gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)
      inputTexture, outputTexture = outputTexture, inputTexture
      subsequenceCount = subsequenceCount * 2
    end
  end
  ocean.displacementTexture = inputTexture

  gl.glUseProgram(programs.normal)
  gl.glUniform1f(locations.normal.oceanSize, ocean.oceanSize)
  gl.glUniform1f(locations.normal.displacementScale, ocean.displacementScale)
  gl.glBindImageTexture(0, ocean.displacementTexture, 0, 0, 0, GL_READ_ONLY, GL_RGBA32F)
  gl.glBindImageTexture(1, ocean.normalTexture, 0, 0, 0, GL_WRITE_ONLY, GL_RGBA32F)
  gl.glDispatchCompute(math.ceil(resolution / 16), math.ceil(resolution / 16), 1)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT + GL_TEXTURE_FETCH_BARRIER_BIT)
  gl.glBindTexture(GL_TEXTURE_2D, ocean.normalTexture)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
  gl.glGenerateMipmap(GL_TEXTURE_2D)
  gl.glBindTexture(GL_TEXTURE_2D, 0)
  gl.glMemoryBarrier(GL_TEXTURE_FETCH_BARRIER_BIT)
end

function effects.releaseOceanSimulation(ocean)
  if not ocean then return end
  if ocean.textures then gl.glDeleteTextures(6, ocean.textures) end
  if ocean.programs then
    for _, program in pairs(ocean.programs) do
      gl.glDeleteProgram(program)
    end
  end
end

function effects.createVolumetricFog(gridWidth, gridHeight, gridDepth)
  local textures = ffi.new("GLuint[2]")
  gl.glGenTextures(2, textures)

  for i = 0, 1 do
    gl.glBindTexture(GL_TEXTURE_3D, textures[i])
    gl.glTexStorage3D(GL_TEXTURE_3D, 1, GL_RGBA16F, gridWidth, gridHeight, gridDepth)
    gl.glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    gl.glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    gl.glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)
  end
  gl.glBindTexture(GL_TEXTURE_3D, 0)

  return {
    width = gridWidth,
    height = gridHeight,
    depth = gridDepth,
    injectionTexture = textures[0],
    integratedTexture = textures[1],
    textures = textures
  }
end

function effects.createVolumetricFogShaders(gridWidth, gridHeight, gridDepth)
  local injectionSource = [[
#version 460 core
layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout (binding = 0, rgba16f) uniform writeonly image3D injectionVolume;

uniform sampler2D shadowMap;
uniform vec3 cameraPosition;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 cameraProjection;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform vec3 skyZenithColor;
uniform vec3 lightColor;
uniform vec3 fogParams;        // start, end, maximum opacity
uniform vec3 atmosphereParams; // sea-level density, height falloff, horizon density
uniform vec3 volumeParams;     // near, far, sunlight scattering strength
uniform float baseHeight;
uniform mat4 lightSpaceMatrix;

const ivec3 GRID_SIZE = ivec3(@GRID_X@, @GRID_Y@, @GRID_Z@);
const float PI = 3.14159265359;

float sliceDistance(float slice) {
  return volumeParams.x * pow(volumeParams.y / volumeParams.x, slice / float(GRID_SIZE.z));
}

float rayleighPhase(float mu) {
  return 3.0 * (1.0 + mu * mu) / (16.0 * PI);
}

float miePhase(float mu, float g) {
  float g2 = g * g;
  float denominator = max(pow(1.0 + g2 - 2.0 * g * mu, 1.5), 1.0e-3);
  return 3.0 * (1.0 - g2) * (1.0 + mu * mu) /
    (8.0 * PI * (2.0 + g2) * denominator);
}

float shadowVisibility(vec3 worldPosition) {
  vec4 lightPosition = lightSpaceMatrix * vec4(worldPosition, 1.0);
  vec3 projected = lightPosition.xyz / max(lightPosition.w, 1.0e-5);
  projected = projected * 0.5 + 0.5;

  if (projected.z <= 0.0 || projected.z >= 1.0 ||
      any(lessThan(projected.xy, vec2(0.0))) || any(greaterThan(projected.xy, vec2(1.0)))) {
    return 1.0;
  }

  float closestDepth = texture(shadowMap, projected.xy).r;
  return projected.z - 0.0018 <= closestDepth ? 1.0 : 0.0;
}

vec3 encodeFogLight(vec3 color) {
  return pow(clamp(color, vec3(0.0), vec3(1.3)), vec3(1.0 / 2.2));
}

void main() {
  ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);
  if (any(greaterThanEqual(coord, GRID_SIZE))) return;

  vec2 uv = (vec2(coord.xy) + 0.5) / vec2(GRID_SIZE.xy);
  vec2 p = uv * 2.0 - 1.0;
  vec3 ray = normalize(
    cameraForward +
    cameraRight * p.x * cameraProjection.x +
    cameraUp * p.y * cameraProjection.y
  );
  float distance = sliceDistance(float(coord.z) + 0.5);
  vec3 worldPosition = cameraPosition + ray * distance;

  float targetTransmittance = max(1.0 - fogParams.z, 0.01);
  float distanceExtinction = -log(targetTransmittance) / max(fogParams.y - fogParams.x, 1.0);
  float altitude = max(worldPosition.y - baseHeight, 0.0);
  float extinction = atmosphereParams.x * exp(-altitude * atmosphereParams.y);
  if (distance > fogParams.x) extinction += distanceExtinction;

  float horizon = 1.0 - smoothstep(-0.08, 0.28, abs(ray.y));
  extinction += horizon * atmosphereParams.z / max(fogParams.y - fogParams.x, 1.0);

  float skyLift = smoothstep(-0.05, 0.70, ray.y) * 0.34;
  vec3 ambientFog = mix(fogColor, skyZenithColor, skyLift);
  float sunMu = dot(ray, normalize(sunDir));
  float daylight = smoothstep(-0.08, 0.20, sunDir.y);
  float phase = rayleighPhase(sunMu) * 0.65 + miePhase(sunMu, 0.76) * 0.42;
  vec3 directFog = lightColor * phase * volumeParams.z * daylight * shadowVisibility(worldPosition);
  vec3 scatteredLight = encodeFogLight(ambientFog + directFog);

  imageStore(injectionVolume, coord, vec4(scatteredLight * extinction, extinction));
}
]]

  local integrationSource = [[
#version 460 core
layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout (binding = 0, rgba16f) uniform writeonly image3D integratedVolume;
uniform sampler3D injectionVolume;
uniform vec3 volumeParams; // near, far, unused

const ivec3 GRID_SIZE = ivec3(@GRID_X@, @GRID_Y@, @GRID_Z@);

float sliceBoundary(int slice) {
  return volumeParams.x * pow(volumeParams.y / volumeParams.x, float(slice) / float(GRID_SIZE.z));
}

void main() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  if (any(greaterThanEqual(coord, GRID_SIZE.xy))) return;

  vec3 accumulatedScattering = vec3(0.0);
  float transmittance = 1.0;

  for (int z = 0; z < GRID_SIZE.z; z++) {
    vec4 scatteringExtinction = texelFetch(injectionVolume, ivec3(coord, z), 0);
    float thickness = sliceBoundary(z + 1) - sliceBoundary(z);
    float extinction = scatteringExtinction.a;
    float sliceTransmittance = exp(-extinction * thickness);
    vec3 sliceIntegral = extinction > 1.0e-6
      ? scatteringExtinction.rgb * (1.0 - sliceTransmittance) / extinction
      : vec3(0.0);

    accumulatedScattering += sliceIntegral * transmittance;
    transmittance *= sliceTransmittance;
    imageStore(integratedVolume, ivec3(coord, z), vec4(accumulatedScattering, transmittance));
  }
}
]]

  local replacements = {
    ["@GRID_X@"] = tostring(gridWidth),
    ["@GRID_Y@"] = tostring(gridHeight),
    ["@GRID_Z@"] = tostring(gridDepth)
  }
  for token, value in pairs(replacements) do
    injectionSource = injectionSource:gsub(token, value)
    integrationSource = integrationSource:gsub(token, value)
  end

  local injection = shaderModule.fromComputeSource(injectionSource)
  local integration = shaderModule.fromComputeSource(integrationSource)
  return {
    injection = injection,
    integration = integration,
    injectionLocations = {
      shadowMap = gl.glGetUniformLocation(injection, "shadowMap"),
      cameraPosition = gl.glGetUniformLocation(injection, "cameraPosition"),
      cameraForward = gl.glGetUniformLocation(injection, "cameraForward"),
      cameraRight = gl.glGetUniformLocation(injection, "cameraRight"),
      cameraUp = gl.glGetUniformLocation(injection, "cameraUp"),
      cameraProjection = gl.glGetUniformLocation(injection, "cameraProjection"),
      sunDir = gl.glGetUniformLocation(injection, "sunDir"),
      fogColor = gl.glGetUniformLocation(injection, "fogColor"),
      skyZenithColor = gl.glGetUniformLocation(injection, "skyZenithColor"),
      lightColor = gl.glGetUniformLocation(injection, "lightColor"),
      fogParams = gl.glGetUniformLocation(injection, "fogParams"),
      atmosphereParams = gl.glGetUniformLocation(injection, "atmosphereParams"),
      volumeParams = gl.glGetUniformLocation(injection, "volumeParams"),
      baseHeight = gl.glGetUniformLocation(injection, "baseHeight"),
      lightSpaceMatrix = gl.glGetUniformLocation(injection, "lightSpaceMatrix")
    },
    integrationLocations = {
      injectionVolume = gl.glGetUniformLocation(integration, "injectionVolume"),
      volumeParams = gl.glGetUniformLocation(integration, "volumeParams")
    }
  }
end

function effects.createAtmospherePostShader()
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
uniform sampler2D sceneColor;
uniform sampler2D sceneDepth;
uniform sampler2D underwaterOverlay;
uniform sampler3D fogVolume;
uniform vec3 cameraPosition;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 cameraProjection;
uniform vec3 depthParams;
uniform vec3 volumeParams; // near, far, maximum opacity
uniform float localSkyVisibility;
uniform float blurAmount;
uniform float underwaterAmount;
uniform float time;
uniform sampler2D bloomTexture;
uniform sampler2D godRaysTexture;
uniform sampler2D eyeExposure;
uniform vec4 gradeParams;   // exposure, bloomStrength, saturation, contrast
uniform vec3 tonemapParams; // mode, knee, white
uniform float godRaysStrength;
uniform vec2 motionBlurVector;

// Exactly identity below `knee`, then compresses smoothly toward `white`.
// This is the operator that suits a retrofit: the scene was authored to look
// correct already, so the curve must not touch anything that was already in
// range -- it only has to handle the overbrights the HDR target now preserves.
vec3 rolloffHighlights(vec3 x, float knee, float white) {
  vec3 low = min(x, vec3(knee));
  vec3 high = max(x - knee, vec3(0.0));
  float range = max(white - knee, 1e-3);
  return low + range * (high / (high + range));
}

// Narkowicz's fitted ACES. Scene-referred: it expects linear input and adds
// considerable midtone contrast and saturation of its own. Available on
// request, but it is not the right default on top of already-graded content.
vec3 acesFilmic(vec3 x) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec3 gradeScene(vec3 color, vec3 bloom, vec3 godRays) {
  float adaptedExposure = texture(eyeExposure, vec2(0.5)).r;
  color = max(color + max(godRays, vec3(0.0)) * godRaysStrength, vec3(0.0)) *
    gradeParams.x * adaptedExposure;
  color += max(bloom, vec3(0.0)) * gradeParams.y;

  float mode = tonemapParams.x;
  if (mode > 1.5) {
    vec3 linear = pow(color, vec3(2.2));
    color = pow(acesFilmic(linear), vec3(1.0 / 2.2));
  } else if (mode > 0.5) {
    color = rolloffHighlights(color, tonemapParams.y, tonemapParams.z);
  }

  // Both of these are identity at 1.0, so neutral settings change nothing.
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, gradeParams.z);
  color = (color - 0.5) * gradeParams.w + 0.5;

  return clamp(color, 0.0, 1.0);
}

float linearDepth(float rawDepth) {
  float nearPlane = depthParams.x;
  float farPlane = depthParams.y;
  float z = rawDepth * 2.0 - 1.0;
  return (2.0 * nearPlane * farPlane) / (farPlane + nearPlane - z * (farPlane - nearPlane));
}

vec4 sampleIntegratedVolume(float distance) {
  float nearDistance = volumeParams.x;
  float farDistance = volumeParams.y;
  float volumeZ = log(clamp(distance, nearDistance, farDistance) / nearDistance) /
    log(farDistance / nearDistance);
  vec4 integrated = texture(fogVolume, vec3(vUv, volumeZ));

  // Preserve the authored maximum opacity even when height and distance layers
  // overlap. Scale in-scattering by the same amount to retain energy balance.
  float opacity = 1.0 - integrated.a;
  float cappedOpacity = min(opacity, volumeParams.z);
  float scale = opacity > 1.0e-5 ? cappedOpacity / opacity : 0.0;
  // The froxel volume describes the open atmosphere and cannot see voxel
  // walls. Suppress its in-scattering when the camera's own voxel cell has no
  // route to the sky; extinction remains so lit cave contents still fade with
  // distance without sealed air glowing on its own.
  float localVisibility = clamp(localSkyVisibility, 0.0, 1.0);
  return vec4(integrated.rgb * scale * localVisibility, 1.0 - cappedOpacity);
}

vec3 sampleMotionBlur(vec2 uv) {
  if (dot(motionBlurVector, motionBlurVector) < 1.0e-8) {
    return texture(sceneColor, uv).rgb;
  }

  float centerDepth = texture(sceneDepth, uv).r;
  vec3 sum = vec3(0.0);
  float totalWeight = 0.0;
  // Trail from the current sample toward the preceding camera pose. Raw depth
  // agreement prevents foreground silhouettes from smearing across the sky.
  for (int index = 0; index < 8; ++index) {
    float amount = float(index) / 7.0;
    vec2 sampleUv = clamp(uv + motionBlurVector * amount, vec2(0.001), vec2(0.999));
    float sampleDepth = texture(sceneDepth, sampleUv).r;
    float depthWeight = 1.0 / (1.0 + abs(sampleDepth - centerDepth) * 160.0);
    float shutterWeight = 1.0 - amount * 0.35;
    float weight = depthWeight * shutterWeight;
    sum += texture(sceneColor, sampleUv).rgb * weight;
    totalWeight += weight;
  }
  return sum / max(totalWeight, 1.0e-4);
}

void main() {
  vec2 texel = 1.0 / vec2(textureSize(sceneColor, 0));
  vec3 scene = sampleMotionBlur(vUv);
  if (blurAmount > 0.001) {
    vec2 radius = texel * blurAmount;
    scene = scene * 0.36;
    scene += texture(sceneColor, vUv + vec2(radius.x, 0.0)).rgb * 0.16;
    scene += texture(sceneColor, vUv - vec2(radius.x, 0.0)).rgb * 0.16;
    scene += texture(sceneColor, vUv + vec2(0.0, radius.y)).rgb * 0.16;
    scene += texture(sceneColor, vUv - vec2(0.0, radius.y)).rgb * 0.16;
  }
  float rawDepth = texture(sceneDepth, vUv).r;
  vec3 bloom = texture(bloomTexture, vUv).rgb;
  vec3 godRays = texture(godRaysTexture, vUv).rgb *
    clamp(localSkyVisibility, 0.0, 1.0);
  if (rawDepth >= 0.9999) {
    vec4 volume = sampleIntegratedVolume(volumeParams.y);
    vec3 skyColor = scene * volume.a + volume.rgb;
    skyColor = mix(skyColor, vec3(0.035, 0.180, 0.330), 0.72 * underwaterAmount);
    FragColor = vec4(gradeScene(skyColor, bloom, godRays), 1.0);
    return;
  }

  vec2 p = vUv * 2.0 - 1.0;
  vec3 ray = normalize(
    cameraForward +
    cameraRight * p.x * cameraProjection.x +
    cameraUp * p.y * cameraProjection.y
  );

  float forwardDot = max(dot(ray, normalize(cameraForward)), 0.035);
  float viewDepth = linearDepth(rawDepth);
  float distance = viewDepth / forwardDot;
  vec4 volume = sampleIntegratedVolume(distance);
  vec3 color = scene * volume.a + volume.rgb;

  if (underwaterAmount > 0.001) {
    vec2 overlayUv = fract(vUv * vec2(2.0, 1.35) + vec2(time * 0.012, -time * 0.007));
    vec4 overlay = texture(underwaterOverlay, overlayUv);
    float waterDistance = smoothstep(1.5, max(8.0, volumeParams.y * 0.45), distance);
    vec3 underwaterColor = vec3(0.035, 0.180, 0.330);
    color = mix(color, underwaterColor, (0.22 + waterDistance * 0.50) * underwaterAmount);
    color += (overlay.rgb - 0.5) * overlay.a * 0.18 * underwaterAmount;
  }

  FragColor = vec4(gradeScene(color, bloom, godRays), 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

-- Average metering for the eye-adaptation pass.
--
-- A flat average of the whole frame is only stable when the sky and the ground
-- are within a factor of two of each other, which is true of Earth and not of
-- Mars: a forward-scattering dust atmosphere runs from a clipped white aureole
-- around the sun to nearly black at the anti-solar horizon within one frame.
-- Averaged flat, that swings by more than an order of magnitude as the player
-- turns around, and the exposure slams between its two clamps.
--
-- Three things keep the metering stable:
--   * the sky is metered at a reduced weight, because it is a light source in
--     the frame rather than the subject of it;
--   * samples are centre-weighted, so what the player is looking at decides the
--     exposure and what is at the edge of vision only nudges it;
--   * each sample is clamped before it is averaged, so the sun disc -- which is
--     several times white on its own -- cannot carry the average by itself.
--
-- The response curve is a power law rather than a straight reciprocal. A pure
-- key/average law fully cancels the scene's own brightness, which is what makes
-- night look like an underexposed day; an exponent below one leaves dark scenes
-- dark and bright scenes bright while still tracking them.
function effects.createEyeAdaptationShader()
  local vertex = [[
#version 460 core
layout (location = 0) in vec3 aPos;
out vec2 vUv;
void main() {
  vUv = aPos.xy * 0.5 + 0.5;
  gl_Position = vec4(aPos.xy, 0.0, 1.0);
}
]]
  local fragment = [[
#version 460 core
in vec2 vUv;
out vec4 FragColor;
uniform sampler2D sceneColor;
uniform sampler2D sceneDepth;
uniform sampler2D previousExposure;
uniform vec4 adaptationParams;  // key, minimum, maximum, delta time
uniform vec2 adaptationSpeeds;  // brighten, darken
uniform vec4 meterParams;       // sky weight, centre bias, sample clamp, response exponent

const int SAMPLE_X = 24;
const int SAMPLE_Y = 14;

void main() {
  float logLuminance = 0.0;
  float totalWeight = 0.0;
  float sampleClamp = max(meterParams.z, 0.01);
  for (int y = 0; y < SAMPLE_Y; ++y) {
    for (int x = 0; x < SAMPLE_X; ++x) {
      vec2 uv = (vec2(x, y) + 0.5) / vec2(SAMPLE_X, SAMPLE_Y);
      vec3 color = max(textureLod(sceneColor, uv, 0.0).rgb, vec3(0.0));
      float luminance = min(dot(color, vec3(0.2126, 0.7152, 0.0722)), sampleClamp);

      // Radial falloff normalised so the frame corners sit at 1.0.
      vec2 offset = (uv - 0.5) * vec2(2.0, 2.0);
      float radius = min(length(offset) * 0.7071, 1.0);
      float weight = mix(1.0, max(meterParams.y, 0.0), radius * radius);

      // The far plane is sky. It still counts -- a bright sky should stop the
      // ground from being lifted to daylight -- but at a fraction of its area.
      float depth = textureLod(sceneDepth, uv, 0.0).r;
      weight *= depth >= 0.9999 ? clamp(meterParams.x, 0.0, 1.0) : 1.0;

      logLuminance += log(max(luminance, 1.0e-4)) * weight;
      totalWeight += weight;
    }
  }

  float average = exp(logLuminance / max(totalWeight, 1.0e-4));
  float key = max(adaptationParams.x, 1.0e-4);
  // Identity at average == key, and meterParams.w controls how much of the
  // remaining difference is compensated for.
  float target = clamp(pow(key / max(average, 1.0e-4), max(meterParams.w, 0.0)),
    adaptationParams.y, adaptationParams.z);
  float previous = texture(previousExposure, vec2(0.5)).r;
  if (!(previous > 0.0)) previous = target;
  float speed = target > previous ? adaptationSpeeds.x : adaptationSpeeds.y;
  float blend = 1.0 - exp(-max(adaptationParams.w, 0.0) * speed);
  float exposure = mix(previous, target, blend);
  FragColor = vec4(exposure, exposure, exposure, 1.0);
}
]]
  return shaderModule.fromSource(vertex, fragment)
end

function effects.createEyeAdaptation()
  local textures, framebuffers = ffi.new("GLuint[2]"), ffi.new("GLuint[2]")
  gl.glGenTextures(2, textures)
  gl.glGenFramebuffers(2, framebuffers)
  local initial = ffi.new("float[4]", {1.0, 1.0, 1.0, 1.0})
  for index = 0, 1 do
    gl.glBindTexture(GL_TEXTURE_2D, textures[index])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, 1, 1, 0, GL_RGBA, GL_FLOAT, initial)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffers[index])
    gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[index], 0)
    if gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) ~= GL_FRAMEBUFFER_COMPLETE then
      error("Failed to create eye-adaptation framebuffer")
    end
  end
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  return {textures = textures, framebuffers = framebuffers, current = 0}
end

function effects.updateEyeAdaptation(program, locations, state, sceneTexture,
    sceneDepthTexture, screenMesh, deltaTime, settings, viewportWidth, viewportHeight)
  settings = settings or {}
  if settings.eyeAdaptation == false then return state.textures[state.current] end
  local nextIndex = state.current == 0 and 1 or 0
  gl.glBindFramebuffer(GL_FRAMEBUFFER, state.framebuffers[nextIndex])
  gl.glViewport(0, 0, 1, 1)
  gl.glUseProgram(program)
  gl.glUniform1i(locations.sceneColor, 0)
  gl.glUniform1i(locations.previousExposure, 1)
  gl.glUniform1i(locations.sceneDepth, 2)
  gl.glUniform4f(locations.adaptationParams,
    settings.eyeKey or 0.34, settings.eyeMinExposure or 0.70,
    settings.eyeMaxExposure or 1.75, math.min(deltaTime or 0.0, 0.1))
  gl.glUniform2f(locations.adaptationSpeeds,
    settings.eyeBrightenSpeed or 0.75, settings.eyeDarkenSpeed or 1.50)
  gl.glUniform4f(locations.meterParams,
    settings.eyeSkyWeight or 0.25, settings.eyeEdgeWeight or 0.35,
    settings.eyeSampleClamp or 2.0, settings.eyeResponse or 0.60)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, sceneTexture)
  gl.glActiveTexture(GL_TEXTURE1)
  gl.glBindTexture(GL_TEXTURE_2D, state.textures[state.current])
  gl.glActiveTexture(GL_TEXTURE2)
  gl.glBindTexture(GL_TEXTURE_2D, sceneDepthTexture)
  gl.glActiveTexture(GL_TEXTURE0)
  rendering.draw(screenMesh)
  state.current = nextIndex
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  gl.glViewport(0, 0, viewportWidth, viewportHeight)
  return state.textures[state.current]
end

function effects.releaseEyeAdaptation(state)
  if not state then return end
  gl.glDeleteFramebuffers(2, state.framebuffers)
  gl.glDeleteTextures(2, state.textures)
end

function effects.createSceneTarget(width, height)
  local colorTexture = ffi.new("GLuint[1]")
  local depthTexture = ffi.new("GLuint[1]")
  local framebuffer = ffi.new("GLuint[1]")

  gl.glGenTextures(1, colorTexture)
  gl.glBindTexture(GL_TEXTURE_2D, colorTexture[0])
  -- Half-float so the scene keeps values above 1.0. An 8-bit target clamps
  -- everything at white, which leaves bloom nothing to pick up and tone mapping
  -- nothing to roll off -- the main reason the image reads as flat.
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, nil)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  gl.glGenTextures(1, depthTexture)
  gl.glBindTexture(GL_TEXTURE_2D, depthTexture[0])
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, width, height, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nil)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  gl.glGenFramebuffers(1, framebuffer)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffer[0])
  gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTexture[0], 0)
  gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depthTexture[0], 0)
  gl.glDrawBuffer(GL_COLOR_ATTACHMENT0)

  if gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) ~= GL_FRAMEBUFFER_COMPLETE then
    error("Failed to create scene framebuffer")
  end

  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)

  return {
    framebuffer = framebuffer,
    colorTexture = colorTexture,
    depthTexture = depthTexture,
    width = width,
    height = height
  }
end

-- Progressive-blur bloom: a chain of half-resolution targets, downsampled with
-- a 13-tap filter and upsampled back with a tent filter, each level added on
-- top. A single wide blur cannot produce the broad soft falloff this gives, and
-- the cost is dominated by the first mip, not the wide ones.
function effects.createBloomChain(width, height, levels)
  levels = levels or 6
  local mips = {}
  local w, h = width, height

  for _ = 1, levels do
    w = math.floor(w / 2)
    h = math.floor(h / 2)
    if w < 2 or h < 2 then
      break
    end

    local texture = ffi.new("GLuint[1]")
    local framebuffer = ffi.new("GLuint[1]")

    gl.glGenTextures(1, texture)
    gl.glBindTexture(GL_TEXTURE_2D, texture[0])
    gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, w, h, 0, GL_RGBA, GL_FLOAT, nil)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    gl.glGenFramebuffers(1, framebuffer)
    gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffer[0])
    gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture[0], 0)
    gl.glDrawBuffer(GL_COLOR_ATTACHMENT0)

    if gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) ~= GL_FRAMEBUFFER_COMPLETE then
      error("Failed to create bloom framebuffer")
    end

    mips[#mips + 1] = {texture = texture, framebuffer = framebuffer, width = w, height = h}
  end

  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  return {mips = mips, width = width, height = height}
end

function effects.releaseBloomChain(chain)
  if not chain then
    return
  end
  for _, mip in ipairs(chain.mips) do
    gl.glDeleteFramebuffers(1, mip.framebuffer)
    gl.glDeleteTextures(1, mip.texture)
  end
  chain.mips = {}
end

function effects.ensureBloomChain(chain, width, height, levels)
  if chain and chain.width == width and chain.height == height then
    return chain
  end
  effects.releaseBloomChain(chain)
  return effects.createBloomChain(width, height, levels)
end

-- Low-resolution HDR target for radial sunlight scattering. Unlike bloom this
-- is a single pass: its source mask is reconstructed from the scene depth while
-- the shader walks from each pixel toward the projected sun.
function effects.createGodRaysTarget(width, height, scale)
  scale = math.max(0.125, math.min(1.0, scale or 0.25))
  local targetWidth = math.max(2, math.floor(width * scale + 0.5))
  local targetHeight = math.max(2, math.floor(height * scale + 0.5))
  local texture = ffi.new("GLuint[1]")
  local framebuffer = ffi.new("GLuint[1]")

  gl.glGenTextures(1, texture)
  gl.glBindTexture(GL_TEXTURE_2D, texture[0])
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, targetWidth, targetHeight, 0,
    GL_RGBA, GL_FLOAT, nil)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  gl.glGenFramebuffers(1, framebuffer)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffer[0])
  gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D, texture[0], 0)
  gl.glDrawBuffer(GL_COLOR_ATTACHMENT0)
  if gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) ~= GL_FRAMEBUFFER_COMPLETE then
    error("Failed to create god-rays framebuffer")
  end
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)

  return {
    texture = texture,
    framebuffer = framebuffer,
    width = targetWidth,
    height = targetHeight,
    sourceWidth = width,
    sourceHeight = height,
    scale = scale
  }
end

function effects.releaseGodRaysTarget(target)
  if not target then return end
  if target.framebuffer then gl.glDeleteFramebuffers(1, target.framebuffer) end
  if target.texture then gl.glDeleteTextures(1, target.texture) end
end

function effects.ensureGodRaysTarget(target, width, height, scale)
  scale = math.max(0.125, math.min(1.0, scale or 0.25))
  if target and target.sourceWidth == width and target.sourceHeight == height and
      math.abs((target.scale or 0.25) - scale) < 0.0001 then
    return target
  end
  effects.releaseGodRaysTarget(target)
  return effects.createGodRaysTarget(width, height, scale)
end

function effects.createGodRaysShader()
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
uniform sampler2D sceneDepth;
uniform vec2 lightPosition;
uniform vec3 lightColor;
uniform vec4 rayParams;    // density, decay, weight, exposure
uniform vec3 sourceParams; // outer radius, inner-radius ratio, visibility
uniform float aspectRatio;
uniform int sampleCount;

const int MAX_SAMPLES = 96;

float sourceMask(vec2 uv) {
  if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
    return 0.0;
  }

  // Sky was drawn first and the depth buffer cleared before world geometry.
  // Consequently untouched far depth is the occlusion map's white value and
  // every rendered surface, including clouds, is black.
  float skyVisibility = smoothstep(0.9995, 0.99998, texture(sceneDepth, uv).r);
  float radius = max(sourceParams.x, 1.0e-4);
  float innerRadius = radius * clamp(sourceParams.y, 0.0, 0.98);
  vec2 sourceDelta = uv - lightPosition;
  sourceDelta.x *= aspectRatio;
  float disc = 1.0 - smoothstep(innerRadius, radius, length(sourceDelta));
  return skyVisibility * disc * sourceParams.z;
}

void main() {
  int count = clamp(sampleCount, 1, MAX_SAMPLES);
  vec2 delta = (vUv - lightPosition) * rayParams.x / float(count);

  // If even the final radial sample cannot enter the light envelope, every
  // depth lookup below would be guaranteed to contribute zero. This rejects
  // most fragments when the sun is near an edge and virtually the whole pass
  // when it has just left the screen.
  vec2 nearestDelta = (vUv - lightPosition) * max(1.0 - rayParams.x, 0.0);
  nearestDelta.x *= aspectRatio;
  if (length(nearestDelta) > sourceParams.x) {
    FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  vec2 uv = vUv;
  float illuminationDecay = 1.0;
  // The sun disc and its immediate halo already exist in the HDR scene and in
  // bloom. Only integrate displaced samples here, otherwise the post effect
  // merely makes the source whiter instead of revealing shafts.
  float scattering = 0.0;

  for (int index = 0; index < MAX_SAMPLES; ++index) {
    if (index >= count) break;
    uv -= delta;
    scattering += sourceMask(uv) * illuminationDecay * rayParams.z;
    illuminationDecay *= rayParams.y;
  }

  FragColor = vec4(lightColor * scattering * rayParams.w, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createBloomDownShader()
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
uniform sampler2D source;
uniform vec2 texelSize;
uniform vec3 prefilter;   // threshold, knee, enabled
uniform float clampMax;

// 13-tap downsample: four inner taps carry most of the weight, which keeps the
// chain stable instead of shimmering as the camera moves.
vec3 sampleBox(vec2 uv) {
  vec2 t = texelSize;
  vec3 a = texture(source, uv + vec2(-2.0, 2.0) * t).rgb;
  vec3 b = texture(source, uv + vec2( 0.0, 2.0) * t).rgb;
  vec3 c = texture(source, uv + vec2( 2.0, 2.0) * t).rgb;
  vec3 d = texture(source, uv + vec2(-2.0, 0.0) * t).rgb;
  vec3 e = texture(source, uv).rgb;
  vec3 f = texture(source, uv + vec2( 2.0, 0.0) * t).rgb;
  vec3 g = texture(source, uv + vec2(-2.0,-2.0) * t).rgb;
  vec3 h = texture(source, uv + vec2( 0.0,-2.0) * t).rgb;
  vec3 i = texture(source, uv + vec2( 2.0,-2.0) * t).rgb;
  vec3 j = texture(source, uv + vec2(-1.0, 1.0) * t).rgb;
  vec3 k = texture(source, uv + vec2( 1.0, 1.0) * t).rgb;
  vec3 l = texture(source, uv + vec2(-1.0,-1.0) * t).rgb;
  vec3 m = texture(source, uv + vec2( 1.0,-1.0) * t).rgb;

  vec3 result = e * 0.125;
  result += (a + c + g + i) * 0.03125;
  result += (b + d + f + h) * 0.0625;
  result += (j + k + l + m) * 0.125;
  return result;
}

void main() {
  vec3 color = sampleBox(vUv);

  if (prefilter.z > 0.5) {
    // soft knee, so surfaces near the threshold ramp in rather than popping
    float threshold = prefilter.x;
    float knee = max(prefilter.y, 1e-4);
    float brightness = max(color.r, max(color.g, color.b));
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    float contribution = max(soft, brightness - threshold) / max(brightness, 1e-5);
    color *= contribution;
  }

  color = min(color, vec3(clampMax));
  FragColor = vec4(color, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createBloomUpShader()
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
uniform sampler2D source;
uniform vec2 texelSize;
uniform float radius;

// 3x3 tent filter. Blended additively into the larger mip by the caller.
void main() {
  vec2 o = texelSize * radius;
  vec3 result = texture(source, vUv + vec2(-o.x,  o.y)).rgb * 1.0;
  result += texture(source, vUv + vec2( 0.0,  o.y)).rgb * 2.0;
  result += texture(source, vUv + vec2( o.x,  o.y)).rgb * 1.0;
  result += texture(source, vUv + vec2(-o.x,  0.0)).rgb * 2.0;
  result += texture(source, vUv).rgb * 4.0;
  result += texture(source, vUv + vec2( o.x,  0.0)).rgb * 2.0;
  result += texture(source, vUv + vec2(-o.x, -o.y)).rgb * 1.0;
  result += texture(source, vUv + vec2( 0.0, -o.y)).rgb * 2.0;
  result += texture(source, vUv + vec2( o.x, -o.y)).rgb * 1.0;
  FragColor = vec4(result * (1.0 / 16.0), 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

-- Runs the whole chain and leaves the result in mips[1], ready to composite.
function effects.renderBloom(shaders, chain, sceneTexture, screenMesh, settings)
  local mips = chain.mips
  if #mips == 0 then
    return nil
  end

  gl.glDisable(GL_DEPTH_TEST)
  gl.glDisable(GL_BLEND)

  -- downsample: scene -> mip1 (with prefilter) -> mip2 -> ...
  gl.glUseProgram(shaders.down)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glUniform1i(shaders.downLoc.source, 0)
  gl.glUniform1f(shaders.downLoc.clampMax, settings.clampMax or 12.0)

  for i = 1, #mips do
    local mip = mips[i]
    local sourceTexture = i == 1 and sceneTexture or mips[i - 1].texture[0]
    local sourceW = i == 1 and chain.width or mips[i - 1].width
    local sourceH = i == 1 and chain.height or mips[i - 1].height

    gl.glBindFramebuffer(GL_FRAMEBUFFER, mip.framebuffer[0])
    gl.glViewport(0, 0, mip.width, mip.height)
    gl.glBindTexture(GL_TEXTURE_2D, sourceTexture)
    gl.glUniform2f(shaders.downLoc.texelSize, 1.0 / sourceW, 1.0 / sourceH)
    gl.glUniform3f(shaders.downLoc.prefilter,
      settings.threshold or 0.7,
      (settings.threshold or 0.7) * (settings.softKnee or 0.6),
      i == 1 and 1.0 or 0.0)
    rendering.draw(screenMesh)
  end

  -- upsample: add each smaller mip back into the one above it
  gl.glUseProgram(shaders.up)
  gl.glUniform1i(shaders.upLoc.source, 0)
  gl.glUniform1f(shaders.upLoc.radius, settings.radius or 1.0)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_ONE, GL_ONE)

  for i = #mips, 2, -1 do
    local source = mips[i]
    local target = mips[i - 1]
    gl.glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer[0])
    gl.glViewport(0, 0, target.width, target.height)
    gl.glBindTexture(GL_TEXTURE_2D, source.texture[0])
    gl.glUniform2f(shaders.upLoc.texelSize, 1.0 / source.width, 1.0 / source.height)
    rendering.draw(screenMesh)
  end

  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)

  return mips[1].texture[0]
end

function effects.releaseSceneTarget(target)
  if not target then return end
  if target.framebuffer then gl.glDeleteFramebuffers(1, target.framebuffer) end
  if target.colorTexture then gl.glDeleteTextures(1, target.colorTexture) end
  if target.depthTexture then gl.glDeleteTextures(1, target.depthTexture) end
end

function effects.ensureSceneTarget(target, width, height)
  if target and target.width == width and target.height == height then
    return target
  end
  effects.releaseSceneTarget(target)
  return effects.createSceneTarget(width, height)
end

function effects.copySceneTarget(source, destination)
  gl.glBindFramebuffer(GL_READ_FRAMEBUFFER, source.framebuffer[0])
  gl.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, destination.framebuffer[0])
  gl.glBlitFramebuffer(
    0, 0, source.width, source.height,
    0, 0, destination.width, destination.height,
    GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT,
    GL_NEAREST
  )
  gl.glBindFramebuffer(GL_FRAMEBUFFER, source.framebuffer[0])
end

function effects.drawDielectrics(shader, meshes, locations, playerCamera, view, projection, sunDir,
    atmosphereState, background, viewportWidth, viewportHeight, nearPlane, farPlane, atlasTex,
    settings, model)
  settings = settings or {}
  local ice = settings.ice or {}
  local glass = settings.glass or {}
  local iceAbsorption = ice.absorption or {0.045, 0.018, 0.008}
  local glassAbsorption = glass.absorption or {0.008, 0.004, 0.002}

  gl.glUseProgram(shader)
  gl.glUniformMatrix4fv(locations.projection, 1, 0, ffi.new("float[16]", projection))
  gl.glUniformMatrix4fv(locations.view, 1, 0, ffi.new("float[16]", view))
  gl.glUniformMatrix4fv(locations.model, 1, 0, ffi.new("float[16]", model))
  gl.glUniform3f(locations.viewPos, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
  gl.glUniform3f(locations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(locations.fogColor,
    atmosphereState.fogColor[1], atmosphereState.fogColor[2], atmosphereState.fogColor[3])
  gl.glUniform3f(locations.skyZenithColor,
    atmosphereState.skyZenith[1], atmosphereState.skyZenith[2], atmosphereState.skyZenith[3])
  gl.glUniform3f(locations.lightColor,
    atmosphereState.lightColor[1], atmosphereState.lightColor[2], atmosphereState.lightColor[3])
  gl.glUniform2f(locations.viewportSize, viewportWidth, viewportHeight)
  gl.glUniform2f(locations.clipPlanes, nearPlane, farPlane)
  gl.glUniform4f(locations.iceOptics,
    ice.ior or 1.31, ice.roughness or 0.16,
    ice.refractionStrength or 0.010, ice.cloudiness or 0.72)
  gl.glUniform4f(locations.glassOptics,
    glass.ior or 1.52, glass.roughness or 0.035,
    glass.refractionStrength or 0.006, glass.cloudiness or 0.04)
  gl.glUniform3f(locations.iceAbsorption,
    iceAbsorption[1], iceAbsorption[2], iceAbsorption[3])
  gl.glUniform3f(locations.glassAbsorption,
    glassAbsorption[1], glassAbsorption[2], glassAbsorption[3])
  gl.glUniform1i(locations.tex0, 0)
  gl.glUniform1i(locations.sceneColor, 1)
  gl.glUniform1i(locations.sceneDepth, 2)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
  gl.glActiveTexture(GL_TEXTURE0 + 1)
  gl.glBindTexture(GL_TEXTURE_2D, background.colorTexture[0])
  gl.glActiveTexture(GL_TEXTURE0 + 2)
  gl.glBindTexture(GL_TEXTURE_2D, background.depthTexture[0])

  -- Refraction is already composited against the copied opaque scene. Writing
  -- the resulting dielectric surface as opaque avoids a second, incorrect
  -- alpha blend and preserves its real depth for water/fog behind it.
  gl.glDisable(GL_BLEND)
  gl.glDepthMask(1)
  for i = 1, #meshes do
    rendering.draw(meshes[i])
  end
  gl.glActiveTexture(GL_TEXTURE0)
end

local function appendWaterVertex(vertices, x, y, z, waveExposure, shoreDistance)
  local n = #vertices
  vertices[n + 1] = x
  vertices[n + 2] = y
  vertices[n + 3] = z
  vertices[n + 4] = 0.0
  vertices[n + 5] = 1.0
  vertices[n + 6] = 0.0
  vertices[n + 7] = 1.0
  vertices[n + 8] = 1.0
  vertices[n + 9] = 1.0
  -- The water shader does not use texture UVs. Attribute 3 instead carries a
  -- stable world-space wave classification: open fetch and shore damping.
  vertices[n + 10] = waveExposure
  vertices[n + 11] = shoreDistance
end

local function appendWaterQuad(vertices, x0, z0, x1, z1, waveDataAt, surfaceY)
  surfaceY = surfaceY or 0.0
  local e01, s01 = 1.0, 1.0
  local e11, s11 = 1.0, 1.0
  local e10, s10 = 1.0, 1.0
  local e00, s00 = 1.0, 1.0
  if waveDataAt then
    e01, s01 = waveDataAt(x0, z1)
    e11, s11 = waveDataAt(x1, z1)
    e10, s10 = waveDataAt(x1, z0)
    e00, s00 = waveDataAt(x0, z0)
  end
  appendWaterVertex(vertices, x0, surfaceY, z1, e01, s01)
  appendWaterVertex(vertices, x1, surfaceY, z1, e11, s11)
  appendWaterVertex(vertices, x1, surfaceY, z0, e10, s10)
  appendWaterVertex(vertices, x1, surfaceY, z0, e10, s10)
  appendWaterVertex(vertices, x0, surfaceY, z0, e00, s00)
  appendWaterVertex(vertices, x0, surfaceY, z1, e01, s01)
end

function effects.waterChunkVertices(chunk, offsetX, offsetZ, waterLevel, waterId, stillWaterId, tessellation, waveDataAt)
  local vertices = {}
  tessellation = math.max(1, math.floor(tessellation or 2))
  local step = 1.0 / tessellation

  local function isWater(id)
    return id == waterId or (stillWaterId and id == stillWaterId)
  end

  local waveCache = {}
  local function cachedWaveDataAt(x, z)
    if not waveDataAt then return 1.0, 1.0 end
    local key = tostring(x) .. "," .. tostring(z)
    local cached = waveCache[key]
    if cached then return cached[1], cached[2] end
    local exposure, shore = waveDataAt(x, z)
    cached = {exposure, shore}
    waveCache[key] = cached
    return exposure, shore
  end

  -- Find the top of each actual water column. Oceans, elevated lakes and river
  -- reaches can therefore share this chunk-owned surface mesh.
  for z = 0, 15 do
    for x = 0, 15 do
      local surfaceY = chunk.waterSurface and chunk.waterSurface[x + z * 16 + 1] or nil
      if not surfaceY then
        local topWaterY = nil
        for y = 255, 0, -1 do
          if isWater(chunk:getBlock(x, y, z)) then
            topWaterY = y
            break
          end
        end
        surfaceY = topWaterY and (topWaterY - 0.35) or nil
      end
      if surfaceY then
        for subZ = 0, tessellation - 1 do
          for subX = 0, tessellation - 1 do
            local x0 = offsetX + x + subX * step
            local x1 = x0 + step
            local z0 = offsetZ + z + subZ * step
            local z1 = z0 + step
            appendWaterQuad(vertices, x0, z0, x1, z1, cachedWaveDataAt, surfaceY)
          end
        end
      end
    end
  end

  return vertices
end

local function createShadowCascade(size)
  local depthTexture, framebuffer = ffi.new("GLuint[1]"), ffi.new("GLuint[1]")

  gl.glGenTextures(1, depthTexture)
  gl.glBindTexture(GL_TEXTURE_2D, depthTexture[0])
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, size, size, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, nil)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  gl.glGenFramebuffers(1, framebuffer)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, framebuffer[0])
  gl.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depthTexture[0], 0)
  gl.glDrawBuffer(GL_NONE)
  gl.glReadBuffer(GL_NONE)

  if gl.glCheckFramebufferStatus(GL_FRAMEBUFFER) ~= GL_FRAMEBUFFER_COMPLETE then
    error("Failed to create shadow framebuffer")
  end

  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)

  return {
    framebuffer = framebuffer,
    depthTexture = depthTexture,
    size = size
  }
end

function effects.createShadowMap(sizeOrSizes)
  local sizes = type(sizeOrSizes) == "table" and sizeOrSizes or {sizeOrSizes}
  local result = {cascades = {}}
  for index = 1, #sizes do
    result.cascades[index] = createShadowCascade(sizes[index])
  end
  -- Legacy aliases keep the fog and any diagnostic code useful with one map.
  result.framebuffer = result.cascades[1].framebuffer
  result.depthTexture = result.cascades[1].depthTexture
  return result
end

function effects.lightSpaceMatrix(playerPosition, sunDir, terrainMaxHeight, distance, near, far)
  local lightDir = math3d.normalize(sunDir)
  local center = {playerPosition[1], terrainMaxHeight * 0.45, playerPosition[3]}
  local eye = {
    center[1] + lightDir[1] * distance,
    center[2] + lightDir[2] * distance,
    center[3] + lightDir[3] * distance
  }
  local up = math.abs(lightDir[2]) > 0.92 and {0.0, 0.0, 1.0} or {0.0, 1.0, 0.0}
  local lightView = math3d.lookAt(eye, center, up)
  local lightProjection = math3d.ortho(-distance, distance, -distance, distance, near, far)

  return math3d.multiplyMat4(lightProjection, lightView)
end

function effects.cascadeShadowMatrices(playerPosition, sunDir, terrainMaxHeight,
    splits, mapSizes, near, far)
  local matrices = {}
  for index = 1, #splits do
    local radius = splits[index]
    local resolution = mapSizes[index] or mapSizes[#mapSizes]
    local texelWorld = radius * 2.0 / resolution
    local snapped = {
      math.floor(playerPosition[1] / texelWorld + 0.5) * texelWorld,
      playerPosition[2],
      math.floor(playerPosition[3] / texelWorld + 0.5) * texelWorld
    }
    matrices[index] = effects.lightSpaceMatrix(snapped, sunDir, terrainMaxHeight,
      radius, near, math.max(far, terrainMaxHeight * 2.0 + radius * 2.0))
  end
  return matrices
end

function effects.renderShadowPass(shadowShader, shadowMap, locations, terrainMeshes,
    characterMesh, lightSpaceMatrices, model, viewportWidth, viewportHeight, atlasTex)
  gl.glUseProgram(shadowShader)
  gl.glUniformMatrix4fv(locations.model, 1, 0, ffi.new("float[16]", model))
  gl.glUniform1i(locations.tex0, 0)
  if atlasTex then
    gl.glActiveTexture(GL_TEXTURE0)
    gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
  end
  gl.glEnable(GL_POLYGON_OFFSET_FILL)
  gl.glPolygonOffset(2.0, 4.0)

  for index, cascade in ipairs(shadowMap.cascades) do
    gl.glViewport(0, 0, cascade.size, cascade.size)
    gl.glBindFramebuffer(GL_FRAMEBUFFER, cascade.framebuffer[0])
    gl.glClear(GL_DEPTH_BUFFER_BIT)
    gl.glUniformMatrix4fv(locations.lightSpaceMatrix, 1, 0,
      ffi.new("float[16]", lightSpaceMatrices[index]))
    for _, mesh in pairs(terrainMeshes) do rendering.draw(mesh) end
    if characterMesh then rendering.draw(characterMesh) end
  end

  gl.glDisable(GL_POLYGON_OFFSET_FILL)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  gl.glViewport(0, 0, viewportWidth, viewportHeight)
end

function effects.drawWater(waterShader, waterMeshes, locations, playerCamera, view, projection, sunDir, atmosphere,
    waterLevel, ocean, background, viewportWidth, viewportHeight, time, nearPlane, farPlane, cloudShadow)
  local cascadeSizes = ocean.cascadeSizes
  local displacementWeights = ocean.displacementWeights
  local normalWeights = ocean.normalWeights
  local absorption = ocean.absorption

  gl.glUseProgram(waterShader)
  gl.glUniformMatrix4fv(locations.projection, 1, 0, ffi.new("float[16]", projection))
  gl.glUniformMatrix4fv(locations.view, 1, 0, ffi.new("float[16]", view))
  gl.glUniform1f(locations.waterLevel, waterLevel)
  gl.glUniform3f(locations.viewPos, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
  gl.glUniform3f(locations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(locations.fogColor, atmosphere.fogColor[1], atmosphere.fogColor[2], atmosphere.fogColor[3])
  gl.glUniform3f(locations.lightColor, atmosphere.lightColor[1], atmosphere.lightColor[2], atmosphere.lightColor[3])
  gl.glUniform3f(locations.skyZenithColor, atmosphere.skyZenith[1], atmosphere.skyZenith[2], atmosphere.skyZenith[3])
  gl.glUniform3f(locations.cascadeSizes, cascadeSizes[1], cascadeSizes[2], cascadeSizes[3])
  gl.glUniform3f(locations.displacementWeights, displacementWeights[1], displacementWeights[2], displacementWeights[3])
  gl.glUniform3f(locations.normalWeights, normalWeights[1], normalWeights[2], normalWeights[3])
  gl.glUniform1f(locations.openWaterWaveBoost, ocean.openWaterWaveBoost)
  gl.glUniform2f(locations.viewportSize, viewportWidth, viewportHeight)
  gl.glUniform2f(locations.clipPlanes, nearPlane, farPlane)
  gl.glUniform1f(locations.time, time or 0.0)
  gl.glUniform1f(locations.refractionStrength, ocean.refractionStrength)
  gl.glUniform3f(locations.absorption, absorption[1], absorption[2], absorption[3])

  gl.glUniform1i(locations.displacementMap0, 0)
  gl.glUniform1i(locations.displacementMap1, 1)
  gl.glUniform1i(locations.displacementMap2, 2)
  gl.glUniform1i(locations.normalMap0, 3)
  gl.glUniform1i(locations.normalMap1, 4)
  gl.glUniform1i(locations.normalMap2, 5)
  gl.glUniform1i(locations.sceneColor, 6)
  gl.glUniform1i(locations.sceneDepth, 7)
  gl.glUniform1i(locations.cloudShadowMap, 8)
  if cloudShadow then
    gl.glUniform4f(locations.cloudShadow, cloudShadow.originX, cloudShadow.originZ,
      cloudShadow.inverseSpan, cloudShadow.altitude)
    gl.glUniform1f(locations.cloudShadowStrength, cloudShadow.strength)
  else
    gl.glUniform1f(locations.cloudShadowStrength, 0.0)
  end
  for unit = 0, 2 do
    gl.glActiveTexture(GL_TEXTURE0 + unit)
    gl.glBindTexture(GL_TEXTURE_2D, ocean.displacementTexture)
  end
  for unit = 3, 5 do
    gl.glActiveTexture(GL_TEXTURE0 + unit)
    gl.glBindTexture(GL_TEXTURE_2D, ocean.normalTexture)
  end
  gl.glActiveTexture(GL_TEXTURE0 + 6)
  gl.glBindTexture(GL_TEXTURE_2D, background.colorTexture[0])
  gl.glActiveTexture(GL_TEXTURE0 + 7)
  gl.glBindTexture(GL_TEXTURE_2D, background.depthTexture[0])
  gl.glActiveTexture(GL_TEXTURE0 + 8)
  gl.glBindTexture(GL_TEXTURE_2D, (cloudShadow and cloudShadow.texture) or 0)

  -- Refraction is composited in the shader from a pre-water scene copy, so the
  -- resulting surface is opaque and must not be alpha-blended a second time.
  gl.glDisable(GL_BLEND)
  gl.glDepthMask(1)
  for i = 1, #waterMeshes do
    rendering.draw(waterMeshes[i])
  end
  gl.glActiveTexture(GL_TEXTURE0)
end

local function cameraViewFront(camera)
  return camera.getViewFront and camera:getViewFront() or camera:getFront()
end

-- Projects an infinitely distant directional light into texture coordinates.
-- The returned visibility also fades a source just outside the viewport, which
-- prevents a hard pop as the sun crosses an edge of the screen.
function effects.directionToScreen(playerCamera, direction, fov, viewportWidth, viewportHeight)
  local forward = math3d.normalize(cameraViewFront(playerCamera))
  local cameraUp = playerCamera.getViewUp and playerCamera:getViewUp() or {0.0, 1.0, 0.0}
  local right = math3d.normalize(math3d.cross(forward, cameraUp))
  local up = math3d.normalize(math3d.cross(right, forward))
  local forwardAmount = math3d.dot(direction, forward)
  if forwardAmount <= 0.001 then
    return {0.5, 0.5}, 0.0
  end

  local projectionY = math.tan(fov / 2)
  local projectionX = viewportWidth / math.max(1, viewportHeight) * projectionY
  local ndcX = math3d.dot(direction, right) / math.max(forwardAmount * projectionX, 1.0e-5)
  local ndcY = math3d.dot(direction, up) / math.max(forwardAmount * projectionY, 1.0e-5)
  local uv = {ndcX * 0.5 + 0.5, ndcY * 0.5 + 0.5}
  local outside = math.max(0.0, -uv[1], uv[1] - 1.0, -uv[2], uv[2] - 1.0)
  return uv, 1.0 - math3d.smoothstep(0.0, 0.30, outside)
end

function effects.renderGodRays(shader, target, locations, sceneDepth, screenMesh,
    playerCamera, sunDir, lightColor, fov, viewportWidth, viewportHeight, settings, visibility)
  settings = settings or {}
  local lightPosition, screenVisibility = effects.directionToScreen(
    playerCamera, sunDir, fov, viewportWidth, viewportHeight)
  local finalVisibility = screenVisibility * math.max(0.0, math.min(1.0, visibility or 1.0))
  local sourceRadius = settings.godRaysSourceRadius or 0.065
  local aspectRatio = viewportWidth / math.max(1, viewportHeight)
  local outsideX = math.max(0.0, -lightPosition[1], lightPosition[1] - 1.0) * aspectRatio
  local outsideY = math.max(0.0, -lightPosition[2], lightPosition[2] - 1.0)
  -- Below this the additive result is imperceptible, but the radial shader
  -- would still pay for a full-screen pass. In particular, this catches a sun
  -- that is in front of the camera but has moved just beyond a viewport edge.
  -- The second test is exact for the circular source mask: once its whole disc
  -- is offscreen there are no source pixels for radial integration to sample.
  if finalVisibility <= 0.035 or
      outsideX * outsideX + outsideY * outsideY > sourceRadius * sourceRadius then
    return nil
  end

  local brightest = math.max(lightColor[1], lightColor[2], lightColor[3], 1.0e-4)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, target.framebuffer[0])
  gl.glViewport(0, 0, target.width, target.height)
  gl.glDisable(GL_DEPTH_TEST)
  gl.glDisable(GL_BLEND)
  gl.glUseProgram(shader)
  gl.glUniform1i(locations.sceneDepth, 0)
  gl.glUniform2f(locations.lightPosition, lightPosition[1], lightPosition[2])
  gl.glUniform3f(locations.lightColor,
    lightColor[1] / brightest, lightColor[2] / brightest, lightColor[3] / brightest)
  gl.glUniform4f(locations.rayParams,
    settings.godRaysDensity or 0.92,
    settings.godRaysDecay or 0.96,
    settings.godRaysWeight or 0.080,
    settings.godRaysExposure or 0.65)
  gl.glUniform3f(locations.sourceParams,
    sourceRadius, 0.18, finalVisibility)
  gl.glUniform1f(locations.aspectRatio, aspectRatio)
  gl.glUniform1i(locations.sampleCount,
    math.max(1, math.min(96, math.floor(settings.godRaysSamples or 16))))
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, sceneDepth)
  rendering.draw(screenMesh)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  gl.glViewport(0, 0, viewportWidth, viewportHeight)
  gl.glEnable(GL_DEPTH_TEST)
  return target.texture[0]
end

function effects.releaseGodRays(runtime)
  if not runtime then return end
  effects.releaseGodRaysTarget(runtime.target)
  if runtime.shader then gl.glDeleteProgram(runtime.shader) end
end

function effects.renderVolumetricFog(volume, shaders, playerCamera, sunDir, atmosphereState, fov, viewportWidth, viewportHeight, waterLevel, settings, shadowMap, lightSpaceMatrix)
  settings = settings or {}
  local forward = cameraViewFront(playerCamera)
  local cameraUp = playerCamera.getViewUp and playerCamera:getViewUp() or {0.0, 1.0, 0.0}
  local right = math3d.normalize(math3d.cross(forward, cameraUp))
  local up = math3d.normalize(math3d.cross(right, forward))
  local cameraPosition = playerCamera.getViewPosition and playerCamera:getViewPosition() or playerCamera.position
  local projectionY = math.tan(fov / 2)
  local projectionX = viewportWidth / viewportHeight * projectionY
  local volumeNear = settings.volumetricNear or 0.5
  local volumeFar = settings.volumetricFar or settings.fogEnd or 360.0
  volume.near = volumeNear
  volume.far = volumeFar

  local injectionLocations = shaders.injectionLocations
  gl.glUseProgram(shaders.injection)
  gl.glUniform1i(injectionLocations.shadowMap, 0)
  gl.glUniform3f(injectionLocations.cameraPosition, cameraPosition[1], cameraPosition[2], cameraPosition[3])
  gl.glUniform3f(injectionLocations.cameraForward, forward[1], forward[2], forward[3])
  gl.glUniform3f(injectionLocations.cameraRight, right[1], right[2], right[3])
  gl.glUniform3f(injectionLocations.cameraUp, up[1], up[2], up[3])
  gl.glUniform3f(injectionLocations.cameraProjection, projectionX, projectionY, 0.0)
  gl.glUniform3f(injectionLocations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(injectionLocations.fogColor, atmosphereState.fogColor[1], atmosphereState.fogColor[2], atmosphereState.fogColor[3])
  gl.glUniform3f(injectionLocations.skyZenithColor, atmosphereState.skyZenith[1], atmosphereState.skyZenith[2], atmosphereState.skyZenith[3])
  gl.glUniform3f(injectionLocations.lightColor, atmosphereState.lightColor[1], atmosphereState.lightColor[2], atmosphereState.lightColor[3])
  gl.glUniform3f(injectionLocations.fogParams, atmosphereState.fogStart, atmosphereState.fogEnd, settings.maxFogAmount or 0.72)
  gl.glUniform3f(injectionLocations.atmosphereParams, settings.heightFogDensity or 0.0045, settings.heightFogFalloff or 0.055, settings.horizonFog or 0.24)
  gl.glUniform3f(injectionLocations.volumeParams, volumeNear, volumeFar, settings.sunScatter or 0.65)
  gl.glUniform1f(injectionLocations.baseHeight, settings.fogBaseHeight or waterLevel)
  gl.glUniformMatrix4fv(injectionLocations.lightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
  gl.glActiveTexture(GL_TEXTURE0)
  local fogShadow = shadowMap.cascades and shadowMap.cascades[#shadowMap.cascades] or shadowMap
  gl.glBindTexture(GL_TEXTURE_2D, fogShadow.depthTexture[0])
  gl.glBindImageTexture(0, volume.injectionTexture, 0, GL_TRUE, 0, GL_WRITE_ONLY, GL_RGBA16F)
  gl.glDispatchCompute(math.ceil(volume.width / 8), math.ceil(volume.height / 8), volume.depth)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT + GL_TEXTURE_FETCH_BARRIER_BIT)

  local integrationLocations = shaders.integrationLocations
  gl.glUseProgram(shaders.integration)
  gl.glUniform1i(integrationLocations.injectionVolume, 0)
  gl.glUniform3f(integrationLocations.volumeParams, volumeNear, volumeFar, 0.0)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_3D, volume.injectionTexture)
  gl.glBindImageTexture(0, volume.integratedTexture, 0, GL_TRUE, 0, GL_WRITE_ONLY, GL_RGBA16F)
  gl.glDispatchCompute(math.ceil(volume.width / 8), math.ceil(volume.height / 8), 1)
  gl.glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT + GL_TEXTURE_FETCH_BARRIER_BIT)
  gl.glBindTexture(GL_TEXTURE_3D, 0)
end

function effects.drawAtmospherePost(postShader, screenMesh, locations, sceneTarget,
    playerCamera, fov, viewportWidth, viewportHeight, nearPlane, farPlane,
    underwaterAmount, localSkyVisibility, settings, blurAmount, underwaterOverlayTexture, time, bloomTexture,
    grade, volume, eyeExposureTexture, godRaysTexture, motionBlurVector)
  settings = settings or {}
  grade = grade or {}

  local forward = cameraViewFront(playerCamera)
  local cameraUp = playerCamera.getViewUp and playerCamera:getViewUp() or {0.0, 1.0, 0.0}
  local right = math3d.normalize(math3d.cross(forward, cameraUp))
  local up = math3d.normalize(math3d.cross(right, forward))
  local cameraPosition = playerCamera.getViewPosition and playerCamera:getViewPosition() or playerCamera.position
  local projectionY = math.tan(fov / 2)
  local projectionX = viewportWidth / viewportHeight * projectionY

  gl.glDisable(GL_DEPTH_TEST)
  gl.glUseProgram(postShader)
  gl.glUniform1i(locations.sceneColor, 0)
  gl.glUniform1i(locations.sceneDepth, 1)
  gl.glUniform1i(locations.underwaterOverlay, 2)
  gl.glUniform1i(locations.fogVolume, 4)
  gl.glUniform3f(locations.cameraPosition, cameraPosition[1], cameraPosition[2], cameraPosition[3])
  gl.glUniform3f(locations.cameraForward, forward[1], forward[2], forward[3])
  gl.glUniform3f(locations.cameraRight, right[1], right[2], right[3])
  gl.glUniform3f(locations.cameraUp, up[1], up[2], up[3])
  gl.glUniform3f(locations.cameraProjection, projectionX, projectionY, 0.0)
  gl.glUniform3f(locations.depthParams, nearPlane, farPlane, 0.0)
  gl.glUniform3f(locations.volumeParams, volume.near, volume.far, settings.maxFogAmount or 0.72)
  gl.glUniform1f(locations.localSkyVisibility, localSkyVisibility or 0.0)
  gl.glUniform1f(locations.blurAmount, blurAmount or 0.0)
  gl.glUniform1f(locations.underwaterAmount, underwaterAmount or 0.0)
  gl.glUniform1f(locations.time, time or 0.0)
  gl.glUniform1i(locations.bloomTexture, 3)
  gl.glUniform1i(locations.godRaysTexture, 6)
  gl.glUniform1i(locations.eyeExposure, 5)
  gl.glUniform1f(locations.godRaysStrength,
    godRaysTexture and (grade.godRaysStrength or 0.30) or 0.0)
  motionBlurVector = motionBlurVector or {0.0, 0.0}
  gl.glUniform2f(locations.motionBlurVector, motionBlurVector[1] or 0.0, motionBlurVector[2] or 0.0)
  gl.glUniform4f(locations.gradeParams,
    grade.exposure or 1.0,
    bloomTexture and (grade.bloomStrength or 0.06) or 0.0,
    grade.saturation or 1.0,
    grade.contrast or 1.0)

  local mode = 1.0
  if grade.tonemap == false or grade.tonemap == "off" then
    mode = 0.0
  elseif grade.tonemap == "aces" then
    mode = 2.0
  end
  gl.glUniform3f(locations.tonemapParams, mode, grade.tonemapKnee or 0.80, grade.tonemapWhite or 2.2)

  gl.glActiveTexture(GL_TEXTURE3)
  gl.glBindTexture(GL_TEXTURE_2D, bloomTexture or sceneTarget.colorTexture[0])

  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, sceneTarget.colorTexture[0])
  gl.glActiveTexture(GL_TEXTURE1)
  gl.glBindTexture(GL_TEXTURE_2D, sceneTarget.depthTexture[0])
  gl.glActiveTexture(GL_TEXTURE2)
  if underwaterOverlayTexture then
    gl.glBindTexture(GL_TEXTURE_2D, underwaterOverlayTexture[0])
  else
    gl.glBindTexture(GL_TEXTURE_2D, sceneTarget.colorTexture[0])
  end
  gl.glActiveTexture(GL_TEXTURE4)
  gl.glBindTexture(GL_TEXTURE_3D, volume.integratedTexture)
  gl.glActiveTexture(GL_TEXTURE5)
  gl.glBindTexture(GL_TEXTURE_2D, eyeExposureTexture)
  gl.glActiveTexture(GL_TEXTURE0 + 6)
  gl.glBindTexture(GL_TEXTURE_2D, godRaysTexture or sceneTarget.colorTexture[0])
  rendering.draw(screenMesh)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glEnable(GL_DEPTH_TEST)
end

function effects.releaseVolumetricFog(volume, shaders)
  if volume and volume.textures then
    gl.glDeleteTextures(2, volume.textures)
  end
  if shaders then
    if shaders.injection then gl.glDeleteProgram(shaders.injection) end
    if shaders.integration then gl.glDeleteProgram(shaders.integration) end
  end
end

return effects
