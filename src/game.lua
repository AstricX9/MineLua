local ffi = require("ffi")
local glfw = require("glfw")
local GL = require("gl")
local atmosphere = require("atmosphere")
local blocks = require("blocks")
local camera = require("camera")
local character = require("character")
local DistantTerrain = require("distant_terrain")
local effects = require("render_effects")
local graphics = require("graphics_settings")
local math3d = require("math3d")
local rendering = require("rendering")
local shaderModule = require("shader")
local texture = require("texture")
local voxel = require("voxel")
local World = require("world")

local game = {}

local gl = GL.gl

local GL_COLOR_BUFFER_BIT = 0x00004000
local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_DEPTH_TEST = 0x0B71
local GL_LESS = 0x0201
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
local GL_TEXTURE_CUBE_MAP_SEAMLESS = 0x884F
local GL_FRAMEBUFFER = 0x8D40

local WINDOW_W = graphics.window.width
local WINDOW_H = graphics.window.height
local windowWidth = WINDOW_W
local windowHeight = WINDOW_H
local CAMERA_FOV = math.rad(graphics.window.fovDegrees)
local CAMERA_NEAR = 0.1
local CAMERA_FAR = graphics.world.visualDistance or 4096.0
local TERRAIN_MAX_H = graphics.world.terrainMaxHeight
local CHUNK_RENDER_RADIUS = graphics.world.chunkRenderRadius
local VERTEX_STRIDE_FLOATS = 11
local FOG_START = graphics.atmosphere.fogStart
local FOG_END = graphics.atmosphere.fogEnd
local SUN_CYCLE_SPEED = graphics.atmosphere.sunCycleSpeed
local SHADOW_MAP_SIZE = graphics.shadows.mapSize
local SHADOW_DISTANCE = graphics.shadows.distance
local SHADOW_NEAR = graphics.shadows.near
local SHADOW_FAR = graphics.shadows.far
local WATER_LEVEL = graphics.water.level
local WATER_RADIUS = graphics.water.radius

local function createShaderProgram()
  local vertSource = [[
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;
out vec3 vColor;
out vec3 vNormal;
out vec3 vFragPos;
out vec2 vTexCoord;
uniform mat4 uProjection;
uniform mat4 uView;
uniform mat4 uModel;
void main() {
  vFragPos = vec3(uModel * vec4(aPos, 1.0));
  vNormal = mat3(transpose(inverse(uModel))) * aNormal;
  vColor = aColor;
  vTexCoord = aTexCoord;
  gl_Position = uProjection * uView * uModel * vec4(aPos, 1.0);
}
]]

  local fragSource = [[
#version 330 core
in vec3 vColor;
in vec3 vNormal;
in vec3 vFragPos;
in vec2 vTexCoord;
out vec4 FragColor;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform sampler2D tex0;
uniform sampler2D shadowMap;
uniform vec3 ambientColor;
uniform vec3 lightColor;
uniform vec3 faceLight;
uniform float exposure;
uniform float shadowStrength;
uniform mat4 lightSpaceMatrix;

vec3 tonemap(vec3 color) {
  color = color / (color + vec3(1.0));
  return pow(color, vec3(1.0 / 2.2));
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
  vec3 norm = normalize(vNormal);
  vec3 light = normalize(-lightDir);
  float diff = max(dot(norm, light), 0.0);
  vec3 viewDir = normalize(viewPos - vFragPos);
  vec3 reflectDir = reflect(-light, norm);
  float spec = pow(max(dot(viewDir, reflectDir), 0.0), 20.0);
  vec4 texColor = texture(tex0, vTexCoord);
  vec3 baseColor = vColor * texColor.rgb;
  if(texColor.a < 0.1) discard;
  float faceShade = faceLight.y;
  faceShade = mix(faceShade, faceLight.x, max(norm.y, 0.0));
  faceShade = mix(faceShade, faceLight.z, max(-norm.y, 0.0));
  baseColor *= faceShade;
  float shadow = shadowAt(norm, light, diff) * shadowStrength;
  vec3 ambient = ambientColor * baseColor;
  vec3 diffuse = diff * baseColor * lightColor * (1.0 - shadow);
  vec3 specular = lightColor * spec * 0.12 * (1.0 - shadow);
  vec3 litColor = ambient + diffuse + specular;
  FragColor = vec4(tonemap(litColor * exposure), texColor.a);
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
uniform vec3 cameraProjection;
uniform vec3 skyTuning;
uniform vec3 fogColor;
uniform sampler2D moonTex;
uniform samplerCube skyboxTex;

const float Br = 0.0025;
const float Bm = 0.0003;
const float g = 0.9800;
const vec3 nitrogen = vec3(0.650, 0.570, 0.475);
const vec3 Kr = Br / pow(nitrogen, vec3(4.0));
const vec3 Km = Bm / pow(nitrogen, vec3(0.84));
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
  float twilightAmount = 1.0 - smoothstep(0.08, 0.44, abs(sun.y));
  vec3 nightSky = mix(vec3(0.050, 0.085, 0.135), vec3(0.018, 0.030, 0.080), altitude);
  vec3 daySky = mix(vec3(0.67, 0.86, 0.98), vec3(0.22, 0.49, 0.88), altitude);
  vec3 twilightSky = mix(vec3(0.86, 0.42, 0.24), vec3(0.17, 0.15, 0.34), altitude);
  vec3 color = mix(nightSky, daySky, dayAmount);
  vec3 skyboxColor = texture(skyboxTex, vec3(pos.x, pos.y, -pos.z)).rgb;
  vec3 skyboxDetail = max(skyboxColor - vec3(0.055), vec3(0.0));
  color += skyboxDetail * nightAmount * smoothstep(0.22, 0.72, pos.y) * 0.18;
  color = mix(color, twilightSky, twilightAmount * smoothstep(0.0, 0.72, skyPos.y) * 0.62);

  float mu = max(dot(skyPos, sun), 0.0);
  float rayleigh = 3.0 / (8.0 * 3.14159) * (1.0 + mu * mu);
  vec3 mie = (Kr + Km * (1.0 - g * g) / (2.0 + g * g) / pow(max(1.0 + g * g - 2.0 * g * mu, 0.02), 1.5)) / (Br + Bm);
  vec3 scatter = rayleigh * mie * 0.045 * dayAmount;
  color += scatter;

  float cloudFade = smoothstep(0.10, 0.34, skyPos.y);
  float cloudHeight = max(skyPos.y, 0.24);
  float cirrus = smoothstep(0.35, 1.0, fbm(skyPos / cloudHeight * 2.0 + time.x * 0.008)) * 0.14 * cloudFade * skyTuning.y;
  vec3 cloudColor = mix(vec3(0.24, 0.28, 0.36), vec3(0.88, 0.92, 0.94), dayAmount);
  cloudColor = mix(cloudColor, vec3(0.98, 0.62, 0.40), twilightAmount * 0.32);
  color = mix(color, cloudColor, cirrus * 0.48);

  for (int i = 0; i < 3; i++) {
    float density = smoothstep(0.62, 1.0, fbm((0.7 + float(i) * 0.01) * skyPos / cloudHeight + time.x * 0.025));
    color = mix(color, cloudColor, min(density, 1.0) * cloudFade * 0.24 * skyTuning.y);
  }

  float moonAmount = max(dot(skyPos, moon), 0.0);
  float moonVisible = smoothstep(0.12, 0.28, -sun.y) * step(0.06, moon.y) * (1.0 - smoothstep(0.94, 0.985, dot(skyPos, sun)));
  float moonDisc = smoothstep(0.99935, 0.99972, moonAmount) * moonVisible;
  vec3 moonRight = normalize(cross(vec3(0.0, 1.0, 0.0), moon));
  vec3 moonUp = normalize(cross(moon, moonRight));
  vec2 moonUv = vec2(dot(skyPos, moonRight), dot(skyPos, moonUp)) / 0.035;
  vec2 moonSampleUv = moonUv * 0.5 + 0.5;
  vec3 moonColor = texture(moonTex, moonSampleUv).rgb;
  float moonImageMask = 1.0 - smoothstep(0.92, 1.0, length(moonUv));
  moonDisc *= moonImageMask;
  float moonPhase = clamp(dot(normalize(vec3(0.65, 0.2, 0.35)), normalize(vec3(moonUv, 0.35))) * 0.75 + 0.55, 0.0, 1.0);
  color = mix(color, moonColor * mix(0.45, 1.0, moonPhase), moonDisc);

  float sunAmount = max(dot(skyPos, sun), 0.0);
  float sunDisc = smoothstep(0.99982, 0.99994, sunAmount);
  vec3 sunTint = mix(vec3(1.0, 0.58, 0.28), vec3(1.0, 0.96, 0.82), dayAmount);
  color += sunTint * pow(sunAmount, 420.0) * 0.16 * max(dayAmount, 0.15) * skyTuning.z;
  color = mix(color, sunTint * 1.02, sunDisc * smoothstep(-0.06, 0.08, sun.y) * skyTuning.z);

  color += vec3(0.82, 0.88, 1.0) * stars(pos) * nightAmount * smoothstep(0.0, 0.18, pos.y);
  color = mix(color, vec3(0.98, 0.38, 0.18), horizonWarmth * smoothstep(0.0, 0.12, skyPos.y) * 0.15);
  color += noise(skyPos * 1000.0) * 0.006;
  color = vec3(1.0) - exp(-color * skyTuning.x);
  color = pow(color, vec3(1.08));
  color = mix(color, sunTint, sunDisc * smoothstep(-0.02, 0.08, sun.y));
  color = mix(fogColor, color, skyMask);
  FragColor = vec4(color, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function configureVertexAttributes()
  local stride = VERTEX_STRIDE_FLOATS * 4
  gl.glVertexAttribPointer(0, 3, GL_FLOAT, 0, stride, nil)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(1, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 3 * 4))
  gl.glEnableVertexAttribArray(1)
  gl.glVertexAttribPointer(2, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 6 * 4))
  gl.glEnableVertexAttribArray(2)
  gl.glVertexAttribPointer(3, 2, GL_FLOAT, 0, stride, ffi.cast("void*", 9 * 4))
  gl.glEnableVertexAttribArray(3)
end

local function uploadMesh(vertices)
  local vao = ffi.new("GLuint[1]")
  local vbo = ffi.new("GLuint[1]")
  local data = ffi.new("float[?]", #vertices, vertices)

  gl.glGenVertexArrays(1, vao)
  gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1, vbo)
  gl.glBindBuffer(GL_ARRAY_BUFFER, vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER, #vertices * 4, data, GL_STATIC_DRAW)
  configureVertexAttributes()

  return {
    vao = vao,
    vbo = vbo,
    count = #vertices / VERTEX_STRIDE_FLOATS,
    data = data
  }
end

local function uploadSkyMesh()
  local vertices = {
    -1, -1, 0, 0,0,1, 1,1,1, 0,0,
     3, -1, 0, 0,0,1, 1,1,1, 1,0,
    -1,  3, 0, 0,0,1, 1,1,1, 0,1
  }

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

local function createImageTexture(path)
  local img = texture.loadPng(path)
  if not img then
    error("Failed to load texture: " .. path)
  end

  local tex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, tex)
  gl.glBindTexture(GL_TEXTURE_2D, tex[0])
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img.w, img.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img.data)

  return tex
end

local function createSkyboxTexture(paths)
  local tex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, tex)
  gl.glBindTexture(GL_TEXTURE_CUBE_MAP, tex[0])

  for i = 1, #paths do
    local img = texture.loadPng(paths[i])
    if not img then
      error("Failed to load skybox texture: " .. paths[i])
    end

    gl.glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i - 1, 0, GL_RGBA, img.w, img.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img.data)
  end

  gl.glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  gl.glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

  return tex
end

local function createTerrainMesh(entry, world)
  return uploadMesh(voxel.meshChunk(entry.chunk, world.maxHeight, entry.offsetX, entry.offsetZ))
end

local function createTerrainMeshes(world)
  local meshes = {}

  world:eachChunk(function(chunk, entry)
    meshes[World.chunkKey(entry.chunkX, entry.chunkZ)] = createTerrainMesh(entry, world)
  end)

  return meshes
end

local function ensureTerrainMeshes(world, terrainMeshes, x, z)
  local added = world:ensureChunksAroundBlock(x, z)

  for i = 1, #added do
    local entry = added[i]
    terrainMeshes[World.chunkKey(entry.chunkX, entry.chunkZ)] = createTerrainMesh(entry, world)
  end
end

local function ensureDistantTerrainMeshes(distantTerrain, distantMeshes, x, z)
  local added = distantTerrain:ensureAround(x, z)

  for i = 1, #added do
    local tile = added[i]
    distantMeshes[tile.key] = uploadMesh(tile.vertices)
    tile.vertices = nil
  end
end

local function rebuildChunkMesh(world, terrainMeshes, chunkX, chunkZ)
  local key = World.chunkKey(chunkX, chunkZ)
  local entry = world.chunks[key]
  if entry then
    terrainMeshes[key] = createTerrainMesh(entry, world)
  end
end

local function rebuildBlockChunkMeshes(world, terrainMeshes, x, z)
  local localX, localZ, chunkX, chunkZ = world:localBlockCoord(x, z)
  rebuildChunkMesh(world, terrainMeshes, chunkX, chunkZ)

  if localX == 0 then
    rebuildChunkMesh(world, terrainMeshes, chunkX - 1, chunkZ)
  elseif localX == 15 then
    rebuildChunkMesh(world, terrainMeshes, chunkX + 1, chunkZ)
  end

  if localZ == 0 then
    rebuildChunkMesh(world, terrainMeshes, chunkX, chunkZ - 1)
  elseif localZ == 15 then
    rebuildChunkMesh(world, terrainMeshes, chunkX, chunkZ + 1)
  end
end

local function createCharacterMesh()
  local player = character.createPlayer({8, 6, 8})
  return uploadMesh(player:createMesh())
end

local function drawSky(skyShader, skyMesh, locations, moonTexture, skyboxTexture, playerCamera, sunDir, sky, time)
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
  gl.glUniform3f(locations.cameraProjection, windowWidth / windowHeight * math.tan(CAMERA_FOV / 2), math.tan(CAMERA_FOV / 2), 0.0)
  gl.glUniform3f(locations.skyTuning, graphics.atmosphere.skyExposure, graphics.atmosphere.cloudDensity, graphics.atmosphere.sunGlare)
  gl.glUniform3f(locations.fogColor, sky.fogColor[1], sky.fogColor[2], sky.fogColor[3])
  gl.glActiveTexture(GL_TEXTURE2)
  gl.glBindTexture(GL_TEXTURE_2D, moonTexture[0])
  gl.glActiveTexture(GL_TEXTURE3)
  gl.glBindTexture(GL_TEXTURE_CUBE_MAP, skyboxTexture[0])
  rendering.draw(skyMesh)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glEnable(GL_DEPTH_TEST)
end

local function updateViewportAndProjection(locP)
  gl.glViewport(0, 0, windowWidth, windowHeight)
  local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, CAMERA_NEAR, CAMERA_FAR)
  gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", projection))
end

local function createDisplayState()
  return {
    fullscreen = false,
    f11WasDown = false,
    escapeWasDown = false,
    breakWasDown = false,
    windowX = 100,
    windowY = 100,
    windowW = WINDOW_W,
    windowH = WINDOW_H
  }
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

local function updateFullscreenInput(window, state, locP)
  local f11Down = glfw.glfwGetKey(window, glfw.GLFW_KEY_F11) == glfw.GLFW_PRESS
  local escapeDown = glfw.glfwGetKey(window, glfw.GLFW_KEY_ESCAPE) == glfw.GLFW_PRESS

  if f11Down and not state.f11WasDown then
    setFullscreen(window, state, not state.fullscreen, locP)
  end

  if escapeDown and not state.escapeWasDown and state.fullscreen then
    setFullscreen(window, state, false, locP)
  end

  state.f11WasDown = f11Down
  state.escapeWasDown = escapeDown
end

local function updateBlockEditInput(window, state, world, terrainMeshes, playerCamera)
  local breakDown = glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS

  if breakDown and not state.breakWasDown then
    local hit = world:raycast(playerCamera.position, playerCamera:getFront(), graphics.player.reach or 6.0)
    if hit then
      world:setBlock(hit.x, hit.y, hit.z, blocks.air or 0)
      rebuildBlockChunkMeshes(world, terrainMeshes, hit.x, hit.z)
    end
  end

  state.breakWasDown = breakDown
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
  glfw.glfwSetInputMode(window, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_DISABLED)

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
    local moonTexture = createImageTexture("textures/sky/moon.png")
    local skyboxTexture = createSkyboxTexture({
      "textures/sky/kurt/space_rt.png",
      "textures/sky/kurt/space_lf.png",
      "textures/sky/kurt/space_up.png",
      "textures/sky/kurt/space_dn.png",
      "textures/sky/kurt/space_bk.png",
      "textures/sky/kurt/space_ft.png"
    })
    local world = World.new({
      chunkRadius = CHUNK_RENDER_RADIUS,
      maxHeight = TERRAIN_MAX_H
    })
    local terrainMeshes = createTerrainMeshes(world)
    local distantTerrain = DistantTerrain.new({
      maxHeight = TERRAIN_MAX_H,
      waterLevel = WATER_LEVEL,
      activeChunkRadius = CHUNK_RENDER_RADIUS,
      visualDistance = CAMERA_FAR,
      cacheDir = graphics.world.distantTerrainCache
    })
    local distantTerrainMeshes = {}
    local characterMesh = graphics.player.showDebugBody and createCharacterMesh() or nil
    local skyMesh = uploadSkyMesh()
    local waterMesh = uploadMesh(effects.waterVertices(WATER_RADIUS))
    local shadowMap = effects.createShadowMap(SHADOW_MAP_SIZE)
    local sceneTarget = effects.createSceneTarget(windowWidth, windowHeight)

    local shader = createShaderProgram()
    local shadowShader = effects.createShadowShader()
    local skyShader = createSkyShaderProgram()
    local waterShader = effects.createWaterShader()
    local atmospherePostShader = effects.createAtmospherePostShader()
    gl.glUseProgram(shader)

    local locP = gl.glGetUniformLocation(shader, "uProjection")
    local locV = gl.glGetUniformLocation(shader, "uView")
    local locM = gl.glGetUniformLocation(shader, "uModel")
    local locLight = gl.glGetUniformLocation(shader, "lightDir")
    local locViewPos = gl.glGetUniformLocation(shader, "viewPos")
    local locTex = gl.glGetUniformLocation(shader, "tex0")

    local locShadowMap = gl.glGetUniformLocation(shader, "shadowMap")
    local locAmbientColor = gl.glGetUniformLocation(shader, "ambientColor")
    local locLightColor = gl.glGetUniformLocation(shader, "lightColor")
    local locFaceLight = gl.glGetUniformLocation(shader, "faceLight")
    local locExposure = gl.glGetUniformLocation(shader, "exposure")
    local locShadowStrength = gl.glGetUniformLocation(shader, "shadowStrength")
    local locLightSpaceMatrix = gl.glGetUniformLocation(shader, "lightSpaceMatrix")
    local shadowLocations = {
      model = gl.glGetUniformLocation(shadowShader, "uModel"),
      lightSpaceMatrix = gl.glGetUniformLocation(shadowShader, "lightSpaceMatrix")
    }
    local skyLocations = {
      sunDir = gl.glGetUniformLocation(skyShader, "sunDir"),
      time = gl.glGetUniformLocation(skyShader, "time"),
      cameraForward = gl.glGetUniformLocation(skyShader, "cameraForward"),
      cameraRight = gl.glGetUniformLocation(skyShader, "cameraRight"),
      cameraUp = gl.glGetUniformLocation(skyShader, "cameraUp"),
      cameraProjection = gl.glGetUniformLocation(skyShader, "cameraProjection"),
      skyTuning = gl.glGetUniformLocation(skyShader, "skyTuning"),
      fogColor = gl.glGetUniformLocation(skyShader, "fogColor"),
      moonTex = gl.glGetUniformLocation(skyShader, "moonTex"),
      skyboxTex = gl.glGetUniformLocation(skyShader, "skyboxTex")
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
      time = gl.glGetUniformLocation(waterShader, "time")
    }
    local atmospherePostLocations = {
      sceneColor = gl.glGetUniformLocation(atmospherePostShader, "sceneColor"),
      sceneDepth = gl.glGetUniformLocation(atmospherePostShader, "sceneDepth"),
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
      scatterParams = gl.glGetUniformLocation(atmospherePostShader, "scatterParams")
    }

    local model = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}

    updateViewportAndProjection(locP)
    gl.glUniformMatrix4fv(locM, 1, 0, ffi.new("float[16]", model))
    gl.glUniform1i(locTex, 0)
    gl.glUniform1i(locShadowMap, 1)
    gl.glUseProgram(skyShader)
    gl.glUniform1i(skyLocations.moonTex, 2)
    gl.glUniform1i(skyLocations.skyboxTex, 3)
    gl.glUseProgram(shader)
    gl.glUniform3f(locFaceLight, graphics.terrain.topLight, graphics.terrain.sideLight, graphics.terrain.bottomLight)
    gl.glUniform1f(locExposure, graphics.terrain.exposure)

    local playerCamera = camera.new(graphics.player)
    playerCamera.position[2] = playerCamera:getGroundY(world)
    local displayState = createDisplayState()
    local lastTime = glfw.glfwGetTime()

    while glfw.glfwWindowShouldClose(window) == 0 do
      local currentTime = glfw.glfwGetTime()
      local dt = currentTime - lastTime
      lastTime = currentTime

      updateFullscreenInput(window, displayState, locP)
      ensureTerrainMeshes(world, terrainMeshes, playerCamera.position[1], playerCamera.position[3])
      playerCamera:update(dt, window, world)
      updateBlockEditInput(window, displayState, world, terrainMeshes, playerCamera)
      if graphics.world.distantTerrain then
        ensureDistantTerrainMeshes(distantTerrain, distantTerrainMeshes, playerCamera.position[1], playerCamera.position[3])
      end
      local sunDir = math3d.normalize(atmosphere.sunDirection(currentTime, SUN_CYCLE_SPEED))
      local sky = atmosphere.forSun(sunDir, FOG_START, FOG_END)
      local lightSpaceMatrix = effects.lightSpaceMatrix(playerCamera.position, sunDir, TERRAIN_MAX_H, SHADOW_DISTANCE, SHADOW_NEAR, SHADOW_FAR)
      effects.renderShadowPass(shadowShader, shadowMap, shadowLocations, terrainMeshes, characterMesh, lightSpaceMatrix, model, SHADOW_MAP_SIZE, windowWidth, windowHeight)

      sceneTarget = effects.ensureSceneTarget(sceneTarget, windowWidth, windowHeight)
      gl.glBindFramebuffer(GL_FRAMEBUFFER, sceneTarget.framebuffer[0])
      gl.glViewport(0, 0, windowWidth, windowHeight)

      local projection = math3d.perspective(CAMERA_FOV, windowWidth / windowHeight, CAMERA_NEAR, CAMERA_FAR)
      local view = math3d.lookAt(playerCamera.position, playerCamera:getCenter(), {0, 1, 0})
      gl.glUseProgram(shader)
      gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", projection))
      gl.glUniformMatrix4fv(locV, 1, 0, ffi.new("float[16]", view))
      gl.glUniformMatrix4fv(locLightSpaceMatrix, 1, 0, ffi.new("float[16]", lightSpaceMatrix))
      gl.glUniform3f(locViewPos, playerCamera.position[1], playerCamera.position[2], playerCamera.position[3])
      gl.glUniform3f(locLight, -sunDir[1], -sunDir[2], -sunDir[3])
      gl.glUniform3f(locAmbientColor, sky.ambient[1], sky.ambient[2], sky.ambient[3])
      gl.glUniform3f(locLightColor, sky.lightColor[1], sky.lightColor[2], sky.lightColor[3])
      gl.glUniform1f(locShadowStrength, sky.shadowStrength)

      gl.glClearColor(sky.fogColor[1], sky.fogColor[2], sky.fogColor[3], 1.0)
      gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)
      drawSky(skyShader, skyMesh, skyLocations, moonTexture, skyboxTexture, playerCamera, sunDir, sky, currentTime)
      gl.glClear(GL_DEPTH_BUFFER_BIT)

      gl.glUseProgram(shader)
      gl.glActiveTexture(GL_TEXTURE0)
      gl.glBindTexture(GL_TEXTURE_2D, atlasTex[0])
      gl.glActiveTexture(GL_TEXTURE1)
      gl.glBindTexture(GL_TEXTURE_2D, shadowMap.depthTexture[0])
      gl.glActiveTexture(GL_TEXTURE0)
      if graphics.world.distantTerrain then
        for _, key in ipairs(distantTerrain.visible) do
          local mesh = distantTerrainMeshes[key]
          if mesh then
            rendering.draw(mesh)
          end
        end
      end
      for _, mesh in pairs(terrainMeshes) do
        rendering.draw(mesh)
      end
      if characterMesh then
        rendering.draw(characterMesh)
      end
      effects.drawWater(waterShader, waterMesh, waterLocations, playerCamera, view, projection, sunDir, sky, currentTime, WATER_LEVEL)

      gl.glBindFramebuffer(GL_FRAMEBUFFER, 0)
      gl.glViewport(0, 0, windowWidth, windowHeight)
      effects.drawAtmospherePost(atmospherePostShader, skyMesh, atmospherePostLocations, sceneTarget, playerCamera, sunDir, sky, CAMERA_FOV, windowWidth, windowHeight, CAMERA_NEAR, CAMERA_FAR, WATER_LEVEL, graphics.atmosphere)

      glfw.glfwSwapBuffers(window)
      glfw.glfwPollEvents()
    end
  end)

  glfw.glfwTerminate()

  if not ok then
    error(err)
  end
end

return game
