local ffi = require("ffi")
local GL = require("gl")
local shaderModule = require("shader")
local rendering = require("rendering")
local texture = require("texture")
local uiMenu = require("ui_menu")
local blocks = require("blocks")
local items = require("items")
local itemMesh = require("item_mesh")
local heldItem = require("held_item")

local hud = {}
hud.__index = hud

local gl = GL.gl

local GL_ARRAY_BUFFER = 0x8892
local GL_STATIC_DRAW = 0x88E4
local GL_FLOAT = 0x1406
local GL_TRIANGLES = 0x0004
local GL_DEPTH_TEST = 0x0B71
local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_LESS = 0x0201
local GL_BLEND = 0x0BE2
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303
local GL_TEXTURE_2D = 0x0DE1
local GL_TEXTURE_MIN_FILTER = 0x2801
local GL_TEXTURE_MAG_FILTER = 0x2800
local GL_TEXTURE_WRAP_S = 0x2802
local GL_TEXTURE_WRAP_T = 0x2803
local GL_NEAREST = 0x2600
local GL_LINEAR = 0x2601
local GL_REPEAT = 0x2901
local GL_CLAMP_TO_EDGE = 0x812F
local GL_RGBA = 0x1908
local GL_UNSIGNED_BYTE = 0x1401
local GL_TEXTURE0 = 0x84C0

local STRIDE_FLOATS = 11

-- How long a newly selected item takes to rise into frame.
local HELD_EQUIP_SECONDS = 0.24

local COLORS = {
  white = {1.0, 1.0, 1.0, 1.0},
  black = {0.02, 0.02, 0.02, 0.88},
  heart = {0.95, 0.04, 0.03, 1.0},
  heartDark = {0.30, 0.00, 0.00, 1.0},
  hunger = {0.73, 0.36, 0.12, 1.0},
  armor = {0.72, 0.76, 0.78, 1.0},
  xp = {0.38, 0.95, 0.12, 1.0},
  skin = {0.64, 0.38, 0.28, 1.0},
  skinLight = {0.78, 0.50, 0.38, 1.0},
  skinDark = {0.42, 0.23, 0.17, 1.0},
  shadow = {0.0, 0.0, 0.0, 0.72},
  panel = {0.0, 0.0, 0.0, 0.72},
  fieldBorder = {0.66, 0.66, 0.66, 1.0},
  field = {0.0, 0.0, 0.0, 1.0}
}

local function createShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aInfo;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;
out vec4 vColor;
out vec2 vTexCoord;
out float vUseTexture;
uniform float uTime;

void main() {
  gl_Position = vec4(aPos.xy, 0.0, 1.0);
  vColor = vec4(aColor, aInfo.x);
  vTexCoord = aTexCoord;
  vUseTexture = step(0.5, aInfo.y);
}
]]

  local fragSource = [[
#version 460 core
in vec4 vColor;
in vec2 vTexCoord;
in float vUseTexture;
out vec4 FragColor;
uniform sampler2D uTexture;

void main() {
  vec4 sampled = texture(uTexture, vTexCoord);
  vec4 color = mix(vec4(1.0), sampled, step(0.5, vUseTexture)) * vColor;
  if (color.a < 0.01) discard;
  FragColor = color;
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

-- The held model is a separate program from the flat HUD: it owns a real
-- vertex format (position, normal, texture coordinate) and finishes its own
-- projection, so animating it costs nothing but a handful of uniforms.
local function createHeldShader()
  local vertSource = [[
#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoord;
out vec2 vTexCoord;
out vec3 vNormal;
uniform mat3 uPose;        // authored orientation
uniform mat3 uSwing;       // animation, applied about the wrist
uniform vec3 uModelScale;  // per-axis scale of the unit model
uniform vec3 uPivot;       // wrist position in posed model space
uniform vec3 uTranslate;   // animation offset in posed model space
uniform vec2 uCenter;      // model origin in normalised device coordinates
uniform vec2 uScale;       // device units per model unit
uniform vec3 uProjection;  // camera distance, near plane, far plane

void main() {
  vec3 posed = uPose * (aPos * uModelScale);
  vec3 model = uSwing * (posed - uPivot) + uPivot + uTranslate;
  float cameraZ = max(uProjection.x - model.z, 0.05);
  float perspective = uProjection.x / cameraZ;
  vec2 device = uCenter + model.xy * uScale * perspective;
  float near = uProjection.y;
  float far = uProjection.z;
  float depth = (far + near) / (far - near) - (2.0 * far * near) / ((far - near) * cameraZ);
  // The perspective divide is finished here and the clip W stays 1. Every
  // quad in this model carries a constant texture coordinate, so none of them
  // needs a perspective-correct interpolant, and a unit W keeps the varyings
  // out of the driver's perspective rescaling entirely.
  gl_Position = vec4(device, clamp(depth, -1.0, 1.0), 1.0);
  vTexCoord = aTexCoord;
  vNormal = uSwing * (uPose * aNormal);
}
]]

  local fragSource = [[
#version 460 core
in vec2 vTexCoord;
in vec3 vNormal;
out vec4 FragColor;
uniform sampler2D uTexture;
uniform vec3 uTint;
uniform vec3 uAmbient;
uniform vec3 uSunColor;
uniform vec3 uMoonColor;
uniform vec3 uLightDir;
uniform vec3 uParams; // local skylight, underwater amount, ambient floor

vec3 srgbToLinear(vec3 color) {
  return pow(max(color, vec3(0.0)), vec3(2.2));
}

vec3 linearToSrgb(vec3 color) {
  return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
}

void main() {
  vec4 sampled = texture(uTexture, vTexCoord);
  if (sampled.a < 0.5) discard;
  vec3 normal = normalize(vNormal);
  vec3 sunDirection = normalize(uLightDir);
  float sunDiffuse = max(dot(normal, sunDirection), 0.0);
  float moonDiffuse = max(dot(normal, -sunDirection), 0.0);
  float localLight = mix(0.08, 1.0, clamp(uParams.x, 0.0, 1.0));
  vec3 totalLight = uAmbient * localLight;
  totalLight += uSunColor * mix(0.26, 1.0, sunDiffuse) * localLight;
  totalLight += uMoonColor * mix(0.34, 0.82, moonDiffuse) * localLight;
  totalLight = max(totalLight, vec3(uParams.z));
  vec3 color = linearToSrgb(srgbToLinear(sampled.rgb * uTint) * totalLight);
  float underwater = clamp(uParams.y, 0.0, 1.0);
  color = mix(color, color * vec3(0.30, 0.68, 0.88), underwater * 0.58);
  FragColor = vec4(color, 1.0);
}
]]

  return shaderModule.fromSource(vertSource, fragSource)
end

local function ndcX(x, width)
  return x / width * 2.0 - 1.0
end

local function ndcY(y, height)
  return 1.0 - y / height * 2.0
end

local function appendVertex(vertices, x, y, color, u, v, useTexture, fallSpeed)
  vertices[#vertices + 1] = x
  vertices[#vertices + 1] = y
  vertices[#vertices + 1] = 0.0
  vertices[#vertices + 1] = color[4] or 1.0
  vertices[#vertices + 1] = useTexture or 0.0
  vertices[#vertices + 1] = fallSpeed or 0.0
  vertices[#vertices + 1] = color[1]
  vertices[#vertices + 1] = color[2]
  vertices[#vertices + 1] = color[3]
  vertices[#vertices + 1] = u or 0.0
  vertices[#vertices + 1] = v or 0.0
end

local function appendQuad(vertices, points, color, uvs, useTexture, fallSpeed)
  appendVertex(vertices, points[1][1], points[1][2], color, uvs[1][1], uvs[1][2], useTexture, fallSpeed)
  appendVertex(vertices, points[2][1], points[2][2], color, uvs[2][1], uvs[2][2], useTexture, fallSpeed)
  appendVertex(vertices, points[3][1], points[3][2], color, uvs[3][1], uvs[3][2], useTexture, fallSpeed)
  appendVertex(vertices, points[3][1], points[3][2], color, uvs[3][1], uvs[3][2], useTexture, fallSpeed)
  appendVertex(vertices, points[4][1], points[4][2], color, uvs[4][1], uvs[4][2], useTexture, fallSpeed)
  appendVertex(vertices, points[1][1], points[1][2], color, uvs[1][1], uvs[1][2], useTexture, fallSpeed)
end

local function appendRect(vertices, width, height, x, y, w, h, color)
  appendQuad(vertices, {
    {ndcX(x, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y + h, height)},
    {ndcX(x, width), ndcY(y + h, height)}
  }, color, {{0, 0}, {0, 0}, {0, 0}, {0, 0}}, 0.0, 0.0)
end

local function appendSprite(vertices, width, height, x, y, w, h, sx, sy, sw, sh, tw, th, color, fallSpeed)
  local u0 = sx / tw
  local v0 = sy / th
  local u1 = (sx + sw) / tw
  local v1 = (sy + sh) / th

  appendQuad(vertices, {
    {ndcX(x, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y + h, height)},
    {ndcX(x, width), ndcY(y + h, height)}
  }, color or COLORS.white, {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}, 1.0, fallSpeed or 0.0)
end

local function appendRotatedSprite(vertices, width, height, x, y, w, h, sx, sy, sw, sh, tw, th, color, angle, pivotX, pivotY)
  local cosine, sine = math.cos(angle or 0.0), math.sin(angle or 0.0)
  pivotX, pivotY = pivotX or (x + w * 0.5), pivotY or (y + h * 0.5)
  local function rotate(px, py)
    local dx, dy = px - pivotX, py - pivotY
    return {ndcX(pivotX + dx * cosine - dy * sine, width), ndcY(pivotY + dx * sine + dy * cosine, height)}
  end
  appendQuad(vertices, {
    rotate(x, y), rotate(x + w, y), rotate(x + w, y + h), rotate(x, y + h)
  }, color or COLORS.white, {
    {sx/tw,sy/th},{(sx+sw)/tw,sy/th},{(sx+sw)/tw,(sy+sh)/th},{sx/tw,(sy+sh)/th}
  }, 1.0, 0.0)
end

local function appendSpriteUv(vertices, width, height, x, y, w, h, u0, v0, u1, v1, color)
  appendQuad(vertices, {
    {ndcX(x, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y + h, height)},
    {ndcX(x, width), ndcY(y + h, height)}
  }, color or COLORS.white, {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}, 1.0, 0.0)
end

local guiScaleOverride = nil

local function guiScale(width, height)
  local scale = 1
  while scale < 4 and width / (scale + 1) >= 320 and height / (scale + 1) >= 240 do
    scale = scale + 1
  end
  if guiScaleOverride then
    return math.max(1, math.min(guiScaleOverride, scale))
  end
  return scale
end

local function colorFromRgb(value, alpha)
  local r = math.floor(value / 65536) % 256
  local g = math.floor(value / 256) % 256
  local b = value % 256
  return {r / 255.0, g / 255.0, b / 255.0, alpha or 1.0}
end

local TEXT_WHITE = colorFromRgb(0xFFFFFF)
local TEXT_NORMAL = colorFromRgb(0xE0E0E0)
local TEXT_HOVER = colorFromRgb(0xFFFFA0)
local TEXT_DISABLED = colorFromRgb(0xA0A0A0)
local TEXT_MUTED = colorFromRgb(0xA0A0A0)
local TEXT_YELLOW = colorFromRgb(0xFFFF00)

local glyphMetrics = nil

local function loadGlyphMetrics()
  if glyphMetrics then
    return glyphMetrics
  end

  glyphMetrics = {}
  for code = 0, 255 do
    glyphMetrics[code] = {left = 0, width = 8, advance = 8}
  end
  glyphMetrics[32] = {left = 0, width = 0, advance = 4}

  local img = texture.loadPng("assets/textures/font/ascii.png")
  if not img then
    return glyphMetrics
  end

  for code = 0, 255 do
    if code == 32 then
      glyphMetrics[code] = {left = 0, width = 0, advance = 4}
    else
      local cellX = (code % 16) * 8
      local cellY = math.floor(code / 16) * 8
      local left = 8
      local right = -1

      for py = 0, 7 do
        for px = 0, 7 do
          local idx = ((cellY + py) * img.w + cellX + px) * 4
          if img.data[idx + 3] > 8 then
            left = math.min(left, px)
            right = math.max(right, px)
          end
        end
      end

      if right < left then
        left = 0
        right = 7
      end

      local glyphWidth = right - left + 1
      glyphMetrics[code] = {
        left = left,
        width = glyphWidth,
        advance = math.min(8, right + 2)
      }
    end
  end

  return glyphMetrics
end

local function glyphMetric(code)
  return loadGlyphMetrics()[code] or loadGlyphMetrics()[63]
end

local function textWidth(text)
  text = tostring(text or "")
  local width = 0
  for i = 1, #text do
    local code = string.byte(text, i)
    if code and code >= 32 and code < 256 then
      width = width + glyphMetric(code).advance
    end
  end
  return width
end

local function appendTextRaw(vertices, width, height, scale, text, x, y, color)
  text = tostring(text or "")
  local cursor = math.floor(x * scale + 0.5)
  local py = math.floor(y * scale + 0.5)
  for i = 1, #text do
    local code = string.byte(text, i)
    if code and code >= 32 and code < 256 then
      local metric = glyphMetric(code)
      if code ~= 32 and metric.width > 0 then
        local sx = (code % 16) * 8 + metric.left
        local sy = math.floor(code / 16) * 8
        appendSprite(vertices, width, height, cursor + metric.left * scale, py, metric.width * scale, 8 * scale, sx, sy, metric.width, 8, 128, 128, color)
      end
      cursor = cursor + metric.advance * scale
    end
  end
end

local function appendText(vertices, width, height, scale, text, x, y, color, shadow)
  if shadow ~= false then
    appendTextRaw(vertices, width, height, scale, text, x + 1, y + 1, COLORS.shadow)
  end
  appendTextRaw(vertices, width, height, scale, text, x, y, color or TEXT_WHITE)
end

local function appendCenteredText(vertices, width, height, scale, text, cx, y, color)
  appendText(vertices, width, height, scale, text, math.floor(cx - textWidth(text) * 0.5 + 0.5), y, color or TEXT_WHITE)
end

local function appendScaledSprite(vertices, width, height, scale, x, y, w, h, sx, sy, sw, sh, tw, th, color)
  appendSprite(vertices, width, height, x * scale, y * scale, w * scale, h * scale, sx, sy, sw, sh, tw, th, color)
end

local function appendScaledRect(vertices, width, height, scale, x, y, w, h, color)
  appendRect(vertices, width, height, x * scale, y * scale, w * scale, h * scale, color)
end

local function appendDirtBackground(vertices, width, height, scale, logicalWidth, logicalHeight)
  appendSpriteUv(vertices, width, height, 0, 0, logicalWidth * scale, logicalHeight * scale, 0, 0, logicalWidth / 32.0, logicalHeight / 32.0, {0.25, 0.25, 0.25, 1.0})
end

local function rotatePoint(x, y, z, yaw, pitch)
  local cy = math.cos(yaw)
  local sy = math.sin(yaw)
  local cp = math.cos(pitch)
  local sp = math.sin(pitch)
  local rx = x * cy - z * sy
  local rz = x * sy + z * cy
  local ry = y * cp - rz * sp
  rz = y * sp + rz * cp
  return rx, ry, rz
end

local function panoramaSample(logicalX, logicalY, logicalWidth, logicalHeight, yaw, pitch)
  local aspect = logicalWidth / math.max(1, logicalHeight)
  local fov = math.rad(70.0)
  local px = ((logicalX / logicalWidth) * 2.0 - 1.0) * math.tan(fov * 0.5) * aspect
  local py = (1.0 - (logicalY / logicalHeight) * 2.0) * math.tan(fov * 0.5)
  local dx, dy, dz = rotatePoint(px, py, 1.0, yaw, pitch)
  local ax = math.abs(dx)
  local ay = math.abs(dy)
  local az = math.abs(dz)

  if ax >= ay and ax >= az then
    if dx > 0.0 then
      local t = 1.0 / ax
      return 2, (1.0 - dz * t) * 0.5, (1.0 - dy * t) * 0.5
    end
    local t = 1.0 / ax
    return 4, (dz * t + 1.0) * 0.5, (1.0 - dy * t) * 0.5
  elseif ay >= ax and ay >= az then
    if dy > 0.0 then
      local t = 1.0 / ay
      return 5, (dx * t + 1.0) * 0.5, (dz * t + 1.0) * 0.5
    end
    local t = 1.0 / ay
    return 6, (dx * t + 1.0) * 0.5, (1.0 - dz * t) * 0.5
  elseif dz > 0.0 then
    local t = 1.0 / az
    return 1, (dx * t + 1.0) * 0.5, (1.0 - dy * t) * 0.5
  end

  local t = 1.0 / az
  return 3, (1.0 - dx * t) * 0.5, (1.0 - dy * t) * 0.5
end

local function panoramaUvForFace(face, logicalX, logicalY, logicalWidth, logicalHeight, yaw, pitch)
  local aspect = logicalWidth / math.max(1, logicalHeight)
  local fov = math.rad(70.0)
  local px = ((logicalX / logicalWidth) * 2.0 - 1.0) * math.tan(fov * 0.5) * aspect
  local py = (1.0 - (logicalY / logicalHeight) * 2.0) * math.tan(fov * 0.5)
  local dx, dy, dz = rotatePoint(px, py, 1.0, yaw, pitch)
  local t = 1.0

  if face == 1 then
    t = dz ~= 0.0 and 1.0 / dz or 1.0
    return (dx * t + 1.0) * 0.5, (1.0 - dy * t) * 0.5
  elseif face == 2 then
    t = dx ~= 0.0 and 1.0 / dx or 1.0
    return (1.0 - dz * t) * 0.5, (1.0 - dy * t) * 0.5
  elseif face == 3 then
    t = dz ~= 0.0 and -1.0 / dz or 1.0
    return (1.0 - dx * t) * 0.5, (1.0 - dy * t) * 0.5
  elseif face == 4 then
    t = dx ~= 0.0 and -1.0 / dx or 1.0
    return (dz * t + 1.0) * 0.5, (1.0 - dy * t) * 0.5
  elseif face == 5 then
    t = dy ~= 0.0 and 1.0 / dy or 1.0
    return (dx * t + 1.0) * 0.5, (dz * t + 1.0) * 0.5
  end

  t = dy ~= 0.0 and -1.0 / dy or 1.0
  return (dx * t + 1.0) * 0.5, (1.0 - dz * t) * 0.5
end

local function appendPanoramaCube(faceMeshes, width, height, scale, logicalWidth, logicalHeight, time, alpha, offsetX, offsetY)
  alpha = alpha or 1.0
  offsetX = offsetX or 0.0
  offsetY = offsetY or 0.0
  local yaw = (time or 0.0) * 0.055
  local pitch = math.sin((time or 0.0) * 0.025) * 0.035 - 0.03
  local tile = 7
  local color = {1.0, 1.0, 1.0, alpha}

  for y = 0, logicalHeight - 1, tile do
    local y1 = math.min(logicalHeight, y + tile)
    for x = 0, logicalWidth - 1, tile do
      local x1 = math.min(logicalWidth, x + tile)
      local face = panoramaSample((x + x1) * 0.5, (y + y1) * 0.5, logicalWidth, logicalHeight, yaw, pitch)
      local u0, v0 = panoramaUvForFace(face, x, y, logicalWidth, logicalHeight, yaw, pitch)
      local u1, v1 = panoramaUvForFace(face, x1, y, logicalWidth, logicalHeight, yaw, pitch)
      local u2, v2 = panoramaUvForFace(face, x1, y1, logicalWidth, logicalHeight, yaw, pitch)
      local u3, v3 = panoramaUvForFace(face, x, y1, logicalWidth, logicalHeight, yaw, pitch)
      appendQuad(faceMeshes[face], {
        {ndcX((x + offsetX) * scale, width), ndcY((y + offsetY) * scale, height)},
        {ndcX((x1 + offsetX) * scale, width), ndcY((y + offsetY) * scale, height)},
        {ndcX((x1 + offsetX) * scale, width), ndcY((y1 + offsetY) * scale, height)},
        {ndcX((x + offsetX) * scale, width), ndcY((y1 + offsetY) * scale, height)}
      }, color, {{u0, v0}, {u1, v1}, {u2, v2}, {u3, v3}}, 1.0, 0.0)
    end
  end
end

local function isHovered(button, mouseX, mouseY)
  return mouseX >= button.x and mouseY >= button.y and mouseX < button.x + button.w and mouseY < button.y + button.h
end

local function appendButton(meshes, width, height, scale, button, mouseX, mouseY)
  local enabled = button.enabled ~= false
  local hover = enabled and isHovered(button, mouseX, mouseY)
  local row = enabled and (hover and 86 or 66) or 46
  local half = math.floor(button.w / 2)
  appendScaledSprite(meshes.widgets, width, height, scale, button.x, button.y, half, button.h, 0, row, half, 20, 256, 256, COLORS.white)
  appendScaledSprite(meshes.widgets, width, height, scale, button.x + half, button.y, button.w - half, button.h, 200 - (button.w - half), row, button.w - half, 20, 256, 256, COLORS.white)
  local textColor = enabled and (hover and TEXT_HOVER or TEXT_NORMAL) or TEXT_DISABLED
  appendCenteredText(meshes.font, width, height, scale, button.label, button.x + button.w * 0.5, button.y + 6, textColor)
end

local function appendSlider(meshes, width, height, scale, button, mouseX, mouseY)
  appendButton(meshes, width, height, scale, button, mouseX, mouseY)
  local minimum = button.minValue or 0
  local maximum = button.maxValue or 1
  local value = math.max(minimum, math.min(maximum, button.value or minimum))
  local amount = (value - minimum) / math.max(1, maximum - minimum)
  local knobX = button.x + math.floor((button.w - 8) * amount)
  appendScaledSprite(meshes.widgets, width, height, scale, knobX, button.y, 4, 20, 0, 66, 4, 20, 256, 256, COLORS.white)
  appendScaledSprite(meshes.widgets, width, height, scale, knobX + 4, button.y, 4, 20, 196, 66, 4, 20, 256, 256, COLORS.white)
end

local function appendTextBox(meshes, width, height, scale, x, y, w, h, text)
  appendScaledRect(meshes.color, width, height, scale, x - 1, y - 1, w + 2, h + 2, COLORS.fieldBorder)
  appendScaledRect(meshes.color, width, height, scale, x, y, w, h, COLORS.field)
  appendText(meshes.font, width, height, scale, text, x + 4, y + 6, TEXT_WHITE)
end

local function appendMinecraftLogo(meshes, width, height, scale, cx)
  local x = cx - 137
  local y = 30
  appendScaledSprite(meshes.logo, width, height, scale, x, y, 155, 44, 0, 0, 155, 44, 256, 256, COLORS.white)
  appendScaledSprite(meshes.logo, width, height, scale, x + 155, y, 155, 44, 0, 45, 155, 44, 256, 256, COLORS.white)
end

local function appendStandaloneIcon(vertices, width, height, x, y, nativeWidth, nativeHeight)
  local scale = 2
  appendSprite(
    vertices, width, height,
    x + (9 - nativeWidth), y + (9 - nativeHeight),
    nativeWidth * scale, nativeHeight * scale,
    0, 0, nativeWidth, nativeHeight, nativeWidth, nativeHeight, COLORS.white
  )
end

local function appendStatusIcon(meshes, kind, width, height, x, y, value)
  appendStandaloneIcon(meshes[kind .. "Empty"], width, height, x, y, 9, 9)
  if value >= 2 then
    appendStandaloneIcon(meshes[kind], width, height, x, y, 7, 7)
  elseif value >= 1 then
    local halfWidth = kind == "hunger" and 6 or 7
    appendStandaloneIcon(meshes[kind .. "Half"], width, height, x, y, halfWidth, 7)
  end
end

local function appendStatusBars(meshes, width, height, state)
  state = state or {}
  local center = math.floor(width * 0.5)
  local left = center - 184
  local right = center + 24
  local y = height - 86
  local health = math.max(0, math.min(20, state.health or 20))
  local hunger = math.max(0, math.min(20, state.hunger or 20))

  for i = 0, 9 do
    appendStatusIcon(meshes, "heart", width, height, left + i * 18, y, health - i * 2)
    appendStatusIcon(meshes, "hunger", width, height, right + i * 18, y, hunger - i * 2)
  end
end

local function appendHotbar(vertices, width, height, selectedSlot)
  local scale = 2
  local hotbarW = 182 * scale
  local hotbarH = 22 * scale
  local x = math.floor((width - hotbarW) * 0.5)
  local y = height - 58
  selectedSlot = math.max(1, math.min(selectedSlot or 1, 9))

  appendSprite(vertices, width, height, x, y, hotbarW, hotbarH, 0, 0, 182, 22, 256, 256, COLORS.white)
  appendSprite(vertices, width, height, x - 2 + (selectedSlot - 1) * 20 * scale, y - 2, 24 * scale, 22 * scale, 0, 22, 24, 22, 256, 256, COLORS.white)
end

local function appendCrosshair(vertices, width, height)
  local size = 18
  local cx = math.floor(width * 0.5 - size * 0.5)
  local cy = math.floor(height * 0.5 - size * 0.5)
  appendSprite(vertices, width, height, cx, cy, size, size, 0, 0, 9, 9, 9, 9, COLORS.white)
end

local function appendInventoryItem(vertices, width, height, x, y, size, stack, renderBlockModel)
  if not stack then return end
  local definition = blocks.mapping[stack.item] or items.mapping[stack.item]
  local uv = definition and definition.uvs and (definition.uvs.top or definition.uvs.side)
  if not uv then return end

  local properties = definition.properties or {}
  local topUv = definition.uvs.top or uv
  local sideUv = definition.uvs.side or uv
  local frontUv = definition.uvs.front or sideUv
  if renderBlockModel ~= false and properties.solid and not itemMesh.isSprite(definition) and topUv and sideUv then
    -- Solid inventory items are equal-dimension 3D cubes fitted into the
    -- square slot. Sprite items keep their flat/extruded item representation.
    local top = {x + size * 0.50, y + size * 0.04}
    local right = {x + size * 0.91, y + size * 0.26}
    local center = {x + size * 0.50, y + size * 0.49}
    local left = {x + size * 0.09, y + size * 0.26}
    -- The vertical edges match the projected top edges, so this reads as a
    -- 1:1:1 cube rather than a short rectangular block.
    local bottomRight = {x + size * 0.91, y + size * 0.725}
    local bottom = {x + size * 0.50, y + size * 0.945}
    local bottomLeft = {x + size * 0.09, y + size * 0.725}
    local colors = definition.colors or {}
    local topColor = definition.biomeTint and definition.color or colors.top or definition.color or {1,1,1}
    local sideColor = definition.biomeTint and definition.color or colors.side or definition.color or {1,1,1}
    local frontColor = definition.biomeTint and definition.color or colors.front or sideColor
    local function shade(color, amount)
      return {color[1] * amount, color[2] * amount, color[3] * amount, 1.0}
    end
    local function point(p) return {ndcX(p[1],width),ndcY(p[2],height)} end
    local sideUvs = {{sideUv.u0,sideUv.v0},{sideUv.u1,sideUv.v0},{sideUv.u1,sideUv.v1},{sideUv.u0,sideUv.v1}}
    local frontUvs = {{frontUv.u0,frontUv.v0},{frontUv.u1,frontUv.v0},{frontUv.u1,frontUv.v1},{frontUv.u0,frontUv.v1}}
    appendQuad(vertices,{point(left),point(center),point(bottom),point(bottomLeft)},shade(sideColor,0.72),sideUvs,1.0,0.0)
    appendQuad(vertices,{point(center),point(right),point(bottomRight),point(bottom)},shade(frontColor,0.88),frontUvs,1.0,0.0)
    appendQuad(vertices,{point(top),point(right),point(center),point(left)},shade(topColor,1.0),
      {{topUv.u0,topUv.v0},{topUv.u1,topUv.v0},{topUv.u1,topUv.v1},{topUv.u0,topUv.v1}},1.0,0.0)
  else
    local iconScale=1.0
    if itemMesh.isSprite(definition) then
      iconScale=items.mapping[stack.item] and 0.82 or 0.90
      if stack.item=="flint" then iconScale=0.68 end
    end
    local iconSize=size*iconScale
    local iconX=x+(size-iconSize)*0.5
    local iconY=y+(size-iconSize)*0.5
    local iconUvs={{uv.u0,uv.v0},{uv.u1,uv.v0},{uv.u1,uv.v1},{uv.u0,uv.v1}}
    local function iconQuad(px,py,color)
      appendQuad(vertices,{
        {ndcX(px,width),ndcY(py,height)}, {ndcX(px+iconSize,width),ndcY(py,height)},
        {ndcX(px+iconSize,width),ndcY(py+iconSize,height)}, {ndcX(px,width),ndcY(py+iconSize,height)}
      },color,iconUvs,1.0,0.0)
    end
    if itemMesh.isSprite(definition) then
      local offset=math.max(1,math.floor(size*0.055))
      iconQuad(iconX+offset,iconY+offset,{0.0,0.0,0.0,0.32})
    end
    iconQuad(iconX,iconY,
      definition.color and {definition.color[1],definition.color[2],definition.color[3],1} or COLORS.white)
  end
end

local function buildMeshes(width, height, selectedSlot, state, time)
  local meshes = {
    color = {},
    widgets = {},
    heartEmpty = {},
    heartHalf = {},
    heart = {},
    hungerEmpty = {},
    hungerHalf = {},
    hunger = {},
    crosshair = {},
    terrain = {},
    font = {}
  }

  local function hotbarStack(index)
    if state and state.inventory and state.inventory.slots then return state.inventory.slots[index] end
    local id = state and state.hotbarBlocks and state.hotbarBlocks[index]
    local definition = id and blocks.list[id]
    return definition and {item = definition.key, count = 1} or nil
  end

  if not state or state.worldGameMode ~= "creative" then appendStatusBars(meshes, width, height, state) end
  appendHotbar(meshes.widgets, width, height, selectedSlot)
  appendCrosshair(meshes.crosshair, width, height)
  local center, x, y = math.floor(width*0.5), math.floor(width*0.5)-174, height-54
  for index=1,9 do
    local stack = hotbarStack(index)
    appendInventoryItem(meshes.terrain,width,height,x+(index-1)*40+5,y+5,30,stack)
    if stack and stack.count > 1 then appendText(meshes.font,width,height,1,tostring(stack.count),x+(index-1)*40+22,y+25,TEXT_WHITE) end
  end
  if state and state.worldGameMode~="creative" and (state.tutorialTime or 0)<75 then
    local hint=state.inventory and state.inventory.recipeHint or "Break a tree, then press E to craft."
    appendCenteredText(meshes.font,width,height,1,hint,center,height-112,TEXT_WHITE)
  end
  return meshes
end

local function appendControlsLabels(meshes, width, height, scale, logicalWidth, logicalHeight)
  local cx = math.floor(logicalWidth * 0.5)
  local y0 = math.floor(logicalHeight / 6)
  local leftLabels = {"Attack", "Forward", "Back", "Jump", "Drop", "Chat", "Pick Block"}
  local rightLabels = {"Use Item", "Left", "Right", "Sneak", "Inventory", "List Players"}

  for i = 1, #leftLabels do
    appendText(meshes.font, width, height, scale, leftLabels[i], cx - 79, y0 + (i - 1) * 24 + 7, TEXT_WHITE)
  end
  for i = 1, #rightLabels do
    appendText(meshes.font, width, height, scale, rightLabels[i], cx + 81, y0 + (i - 1) * 24 + 7, TEXT_WHITE)
  end
end

local function buildMenuMeshes(width, height, screen, mouseX, mouseY, menuState, time)
  menuState = menuState or {}
  local scale = guiScale(width, height)
  local logicalWidth = math.floor(width / scale)
  local logicalHeight = math.floor(height / scale)
  local cx = math.floor(logicalWidth * 0.5)
  local meshes = {
    panorama = {},
    panoramaFaces = {{}, {}, {}, {}, {}, {}},
    background = {},
    color = {},
    logo = {},
    widgets = {},
    font = {}
  }

  if screen == "pause" then
    appendScaledRect(meshes.color, width, height, scale, 0, 0, logicalWidth, logicalHeight, {0.0, 0.0, 0.0, 0.20})
  elseif screen ~= "main" then
    appendDirtBackground(meshes.background, width, height, scale, logicalWidth, logicalHeight)
  else
    appendScaledRect(meshes.panorama, width, height, scale, 0, 0, logicalWidth, logicalHeight, {0.0, 0.0, 0.0, 1.0})
    appendPanoramaCube(meshes.panoramaFaces, width, height, scale, logicalWidth, logicalHeight, time or 0.0, 0.68, 0, 0)
    appendPanoramaCube(meshes.panoramaFaces, width, height, scale, logicalWidth, logicalHeight, (time or 0.0) + 0.10, 0.08, -1, 0)
    appendPanoramaCube(meshes.panoramaFaces, width, height, scale, logicalWidth, logicalHeight, (time or 0.0) - 0.10, 0.08, 1, 0)
    appendPanoramaCube(meshes.panoramaFaces, width, height, scale, logicalWidth, logicalHeight, (time or 0.0) + 0.16, 0.08, 0, -1)
    appendPanoramaCube(meshes.panoramaFaces, width, height, scale, logicalWidth, logicalHeight, (time or 0.0) - 0.16, 0.08, 0, 1)
    appendScaledRect(meshes.color, width, height, scale, 0, 0, logicalWidth, logicalHeight, {0.0, 0.0, 0.0, 0.24})
    appendMinecraftLogo(meshes, width, height, scale, cx)
    appendCenteredText(meshes.font, width, height, scale, "Pre-alpha!", cx + 118, 67, TEXT_YELLOW)
    appendText(meshes.font, width, height, scale, "Minecraft 1.0.0", 2, logicalHeight - 10, TEXT_WHITE)
    local copyright = "Copyright Mojang AB. Do not distribute!"
    appendText(meshes.font, width, height, scale, copyright, logicalWidth - textWidth(copyright) - 2, logicalHeight - 10, TEXT_WHITE)
  end

  if screen == "pause" then
    appendCenteredText(meshes.font, width, height, scale, "Game menu", cx, 40, TEXT_WHITE)
  elseif screen == "select_world" then
    appendCenteredText(meshes.font, width, height, scale, "Select World", cx, 20, TEXT_WHITE)
    appendScaledRect(meshes.color, width, height, scale, 0, 32, logicalWidth, logicalHeight - 88, COLORS.panel)
    if #(menuState.savedWorlds or {}) == 0 then
      appendCenteredText(meshes.font, width, height, scale, "No saved worlds yet", cx, 74, TEXT_WHITE)
      appendCenteredText(meshes.font, width, height, scale, "Create one to begin", cx, 90, TEXT_MUTED)
    end
    if menuState.statusMessage and menuState.statusMessage ~= "" then
      appendCenteredText(meshes.font, width, height, scale, menuState.statusMessage, cx, logicalHeight - 68, TEXT_MUTED)
    end
  elseif screen == "confirm_delete_world" then
    local world = menuState.pendingDeleteWorld or {}
    appendCenteredText(meshes.font, width, height, scale, "Delete World?", cx, 54, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale,
      "'" .. tostring(world.worldName or "Selected World") .. "' will be lost forever!", cx, 82, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale, "This cannot be undone.", cx, 98, TEXT_MUTED)
  elseif screen == "create_world" then
    appendCenteredText(meshes.font, width, height, scale, "Create New World", cx, 20, TEXT_WHITE)
    if menuState.moreWorldOptions then
      appendText(meshes.font, width, height, scale, "Seed for the World Generator", cx - 100, 47, TEXT_MUTED)
      appendTextBox(meshes, width, height, scale, cx - 100, 60, 200, 20, menuState.worldSeedText or "")
      appendText(meshes.font, width, height, scale, "Leave blank for a random seed", cx - 100, 84, TEXT_MUTED)
    else
      local worldName = menuState.worldNameText or "New World"
      appendText(meshes.font, width, height, scale, "World Name", cx - 100, 47, TEXT_MUTED)
      appendTextBox(meshes, width, height, scale, cx - 100, 60, 200, 20, worldName)
      appendText(meshes.font, width, height, scale, "Will be saved in: " .. worldName, cx - 100, 85, TEXT_MUTED)
      if (menuState.worldGameMode or "survival") == "creative" then
        appendText(meshes.font, width, height, scale, "Unlimited resources and free flying", cx - 100, 152, TEXT_MUTED)
      else
        appendText(meshes.font, width, height, scale, "Search for resources, craft and survive", cx - 100, 152, TEXT_MUTED)
      end
    end
  elseif screen == "options" then
    appendCenteredText(meshes.font, width, height, scale, "Options", cx, 20, TEXT_WHITE)
  elseif screen == "video" then
    appendCenteredText(meshes.font, width, height, scale, "Video Settings", cx, 20, TEXT_WHITE)
  elseif screen == "controls" then
    appendCenteredText(meshes.font, width, height, scale, "Controls", cx, 20, TEXT_WHITE)
    appendControlsLabels(meshes, width, height, scale, logicalWidth, logicalHeight)
    appendCenteredText(meshes.font, width, height, scale, "Click a binding to cycle its available inputs", cx, logicalHeight - 48, TEXT_MUTED)
  elseif screen == "multiplayer" then
    appendCenteredText(meshes.font, width, height, scale, "Play Multiplayer", cx, 20, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale, "MineLua is currently a local-only build.", cx, 76, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale, "Networking is not implemented yet.", cx, 92, TEXT_MUTED)
  elseif screen == "texture_packs" then
    appendCenteredText(meshes.font, width, height, scale, "Texture Packs", cx, 20, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale, "Default MineLua resources", cx, 70, TEXT_WHITE)
    appendCenteredText(meshes.font, width, height, scale, "Runtime resource-pack switching is not implemented yet.", cx, 94, TEXT_MUTED)
  elseif screen == "achievements" then
    local stats = menuState.stats or {}
    appendCenteredText(meshes.font, width, height, scale, "Achievements", cx, 20, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, (stats.blocksMined or 0) > 0 and "[x] Getting Started - Mine a block" or "[ ] Getting Started - Mine a block", cx - 120, 60, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, (stats.blocksPlaced or 0) > 0 and "[x] Builder - Place a block" or "[ ] Builder - Place a block", cx - 120, 82, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, (stats.distance or 0) >= 100 and "[x] Explorer - Travel 100 blocks" or "[ ] Explorer - Travel 100 blocks", cx - 120, 104, TEXT_WHITE)
  elseif screen == "stats" then
    local stats = menuState.stats or {}
    appendCenteredText(meshes.font, width, height, scale, "Statistics", cx, 20, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, "Blocks mined: " .. tostring(stats.blocksMined or 0), cx - 100, 60, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, "Blocks placed: " .. tostring(stats.blocksPlaced or 0), cx - 100, 82, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, string.format("Distance travelled: %.1f m", stats.distance or 0), cx - 100, 104, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, string.format("Time played: %.1f min", (stats.playTime or 0) / 60), cx - 100, 126, TEXT_WHITE)
  end

  local buttons = uiMenu.buttons(screen, logicalWidth, logicalHeight, menuState)
  for i = 1, #buttons do
    local button = buttons[i]
    if button.worldIndex then
      local world = (menuState.savedWorlds or {})[button.worldIndex]
      if world then
        local selected = button.worldIndex == menuState.selectedWorldIndex
        local hovered = isHovered(button, mouseX, mouseY)
        local border = selected and {0.78, 0.78, 0.78, 1.0} or {0.12, 0.12, 0.12, 1.0}
        local fill = hovered and {0.24, 0.24, 0.24, 0.94} or {0.04, 0.04, 0.04, 0.88}
        appendScaledRect(meshes.color, width, height, scale, button.x, button.y, button.w, button.h, border)
        appendScaledRect(meshes.color, width, height, scale, button.x + 1, button.y + 1, button.w - 2, button.h - 2, fill)
        local iconSky = world.worldId == "mars" and {0.66, 0.31, 0.17, 1.0} or
          (world.generatorType == "superflat" and {0.34, 0.65, 0.20, 1.0} or {0.16, 0.43, 0.72, 1.0})
        local iconGround = world.worldId == "mars" and {0.44, 0.20, 0.12, 1.0} or {0.20, 0.52, 0.16, 1.0}
        appendScaledRect(meshes.color, width, height, scale, button.x + 3, button.y + 3, 28, 28, iconSky)
        appendScaledRect(meshes.color, width, height, scale, button.x + 3, button.y + 19, 28, 12, iconGround)
        appendText(meshes.font, width, height, scale, tostring(world.worldName):sub(1, 34), button.x + 36, button.y + 3, TEXT_WHITE)
        appendText(meshes.font, width, height, scale,
          (tostring(world.folderName):sub(1, 18) .. " - " .. tostring(world.lastPlayedText)), button.x + 36, button.y + 13, TEXT_MUTED)
        appendText(meshes.font, width, height, scale, tostring(world.summary), button.x + 36, button.y + 23, TEXT_MUTED)
      end
    elseif button.kind == "slider" then
      appendSlider(meshes, width, height, scale, button, mouseX, mouseY)
    else
      appendButton(meshes, width, height, scale, button, mouseX, mouseY)
    end
  end

  return meshes
end

local function appendLoadingSegment(vertices, width, height, scale, x, y, w, h, amount, offset, length, color)
  local localAmount = math.max(0.0, math.min(1.0, (amount - offset) / length))
  if localAmount <= 0.0 then
    return
  end

  appendScaledRect(vertices, width, height, scale, x, y, math.floor(w * localAmount + 0.5), h, color)
end

local function appendVerticalLoadingSegment(vertices, width, height, scale, x, y, w, h, amount, offset, length, color)
  local localAmount = math.max(0.0, math.min(1.0, (amount - offset) / length))
  if localAmount <= 0.0 then
    return
  end

  appendScaledRect(vertices, width, height, scale, x, y, w, math.floor(h * localAmount + 0.5), color)
end

local function appendLoadingSquareGraph(meshes, width, height, scale, cx, cy, progress)
  local green = {0.08, 0.78, 0.08, 1.0}
  local darkGreen = {0.02, 0.36, 0.02, 1.0}
  local outer = {0.50, 0.50, 0.50, 1.0}
  local inner = {0.96, 0.96, 0.96, 1.0}
  local border = {0.18, 0.18, 0.18, 1.0}
  local x = cx - 18
  local y = cy - 18
  local amount = math.max(0.0, math.min(1.0, progress or 0.0)) * 4.0

  appendScaledRect(meshes.color, width, height, scale, x - 1, y - 1, 38, 38, border)
  appendScaledRect(meshes.color, width, height, scale, x, y, 36, 36, outer)
  appendScaledRect(meshes.color, width, height, scale, x + 8, y + 8, 20, 20, inner)

  appendLoadingSegment(meshes.color, width, height, scale, x + 8, y + 6, 20, 2, amount, 0.0, 1.0, green)
  appendVerticalLoadingSegment(meshes.color, width, height, scale, x + 28, y + 8, 2, 20, amount, 1.0, 1.0, green)
  appendLoadingSegment(meshes.color, width, height, scale, x + 8, y + 28, 20, 2, amount, 2.0, 1.0, green)
  appendVerticalLoadingSegment(meshes.color, width, height, scale, x + 6, y + 8, 2, 20, amount, 3.0, 1.0, green)

  if progress >= 0.20 then
    appendScaledRect(meshes.color, width, height, scale, x + 16, y + 2, 4, 4, green)
  else
    appendScaledRect(meshes.color, width, height, scale, x + 16, y + 2, 4, 4, darkGreen)
  end
  if progress >= 0.45 then
    appendScaledRect(meshes.color, width, height, scale, x + 32, y + 16, 4, 4, green)
  else
    appendScaledRect(meshes.color, width, height, scale, x + 32, y + 16, 4, 4, darkGreen)
  end
  if progress >= 0.70 then
    appendScaledRect(meshes.color, width, height, scale, x + 16, y + 32, 4, 4, green)
  else
    appendScaledRect(meshes.color, width, height, scale, x + 16, y + 32, 4, 4, darkGreen)
  end
  if progress >= 0.95 then
    appendScaledRect(meshes.color, width, height, scale, x + 2, y + 16, 4, 4, green)
  else
    appendScaledRect(meshes.color, width, height, scale, x + 2, y + 16, 4, 4, darkGreen)
  end
end

local function buildLoadingMeshes(width, height, loadingState)
  loadingState = loadingState or {}
  local progress = math.max(0.0, math.min(1.0, loadingState.progress or 0.0))
  local scale = guiScale(width, height)
  local logicalWidth = math.floor(width / scale)
  local logicalHeight = math.floor(height / scale)
  local cx = math.floor(logicalWidth * 0.5)
  local cy = math.floor(logicalHeight * 0.5)
  local meshes = {
    background = {},
    color = {},
    font = {}
  }

  appendDirtBackground(meshes.background, width, height, scale, logicalWidth, logicalHeight)
  appendScaledRect(meshes.color, width, height, scale, 0, 0, logicalWidth, logicalHeight, {0.0, 0.0, 0.0, 0.30})

  local percent = tostring(math.floor(progress * 100.0 + 0.5)) .. "%"
  appendCenteredText(meshes.font, width, height, scale, percent, cx, cy - 34, TEXT_WHITE)
  appendLoadingSquareGraph(meshes, width, height, scale, cx, cy + 2, progress)

  return meshes
end

local function inventoryLayout(width, height, creative)
  local scale = 2
  local w, h = creative and 390 or 352, creative and 272 or 332
  return {x=math.floor((width-w)/2),y=math.floor((height-h)/2),w=w,h=h,scale=scale}
end

local function inventoryRect(layout, sourceX, sourceY, sourceSize)
  local scale = layout.scale
  return {
    x = layout.x + sourceX * scale,
    y = layout.y + sourceY * scale,
    w = sourceSize * scale,
    h = sourceSize * scale
  }
end

local function appendInventorySteve(vertices, width, height, layout, mouseX, mouseY, time)
  local centerX = layout.x + 50 * layout.scale
  local centerY = layout.y + 43 * layout.scale
  local lookX = math.max(-1.0, math.min(1.0, ((mouseX or centerX) - centerX) / 150.0))
  local lookY = math.max(-1.0, math.min(1.0, ((mouseY or centerY) - centerY) / 150.0))
  local idle = math.sin((time or 0.0) * 2.1)
  local bob = idle * 1.25

  local headX, headY = centerX - 16 + lookX * 3.0, layout.y + 47 + bob + lookY * 2.0
  local headAngle = lookX * 0.11
  appendRotatedSprite(vertices,width,height,headX,headY,32,32,8,8,8,8,64,64,COLORS.white,headAngle)
  appendRotatedSprite(vertices,width,height,headX,headY,32,32,40,8,8,8,64,64,{1,1,1,0.94},headAngle)

  local bodyX, bodyY = centerX - 16, layout.y + 79 + bob
  appendRotatedSprite(vertices,width,height,bodyX,bodyY,32,48,20,20,8,12,64,64,COLORS.white,idle*0.012)

  local armSwing = math.sin((time or 0.0) * 1.55) * 0.055
  appendRotatedSprite(vertices,width,height,bodyX-16,bodyY,16,48,44,20,4,12,64,64,COLORS.white,-0.055-armSwing,bodyX,bodyY+3)
  appendRotatedSprite(vertices,width,height,bodyX+32,bodyY,16,48,36,52,4,12,64,64,COLORS.white,0.055+armSwing,bodyX+32,bodyY+3)
end

local CREATIVE_TABS = {
  {id="building", item="cobblestone", x=0},
  {id="nature", item="oak_leaves", x=56},
  {id="materials", item="diamond_ore", x=112},
  {id="redstone", item="redstone_ore", x=168},
  {id="search", item="crafting_table", x=280}
}

local function creativeSlotPosition(layout, row, col)
  return layout.x + 18 + col * 36, layout.y + 36 + row * 36
end

local function pointIn(x,y,rx,ry,rw,rh)
  return x >= rx and x < rx+rw and y >= ry and y < ry+rh
end

function hud.inventorySlotAt(screen, width, height, mouseX, mouseY, state)
  local creative = screen == "creative_inventory"
  local layout = inventoryLayout(width,height,creative)
  if creative then
    for _,tab in ipairs(CREATIVE_TABS) do
      if pointIn(mouseX,mouseY,layout.x+tab.x,layout.y-54,56,58) then
        return {kind="creative_tab",tab=tab.id}
      end
    end
    local activeTab = state and state.creativeTab or "building"
    if activeTab == "search" then
      local search = {x=layout.x+164,y=layout.y+10,w=178,h=24}
      if pointIn(mouseX,mouseY,search.x,search.y,search.w,search.h) then return {kind="search"} end
    end
    local filtered = state and state.creativeFiltered or {}
    for row=0,4 do for col=0,8 do
      local x,y=creativeSlotPosition(layout,row,col)
      if pointIn(mouseX,mouseY,x,y,32,32) then return {kind="creative",index=row*9+col+1,item=filtered[row*9+col+1],x=x,y=y,w=32,h=32} end
    end end
    for col=0,8 do
      local x,y=layout.x+18+col*36,layout.y+224
      if pointIn(mouseX,mouseY,x,y,32,32) then return {kind="slot",index=col+1,x=x,y=y,w=32,h=32} end
    end
    return nil
  end

  if screen == "crafting_table" then
    for row=0,2 do for col=0,2 do
      local rect=inventoryRect(layout,30+col*18,17+row*18,16)
      if pointIn(mouseX,mouseY,rect.x,rect.y,rect.w,rect.h) then
        return {kind="craft",index=1+row*3+col,x=rect.x,y=rect.y,w=rect.w,h=rect.h}
      end
    end end
    local result=inventoryRect(layout,124,35,16)
    if pointIn(mouseX,mouseY,result.x,result.y,result.w,result.h) then
      return {kind="result",x=result.x,y=result.y,w=result.w,h=result.h}
    end
  end
  if screen == "furnace" then
    local input=inventoryRect(layout,56,17,16)
    local fuel=inventoryRect(layout,56,53,16)
    local output=inventoryRect(layout,116,35,16)
    if pointIn(mouseX,mouseY,input.x,input.y,input.w,input.h) then
      return {kind="furnace_input",x=input.x,y=input.y,w=input.w,h=input.h}
    end
    if pointIn(mouseX,mouseY,fuel.x,fuel.y,fuel.w,fuel.h) then
      return {kind="furnace_fuel",x=fuel.x,y=fuel.y,w=fuel.w,h=fuel.h}
    end
    if pointIn(mouseX,mouseY,output.x,output.y,output.w,output.h) then
      return {kind="furnace_output",x=output.x,y=output.y,w=output.w,h=output.h}
    end
  end

  for row=0,2 do for col=0,8 do
    local x,y=layout.x+16+col*36,layout.y+168+row*36
    if pointIn(mouseX,mouseY,x,y,32,32) then return {kind="slot",index=10+row*9+col,x=x,y=y,w=32,h=32} end
  end end
  for col=0,8 do
    local x,y=layout.x+16+col*36,layout.y+284
    if pointIn(mouseX,mouseY,x,y,32,32) then return {kind="slot",index=col+1,x=x,y=y,w=32,h=32} end
  end
  if screen == "crafting_table" or screen == "furnace" then return nil end
  for row=0,3 do
    local rect=inventoryRect(layout,8,8+row*18,16)
    if pointIn(mouseX,mouseY,rect.x,rect.y,rect.w,rect.h) then
      return {kind="armor",index=row+1,x=rect.x,y=rect.y,w=rect.w,h=rect.h}
    end
  end
  local offhand=inventoryRect(layout,77,62,16)
  if pointIn(mouseX,mouseY,offhand.x,offhand.y,offhand.w,offhand.h) then
    return {kind="offhand",x=offhand.x,y=offhand.y,w=offhand.w,h=offhand.h}
  end
  for row=0,1 do for col=0,1 do
    local rect=inventoryRect(layout,98+col*18,18+row*18,16)
    if pointIn(mouseX,mouseY,rect.x,rect.y,rect.w,rect.h) then
      return {kind="craft",index=1+row*2+col,x=rect.x,y=rect.y,w=rect.w,h=rect.h}
    end
  end end
  local result=inventoryRect(layout,154,28,16)
  if pointIn(mouseX,mouseY,result.x,result.y,result.w,result.h) then
    return {kind="result",x=result.x,y=result.y,w=result.w,h=result.h}
  end
  return nil
end

local function buildInventoryMeshes(width,height,screen,state,mouseX,mouseY,time)
  local creative = screen == "creative_inventory"
  local layout = inventoryLayout(width,height,creative)
  local meshes={panel={},creativePanel={},creativeTabs={},color={},overlay={},terrain={},font={},skin={}}
  if creative then
    local activeTab = state.creativeTab or "building"
    -- The supplied 195x136 creative container art is authored at Minecraft's
    -- logical GUI scale. Draw it exactly 2x so every native 18px slot aligns
    -- with input hit-testing and item placement.
    appendSprite(meshes.creativePanel,width,height,layout.x,layout.y,layout.w,layout.h,
      0,0,195,136,256,256,COLORS.white)
    for index,tab in ipairs(CREATIVE_TABS) do
      local selected = tab.id == activeTab
      local sourceX = selected and 28 or 0
      appendSprite(meshes.creativeTabs,width,height,layout.x+tab.x,layout.y-54,56,64,
        sourceX,0,28,32,256,256,COLORS.white)
      appendInventoryItem(meshes.terrain,width,height,layout.x+tab.x+13,layout.y-43,30,
        {item=tab.item,count=1})
    end

    local titles = {
      building="Building Blocks", nature="Decoration Blocks",
      materials="Materials", redstone="Redstone", search="Search Items"
    }
    if activeTab == "search" then
      appendText(meshes.font,width,height,2,(state.inventory.search or "").."_",layout.x+170,layout.y+12,TEXT_NORMAL)
    else
      appendText(meshes.font,width,height,2,titles[activeTab] or "Building Blocks",layout.x+18,layout.y+12,TEXT_NORMAL)
    end
    local items=state.creativeFiltered or {}
    for row=0,4 do for col=0,8 do
      local index=row*9+col+1
      local x,y=creativeSlotPosition(layout,row,col)
      if items[index] then appendInventoryItem(meshes.terrain,width,height,x+2,y+1,28,{item=items[index],count=64}) end
    end end
    -- The current catalog fits on one page; keep the native scrollbar parked at
    -- its top position so the container still reads as the stock creative GUI.
    appendRect(meshes.overlay,width,height,layout.x+350,layout.y+37,24,30,{0.58,0.58,0.58,1.0})
    for col=0,8 do
      local x,y=layout.x+18+col*36,layout.y+224
      local stack=state.inventory.slots[col+1]
      appendInventoryItem(meshes.terrain,width,height,x+2,y+1,28,stack)
      if stack and stack.count>1 then appendText(meshes.font,width,height,1,tostring(stack.count),x+18,y+20,TEXT_WHITE) end
    end
  else
    appendSprite(meshes.panel,width,height,layout.x,layout.y,layout.w,layout.h,0,0,176,166,176,166,COLORS.white)
    if screen ~= "crafting_table" and screen ~= "furnace" then
      appendInventorySteve(meshes.skin,width,height,layout,mouseX,mouseY,time)
    end
    local inv=state.inventory
    for row=0,2 do for col=0,8 do
      local index=10+row*9+col local x,y=layout.x+16+col*36,layout.y+168+row*36
      local stack=inv.slots[index] appendInventoryItem(meshes.terrain,width,height,x,y,32,stack)
      if stack and stack.count>1 then appendText(meshes.font,width,height,1,tostring(stack.count),x+18,y+20,TEXT_WHITE) end
    end end
    for col=0,8 do
      local stack=inv.slots[col+1] local x,y=layout.x+16+col*36,layout.y+284
      appendInventoryItem(meshes.terrain,width,height,x,y,32,stack)
      if stack and stack.count>1 then appendText(meshes.font,width,height,1,tostring(stack.count),x+18,y+20,TEXT_WHITE) end
    end
    if screen=="furnace" then
      local furnace=inv.furnace or {}
      local input=inventoryRect(layout,56,17,16)
      local fuel=inventoryRect(layout,56,53,16)
      local output=inventoryRect(layout,116,35,16)
      appendInventoryItem(meshes.terrain,width,height,input.x,input.y,input.w,furnace.input)
      appendInventoryItem(meshes.terrain,width,height,fuel.x,fuel.y,fuel.w,furnace.fuel)
      appendInventoryItem(meshes.terrain,width,height,output.x,output.y,output.w,furnace.output)
      for _,entry in ipairs({{furnace.input,input},{furnace.fuel,fuel},{furnace.output,output}}) do
        local stack,rect=entry[1],entry[2]
        if stack and stack.count>1 then appendText(meshes.font,width,height,1,tostring(stack.count),rect.x+18,rect.y+20,TEXT_WHITE) end
      end
      local burn=(furnace.burnTotal or 0)>0 and (furnace.burnTime or 0)/furnace.burnTotal or 0
      local cook=(furnace.cookTotal or 10)>0 and (furnace.cookTime or 0)/furnace.cookTotal or 0
      if burn>0 then
        local flameH=math.floor(26*math.min(1,burn)+0.5)
        appendRect(meshes.overlay,width,height,layout.x+114,layout.y+104-flameH,26,flameH,{1.0,0.52,0.08,0.82})
      end
      if cook>0 then
        appendRect(meshes.overlay,width,height,layout.x+158,layout.y+70,
          math.floor(46*math.min(1,cook)+0.5),10,{0.90,0.66,0.30,0.78})
      end
    else
      local gridSize=screen=="crafting_table" and 3 or 2
      local gridX,gridY=screen=="crafting_table" and 30 or 98,screen=="crafting_table" and 17 or 18
      for row=0,gridSize-1 do for col=0,gridSize-1 do
        local rect=inventoryRect(layout,gridX+col*18,gridY+row*18,16)
        appendInventoryItem(meshes.terrain,width,height,rect.x,rect.y,rect.w,inv.crafting[1+row*gridSize+col])
      end end
      local result=inventoryRect(layout,screen=="crafting_table" and 124 or 154,screen=="crafting_table" and 35 or 28,16)
      appendInventoryItem(meshes.terrain,width,height,result.x,result.y,result.w,inv:craftResult())
    end
  end
  local hovered=hud.inventorySlotAt(screen,width,height,mouseX or -1,mouseY or -1,state)
  if hovered and hovered.x then
    appendRect(meshes.overlay,width,height,hovered.x,hovered.y,hovered.w,hovered.h,{1.0,1.0,1.0,0.24})
  end
  local cursor=state.inventory.cursor
  if cursor then
    appendInventoryItem(meshes.terrain,width,height,mouseX-16,mouseY-16,32,cursor)
    if cursor.count>1 then appendText(meshes.font,width,height,1,tostring(cursor.count),mouseX+3,mouseY+3,TEXT_WHITE) end
  end
  return meshes
end

local function appendDebugLine(meshes, width, height, scale, x, y, text, color)
  text = tostring(text or "")
  local lineWidth = textWidth(text)
  appendScaledRect(meshes.color, width, height, scale, x - 1, y - 1, lineWidth + 2, 10, {0.0, 0.0, 0.0, 0.46})
  appendText(meshes.font, width, height, scale, text, x, y, color or TEXT_WHITE, false)
end

local function buildDebugMeshes(width, height, debugState)
  debugState = debugState or {}
  local scale = guiScale(width, height)
  local logicalWidth = math.floor(width / scale)
  local logicalHeight = math.floor(height / scale)
  local meshes = {
    color = {},
    font = {}
  }
  local leftLines = debugState.leftLines or {}
  local rightLines = debugState.rightLines or {}
  local lineHeight = 9

  for i = 1, #leftLines do
    local y = 2 + (i - 1) * lineHeight
    if y + 9 <= logicalHeight then
      appendDebugLine(meshes, width, height, scale, 2, y, leftLines[i], TEXT_WHITE)
    end
  end

  for i = 1, #rightLines do
    local line = tostring(rightLines[i] or "")
    local y = 2 + (i - 1) * lineHeight
    if y + 9 <= logicalHeight then
      local x = math.max(2, logicalWidth - textWidth(line) - 2)
      appendDebugLine(meshes, width, height, scale, x, y, line, TEXT_WHITE)
    end
  end

  return meshes
end

local function upload(vertices)
  local vao = ffi.new("GLuint[1]")
  local vbo = ffi.new("GLuint[1]")
  local data = ffi.new("float[?]", #vertices, vertices)
  local stride = STRIDE_FLOATS * 4

  gl.glGenVertexArrays(1, vao)
  gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1, vbo)
  gl.glBindBuffer(GL_ARRAY_BUFFER, vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER, #vertices * 4, data, GL_STATIC_DRAW)

  gl.glVertexAttribPointer(0, 3, GL_FLOAT, 0, stride, nil)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(1, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 3 * 4))
  gl.glEnableVertexAttribArray(1)
  gl.glVertexAttribPointer(2, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 6 * 4))
  gl.glEnableVertexAttribArray(2)
  gl.glVertexAttribPointer(3, 2, GL_FLOAT, 0, stride, ffi.cast("void*", 9 * 4))
  gl.glEnableVertexAttribArray(3)

  return {
    vao = vao,
    vbo = vbo,
    data = data,
    count = #vertices / STRIDE_FLOATS
  }
end

local function createTexture(path, repeatWrap, linear)
  local img = texture.loadPng(path)
  if not img then
    error("Failed to load HUD texture: " .. path)
  end

  local tex = ffi.new("GLuint[1]")
  gl.glGenTextures(1, tex)
  gl.glBindTexture(GL_TEXTURE_2D, tex[0])
  local filter = linear and GL_LINEAR or GL_NEAREST
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, repeatWrap and GL_REPEAT or GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, repeatWrap and GL_REPEAT or GL_CLAMP_TO_EDGE)
  gl.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img.w, img.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img.data)

  return {id = tex, image = img}
end

local function heldTextureFor(self,path)
  if not path then return nil end
  local cached=self.heldTextures[path]
  if not cached then
    cached=createTexture(path)
    self.heldTextures[path]=cached
  end
  return cached
end

-- One upload per item. The model is independent of the pose, so switching back
-- to something already carried costs nothing.
local function uploadHeldModel(vertices)
  local vao = ffi.new("GLuint[1]")
  local vbo = ffi.new("GLuint[1]")
  local data = ffi.new("float[?]", #vertices, vertices)
  local stride = heldItem.STRIDE_FLOATS * 4

  gl.glGenVertexArrays(1, vao)
  gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1, vbo)
  gl.glBindBuffer(GL_ARRAY_BUFFER, vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER, #vertices * 4, data, GL_STATIC_DRAW)
  gl.glVertexAttribPointer(0, 3, GL_FLOAT, 0, stride, nil)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(1, 3, GL_FLOAT, 0, stride, ffi.cast("void*", 3 * 4))
  gl.glEnableVertexAttribArray(1)
  gl.glVertexAttribPointer(2, 2, GL_FLOAT, 0, stride, ffi.cast("void*", 6 * 4))
  gl.glEnableVertexAttribArray(2)
  gl.glBindVertexArray(0)

  return {vao = vao, vbo = vbo, data = data, count = #vertices / heldItem.STRIDE_FLOATS}
end

local function heldModelFor(self, stack)
  local definition = stack and (blocks.mapping[stack.item] or items.mapping[stack.item])
  if not definition then return nil end
  local cached = self.heldModels[stack.item]
  if cached == nil then
    local model = heldItem.model(definition)
    cached = false
    if model and #model.vertices > 0 then
      cached = {
        mesh = uploadHeldModel(model.vertices),
        sprite = model.sprite,
        atlas = model.atlas,
        source = model.source,
        definition = definition
      }
    end
    self.heldModels[stack.item] = cached
  end
  return cached or nil
end

function hud.create(skinPath)
  local shader = createShader()
  local heldShader = createHeldShader()
  local function heldUniform(name) return gl.glGetUniformLocation(heldShader, name) end
  return setmetatable({
    shader = shader,
    timeLocation = gl.glGetUniformLocation(shader, "uTime"),
    textureLocation = gl.glGetUniformLocation(shader, "uTexture"),
    heldShader = heldShader,
    heldLocations = {
      texture = heldUniform("uTexture"),
      pose = heldUniform("uPose"),
      swing = heldUniform("uSwing"),
      modelScale = heldUniform("uModelScale"),
      pivot = heldUniform("uPivot"),
      translate = heldUniform("uTranslate"),
      center = heldUniform("uCenter"),
      scale = heldUniform("uScale"),
      projection = heldUniform("uProjection"),
      tint = heldUniform("uTint"),
      ambient = heldUniform("uAmbient"),
      sunColor = heldUniform("uSunColor"),
      moonColor = heldUniform("uMoonColor"),
      lightDir = heldUniform("uLightDir"),
      params = heldUniform("uParams")
    },
    textures = {
      widgets = createTexture("assets/textures/gui/widgets.png"),
      heartEmpty = createTexture("assets/textures/gui/icons/heart_empty.png"),
      heartHalf = createTexture("assets/textures/gui/icons/heart_half.png"),
      heart = createTexture("assets/textures/gui/icons/heart.png"),
      hungerEmpty = createTexture("assets/textures/gui/icons/hunger_empty.png"),
      hungerHalf = createTexture("assets/textures/gui/icons/hunger_half.png"),
      hunger = createTexture("assets/textures/gui/icons/hunger.png"),
      crosshair = createTexture("assets/textures/gui/icons/crosshair.png"),
      font = createTexture("assets/textures/font/ascii.png"),
      background = createTexture("assets/textures/gui/options_background.png", true),
      logo = createTexture("assets/textures/gui/title/minecraft.png"),
      skin = createTexture(skinPath or "assets/textures/entity/steve.png"),
      inventory = createTexture("assets/textures/gui/container/inventory.png"),
      craftingTable = createTexture("assets/textures/gui/container/crafting_table.png"),
      furnace = createTexture("assets/textures/gui/container/furnace.png"),
      creativeItems = createTexture("assets/textures/gui/container/creative_inventory/tab_items.png"),
      creativeSearch = createTexture("assets/textures/gui/container/creative_inventory/tab_item_search.png"),
      creativeInventory = createTexture("assets/textures/gui/container/creative_inventory/tab_inventory.png"),
      creativeTabs = createTexture("assets/textures/gui/container/creative_inventory/tabs.png"),
      panoramaFaces = {
        createTexture("assets/textures/gui/title/background/panorama_0.png", false, true),
        createTexture("assets/textures/gui/title/background/panorama_1.png", false, true),
        createTexture("assets/textures/gui/title/background/panorama_2.png", false, true),
        createTexture("assets/textures/gui/title/background/panorama_3.png", false, true),
        createTexture("assets/textures/gui/title/background/panorama_4.png", false, true),
        createTexture("assets/textures/gui/title/background/panorama_5.png", false, true)
      },
      white = createTexture("assets/textures/gui/widgets.png")
    },
    heldTextures = {},
    heldModels = {},
    heldEquipKey = nil,
    heldEquipStart = 0.0,
    meshes = nil,
    menuMeshes = nil,
    menuKey = nil,
    loadingMeshes = nil,
    loadingKey = nil,
    debugMeshes = nil,
    debugKey = nil,
    inventoryMeshes = nil,
    inventoryKey = nil,
    width = 0,
    height = 0,
    selectedSlot = 0
  }, hud)
end

function hud:ensureMeshes(width, height, selectedSlot, state, time)
  selectedSlot = selectedSlot or 1
  local inventoryVersion = state and state.inventoryVersion or 0
  -- The held model animates from uniforms now, so the flat HUD only rebuilds
  -- when something it actually draws changes.
  local statusKey = table.concat({selectedSlot, math.ceil(state and state.health or 20), math.ceil(state and state.hunger or 20), state and state.worldGameMode or "survival", inventoryVersion}, ":")
  if self.meshes and self.width == width and self.height == height and self.statusKey == statusKey then
    return
  end

  self.width = width
  self.height = height
  self.selectedSlot = selectedSlot
  self.statusKey = statusKey
  local rawMeshes = buildMeshes(width, height, selectedSlot, state, time)
  rendering.releaseGroup(self.meshes)
  self.meshes = {
    color = upload(rawMeshes.color),
    widgets = upload(rawMeshes.widgets),
    heartEmpty = upload(rawMeshes.heartEmpty),
    heartHalf = upload(rawMeshes.heartHalf),
    heart = upload(rawMeshes.heart),
    hungerEmpty = upload(rawMeshes.hungerEmpty),
    hungerHalf = upload(rawMeshes.hungerHalf),
    hunger = upload(rawMeshes.hunger),
    crosshair = upload(rawMeshes.crosshair),
    terrain = upload(rawMeshes.terrain),
    font = upload(rawMeshes.font)
  }
end

function hud:drawMesh(mesh, tex)
  if not mesh or mesh.count == 0 then
    return
  end

  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, tex.id[0])
  gl.glBindVertexArray(mesh.vao[0])
  gl.glDrawArrays(GL_TRIANGLES, 0, mesh.count)
end

-- Draws the first-person model. The mesh is a cached unit model; placement,
-- the mining swing, the equip lift and camera sway are all uniforms, so this
-- runs every frame without touching a vertex buffer.
function hud:drawHeldItem(width, height, time, selectedSlot, state, atlasTexture, environment)
  local stack = state and state.inventory and state.inventory.slots and state.inventory.slots[selectedSlot or 1]
  if not stack then
    self.heldEquipKey = nil
    return
  end
  local model = heldModelFor(self, stack)
  if not model or model.mesh.count == 0 then return end

  local texture = model.atlas and atlasTexture or heldTextureFor(self, model.source)
  if not texture then return end

  -- A new item rises into frame instead of appearing. Tracking the key here
  -- keeps the animation working for hotbar scrolling, crafting and pick-block
  -- alike, without the game loop having to notice the change.
  if self.heldEquipKey ~= stack.item then
    self.heldEquipKey = stack.item
    self.heldEquipStart = time or 0.0
  end
  local equip = heldItem.equipPose(((time or 0.0) - self.heldEquipStart) / HELD_EQUIP_SECONDS)
  local swingStyle = state.handSwingStyle
  local swing = heldItem.swingPose(state.handSwing, swingStyle)
  local transform = environment.heldTransform or {}
  local defaults = heldItem.DEFAULTS
  local motion = heldItem.motionOffset(environment.heldMotion)

  -- Placement is authored against 720p and scales with the drawable, so the
  -- model keeps the same share of the frame on any display.
  local displayScale = math.max(0.75, height / 720)
  local blockScale = model.sprite and 1.0 or heldItem.BLOCK_SCALE
  local size = (transform.size or defaults.size) * displayScale * blockScale
  local centerX = width - ((transform.xInset or defaults.xInset) + motion.x) * displayScale
  local centerY = height - ((transform.yInset or defaults.yInset) + motion.y) * displayScale

  local basePose = heldItem.BLOCK_POSE
  if model.sprite then
    basePose = {
      roll = transform.roll or defaults.roll,
      yaw = transform.yaw or defaults.yaw,
      pitch = transform.pitch or defaults.pitch
    }
  end
  local poseMatrix = heldItem.rotationMatrix(basePose.roll, basePose.yaw, basePose.pitch)
  local swingMatrix = heldItem.rotationMatrix(
    swing.roll + equip.roll, swing.yaw + equip.yaw, swing.pitch + equip.pitch)

  local cameraDistance = math.max(1.2, transform.perspective or defaults.perspective)
  local near = math.max(0.1, cameraDistance - 1.4)
  local far = cameraDistance + 1.4
  local thickness = model.sprite and math.max(0.002, transform.thickness or defaults.thickness) or 1.0

  local tint = model.definition.color or {1,1,1}
  local ambient = environment.ambient or {0.72,0.75,0.80}
  local sunColor = environment.sunColor or {0.38,0.38,0.36}
  local moonColor = environment.moonColor or {0.0,0.0,0.0}
  local lightDir = environment.lightDir or {0.3,0.8,0.5}
  local locations = self.heldLocations

  gl.glUseProgram(self.heldShader)
  gl.glUniform1i(locations.texture, 0)
  gl.glUniformMatrix3fv(locations.pose, 1, 0, ffi.new("float[9]", poseMatrix))
  gl.glUniformMatrix3fv(locations.swing, 1, 0, ffi.new("float[9]", swingMatrix))
  gl.glUniform3f(locations.modelScale, 1.0, 1.0, thickness)
  local pivot = heldItem.pivotFor(swingStyle)
  gl.glUniform3f(locations.pivot, pivot[1], pivot[2], pivot[3])
  gl.glUniform3f(locations.translate, swing.x + equip.x, swing.y + equip.y, swing.z + equip.z)
  gl.glUniform2f(locations.center, ndcX(centerX, width), ndcY(centerY, height))
  gl.glUniform2f(locations.scale, size / width * 2.0, size / height * 2.0)
  gl.glUniform3f(locations.projection, cameraDistance, near, far)
  gl.glUniform3f(locations.tint, tint[1], tint[2], tint[3])
  gl.glUniform3f(locations.ambient, ambient[1], ambient[2], ambient[3])
  gl.glUniform3f(locations.sunColor, sunColor[1], sunColor[2], sunColor[3])
  gl.glUniform3f(locations.moonColor, moonColor[1], moonColor[2], moonColor[3])
  gl.glUniform3f(locations.lightDir, lightDir[1], lightDir[2], lightDir[3])
  gl.glUniform3f(locations.params, environment.localLight or 1.0,
    environment.underwater and 1.0 or 0.0, environment.ambientFloor or 0.04)

  -- A real depth-tested model, isolated from both the world's depth buffer and
  -- the flat HUD that follows it.
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
  gl.glDepthFunc(GL_LESS)
  gl.glDepthMask(1)
  gl.glClear(GL_DEPTH_BUFFER_BIT)
  gl.glActiveTexture(GL_TEXTURE0)
  gl.glBindTexture(GL_TEXTURE_2D, texture.id[0])
  gl.glBindVertexArray(model.mesh.vao[0])
  gl.glDrawArrays(GL_TRIANGLES, 0, model.mesh.count)
  gl.glBindVertexArray(0)
end

function hud:draw(width, height, time, selectedSlot, state, atlasTexture, environment)
  environment=environment or {}
  self:ensureMeshes(width, height, selectedSlot, state, time)

  self:drawHeldItem(width, height, time, selectedSlot, state, atlasTexture, environment)

  gl.glUseProgram(self.shader)
  gl.glUniform1f(self.timeLocation, time)
  gl.glUniform1i(self.textureLocation, 0)

  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  self:drawMesh(self.meshes.color, self.textures.white)
  self:drawMesh(self.meshes.widgets, self.textures.widgets)
  self:drawMesh(self.meshes.heartEmpty, self.textures.heartEmpty)
  self:drawMesh(self.meshes.heartHalf, self.textures.heartHalf)
  self:drawMesh(self.meshes.heart, self.textures.heart)
  self:drawMesh(self.meshes.hungerEmpty, self.textures.hungerEmpty)
  self:drawMesh(self.meshes.hungerHalf, self.textures.hungerHalf)
  self:drawMesh(self.meshes.hunger, self.textures.hunger)
  self:drawMesh(self.meshes.crosshair, self.textures.crosshair)
  if atlasTexture then self:drawMesh(self.meshes.terrain, atlasTexture) end
  self:drawMesh(self.meshes.font, self.textures.font)

  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
end

function hud:drawInventory(width,height,screen,state,mouseX,mouseY,atlasTexture,time)
  local key=table.concat({screen,width,height,state.inventoryVersion or 0,state.creativeTab or "building",state.inventory.search or "",math.floor(mouseX or 0),math.floor(mouseY or 0),math.floor((time or 0)*12)},":")
  if not self.inventoryMeshes or self.inventoryKey~=key then
    local raw=buildInventoryMeshes(width,height,screen,state,mouseX or 0,mouseY or 0,time or 0)
    rendering.releaseGroup(self.inventoryMeshes)
    self.inventoryMeshes={
      panel=upload(raw.panel),creativePanel=upload(raw.creativePanel),creativeTabs=upload(raw.creativeTabs),
      color=upload(raw.color),overlay=upload(raw.overlay),terrain=upload(raw.terrain),font=upload(raw.font),skin=upload(raw.skin)
    }
    self.inventoryKey=key
  end
  gl.glDisable(GL_DEPTH_TEST) gl.glEnable(GL_BLEND) gl.glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA) gl.glDepthMask(0)
  gl.glUseProgram(self.shader) gl.glUniform1f(self.timeLocation,0) gl.glUniform1i(self.textureLocation,0)
  self:drawMesh(self.inventoryMeshes.color,self.textures.white)
  local panelTexture=screen=="crafting_table" and self.textures.craftingTable or
    (screen=="furnace" and self.textures.furnace or self.textures.inventory)
  self:drawMesh(self.inventoryMeshes.panel,panelTexture)
  local creativeBackground = state.creativeTab == "search" and self.textures.creativeSearch or self.textures.creativeItems
  self:drawMesh(self.inventoryMeshes.creativePanel,creativeBackground)
  self:drawMesh(self.inventoryMeshes.creativeTabs,self.textures.creativeTabs)
  self:drawMesh(self.inventoryMeshes.overlay,self.textures.white)
  self:drawMesh(self.inventoryMeshes.skin,self.textures.skin)
  if atlasTexture then self:drawMesh(self.inventoryMeshes.terrain,atlasTexture) end
  self:drawMesh(self.inventoryMeshes.font,self.textures.font)
  gl.glDepthMask(1) gl.glDisable(GL_BLEND) gl.glEnable(GL_DEPTH_TEST)
end

function hud:ensureMenuMeshes(width, height, screen, mouseX, mouseY, menuState, time)
  local scale = guiScale(width, height)
  local logicalMouseX = mouseX / scale
  local logicalMouseY = mouseY / scale
  local hovered = hud.menuButtonAt(screen, width, height, mouseX, mouseY, menuState) or "none"
  local panoramaFrame = screen == "main" and math.floor((time or 0.0) * 20.0) or 0
  local key = table.concat({screen or "none", width, height, hovered, uiMenu.stateKey(menuState), panoramaFrame}, ":")
  if self.menuMeshes and self.menuKey == key then
    return
  end

  local rawMeshes = buildMenuMeshes(width, height, screen, logicalMouseX, logicalMouseY, menuState, time)
  local panoramaFaces = {}
  for i = 1, #rawMeshes.panoramaFaces do
    panoramaFaces[i] = upload(rawMeshes.panoramaFaces[i])
  end

  rendering.releaseGroup(self.menuMeshes)
  self.menuMeshes = {
    panorama = upload(rawMeshes.panorama),
    panoramaFaces = panoramaFaces,
    background = upload(rawMeshes.background),
    color = upload(rawMeshes.color),
    logo = upload(rawMeshes.logo),
    widgets = upload(rawMeshes.widgets),
    font = upload(rawMeshes.font)
  }
  self.menuKey = key
end

function hud:drawMenu(width, height, screen, mouseX, mouseY, menuState, time)
  self:ensureMenuMeshes(width, height, screen, mouseX or -1, mouseY or -1, menuState, time)

  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  gl.glUseProgram(self.shader)
  gl.glUniform1f(self.timeLocation, 0.0)
  gl.glUniform1i(self.textureLocation, 0)

  self:drawMesh(self.menuMeshes.panorama, self.textures.white)
  if screen == "main" then
    for i = 1, #self.menuMeshes.panoramaFaces do
      self:drawMesh(self.menuMeshes.panoramaFaces[i], self.textures.panoramaFaces[i])
    end
  end
  self:drawMesh(self.menuMeshes.background, self.textures.background)
  self:drawMesh(self.menuMeshes.color, self.textures.white)
  self:drawMesh(self.menuMeshes.logo, self.textures.logo)
  self:drawMesh(self.menuMeshes.widgets, self.textures.widgets)
  self:drawMesh(self.menuMeshes.font, self.textures.font)

  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
end

function hud:ensureLoadingMeshes(width, height, loadingState)
  loadingState = loadingState or {}
  local key = table.concat({
    width,
    height,
    loadingState.title or "",
    loadingState.message or "",
    tostring(math.floor((loadingState.progress or 0.0) * 64.0 + 0.5))
  }, ":")
  if self.loadingMeshes and self.loadingKey == key then
    return
  end

  local rawMeshes = buildLoadingMeshes(width, height, loadingState)
  rendering.releaseGroup(self.loadingMeshes)
  self.loadingMeshes = {
    background = upload(rawMeshes.background),
    color = upload(rawMeshes.color),
    font = upload(rawMeshes.font)
  }
  self.loadingKey = key
end

function hud:drawLoading(width, height, loadingState)
  self:ensureLoadingMeshes(width, height, loadingState)

  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  gl.glUseProgram(self.shader)
  gl.glUniform1f(self.timeLocation, 0.0)
  gl.glUniform1i(self.textureLocation, 0)

  self:drawMesh(self.loadingMeshes.background, self.textures.background)
  self:drawMesh(self.loadingMeshes.color, self.textures.white)
  self:drawMesh(self.loadingMeshes.font, self.textures.font)

  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
end

function hud:ensureDebugMeshes(width, height, debugState)
  debugState = debugState or {}
  local key = debugState.key or table.concat({
    width,
    height,
    table.concat(debugState.leftLines or {}, "\n"),
    table.concat(debugState.rightLines or {}, "\n")
  }, "\30")

  if self.debugMeshes and self.debugKey == key then
    return
  end

  local rawMeshes = buildDebugMeshes(width, height, debugState)
  rendering.releaseGroup(self.debugMeshes)
  self.debugMeshes = {
    color = upload(rawMeshes.color),
    font = upload(rawMeshes.font)
  }
  self.debugKey = key
end

function hud:drawDebug(width, height, debugState)
  self:ensureDebugMeshes(width, height, debugState)

  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  gl.glUseProgram(self.shader)
  gl.glUniform1f(self.timeLocation, 0.0)
  gl.glUniform1i(self.textureLocation, 0)

  self:drawMesh(self.debugMeshes.color, self.textures.white)
  self:drawMesh(self.debugMeshes.font, self.textures.font)

  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
end

function hud:release()
  rendering.releaseGroup(self.meshes)
  rendering.releaseGroup(self.menuMeshes)
  rendering.releaseGroup(self.loadingMeshes)
  rendering.releaseGroup(self.debugMeshes)
  rendering.releaseGroup(self.inventoryMeshes)
  for _,model in pairs(self.heldModels or {}) do
    if model then
      gl.glDeleteVertexArrays(1, model.mesh.vao)
      gl.glDeleteBuffers(1, model.mesh.vbo)
    end
  end
  self.heldModels = {}
  for _,heldTexture in pairs(self.heldTextures or {}) do
    if heldTexture.id then gl.glDeleteTextures(1,heldTexture.id) end
  end
  self.meshes = nil
  self.menuMeshes = nil
  self.loadingMeshes = nil
  self.debugMeshes = nil
  self.inventoryMeshes = nil
  self.heldTextures = {}
  self.menuKey = nil
  self.loadingKey = nil
  self.debugKey = nil
  self.inventoryKey = nil
end

function hud.menuButtonAt(screen, width, height, mouseX, mouseY, menuState)
  if not screen then
    return nil
  end

  local scale = guiScale(width, height)
  local logicalWidth = math.floor(width / scale)
  local logicalHeight = math.floor(height / scale)
  local logicalMouseX = mouseX / scale
  local logicalMouseY = mouseY / scale
  local buttons = uiMenu.buttons(screen, logicalWidth, logicalHeight, menuState)
  for i = 1, #buttons do
    local button = buttons[i]
    if button.enabled ~= false and isHovered(button, logicalMouseX, logicalMouseY) then
      return button.id
    end
  end

  return nil
end

function hud.menuSliderValueAt(screen, width, height, mouseX, mouseY, menuState, activeSlider)
  if not screen then
    return nil
  end

  local scale = guiScale(width, height)
  local logicalWidth = math.floor(width / scale)
  local logicalHeight = math.floor(height / scale)
  local logicalMouseX = mouseX / scale
  local logicalMouseY = mouseY / scale
  local buttons = uiMenu.buttons(screen, logicalWidth, logicalHeight, menuState)
  for i = 1, #buttons do
    local slider = buttons[i]
    if slider.kind == "slider" and slider.enabled ~= false and
        ((activeSlider and slider.id == activeSlider) or
         (not activeSlider and isHovered(slider, logicalMouseX, logicalMouseY))) then
      local amount = math.max(0.0, math.min(1.0, (logicalMouseX - slider.x) / math.max(1, slider.w - 1)))
      local minimum = slider.minValue or 0
      local maximum = slider.maxValue or 1
      return slider.id, math.floor(minimum + amount * (maximum - minimum) + 0.5)
    end
  end

  return nil
end

function hud.setGuiScale(scale)
  local numeric = tonumber(scale) or 0
  guiScaleOverride = numeric > 0 and math.floor(numeric) or nil
end

return hud
