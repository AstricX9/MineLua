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
local GL_TEXTURE_2D = 0x0DE1
local GL_TEXTURE_MIN_FILTER = 0x2801
local GL_TEXTURE_MAG_FILTER = 0x2800
local GL_TEXTURE_WRAP_S = 0x2802
local GL_TEXTURE_WRAP_T = 0x2803
local GL_LINEAR = 0x2601
local GL_RGBA = 0x1908
local GL_CLAMP_TO_EDGE = 0x812F
local GL_DEPTH_COMPONENT = 0x1902
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_UNSIGNED_INT = 0x1405
local GL_UNSIGNED_BYTE = 0x1401
local GL_FRAMEBUFFER = 0x8D40
local GL_COLOR_ATTACHMENT0 = 0x8CE0
local GL_DEPTH_ATTACHMENT = 0x8D00
local GL_FRAMEBUFFER_COMPLETE = 0x8CD5
local GL_NONE = 0
local GL_POLYGON_OFFSET_FILL = 0x8037
local GL_DEPTH_TEST = 0x0B71
local GL_BLEND = 0x0BE2
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303

function effects.createShadowShader()
  local vertSource = [[
#version 330 core
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
#version 330 core
in vec2 vTexCoord;
uniform sampler2D tex0;
void main() {
  if (texture(tex0, vTexCoord).a < 0.5) discard;
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createWaterShader()
  local vertSource = [[
#version 330 core
layout (location = 0) in vec3 aPos;
out vec3 vWorldPos;
out vec2 vUv;
uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 waterCenter;
uniform float waterLevel;
void main() {
  vec3 worldPos = vec3(aPos.x + waterCenter.x, waterLevel, aPos.z + waterCenter.z);
  vWorldPos = worldPos;
  vUv = worldPos.xz;
  gl_Position = uProjection * uView * vec4(worldPos, 1.0);
}
]]

  local fragSource = [[
#version 330 core
in vec3 vWorldPos;
in vec2 vUv;
out vec4 FragColor;
uniform vec3 viewPos;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform vec3 fogParams;
uniform vec3 lightColor;
uniform vec3 skyZenithColor;
uniform float time;
uniform sampler2D waterTex;

float waterSignal(vec2 p) {
  vec2 uv0 = fract(p / 16.0 + vec2(time * 0.018, time * 0.006));
  vec2 uv1 = fract(p / 9.0 + vec2(-time * 0.011, time * 0.014));
  float caustic = texture(waterTex, uv0).b * 0.72 + texture(waterTex, uv1).g * 0.28;
  float ripple = sin((uv0.x + time * 0.035) * 6.28318) * 0.12;
  ripple += sin((uv1.y - time * 0.025) * 6.28318) * 0.10;
  return clamp(caustic * 0.72 + ripple + 0.16, 0.0, 1.0);
}

void main() {
  vec2 p = vUv;
  float signal = waterSignal(p);
  float signal2 = signal * signal;
  vec3 viewDir = normalize(viewPos - vWorldPos);
  float grazing = 1.0 - clamp(abs(viewDir.y), 0.0, 1.0);
  float distanceFade = smoothstep(fogParams.x * 0.22, fogParams.y * 0.72, length(viewPos - vWorldPos));
  vec3 waterColor = vec3(
    (26.0 + signal2 * 34.0) / 255.0,
    (46.0 + signal2 * 62.0) / 255.0,
    (185.0 + signal2 * 70.0) / 255.0
  );
  float light = mix(0.70, 1.0, clamp(sunDir.y * 0.5 + 0.5, 0.0, 1.0));
  vec3 deepWater = vec3(0.030, 0.095, 0.230);
  vec3 reflectedSky = mix(fogColor * 0.72, skyZenithColor * 0.86, 0.45 + grazing * 0.38);
  vec3 color = mix(waterColor, deepWater, distanceFade * 0.42 + grazing * 0.18);
  color = mix(color, reflectedSky, grazing * 0.20);
  color *= light;

  float fogDistance = length(viewPos - vWorldPos);
  float fogAmount = smoothstep(fogParams.x * 0.85, fogParams.y, fogDistance);
  color = mix(color, fogColor, fogAmount);

  float alpha = (146.0 + signal2 * 50.0) / 255.0;
  FragColor = vec4(color, clamp(alpha, 0.55, 0.77));
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createAtmospherePostShader()
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
uniform sampler2D sceneColor;
uniform sampler2D sceneDepth;
uniform sampler2D underwaterOverlay;
uniform vec3 cameraPosition;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 cameraProjection;
uniform vec3 sunDir;
uniform vec3 fogColor;
uniform vec3 fogParams;
uniform vec3 skyZenithColor;
uniform vec3 lightColor;
uniform vec3 depthParams;
uniform vec3 atmosphereParams;
uniform vec3 scatterParams;
uniform float blurAmount;
uniform float time;

float linearDepth(float rawDepth) {
  float nearPlane = depthParams.x;
  float farPlane = depthParams.y;
  float z = rawDepth * 2.0 - 1.0;
  return (2.0 * nearPlane * farPlane) / (farPlane + nearPlane - z * (farPlane - nearPlane));
}

vec3 encodeFogLight(vec3 color) {
  return pow(clamp(color, vec3(0.0), vec3(1.3)), vec3(1.0 / 2.2));
}

void main() {
  vec2 texel = 1.0 / vec2(textureSize(sceneColor, 0));
  vec3 scene = texture(sceneColor, vUv).rgb;
  if (blurAmount > 0.001) {
    vec2 radius = texel * blurAmount;
    scene = scene * 0.36;
    scene += texture(sceneColor, vUv + vec2(radius.x, 0.0)).rgb * 0.16;
    scene += texture(sceneColor, vUv - vec2(radius.x, 0.0)).rgb * 0.16;
    scene += texture(sceneColor, vUv + vec2(0.0, radius.y)).rgb * 0.16;
    scene += texture(sceneColor, vUv - vec2(0.0, radius.y)).rgb * 0.16;
  }
  float rawDepth = texture(sceneDepth, vUv).r;

  if (rawDepth >= 0.9999) {
    FragColor = vec4(scene, 1.0);
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
  vec3 worldPos = cameraPosition + ray * distance;

  float fogStart = fogParams.x;
  float fogEnd = max(fogParams.y, fogStart + 1.0);
  float maxFog = fogParams.z;
  float distFog = smoothstep(fogStart, fogEnd, distance);
  distFog = 1.0 - exp(-distFog * distFog * 2.25);

  float waterLevel = depthParams.z;
  float heightDensity = atmosphereParams.x;
  float heightFalloff = atmosphereParams.y;
  float horizonDensity = atmosphereParams.z;
  float heightLayer = exp(-max(worldPos.y - waterLevel, 0.0) * heightFalloff);
  float heightFog = (1.0 - exp(-distance * 0.014)) * heightLayer * heightDensity;
  float horizonFog = smoothstep(0.04, -0.18, ray.y) * smoothstep(fogStart * 0.35, fogEnd, distance) * horizonDensity;
  float fogAmount = clamp(distFog + heightFog + horizonFog, 0.0, maxFog);

  float skyLift = smoothstep(-0.05, 0.70, ray.y) * 0.42;
  vec3 fogLight = mix(fogColor, skyZenithColor, skyLift);
  float sunScatter = pow(max(dot(ray, normalize(sunDir)), 0.0), 9.0) * smoothstep(-0.08, 0.20, sunDir.y);
  fogLight += lightColor * sunScatter * scatterParams.x;
  fogLight = encodeFogLight(fogLight);

  vec3 color = mix(scene, fogLight, fogAmount);

  if (cameraPosition.y < waterLevel) {
    vec2 overlayUv = fract(vUv * vec2(2.0, 1.35) + vec2(time * 0.012, -time * 0.007));
    vec4 overlay = texture(underwaterOverlay, overlayUv);
    float waterDistance = smoothstep(1.5, max(8.0, fogEnd * 0.45), distance);
    vec3 underwaterColor = vec3(0.035, 0.180, 0.330);
    color = mix(color, underwaterColor, 0.22 + waterDistance * 0.50);
    color += (overlay.rgb - 0.5) * overlay.a * 0.18;
  }

  FragColor = vec4(color, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

function effects.createSceneTarget(width, height)
  local colorTexture = ffi.new("GLuint[1]")
  local depthTexture = ffi.new("GLuint[1]")
  local framebuffer = ffi.new("GLuint[1]")

  gl.glGenTextures(1, colorTexture)
  gl.glBindTexture(GL_TEXTURE_2D, colorTexture[0])
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
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

function effects.ensureSceneTarget(target, width, height)
  if target and target.width == width and target.height == height then
    return target
  end

  return effects.createSceneTarget(width, height)
end

function effects.waterVertices(radius)
  local r = radius
  return {
    -r, 0, -r, 0,1,0, 1,1,1, 0,0,
     r, 0, -r, 0,1,0, 1,1,1, 1,0,
     r, 0,  r, 0,1,0, 1,1,1, 1,1,
     r, 0,  r, 0,1,0, 1,1,1, 1,1,
    -r, 0,  r, 0,1,0, 1,1,1, 0,1,
    -r, 0, -r, 0,1,0, 1,1,1, 0,0
  }
end

function effects.createShadowMap(size)
  local depthTexture = ffi.new("GLuint[1]")
  local framebuffer = ffi.new("GLuint[1]")

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
    depthTexture = depthTexture
  }
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

function effects.renderShadowPass(shadowShader, shadowMap, locations, terrainMeshes, characterMesh, lightSpaceMatrix, model, mapSize, viewportWidth, viewportHeight, atlasTex)
  gl.glViewport(0, 0, mapSize, mapSize)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, shadowMap.framebuffer[0])
  gl.glClear(GL_DEPTH_BUFFER_BIT)
  gl.glUseProgram(shadowShader)
  gl.glUniformMatrix4fv(locations.lightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
  gl.glUniformMatrix4fv(locations.model, 1, 0, ffi.new("float[16]", model))
  gl.glUniform1i(locations.tex0, 0)
  if atlasTex then
    gl.glActiveTexture(GL_TEXTURE0)
    gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
  end
  gl.glEnable(GL_POLYGON_OFFSET_FILL)
  gl.glPolygonOffset(2.0, 4.0)

  for _, mesh in pairs(terrainMeshes) do
    rendering.draw(mesh)
  end
  if characterMesh then
    rendering.draw(characterMesh)
  end

  gl.glDisable(GL_POLYGON_OFFSET_FILL)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  gl.glViewport(0, 0, viewportWidth, viewportHeight)
end

function effects.drawWater(waterShader, waterMesh, locations, playerCamera, view, projection, sunDir, atmosphere, time, waterLevel, waterTexture)
  local centerX = math.floor(playerCamera.position[1] / 16.0) * 16.0
  local centerZ = math.floor(playerCamera.position[3] / 16.0) * 16.0

  gl.glUseProgram(waterShader)
  gl.glUniformMatrix4fv(locations.projection, 1, 0, ffi.new("float[16]", projection))
  gl.glUniformMatrix4fv(locations.view, 1, 0, ffi.new("float[16]", view))
  gl.glUniform3f(locations.waterCenter, centerX, 0.0, centerZ)
  gl.glUniform1f(locations.waterLevel, waterLevel)
  gl.glUniform3f(locations.viewPos, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
  gl.glUniform3f(locations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(locations.fogColor, atmosphere.fogColor[1], atmosphere.fogColor[2], atmosphere.fogColor[3])
  gl.glUniform3f(locations.fogParams, atmosphere.fogStart, atmosphere.fogEnd, 0.0)
  gl.glUniform3f(locations.lightColor, atmosphere.lightColor[1], atmosphere.lightColor[2], atmosphere.lightColor[3])
  gl.glUniform3f(locations.skyZenithColor, atmosphere.skyZenith[1], atmosphere.skyZenith[2], atmosphere.skyZenith[3])
  gl.glUniform1f(locations.time, time)
  gl.glUniform1i(locations.waterTex, 0)

  if waterTexture then
    gl.glActiveTexture(GL_TEXTURE0)
    gl.glBindTexture(GL_TEXTURE_2D, waterTexture[0])
  end

  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  rendering.draw(waterMesh)
  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
end

function effects.drawAtmospherePost(postShader, screenMesh, locations, sceneTarget, playerCamera, sunDir, atmosphereState, fov, viewportWidth, viewportHeight, nearPlane, farPlane, waterLevel, settings, blurAmount, underwaterOverlayTexture, time)
  settings = settings or {}

  local forward = playerCamera:getFront()
  local worldUp = {0.0, 1.0, 0.0}
  local right = math3d.normalize(math3d.cross(forward, worldUp))
  local up = math3d.normalize(math3d.cross(right, forward))
  local projectionY = math.tan(fov / 2)
  local projectionX = viewportWidth / viewportHeight * projectionY

  gl.glDisable(GL_DEPTH_TEST)
  gl.glUseProgram(postShader)
  gl.glUniform1i(locations.sceneColor, 0)
  gl.glUniform1i(locations.sceneDepth, 1)
  gl.glUniform1i(locations.underwaterOverlay, 2)
  gl.glUniform3f(locations.cameraPosition, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
  gl.glUniform3f(locations.cameraForward, forward[1], forward[2], forward[3])
  gl.glUniform3f(locations.cameraRight, right[1], right[2], right[3])
  gl.glUniform3f(locations.cameraUp, up[1], up[2], up[3])
  gl.glUniform3f(locations.cameraProjection, projectionX, projectionY, 0.0)
  gl.glUniform3f(locations.sunDir, sunDir[1], sunDir[2], sunDir[3])
  gl.glUniform3f(locations.fogColor, atmosphereState.fogColor[1], atmosphereState.fogColor[2], atmosphereState.fogColor[3])
  gl.glUniform3f(locations.fogParams, atmosphereState.fogStart, atmosphereState.fogEnd, settings.maxFogAmount or 0.86)
  gl.glUniform3f(locations.skyZenithColor, atmosphereState.skyZenith[1], atmosphereState.skyZenith[2], atmosphereState.skyZenith[3])
  gl.glUniform3f(locations.lightColor, atmosphereState.lightColor[1], atmosphereState.lightColor[2], atmosphereState.lightColor[3])
  gl.glUniform3f(locations.depthParams, nearPlane, farPlane, waterLevel)
  gl.glUniform3f(locations.atmosphereParams, settings.heightFogDensity or 0.32, settings.heightFogFalloff or 0.080, settings.horizonFog or 0.22)
  gl.glUniform3f(locations.scatterParams, settings.sunScatter or 0.45, 0.0, 0.0)
  gl.glUniform1f(locations.blurAmount, blurAmount or 0.0)
  gl.glUniform1f(locations.time, time or 0.0)

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
  rendering.draw(screenMesh)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glEnable(GL_DEPTH_TEST)
end

return effects
