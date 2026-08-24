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

function noise.hash2(x, z, salt, worldSeed)
  local seed = (tonumber(worldSeed) or 1) * 101 + (tonumber(salt) or 0)
  local value = math.sin(x * 374761393 + z * 668265263 + seed * 1442695041) * 43758.5453123
  return value - math.floor(value)
end

local function valueNoise(x, z, salt, worldSeed)
  local x0 = math.floor(x)
  local z0 = math.floor(z)
  local sx = noise.smoothstep(x - x0)
  local sz = noise.smoothstep(z - z0)
  local a = noise.lerp(
    noise.hash2(x0, z0, salt, worldSeed),
    noise.hash2(x0 + 1, z0, salt, worldSeed), sx)
  local b = noise.lerp(
    noise.hash2(x0, z0 + 1, salt, worldSeed),
    noise.hash2(x0 + 1, z0 + 1, salt, worldSeed), sx)
  return noise.lerp(a, b, sz)
end

function noise.fbm(x, z, salt, octaves, frequency, worldSeed)
  local amplitude = 1.0
  local total = 0.0
  local normalizer = 0.0
  local f = frequency
  for octave = 1, octaves do
    total = total + valueNoise(x * f, z * f, salt + octave * 17, worldSeed) * amplitude
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
