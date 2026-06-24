local ffi = require("ffi")

local M = {}

-- STB Image loader via FFI
ffi.cdef[[
  unsigned char *stbi_load(char const *filename, int *x, int *y, int *channels_in_file, int desired_channels);
  void stbi_image_free(void *retval_from_stbi_load);
]]

local stbi = ffi.load("lib/stb_image.dll")

local function load_png(path)
  local w = ffi.new("int[1]")
  local h = ffi.new("int[1]")
  local channels = ffi.new("int[1]")
  
  -- Force 4 channels (RGBA)
  local data = stbi.stbi_load(path, w, h, channels, 4)
  if data == nil then return nil end

  local width = w[0]
  local height = h[0]
  local rgba = ffi.new("uint8_t[?]", width * height * 4)
  
  -- Copy the data and free the STB memory
  ffi.copy(rgba, data, width * height * 4)
  stbi.stbi_image_free(data)

  return { w = width, h = height, data = rgba }
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

function M.createAtlas()
  local self = {
    w = 256,
    h = 256,
    pixels = ffi.new("uint8_t[?]", 256 * 256 * 4),
    current_x = 0,
    current_y = 0,
    row_h = 16,
    mapping = {}
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

    if self.current_x + img.w > self.w then
      self.current_x = 0
      self.current_y = self.current_y + self.row_h
    end

    for y = 0, img.h - 1 do
      local dst_y = self.current_y + y
      for x = 0, img.w - 1 do
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
      u1 = (self.current_x + img.w) / self.w,
      v1 = (self.current_y + img.h) / self.h
    }

    self.current_x = self.current_x + img.w
    
    return self.mapping[name]
  end

  return self
end

return M
