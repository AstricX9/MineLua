local ffi = require("ffi")
local GL = require("gl")
local shaderModule = require("shader")
local rendering = require("rendering")
local texture = require("texture")
local uiMenu = require("ui_menu")

local hud = {}
hud.__index = hud

local gl = GL.gl

local GL_ARRAY_BUFFER = 0x8892
local GL_STATIC_DRAW = 0x88E4
local GL_FLOAT = 0x1406
local GL_TRIANGLES = 0x0004
local GL_DEPTH_TEST = 0x0B71
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
  vec2 p = aPos.xy;
  gl_Position = vec4(p, 0.0, 1.0);
  vColor = vec4(aColor, aInfo.x);
  vTexCoord = aTexCoord;
  vUseTexture = aInfo.y;
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

local function appendSpriteUv(vertices, width, height, x, y, w, h, u0, v0, u1, v1, color)
  appendQuad(vertices, {
    {ndcX(x, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y, height)},
    {ndcX(x + w, width), ndcY(y + h, height)},
    {ndcX(x, width), ndcY(y + h, height)}
  }, color or COLORS.white, {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}, 1.0, 0.0)
end

local function guiScale(width, height)
  local scale = 1
  while scale < 4 and width / (scale + 1) >= 320 and height / (scale + 1) >= 240 do
    scale = scale + 1
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

local function appendSlider(meshes, width, height, scale, x, y, w, label, value)
  local button = {label = label, x = x, y = y, w = w, h = 20}
  appendButton(meshes, width, height, scale, button, -1, -1)
  local knobX = x + math.floor((w - 4) * value)
  appendScaledSprite(meshes.widgets, width, height, scale, knobX, y, 4, 20, 0, 66, 4, 20, 256, 256, COLORS.white)
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

local function appendPixelHeart(vertices, width, height, x, y)
  appendSprite(vertices, width, height, x, y, 18, 18, 16, 0, 9, 9, 256, 256, COLORS.white)
  appendSprite(vertices, width, height, x, y, 18, 18, 52, 0, 9, 9, 256, 256, COLORS.white)
end

local function appendHunger(vertices, width, height, x, y)
  appendSprite(vertices, width, height, x, y, 18, 18, 16, 27, 9, 9, 256, 256, COLORS.white)
  appendSprite(vertices, width, height, x, y, 18, 18, 52, 27, 9, 9, 256, 256, COLORS.white)
end

local function appendArmor(vertices, width, height, x, y)
  appendSprite(vertices, width, height, x, y, 18, 18, 16, 9, 9, 9, 256, 256, COLORS.white)
  appendSprite(vertices, width, height, x, y, 18, 18, 34, 9, 9, 9, 256, 256, COLORS.white)
end

local function appendStatusBars(vertices, width, height)
  local center = math.floor(width * 0.5)
  local left = center - 184
  local right = center + 24
  local y = height - 86

  for i = 0, 9 do
    appendPixelHeart(vertices, width, height, left + i * 18, y)
    appendHunger(vertices, width, height, right + i * 18, y)
    appendArmor(vertices, width, height, left + i * 18, y - 18)
  end

  appendSprite(vertices, width, height, center - 182, height - 64, 364, 10, 0, 64, 182, 5, 256, 256, COLORS.white)
  appendSprite(vertices, width, height, center - 182, height - 64, 180, 10, 0, 69, 182, 5, 256, 256, COLORS.white)
end

local function appendHand(vertices, width, height)
  local scale = math.max(0.75, math.min(1.18, height / 720.0))
  local x = width - 128 * scale
  local y = height - 205 * scale
  local armW = 82 * scale
  local armH = 218 * scale

  appendQuad(vertices, {
    {ndcX(x + 12 * scale, width), ndcY(y + 8 * scale, height)},
    {ndcX(x + armW, width), ndcY(y + 38 * scale, height)},
    {ndcX(x + armW - 6 * scale, width), ndcY(y + armH, height)},
    {ndcX(x - 4 * scale, width), ndcY(y + armH, height)}
  }, COLORS.skin, {{0, 0}, {0, 0}, {0, 0}, {0, 0}}, 0.0, 0.0)

  appendQuad(vertices, {
    {ndcX(x + 24 * scale, width), ndcY(y + 25 * scale, height)},
    {ndcX(x + 54 * scale, width), ndcY(y + 38 * scale, height)},
    {ndcX(x + 49 * scale, width), ndcY(y + 126 * scale, height)},
    {ndcX(x + 18 * scale, width), ndcY(y + 112 * scale, height)}
  }, COLORS.skinLight, {{0, 0}, {0, 0}, {0, 0}, {0, 0}}, 0.0, 0.0)

  appendQuad(vertices, {
    {ndcX(x + 62 * scale, width), ndcY(y + 44 * scale, height)},
    {ndcX(x + armW, width), ndcY(y + 53 * scale, height)},
    {ndcX(x + armW - 6 * scale, width), ndcY(y + armH, height)},
    {ndcX(x + 57 * scale, width), ndcY(y + armH, height)}
  }, COLORS.skinDark, {{0, 0}, {0, 0}, {0, 0}, {0, 0}}, 0.0, 0.0)
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
  local size = 24
  local cx = math.floor(width * 0.5 - size * 0.5)
  local cy = math.floor(height * 0.5 - size * 0.5)
  appendSprite(vertices, width, height, cx, cy, size, size, 0, 0, 16, 16, 256, 256, COLORS.white)
end

local function buildMeshes(width, height, selectedSlot)
  local meshes = {
    color = {},
    widgets = {},
    icons = {}
  }

  appendHand(meshes.color, width, height)
  appendStatusBars(meshes.icons, width, height)
  appendHotbar(meshes.widgets, width, height, selectedSlot)
  appendCrosshair(meshes.icons, width, height)
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
    appendCenteredText(meshes.font, width, height, scale, "Singleplayer", cx, 20, TEXT_WHITE)
    appendScaledRect(meshes.color, width, height, scale, 0, 32, logicalWidth, logicalHeight - 96, COLORS.panel)
    appendText(meshes.font, width, height, scale, "Gather resources, craft, survive", cx - 100, 52, TEXT_MUTED)
    appendText(meshes.font, width, height, scale, "Build freely with flight enabled", cx - 100, 112, TEXT_MUTED)
  elseif screen == "create_world" then
    appendCenteredText(meshes.font, width, height, scale, "Create New World", cx, 20, TEXT_WHITE)
    appendText(meshes.font, width, height, scale, "World Name", cx - 100, 47, TEXT_MUTED)
    appendTextBox(meshes, width, height, scale, cx - 100, 60, 200, 20, "New World")
    appendText(meshes.font, width, height, scale, "Will be saved in: New World", cx - 100, 85, TEXT_MUTED)
    if menuState.moreWorldOptions then
      appendText(meshes.font, width, height, scale, "Seed for the World Generator", cx - 100, 104, TEXT_MUTED)
      appendTextBox(meshes, width, height, scale, cx - 100, 116, 200, 20, menuState.worldSeedText or "")
      appendText(meshes.font, width, height, scale, "Leave blank for a random seed", cx - 100, 140, TEXT_MUTED)
      if (menuState.worldGeneratorType or "default") == "superflat" then
        appendText(meshes.font, width, height, scale, "Flat grass, dirt and stone layers", cx - 100, 176, TEXT_MUTED)
      else
        appendText(meshes.font, width, height, scale, "Biomes, hills, oceans and trees", cx - 100, 176, TEXT_MUTED)
      end
    else
      if (menuState.worldGameMode or "survival") == "creative" then
        appendText(meshes.font, width, height, scale, "Unlimited resources and free flying", cx - 100, 124, TEXT_MUTED)
      else
        appendText(meshes.font, width, height, scale, "Search for resources, craft and survive", cx - 100, 124, TEXT_MUTED)
      end
    end
  elseif screen == "options" then
    appendCenteredText(meshes.font, width, height, scale, "Options", cx, 20, TEXT_WHITE)
    local y0 = math.floor(logicalHeight / 6)
    appendSlider(meshes, width, height, scale, cx - 155, y0, 150, "Music: 100%", 0.96)
    appendSlider(meshes, width, height, scale, cx + 5, y0, 150, "Sound: 100%", 0.96)
    appendSlider(meshes, width, height, scale, cx + 5, y0 + 24, 150, "Sensitivity: 100%", 0.50)
    appendSlider(meshes, width, height, scale, cx - 155, y0 + 48, 150, "FOV: Normal", 0.02)
  elseif screen == "video" then
    appendCenteredText(meshes.font, width, height, scale, "Video Settings", cx, 20, TEXT_WHITE)
    local y0 = math.floor(logicalHeight / 6)
    appendSlider(meshes, width, height, scale, cx - 155, y0 + 96, 150, "Brightness: Moody", 0.02)
  elseif screen == "controls" then
    appendCenteredText(meshes.font, width, height, scale, "Controls", cx, 20, TEXT_WHITE)
    appendControlsLabels(meshes, width, height, scale, logicalWidth, logicalHeight)
  end

  local buttons = uiMenu.buttons(screen, logicalWidth, logicalHeight, menuState)
  for i = 1, #buttons do
    appendButton(meshes, width, height, scale, buttons[i], mouseX, mouseY)
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

function hud.create()
  local shader = createShader()
  return setmetatable({
    shader = shader,
    timeLocation = gl.glGetUniformLocation(shader, "uTime"),
    textureLocation = gl.glGetUniformLocation(shader, "uTexture"),
    textures = {
      widgets = createTexture("assets/textures/gui/widgets.png"),
      icons = createTexture("assets/textures/gui/icons.png"),
      font = createTexture("assets/textures/font/ascii.png"),
      background = createTexture("assets/textures/gui/options_background.png", true),
      logo = createTexture("assets/textures/gui/title/minecraft.png"),
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
    meshes = nil,
    menuMeshes = nil,
    menuKey = nil,
    loadingMeshes = nil,
    loadingKey = nil,
    debugMeshes = nil,
    debugKey = nil,
    width = 0,
    height = 0,
    selectedSlot = 0
  }, hud)
end

function hud:ensureMeshes(width, height, selectedSlot)
  selectedSlot = selectedSlot or 1
  if self.meshes and self.width == width and self.height == height and self.selectedSlot == selectedSlot then
    return
  end

  self.width = width
  self.height = height
  self.selectedSlot = selectedSlot
  local rawMeshes = buildMeshes(width, height, selectedSlot)
  rendering.releaseGroup(self.meshes)
  self.meshes = {
    color = upload(rawMeshes.color),
    widgets = upload(rawMeshes.widgets),
    icons = upload(rawMeshes.icons)
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

function hud:draw(width, height, time, selectedSlot)
  self:ensureMeshes(width, height, selectedSlot)

  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  gl.glDepthMask(0)
  gl.glUseProgram(self.shader)
  gl.glUniform1f(self.timeLocation, time)
  gl.glUniform1i(self.textureLocation, 0)

  self:drawMesh(self.meshes.color, self.textures.white)
  self:drawMesh(self.meshes.widgets, self.textures.widgets)
  self:drawMesh(self.meshes.icons, self.textures.icons)

  gl.glDepthMask(1)
  gl.glDisable(GL_BLEND)
  gl.glEnable(GL_DEPTH_TEST)
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
  self.meshes = nil
  self.menuMeshes = nil
  self.loadingMeshes = nil
  self.debugMeshes = nil
  self.menuKey = nil
  self.loadingKey = nil
  self.debugKey = nil
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

return hud
