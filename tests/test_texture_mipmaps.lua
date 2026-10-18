package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")
local texture = require("texture")

local function image(width, height)
  return {
    w = width,
    h = height,
    data = ffi.new("uint8_t[?]", width * height * 4)
  }
end

local atlas = texture.createAtlas()
atlas:addImage("first", image(16, 16))
atlas:addImage("second", image(16, 16))
assert(atlas:getMaxMipLevel() == 4,
  "16-pixel atlas tiles should support levels 0 through 4 without bleeding")

local unevenAtlas = texture.createAtlas()
unevenAtlas:addImage("wide", image(24, 16))
unevenAtlas:addImage("next", image(16, 16))
assert(unevenAtlas:getMaxMipLevel() == 3,
  "mip depth should stop when a packed edge no longer aligns to the downsample grid")

local oddAtlas = texture.createAtlas()
oddAtlas:addImage("odd", image(15, 15))
assert(oddAtlas:getMaxMipLevel() == 0,
  "odd-sized atlas tiles should disable mipmapping instead of sampling neighbours")

print("texture mipmap tests passed")
