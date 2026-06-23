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
