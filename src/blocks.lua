local json = require("json")
local texture = require("texture")
local ffi = require("ffi")
local modApi = require("mod_api")

-- Small helper to sample center pixel from a PNG
local function sampleCenterColor(path)
  local stbi = ffi.load("lib/stb_image.dll")
  local load_png = function(p)
    local w, h, channels = ffi.new("int[1]"), ffi.new("int[1]"), ffi.new("int[1]")
    local data = stbi.stbi_load(p, w, h, channels, 4)
    if data == nil then return {255, 255, 255} end
    local cx, cy = math.floor(w[0]/2), math.floor(h[0]/2)
    local idx = (cy * w[0] + cx) * 4
    local r, g, b = data[idx], data[idx+1], data[idx+2]
    stbi.stbi_image_free(data)
    return {r, g, b}
  end
  return load_png(path)
end

local function colorToUnit(color)
  return {color[1] / 255, color[2] / 255, color[3] / 255}
end

local function isLayeredTexture(value)
  return type(value) == "table" and #value > 0
end

local function addFaceTexture(atlas, name, value, tint)
  if isLayeredTexture(value) then
    return atlas:addLayeredTexture(name, value, tint)
  end

  return atlas:addTexture(name, value)
end

local M = {
  mapping = modApi.blocks.byName,
  list = modApi.blocks.byId
}

local function loadDataFile(name)
  local f = io.open("data/" .. name, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return json.decode(content)
end

-- Fallback basic list if data/blocks.json is missing
local blockList = loadDataFile("blocks.json") or {"air", "grass", "dirt", "stone"}

for i, bname in ipairs(blockList) do
  local def = loadDataFile(bname .. ".json")
  if def then
    def.id = i - 1
    M[bname] = modApi.registerBlock(bname, def)
  end
end

-- Fallbacks just in case
if not M.air then
  M.air = modApi.registerBlock("air", {
    id = 0,
    name = "Air",
    texture = nil,
    properties = {solid = false}
  })
end

function M.register(name, definition)
  local id = modApi.registerBlock(name, definition)
  M[name] = id
  return id
end

function M.initTextures(atlas)
  for _, def in pairs(M.list) do
    def.uvs = { top = nil, bottom = nil, side = nil }
    def.color = {1.0, 1.0, 1.0}
    def.colors = {
      top = {1.0, 1.0, 1.0},
      bottom = {1.0, 1.0, 1.0},
      side = {1.0, 1.0, 1.0}
    }

    local colormapColor = nil
    if def.colormap then
      local col = sampleCenterColor(def.colormap)
      colormapColor = colorToUnit(col)
      def.color = colormapColor
    end

    if type(def.texture) == "string" then
      local uv = atlas:addTexture(def.name, def.texture)
      def.uvs.top = uv; def.uvs.bottom = uv; def.uvs.side = uv
      if colormapColor then
        def.colors.top = colormapColor
        def.colors.bottom = colormapColor
        def.colors.side = colormapColor
      end
    elseif type(def.texture) == "table" then
      def.uvs.top = addFaceTexture(atlas, def.name .. "_top", def.texture.top, colormapColor)
      def.uvs.bottom = addFaceTexture(atlas, def.name .. "_bottom", def.texture.bottom, colormapColor)
      def.uvs.side = addFaceTexture(atlas, def.name .. "_side", def.texture.side, colormapColor)

      if colormapColor then
        def.colors.top = isLayeredTexture(def.texture.top) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.bottom = isLayeredTexture(def.texture.bottom) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.side = isLayeredTexture(def.texture.side) and {1.0, 1.0, 1.0} or colormapColor
      end
    else
      -- air, etc
    end
  end
end

return M
