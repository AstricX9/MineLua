-- Perlin-Worley volume textures for the volumetric cloud march.
--
-- Two volumes, following the Nubis/Horizon layout:
--   base   64^3 RGBA - R is Perlin-Worley (overall shape), GBA are Worley at
--                      rising frequencies (used to erode the shape)
--   detail 32^3 RGB  - Worley at rising frequencies, erodes the wispy edges
--
-- Both tile, so the march can sample them at any world position without seams.
-- Generation takes a couple of seconds, so the result is cached on disk and
-- only rebuilt when CACHE_VERSION changes.

local ffi = require("ffi")
local bit = require("bit")

local M = {}

local BASE_SIZE = 64
local DETAIL_SIZE = 32
local CACHE_PATH = "data/cloud_noise.bin"
local CACHE_VERSION = 2

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local band, bxor, rshift, tobit = bit.band, bit.bxor, bit.rshift, bit.tobit

local function clamp01(v)
  return v < 0.0 and 0.0 or (v > 1.0 and 1.0 or v)
end

-- Integer bit-mix. Deliberately not sin-based: sin hashing is both slower and
-- poorly distributed at large arguments.
local function hash3(x, y, z, seed)
  local h = tobit(x * 73856093)
  h = bxor(h, tobit(y * 19349663))
  h = bxor(h, tobit(z * 83492791))
  h = bxor(h, tobit(seed * 2654435761))
  h = tobit(bxor(h, rshift(h, 15)) * 2246822519)
  h = tobit(bxor(h, rshift(h, 13)) * 3266489917)
  h = bxor(h, rshift(h, 16))
  return band(h, 0x7fffffff) / 2147483647
end

-- Distance to the nearest feature point, one point per cell, wrapped so the
-- result tiles at `cells`.
local function worley(px, py, pz, cells)
  local ix, iy, iz = floor(px), floor(py), floor(pz)
  local best = 1e9

  for dz = -1, 1 do
    local cz = iz + dz
    local wz = cz % cells
    for dy = -1, 1 do
      local cy = iy + dy
      local wy = cy % cells
      for dx = -1, 1 do
        local cx = ix + dx
        local wx = cx % cells

        local fx = cx + hash3(wx, wy, wz, 17)
        local fy = cy + hash3(wx, wy, wz, 31)
        local fz = cz + hash3(wx, wy, wz, 47)

        local ox, oy, oz = fx - px, fy - py, fz - pz
        local d = ox * ox + oy * oy + oz * oz
        if d < best then best = d end
      end
    end
  end

  return sqrt(best)
end

-- Inverted and clamped: 1 at a feature point, falling to 0 between them, which
-- is the billowy shape clouds want.
local function worleyFbm(px, py, pz, cells)
  local a = 1.0 - min(worley(px, py, pz, cells), 1.0)
  local b = 1.0 - min(worley(px * 2.0, py * 2.0, pz * 2.0, cells * 2), 1.0)
  local c = 1.0 - min(worley(px * 4.0, py * 4.0, pz * 4.0, cells * 4), 1.0)
  return a * 0.625 + b * 0.25 + c * 0.125
end

local function smootherstep(t)
  return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
end

-- Tileable value noise; stands in for Perlin here, which is adequate once it is
-- remapped against Worley.
local function valueNoise(px, py, pz, cells)
  local ix, iy, iz = floor(px), floor(py), floor(pz)
  local fx, fy, fz = smootherstep(px - ix), smootherstep(py - iy), smootherstep(pz - iz)

  local x0, y0, z0 = ix % cells, iy % cells, iz % cells
  local x1, y1, z1 = (ix + 1) % cells, (iy + 1) % cells, (iz + 1) % cells

  local c000 = hash3(x0, y0, z0, 7)
  local c100 = hash3(x1, y0, z0, 7)
  local c010 = hash3(x0, y1, z0, 7)
  local c110 = hash3(x1, y1, z0, 7)
  local c001 = hash3(x0, y0, z1, 7)
  local c101 = hash3(x1, y0, z1, 7)
  local c011 = hash3(x0, y1, z1, 7)
  local c111 = hash3(x1, y1, z1, 7)

  local x00 = c000 + (c100 - c000) * fx
  local x10 = c010 + (c110 - c010) * fx
  local x01 = c001 + (c101 - c001) * fx
  local x11 = c011 + (c111 - c011) * fx
  local y0v = x00 + (x10 - x00) * fy
  local y1v = x01 + (x11 - x01) * fy
  return y0v + (y1v - y0v) * fz
end

-- Averaging octaves concentrates the result near 0.5 -- measured stddev was
-- 0.09 against the ~0.29 a full-range field would have, which left the
-- Perlin-Worley remap below spanning only 0.61..0.72 and gave the density field
-- almost nothing to carve with. Expanding around the midpoint restores it.
local PERLIN_SPREAD = 2.6

local function perlinFbm(px, py, pz, cells)
  local total = valueNoise(px, py, pz, cells) * 0.5
  total = total + valueNoise(px * 2.0, py * 2.0, pz * 2.0, cells * 2) * 0.25
  total = total + valueNoise(px * 4.0, py * 4.0, pz * 4.0, cells * 4) * 0.125
  total = total + valueNoise(px * 8.0, py * 8.0, pz * 8.0, cells * 8) * 0.0625
  total = total / 0.9375
  return clamp01(0.5 + (total - 0.5) * PERLIN_SPREAD)
end

local function remap(value, oldMin, oldMax, newMin, newMax)
  return newMin + (value - oldMin) / math.max(oldMax - oldMin, 1e-6) * (newMax - newMin)
end

local function generateBase()
  local size = BASE_SIZE
  local data = ffi.new("uint8_t[?]", size * size * size * 4)

  for z = 0, size - 1 do
    for y = 0, size - 1 do
      for x = 0, size - 1 do
        local u = x / size
        local v = y / size
        local w = z / size

        local perlin = perlinFbm(u * 4.0, v * 4.0, w * 4.0, 4)
        local worleyLow = worleyFbm(u * 4.0, v * 4.0, w * 4.0, 4)

        -- Perlin-Worley: the Perlin field remapped into the Worley field, which
        -- keeps the connected wispiness of Perlin but with billowy edges.
        local perlinWorley = clamp01(remap(perlin, worleyLow - 1.0, 1.0, 0.0, 1.0))

        local index = ((z * size + y) * size + x) * 4
        data[index + 0] = floor(perlinWorley * 255.0 + 0.5)
        data[index + 1] = floor(clamp01(worleyFbm(u * 8.0, v * 8.0, w * 8.0, 8)) * 255.0 + 0.5)
        data[index + 2] = floor(clamp01(worleyFbm(u * 16.0, v * 16.0, w * 16.0, 16)) * 255.0 + 0.5)
        data[index + 3] = floor(clamp01(worleyFbm(u * 32.0, v * 32.0, w * 32.0, 32)) * 255.0 + 0.5)
      end
    end
  end

  return data, size * size * size * 4
end

local function generateDetail()
  local size = DETAIL_SIZE
  local data = ffi.new("uint8_t[?]", size * size * size * 3)

  for z = 0, size - 1 do
    for y = 0, size - 1 do
      for x = 0, size - 1 do
        local u, v, w = x / size, y / size, z / size
        local index = ((z * size + y) * size + x) * 3
        data[index + 0] = floor(clamp01(worleyFbm(u * 4.0, v * 4.0, w * 4.0, 4)) * 255.0 + 0.5)
        data[index + 1] = floor(clamp01(worleyFbm(u * 8.0, v * 8.0, w * 8.0, 8)) * 255.0 + 0.5)
        data[index + 2] = floor(clamp01(worleyFbm(u * 16.0, v * 16.0, w * 16.0, 16)) * 255.0 + 0.5)
      end
    end
  end

  return data, size * size * size * 3
end

local function readCache(baseBytes, detailBytes)
  local file = io.open(CACHE_PATH, "rb")
  if not file then
    return nil
  end

  local header = file:read(8)
  if not header or #header < 8 then
    file:close()
    return nil
  end

  local version, baseSize, detailSize = header:byte(1), header:byte(2), header:byte(3)
  if version ~= CACHE_VERSION or baseSize ~= BASE_SIZE or detailSize ~= DETAIL_SIZE then
    file:close()
    return nil
  end

  local baseData = file:read(baseBytes)
  local detailData = file:read(detailBytes)
  file:close()

  if not baseData or #baseData ~= baseBytes or not detailData or #detailData ~= detailBytes then
    return nil
  end

  local base = ffi.new("uint8_t[?]", baseBytes)
  local detail = ffi.new("uint8_t[?]", detailBytes)
  ffi.copy(base, baseData, baseBytes)
  ffi.copy(detail, detailData, detailBytes)
  return base, detail
end

local function writeCache(base, baseBytes, detail, detailBytes)
  local file = io.open(CACHE_PATH, "wb")
  if not file then
    return
  end

  file:write(string.char(CACHE_VERSION, BASE_SIZE, DETAIL_SIZE, 0, 0, 0, 0, 0))
  file:write(ffi.string(base, baseBytes))
  file:write(ffi.string(detail, detailBytes))
  file:close()
end

-- Returns the two volumes, generating and caching them on first run.
function M.build()
  local baseBytes = BASE_SIZE * BASE_SIZE * BASE_SIZE * 4
  local detailBytes = DETAIL_SIZE * DETAIL_SIZE * DETAIL_SIZE * 3

  local base, detail = readCache(baseBytes, detailBytes)
  if base then
    return {
      base = base, baseSize = BASE_SIZE,
      detail = detail, detailSize = DETAIL_SIZE,
      cached = true
    }
  end

  base = generateBase()
  detail = generateDetail()
  writeCache(base, baseBytes, detail, detailBytes)

  return {
    base = base, baseSize = BASE_SIZE,
    detail = detail, detailSize = DETAIL_SIZE,
    cached = false
  }
end

M.BASE_SIZE = BASE_SIZE
M.DETAIL_SIZE = DETAIL_SIZE

return M
