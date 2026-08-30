local ffi = require("ffi")
local vfs = require("vfs")

local M = {}

-- STB Image loader via FFI. The from-memory entry point is what a packed
-- release decodes through: stbi_load only ever sees a real path, and in a
-- release build the PNGs live inside the container instead.
ffi.cdef[[
  unsigned char *stbi_load(char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
  unsigned char *stbi_load_from_memory(unsigned char const *buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels);
  void stbi_image_free(void *retval_from_stbi_load);
]]

local stbi = ffi.load("lib/stb_image.dll")

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function normalize_path(path)
  return (path:gsub("\\", "/"):gsub("^%./", ""))
end

function M.resolvePath(path)
  if not path then
    return nil
  end

  local clean = normalize_path(path)
  local candidates = {clean}

  if clean:sub(1, 9) == "textures/" then
    candidates[#candidates + 1] = "assets/" .. clean
  elseif clean:sub(1, 7) ~= "assets/" then
    candidates[#candidates + 1] = "assets/" .. clean
  end

  for i = 1, #candidates do
    if file_exists(candidates[i]) then
      return candidates[i]
    end
  end

  return clean
end

local function load_png(path)
  path = M.resolvePath(path)
  local w = ffi.new("int[1]")
  local h = ffi.new("int[1]")
  local channels = ffi.new("int[1]")

  -- Force 4 channels (RGBA). A loose file on disk wins; only when there is
  -- none does the container get asked, which keeps texture overrides working
  -- and costs a packed build one failed open per image.
  local data = stbi.stbi_load(path, w, h, channels, 4)
  local packed
  if data == nil then
    packed = vfs.read(path)
    if packed then
      data = stbi.stbi_load_from_memory(ffi.cast("const unsigned char *", packed), #packed,
        w, h, channels, 4)
    end
  end
  if data == nil then return nil end

  local width = w[0]
  local height = h[0]
  local rgba = ffi.new("uint8_t[?]", width * height * 4)
  
  -- Copy the data and free the STB memory
  ffi.copy(rgba, data, width * height * 4)
  stbi.stbi_image_free(data)

  return { w = width, h = height, data = rgba }
end

function M.loadPng(path)
  return load_png(path)
end

-- The classic 176x166 container panels have a tiny rounded silhouette. Some
-- source packs store those corner texels against an opaque white matte, so
-- blending alone cannot reveal the world behind them. Clear only the canonical
-- 18 corner texels and leave every authored interior pixel untouched.
function M.applyGuiCornerTransparency(img)
  if not img or img.w ~= 176 or img.h ~= 166 or not img.data then return img end

  local corners = {
    {0,0},{1,0},{173,0},{174,0},{175,0},
    {0,1},{174,1},{175,1},{175,2},
    {0,163},{0,164},{1,164},{175,164},
    {0,165},{1,165},{2,165},{174,165},{175,165}
  }
  for _, point in ipairs(corners) do
    img.data[(point[2] * img.w + point[1]) * 4 + 3] = 0
  end
  return img
end

-- Minimal PNG writer, used for screenshots.
--
-- Deflate is written as stored blocks: a screenshot is a one-off keypress, and
-- an uncompressed PNG every viewer can open beats pulling in a compressor.
local crc_table

local function crc32(buffer, length)
  if not crc_table then
    crc_table = ffi.new("uint32_t[256]")
    for n = 0, 255 do
      local c = n
      for _ = 1, 8 do
        if bit.band(c, 1) ~= 0 then
          c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
        else
          c = bit.rshift(c, 1)
        end
      end
      crc_table[n] = c
    end
  end

  local crc = 0xFFFFFFFF
  for i = 0, length - 1 do
    crc = bit.bxor(crc_table[bit.band(bit.bxor(crc, buffer[i]), 0xFF)], bit.rshift(crc, 8))
  end
  return bit.bxor(crc, 0xFFFFFFFF)
end

local function adler32(buffer, length)
  local a, b, i = 1, 0, 0
  while i < length do
    -- 5552 is the most bytes that can be summed before b can overflow the
    -- exact integer range of a double.
    local span = math.min(length - i, 5552)
    for j = 0, span - 1 do
      a = a + buffer[i + j]
      b = b + a
    end
    a = a % 65521
    b = b % 65521
    i = i + span
  end
  return b * 65536 + a
end

-- Writes `width * height` RGB triples. `bottomUp` flips the rows on the way
-- out, which is what OpenGL hands back from glReadPixels.
function M.writePng(path, width, height, rgb, bottomUp)
  local rowBytes = width * 3
  local rawLength = height * (1 + rowBytes)
  local blocks = math.max(1, math.ceil(rawLength / 65535))
  local zlibLength = 2 + blocks * 5 + rawLength + 4
  local total = 8 + 25 + (12 + zlibLength) + 12
  local out = ffi.new("uint8_t[?]", total)
  local at = 0

  local function byte(value)
    out[at] = bit.band(value, 0xFF)
    at = at + 1
  end
  local function be32(value)
    byte(bit.rshift(value, 24)) byte(bit.rshift(value, 16))
    byte(bit.rshift(value, 8)) byte(value)
  end
  local function tag(text)
    for i = 1, #text do byte(text:byte(i)) end
  end
  local function chunk(name, dataStart, dataLength)
    local crcStart = dataStart - 4
    be32(crc32(out + crcStart, dataLength + 4))
  end

  for _, value in ipairs({0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}) do byte(value) end

  be32(13) local ihdr = at + 4 tag("IHDR")
  be32(width) be32(height)
  byte(8) byte(2) byte(0) byte(0) byte(0)
  chunk("IHDR", ihdr, 13)

  be32(zlibLength) local idat = at + 4 tag("IDAT")
  byte(0x78) byte(0x01)
  local raw = ffi.new("uint8_t[?]", rawLength)
  for row = 0, height - 1 do
    local source = bottomUp and (height - 1 - row) or row
    local destination = row * (1 + rowBytes)
    raw[destination] = 0
    ffi.copy(raw + destination + 1, rgb + source * rowBytes, rowBytes)
  end
  local written = 0
  while written < rawLength do
    local span = math.min(rawLength - written, 65535)
    byte(written + span >= rawLength and 1 or 0)
    byte(bit.band(span, 0xFF)) byte(bit.rshift(span, 8))
    byte(bit.band(bit.bxor(span, 0xFFFF), 0xFF)) byte(bit.rshift(bit.bxor(span, 0xFFFF), 8))
    ffi.copy(out + at, raw + written, span)
    at = at + span
    written = written + span
  end
  be32(adler32(raw, rawLength))
  chunk("IDAT", idat, zlibLength)

  be32(0) local iend = at + 4 tag("IEND") chunk("IEND", iend, 0)

  local file = io.open(path, "wb")
  if not file then return false end
  file:write(ffi.string(out, at))
  file:close()
  return true
end

local function create_missing_texture()
  local img = { w = 16, h = 16, data = ffi.new("uint8_t[?]", 16 * 16 * 4) }

  for y = 0, 15 do
    for x = 0, 15 do
      local idx = (y * 16 + x) * 4
      local magenta = (x < 8 and y < 8) or (x >= 8 and y >= 8)

      img.data[idx + 0] = magenta and 255 or 20
      img.data[idx + 1] = magenta and 0 or 20
      img.data[idx + 2] = magenta and 255 or 20
      img.data[idx + 3] = 255
    end
  end

  return img
end

local function copy_image(img)
  local copy = { w = img.w, h = img.h, data = ffi.new("uint8_t[?]", img.w * img.h * 4) }
  ffi.copy(copy.data, img.data, img.w * img.h * 4)
  return copy
end

local function blend_layer(dst, src, tint)
  local tintR = tint and tint[1] or 1.0
  local tintG = tint and tint[2] or 1.0
  local tintB = tint and tint[3] or 1.0
  local width = math.min(dst.w, src.w)
  local height = math.min(dst.h, src.h)

  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local idx = (y * dst.w + x) * 4
      local srcIdx = (y * src.w + x) * 4
      local alpha = src.data[srcIdx + 3] / 255
      local invAlpha = 1.0 - alpha

      dst.data[idx + 0] = math.floor(dst.data[idx + 0] * invAlpha + src.data[srcIdx + 0] * tintR * alpha + 0.5)
      dst.data[idx + 1] = math.floor(dst.data[idx + 1] * invAlpha + src.data[srcIdx + 1] * tintG * alpha + 0.5)
      dst.data[idx + 2] = math.floor(dst.data[idx + 2] * invAlpha + src.data[srcIdx + 2] * tintB * alpha + 0.5)
      dst.data[idx + 3] = math.floor((alpha + dst.data[idx + 3] / 255 * invAlpha) * 255 + 0.5)
    end
  end
end

-- Return the number of times an integer can be halved without crossing a
-- texel boundary. Atlas mipmaps are safe only while every packed rectangle
-- remains aligned to the downsample grid; beyond that point adjacent block
-- textures would be averaged together.
local function mip_alignment(value)
  if value == 0 then
    return math.huge
  end

  local levels = 0
  while value % 2 == 0 do
    value = value / 2
    levels = levels + 1
  end
  return levels
end

function M.createAtlas()
  local self = {
    w = 256,
    h = 256,
    pixels = ffi.new("uint8_t[?]", 256 * 256 * 4),
    current_x = 0,
    current_y = 0,
    row_h = 0,
    mapping = {},
    max_mip_level = math.huge
  }
  
  -- Fill with magenta (missing texture)
  for i = 0, 256*256-1 do
    self.pixels[i*4 + 0] = 255
    self.pixels[i*4 + 1] = 0
    self.pixels[i*4 + 2] = 255
    self.pixels[i*4 + 3] = 255
  end

  function self:addTexture(name, path)
    local img = load_png(path)
    if not img then
      print("Missing texture: " .. tostring(path))
      img = create_missing_texture()
    end

    return self:addImage(name, img)
  end

  function self:addLayeredTexture(name, paths, tint)
    local images = {}
    for i = 1, #paths do
      local img = load_png(paths[i])
      if not img then
        print("Missing texture: " .. tostring(paths[i]))
        img = create_missing_texture()
      end
      images[i] = img
    end

    local img = copy_image(images[#images])
    for i = #images - 1, 1, -1 do
      blend_layer(img, images[i], tint)
    end

    return self:addImage(name, img)
  end

  function self:addImage(name, img)
    local copy_w = img.w
    local copy_h = img.h
    if copy_h > copy_w and copy_w <= 64 then
      copy_h = copy_w
    end

    if self.current_x + copy_w > self.w then
      self.current_x = 0
      self.current_y = self.current_y + self.row_h
      self.row_h = 0
    end

    if self.current_y + copy_h > self.h then
      error("Texture atlas is full while adding " .. tostring(name))
    end

    for y = 0, copy_h - 1 do
      local dst_y = self.current_y + y
      for x = 0, copy_w - 1 do
        local dst_x = self.current_x + x
        local src_idx = (y * img.w + x) * 4
        local dst_idx = (dst_y * self.w + dst_x) * 4
        self.pixels[dst_idx + 0] = img.data[src_idx + 0]
        self.pixels[dst_idx + 1] = img.data[src_idx + 1]
        self.pixels[dst_idx + 2] = img.data[src_idx + 2]
        self.pixels[dst_idx + 3] = img.data[src_idx + 3]
      end
    end

    self.mapping[name] = {
      u0 = self.current_x / self.w,
      v0 = self.current_y / self.h,
      u1 = (self.current_x + copy_w) / self.w,
      v1 = (self.current_y + copy_h) / self.h
    }

    self.max_mip_level = math.min(self.max_mip_level,
      mip_alignment(self.current_x), mip_alignment(self.current_y),
      mip_alignment(copy_w), mip_alignment(copy_h))

    self.current_x = self.current_x + copy_w
    self.row_h = math.max(self.row_h, copy_h)
    
    return self.mapping[name]
  end

  function self:getMaxMipLevel()
    if self.max_mip_level == math.huge then
      return 0
    end
    return self.max_mip_level
  end

  return self
end

return M
