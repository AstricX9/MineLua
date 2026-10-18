local json = require("json")
local texture = require("texture")
local modApi = require("mod_api")
local filesystem = require("filesystem")

-- Small helper to sample center pixel from a PNG. It goes through the shared
-- loader rather than calling stb directly, so block tint colours come out of a
-- packed container as readily as out of a loose file.
local function sampleCenterColor(path)
  local image = texture.loadPng(path)
  if not image then return {255, 255, 255} end

  local index = (math.floor(image.h / 2) * image.w + math.floor(image.w / 2)) * 4
  return {image.data[index], image.data[index + 1], image.data[index + 2]}
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

local BLOCK_DATA_ROOT = "data/minecraft/block/"

local function loadDataFile(name)
  local f = io.open(BLOCK_DATA_ROOT .. name, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return json.decode(content)
end

-- Preserve registry order so numeric block IDs remain stable across saves.
local blockList = loadDataFile("index.json") or {"air", "grass", "dirt", "stone"}

-- Definitions no longer have to be added to index.json by hand. Keep every
-- indexed entry first (and therefore keep its save-compatible numeric ID),
-- then append newly discovered JSON definitions in alphabetical order.
local indexed = {}
for _, name in ipairs(blockList) do indexed[name] = true end
for _, entry in ipairs(filesystem.entries(BLOCK_DATA_ROOT)) do
  local name = not entry.isDirectory and entry.name:match("^(.*)%.json$") or nil
  if name and name ~= "index" and not indexed[name] then
    indexed[name] = true
    blockList[#blockList + 1] = name
  end
end

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

local function initDefinitionTexture(atlas, def)
    def.uvs = { top = nil, bottom = nil, side = nil, front = nil, back = nil }
    def.color = {1.0, 1.0, 1.0}
    def.colors = {
      top = {1.0, 1.0, 1.0},
      bottom = {1.0, 1.0, 1.0},
      side = {1.0, 1.0, 1.0},
      front = {1.0, 1.0, 1.0},
      back = {1.0, 1.0, 1.0}
    }

    local colormapColor = nil
    if def.colormap then
      local col = sampleCenterColor(def.colormap)
      colormapColor = colorToUnit(col)
      def.color = colormapColor
    end

    local atlasTint = def.biomeTint and nil or colormapColor

    if type(def.texture) == "string" then
      local uv = atlas:addTexture(def.name, def.texture)
      def.uvs.top = uv; def.uvs.bottom = uv; def.uvs.side = uv
      def.uvs.front = uv; def.uvs.back = uv
      if colormapColor and not def.biomeTint then
        def.colors.top = colormapColor
        def.colors.bottom = colormapColor
        def.colors.side = colormapColor
        def.colors.front = colormapColor
        def.colors.back = colormapColor
      end
    elseif type(def.texture) == "table" then
      def.uvs.top = addFaceTexture(atlas, def.name .. "_top", def.texture.top, atlasTint)
      def.uvs.bottom = addFaceTexture(atlas, def.name .. "_bottom", def.texture.bottom, atlasTint)
      def.uvs.side = addFaceTexture(atlas, def.name .. "_side", def.texture.side, atlasTint)
      def.uvs.front = addFaceTexture(atlas, def.name .. "_front", def.texture.front or def.texture.side, atlasTint)
      def.uvs.back = addFaceTexture(atlas, def.name .. "_back", def.texture.back or def.texture.side, atlasTint)

      if colormapColor and not def.biomeTint then
        def.colors.top = isLayeredTexture(def.texture.top) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.bottom = isLayeredTexture(def.texture.bottom) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.side = isLayeredTexture(def.texture.side) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.front = isLayeredTexture(def.texture.front or def.texture.side) and {1.0, 1.0, 1.0} or colormapColor
        def.colors.back = isLayeredTexture(def.texture.back or def.texture.side) and {1.0, 1.0, 1.0} or colormapColor
      end
    else
      -- air, etc
    end
end

local function livingTextureSource(def)
  local properties=def.properties or {}
  if not properties.aliveTree then return nil end
  local base,axis=def.key:match("^(.-)_alive(_[xz])$")
  if base then return base..axis end
  return def.key:match("^(.-)_alive$")
end

function M.initTextures(atlas)
  local aliases={}
  for _,def in pairs(M.list) do
    local sourceKey=livingTextureSource(def)
    if sourceKey then
      aliases[#aliases+1]={definition=def,sourceKey=sourceKey}
    else
      initDefinitionTexture(atlas,def)
    end
  end

  -- Living/dead is voxel state, not a new appearance. Reuse the ordinary log's
  -- atlas coordinates instead of packing identical images for every state and
  -- axis variant.
  for _,alias in ipairs(aliases) do
    local source=M.mapping[alias.sourceKey]
    if source and source.uvs then
      alias.definition.uvs=source.uvs
      alias.definition.color=source.color
      alias.definition.colors=source.colors
    else
      initDefinitionTexture(atlas,alias.definition)
    end
  end
end

return M
