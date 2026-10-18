-- Deterministic world-space noise primitives shared by every generation stage.
-- Keeping seed derivation and interpolation here prevents geology, climate and
-- hydrology from quietly developing incompatible coordinate systems.
local noise = {}

function noise.clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

function noise.lerp(a, b, t)
  return a + (b - a) * noise.clamp(t, 0.0, 1.0)
end

function noise.smoothstep(t)
  t = noise.clamp(t, 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)
end

function noise.edge(value, low, high)
  if low == high then return value >= high and 1.0 or 0.0 end
  return noise.smoothstep((value - low) / (high - low))
end

function noise.ridged(value)
  return 1.0 - math.abs(value * 2.0 - 1.0)
end

-- fbm is the innermost loop of world generation: every field, ridge chain and
-- warp goes through it, hundreds of thousands of times per chunk, so everything
-- it touches is hoisted into locals here.
local floor = math.floor
local bit = require("bit")
local band, bxor, lshift, rshift, tobit = bit.band, bit.bxor, bit.lshift, bit.rshift, bit.tobit

local INV32 = 1.0 / 4294967296.0

-- Low 32 bits of a 32x32 multiply. Doing it directly would produce a product
-- above 2^53, where a double no longer holds the low bits that matter; the
-- 16-bit split keeps every intermediate exact.
local function imul(a, b)
  local low = band(a, 0xffff)
  return tobit(low * b + lshift(rshift(a, 16) * b, 16))
end

-- Integer avalanche, the xxHash finaliser.
--
-- This replaces fract(sin(n) * 43758.5) -- the GLSL hashing trick, which on a
-- CPU is a libm call with full argument reduction on every lattice corner:
-- about 85 ns against 9 ns here. It was also losing precision as its argument
-- grew, so the noise degraded the further a world ran from the origin. This is
-- uniform everywhere: over a quarter of a million samples the worst sixteenth
-- of the range is within 2% of even.
local function mix32(n)
  n = bxor(n, rshift(n, 16))
  n = imul(n, 2246822519)
  n = bxor(n, rshift(n, 13))
  n = imul(n, 3266489917)
  n = bxor(n, rshift(n, 16))
  return (n % 4294967296) * INV32
end

noise.imul = imul
noise.mix32 = mix32

-- Folds a seed and salt into the 32-bit key the corner hashes add in. Callers
-- that sample a lattice hoist this out of their corner loop.
function noise.seedKey(salt, worldSeed)
  return imul(tobit((tonumber(worldSeed) or 1) * 101 + (tonumber(salt) or 0)), 1442695041)
end

local function rawHash2(x, z, seedKey)
  return mix32(tobit(tobit(x * 374761393) + tobit(z * 668265263) + seedKey))
end

function noise.hash2(x, z, salt, worldSeed)
  return rawHash2(x, z, noise.seedKey(salt, worldSeed))
end

local function valueNoise(x, z, seed)
  local x0 = floor(x)
  local z0 = floor(z)
  local x1, z1 = x0 + 1, z0 + 1

  local tx = x - x0
  if tx < 0.0 then tx = 0.0 elseif tx > 1.0 then tx = 1.0 end
  local sx = tx * tx * (3.0 - 2.0 * tx)
  local tz = z - z0
  if tz < 0.0 then tz = 0.0 elseif tz > 1.0 then tz = 1.0 end
  local sz = tz * tz * (3.0 - 2.0 * tz)

  local n00 = rawHash2(x0, z0, seed)
  local n10 = rawHash2(x1, z0, seed)
  local n01 = rawHash2(x0, z1, seed)
  local n11 = rawHash2(x1, z1, seed)

  local a = n00 + (n10 - n00) * sx
  local b = n01 + (n11 - n01) * sx
  return a + (b - a) * sz
end

function noise.fbm(x, z, salt, octaves, frequency, worldSeed)
  local amplitude = 1.0
  local total = 0.0
  local normalizer = 0.0
  local f = frequency
  local seedBase = (tonumber(worldSeed) or 1) * 101 + (tonumber(salt) or 0)
  for octave = 1, octaves do
    total = total + valueNoise(x * f, z * f,
      imul(tobit(seedBase + octave * 17), 1442695041)) * amplitude
    normalizer = normalizer + amplitude
    amplitude = amplitude * 0.5
    f = f * 2.0
  end
  return normalizer > 0.0 and total / normalizer or 0.5
end

function noise.rotated(x, z, angle)
  local c, s = math.cos(angle), math.sin(angle)
  return x * c + z * s, -x * s + z * c
end

function noise.ridgeChain(x, z, salt, frequency, angle, stretch, worldSeed)
  local rx, rz = noise.rotated(x, z, angle)
  return noise.ridged(noise.fbm(rx, rz * stretch, salt, 5, frequency, worldSeed))
end

function noise.warp2(x, z, frequency, amount, salt, worldSeed)
  local dx = (noise.fbm(x + 9100.0, z - 4100.0, salt, 3, frequency, worldSeed) - 0.5) * amount
  local dz = (noise.fbm(x - 2800.0, z + 7600.0, salt + 6, 3, frequency, worldSeed) - 0.5) * amount
  return x + dx, z + dz, dx, dz
end

function noise.distanceToSegment(px, pz, ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  local lengthSquared = dx * dx + dz * dz
  if lengthSquared <= 0.000001 then
    dx, dz = px - ax, pz - az
    return math.sqrt(dx * dx + dz * dz), 0.0
  end
  local t = noise.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSquared, 0.0, 1.0)
  local qx, qz = ax + dx * t, az + dz * t
  dx, dz = px - qx, pz - qz
  return math.sqrt(dx * dx + dz * dz), t
end

return noise
