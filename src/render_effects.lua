local ffi = require("ffi")
local GL = require("gl")
local math3d = require("math3d")
local rendering = require("rendering")
local shaderModule = require("shader")

local effects = {}

local gl = GL.gl

local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_TEXTURE_2D = 0x0DE1
local GL_TEXTURE_MIN_FILTER = 0x2801
local GL_TEXTURE_MAG_FILTER = 0x2800
local GL_TEXTURE_WRAP_S = 0x2802
local GL_TEXTURE_WRAP_T = 0x2803
local GL_LINEAR = 0x2601
local GL_CLAMP_TO_EDGE = 0x812F
local GL_DEPTH_COMPONENT = 0x1902
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_UNSIGNED_INT = 0x1405
local GL_FRAMEBUFFER = 0x8D40
local GL_DEPTH_ATTACHMENT = 0x8D00
local GL_FRAMEBUFFER_COMPLETE = 0x8CD5
local GL_NONE = 0
local GL_POLYGON_OFFSET_FILL = 0x8037
local GL_BLEND = 0x0BE2
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303

function effects.createShadowShader()
  local vertSource = [[
#version 330 core
layout (location = 0) in vec3 aPos;
uniform mat4 uModel;
uniform mat4 lightSpaceMatrix;
void main() {
  gl_Position = lightSpaceMatrix * uModel * vec4(aPos, 1.0);
}
]]

  local fragSource = [[
#version 330 core
void main() {
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
  vUv = aPos.xz * 0.045 + waterCenter.xz * 0.003;
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

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

float waveHeight(vec2 p) {
  float waves = sin(p.x * 3.4 + time * 0.85) * 0.055;
  waves += sin((p.x + p.y) * 2.1 - time * 0.62) * 0.040;
  waves += (noise(p * 1.8 + time * 0.035) - 0.5) * 0.075;
  return waves;
}

vec3 tonemap(vec3 color) {
  color = color / (color + vec3(1.0));
  return pow(color, vec3(1.0 / 2.2));
}

void main() {
  vec2 p = vUv;
  float h = waveHeight(p);
  float hx = waveHeight(p + vec2(0.035, 0.0)) - h;
  float hz = waveHeight(p + vec2(0.0, 0.035)) - h;
  vec3 normal = normalize(vec3(-hx * 16.0, 1.0, -hz * 16.0));
  vec3 viewDir = normalize(viewPos - vWorldPos);
  vec3 sun = normalize(sunDir);

  float fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 4.5);
  vec3 reflectionDir = reflect(-viewDir, normal);
  float skyFactor = clamp(reflectionDir.y * 0.5 + 0.5, 0.0, 1.0);
  vec3 reflectedSky = mix(fogColor * 0.75, skyZenithColor * 1.35, skyFactor);
  vec3 shallowWater = vec3(0.13, 0.48, 0.50);
  vec3 deepWater = vec3(0.015, 0.13, 0.22);
  vec3 waterColor = mix(deepWater, shallowWater, 0.42 + noise(p * 0.8) * 0.12);

  vec3 halfDir = normalize(viewDir + sun);
  float sparkleMask = pow(max(dot(normal, halfDir), 0.0), 230.0);
  sparkleMask += pow(max(dot(normal, halfDir), 0.0), 48.0) * 0.18;
  float sunFacing = smoothstep(-0.08, 0.16, sun.y);
  vec3 sunGlint = lightColor * sparkleMask * 5.8 * sunFacing;

  vec3 color = mix(waterColor, reflectedSky, 0.24 + fresnel * 0.68);
  color += sunGlint;
  color += vec3(0.07, 0.18, 0.20) * max(dot(normal, sun), 0.0) * 0.24;

  float fogDistance = length(viewPos - vWorldPos);
  float fogAmount = smoothstep(fogParams.x * 0.85, fogParams.y, fogDistance);
  color = mix(color, fogColor, fogAmount);

  float alpha = mix(0.54, 0.82, fresnel) + smoothstep(55.0, 105.0, fogDistance) * 0.10;
  FragColor = vec4(tonemap(color * 1.28), clamp(alpha, 0.48, 0.90));
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
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

function effects.renderShadowPass(shadowShader, shadowMap, locations, terrainMeshes, characterMesh, lightSpaceMatrix, model, mapSize, viewportWidth, viewportHeight)
  gl.glViewport(0, 0, mapSize, mapSize)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, shadowMap.framebuffer[0])
  gl.glClear(GL_DEPTH_BUFFER_BIT)
  gl.glUseProgram(shadowShader)
  gl.glUniformMatrix4fv(locations.lightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
  gl.glUniformMatrix4fv(locations.model, 1, 0, ffi.new("float[16]", model))
  gl.glEnable(GL_POLYGON_OFFSET_FILL)
  gl.glPolygonOffset(2.0, 4.0)

  for _, mesh in pairs(terrainMeshes) do
    rendering.draw(mesh)
  end
  rendering.draw(characterMesh)

  gl.glDisable(GL_POLYGON_OFFSET_FILL)
  gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
  gl.glViewport(0, 0, viewportWidth, viewportHeight)
end

function effects.drawWater(waterShader, waterMesh, locations, playerCamera, view, projection, sunDir, atmosphere, time, waterLevel)
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

  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  rendering.draw(waterMesh)
  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
end

return effects
