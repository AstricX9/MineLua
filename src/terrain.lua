local blocks = require("blocks")

local terrain = {}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function smoothstep(t)
  return t * t * (3 - 2 * t)
end

local function hash2(x, z, seed)
  local n = x * 374761393 + z * 668265263 + seed * 1442695041
  n = math.sin(n) * 43758.5453123
  return n - math.floor(n)
end

local function valueNoise(x, z, seed)
  local x0 = math.floor(x)
  local z0 = math.floor(z)
  local x1 = x0 + 1
  local z1 = z0 + 1

  local sx = smoothstep(x - x0)
  local sz = smoothstep(z - z0)

  local n00 = hash2(x0, z0, seed)
  local n10 = hash2(x1, z0, seed)
  local n01 = hash2(x0, z1, seed)
  local n11 = hash2(x1, z1, seed)

  local ix0 = n00 + (n10 - n00) * sx
  local ix1 = n01 + (n11 - n01) * sx
  return ix0 + (ix1 - ix0) * sz
end

local function fbm(x, z)
  local total = 0
  local amplitude = 1
  local frequency = 0.05
  local normalization = 0

  for octave = 1, 4 do
    total = total + valueNoise(x * frequency, z * frequency, octave * 19) * amplitude
    normalization = normalization + amplitude
    amplitude = amplitude * 0.5
    frequency = frequency * 2.0
  end

  return total / normalization
end

function terrain.heightAt(x, z, maxHeight)
  local baseHeight = math.floor(maxHeight * 0.35)
  local hillHeight = math.max(2, math.floor(maxHeight * 0.55))
  local ridgeHeight = math.max(1, math.floor(maxHeight * 0.18))

  local hills = fbm(x, z)
  local ridges = fbm(x * 1.8 + 100.0, z * 1.8 + 100.0)
  local height = baseHeight + hills * hillHeight + ridges * ridgeHeight

  return clamp(math.floor(height), 1, maxHeight)
end

function terrain.fillChunk(chunk, offsetX, offsetZ, width, depth, maxHeight)
  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local height = terrain.heightAt(x + offsetX, z + offsetZ, maxHeight)

      for y = 0, height do
        if y == height then
          chunk:setBlock(x, y, z, blocks.grass)
        elseif y >= height - 3 then
          chunk:setBlock(x, y, z, blocks.dirt)
        else
          chunk:setBlock(x, y, z, blocks.stone)
        end
      end
    end
  end
end

return terrain
