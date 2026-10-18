-- Procedural per-world acoustics.
--
-- A world profile already describes the gas it is wrapped in: composition,
-- surface pressure and temperature. Those three numbers decide how a sound
-- reaches the listener, so the audio filter chain is derived from them instead
-- of being hand-authored per planet:
--
--   * acoustic impedance (density x speed of sound) sets how much energy a
--     vibrating block can radiate into the air at all -- loudness;
--   * viscous drag plus molecular relaxation set how fast the highs are eaten
--     with distance -- the low-pass corner of every voice;
--   * the speed of sound sets propagation delay;
--   * density decides how much energy a room can keep ringing -- reverb.
--
-- Earth is the calibration point, so it comes out neutral. Mars falls out of
-- the same equations as a quiet, dark world: 0.6 kPa of CO2 radiates far less,
-- its vibrational relaxation swallows everything above a few hundred Hz within
-- metres, and its caves barely ring. Any future world gets its own character
-- for free by declaring its air.
--
-- References:
--   * Maurice et al., "In situ recording of Mars soundscape" (Nature, 2022) --
--     the CO2 relaxation split near 240 Hz.
--   * ISO 9613-1, atmospheric absorption of sound -- the relaxation term shape
--     used below, alpha(f) ~ f^2 / (f^2 + fr^2).
local audioAtmosphere = {}

local GAS_CONSTANT = 8.314462618

-- molarMass kg/mol, gamma = Cp/Cv, viscosity Pa*s.
-- relaxationHzPerPa scales a species' vibrational relaxation frequency with its
-- partial pressure; relaxationNepersPerWavelength is its peak absorption per
-- wavelength. Both are calibrated so dry Earth air lands near the measured
-- 0.005 dB/m at 1 kHz and Mars near 1 dB/m at 1 kHz.
local GAS = {
  nitrogen      = {molarMass = 0.028014, gamma = 1.400, viscosity = 1.78e-5,
                   relaxationHzPerPa = 2.0e-3, relaxationNepersPerWavelength = 5.0e-4},
  oxygen        = {molarMass = 0.031998, gamma = 1.400, viscosity = 2.04e-5,
                   relaxationHzPerPa = 2.4e-1, relaxationNepersPerWavelength = 2.2e-4},
  argon         = {molarMass = 0.039948, gamma = 1.667, viscosity = 2.23e-5,
                   relaxationHzPerPa = 0.0, relaxationNepersPerWavelength = 0.0},
  carbonDioxide = {molarMass = 0.044010, gamma = 1.289, viscosity = 1.06e-5,
                   relaxationHzPerPa = 3.93e-1, relaxationNepersPerWavelength = 6.0e-2},
  waterVapor    = {molarMass = 0.018015, gamma = 1.330, viscosity = 1.00e-5,
                   relaxationHzPerPa = 1.0e-1, relaxationNepersPerWavelength = 8.0e-3},
  methane       = {molarMass = 0.016043, gamma = 1.320, viscosity = 1.10e-5,
                   relaxationHzPerPa = 2.0e-1, relaxationNepersPerWavelength = 3.0e-2},
  hydrogen      = {molarMass = 0.002016, gamma = 1.410, viscosity = 8.80e-6,
                   relaxationHzPerPa = 5.0e-2, relaxationNepersPerWavelength = 2.0e-3},
  helium        = {molarMass = 0.004003, gamma = 1.667, viscosity = 1.99e-5,
                   relaxationHzPerPa = 0.0, relaxationNepersPerWavelength = 0.0}
}

local EARTH_AIR = {nitrogen = 0.78, oxygen = 0.21, argon = 0.01}
local EARTH_PRESSURE_PA = 101325.0
local EARTH_TEMPERATURE_K = 288.15

-- A voice counts as cut where the atmosphere has taken this many nepers out of
-- it over the travel distance, which is where the derived low-pass corner sits.
local CORNER_THRESHOLD_NEPERS = 0.5
local MIN_CORNER_HZ = 90.0
local MAX_CORNER_HZ = 18000.0

-- Presentation, not physics. A literal impedance ratio drops Mars about 20 dB
-- and a thinner world into inaudibility, which is accurate and unplayable.
-- Amplitude ratios are raised to this exponent so the ordering and the
-- character survive while the levels stay usable.
local PRESENCE = 0.55

-- Radius of the radiating patch behind a block event: roughly a block face, or
-- a boot. A source only couples fully into the air above ka = 1, so its
-- radiation corner sits at c / (2*pi*a) and moves with the world's speed of
-- sound. Below that corner radiated power follows density/speed instead of
-- density*speed, which is a real per-world tilt rather than a level change.
local SOURCE_RADIUS_METERS = 0.25
-- How much of a sound the player makes themselves arrives through their own
-- legs, arms and helmet instead of through the air. That path does not care how
-- thin the atmosphere is, so it puts a floor under contact sounds. It never
-- lifts a world above Earth, where the airborne path already wins outright.
local CONTACT_CONDUCTION = 0.35

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function normalizedComposition(composition)
  local total = 0.0
  for gas, fraction in pairs(composition) do
    if GAS[gas] and fraction > 0 then total = total + fraction end
  end
  if total <= 0 then return {nitrogen = 0.78, oxygen = 0.21, argon = 0.01} end
  local result = {}
  for gas, fraction in pairs(composition) do
    if GAS[gas] and fraction > 0 then result[gas] = fraction / total end
  end
  return result
end

-- The physical medium behind one atmosphere definition. Everything the mixer
-- needs is a function of these numbers.
local function medium(definition)
  definition = definition or {}
  local composition = normalizedComposition(definition.composition or EARTH_AIR)
  -- A vacuum divides by zero on its way to silence, so floor it instead.
  local pressure = math.max(definition.surfacePressurePa or EARTH_PRESSURE_PA, 1e-3)
  local temperature = math.max(definition.surfaceTemperatureK or EARTH_TEMPERATURE_K, 1.0)

  local molarMass, gamma, viscosity = 0.0, 0.0, 0.0
  for gas, fraction in pairs(composition) do
    local properties = GAS[gas]
    molarMass = molarMass + fraction * properties.molarMass
    gamma = gamma + fraction * properties.gamma
    viscosity = viscosity + fraction * properties.viscosity
  end

  local density = pressure * molarMass / (GAS_CONSTANT * temperature)
  local speedOfSound = math.sqrt(gamma * GAS_CONSTANT * temperature / molarMass)

  local relaxers = {}
  for gas, fraction in pairs(composition) do
    local properties = GAS[gas]
    if properties.relaxationNepersPerWavelength > 0 and properties.relaxationHzPerPa > 0 then
      local frequency = properties.relaxationHzPerPa * pressure * fraction
      if frequency > 1e-3 then
        relaxers[#relaxers + 1] = {
          frequencySquared = frequency * frequency,
          -- Plateau absorption above the relaxation frequency. Absorption per
          -- wavelength peaks at f = fr, which fixes this constant.
          plateau = 2.0 * properties.relaxationNepersPerWavelength * frequency / speedOfSound
        }
      end
    end
  end

  return {
    composition = composition,
    pressurePa = pressure,
    temperatureK = temperature,
    molarMass = molarMass,
    gamma = gamma,
    viscosity = viscosity,
    density = density,
    speedOfSound = speedOfSound,
    impedance = density * speedOfSound,
    relaxers = relaxers
  }
end

audioAtmosphere.medium = medium

-- Absorption in nepers per metre. Classical (viscous) loss rises with f^2; each
-- relaxing species adds a term that rises with f^2 and saturates above its own
-- relaxation frequency. Monotonic in frequency, which the bisection below
-- relies on.
local function absorptionAt(air, frequency)
  local squared = frequency * frequency
  local total = (2.0 * math.pi * math.pi) * (4.0 / 3.0) * air.viscosity * squared /
    (air.density * air.speedOfSound ^ 3)
  for index = 1, #air.relaxers do
    local relaxer = air.relaxers[index]
    total = total + relaxer.plateau * squared / (squared + relaxer.frequencySquared)
  end
  return total
end

audioAtmosphere.absorptionAt = absorptionAt

-- The frequency the atmosphere has taken CORNER_THRESHOLD_NEPERS out of by the
-- time the sound has travelled `distance` metres.
local function cornerFrequency(air, distance)
  local target = CORNER_THRESHOLD_NEPERS / math.max(distance or 0.0, 0.35)
  if absorptionAt(air, MAX_CORNER_HZ) <= target then return MAX_CORNER_HZ end
  if absorptionAt(air, MIN_CORNER_HZ) >= target then return MIN_CORNER_HZ end
  local low, high = MIN_CORNER_HZ, MAX_CORNER_HZ
  for _ = 1, 24 do
    local middle = (low + high) * 0.5
    if absorptionAt(air, middle) < target then low = middle else high = middle end
  end
  return (low + high) * 0.5
end

-- One-pole low-pass coefficient for a corner frequency.
function audioAtmosphere.onePoleCoefficient(cutoffHz, sampleRate)
  local coefficient = 1.0 - math.exp(-2.0 * math.pi * cutoffHz / sampleRate)
  return clamp(coefficient, 1e-5, 1.0)
end

local earthMedium = medium({
  composition = EARTH_AIR,
  surfacePressurePa = EARTH_PRESSURE_PA,
  surfaceTemperatureK = EARTH_TEMPERATURE_K
})

-- The mixer-facing acoustic profile of one world. The atmosphere decides how
-- sound travels; surface gravity decides how hard the player lands on the
-- ground in the first place, so both fields of the profile are read here.
function audioAtmosphere.acoustics(worldProfile, sampleRate)
  sampleRate = sampleRate or 44100
  local air = medium(worldProfile and worldProfile.atmosphere)
  local gravityScale = math.max((worldProfile and worldProfile.gravityScale) or 1.0, 0.0)
  -- Radiated pressure amplitude scales with the square root of the impedance
  -- the source is loading into.
  local amplitudeRatio = math.sqrt(air.impedance / earthMedium.impedance)

  -- Radiation shelf. Above ka = 1 a source radiates with the impedance the dry
  -- gain already carries; below it, power follows density/speed, so a slow
  -- world gets relatively more bass out of the same struck block and a fast one
  -- less. Expressed against Earth, so Earth's shelf is exactly flat.
  local earthCorner = earthMedium.speedOfSound / (2.0 * math.pi * SOURCE_RADIUS_METERS)
  local worldCorner = air.speedOfSound / (2.0 * math.pi * SOURCE_RADIUS_METERS)
  local shelfGain = clamp((earthMedium.speedOfSound / air.speedOfSound) ^ 2 - 1.0, -0.95, 8.0)

  return {
    id = worldProfile and worldProfile.id or "earth",
    name = worldProfile and worldProfile.name or "Earth",
    air = air,
    sampleRate = sampleRate,
    densityKgPerM3 = air.density,
    speedOfSound = air.speedOfSound,
    impedance = air.impedance,
    -- Dry level of every voice.
    gain = amplitudeRatio ^ PRESENCE,
    -- Thin air both radiates and stores less, so its rooms stop ringing.
    reverbScale = clamp(amplitudeRatio ^ 0.75, 0.0, 1.0),
    -- Corner of the tone filter for a source right next to the listener.
    nearCornerHz = cornerFrequency(air, 1.0),
    -- Source-side radiation shelf, flat on Earth by construction.
    radiationShelfGain = shelfGain,
    radiationShelfHz = math.sqrt(earthCorner * worldCorner),
    radiationShelfCoefficient = audioAtmosphere.onePoleCoefficient(
      math.sqrt(earthCorner * worldCorner), sampleRate),
    -- A footfall carries the player's weight into the ground, so contact energy
    -- scales with surface gravity, under the same presentation compression.
    contactScale = gravityScale ^ PRESENCE
  }
end

-- Level of an event that reaches the player partly through their own body.
-- `conduction` is how much of it does, from 0 for something happening across
-- the valley to 1 for a boot hitting the ground underneath them. The body path
-- is a floor rather than an addition, so a world can never come out louder than
-- its air alone would make it.
function audioAtmosphere.contactGain(acoustics, conduction)
  local body = clamp(conduction or 0.0, 0.0, 1.0) * CONTACT_CONDUCTION
  return math.max(acoustics.gain, body)
end

-- Per-voice low-pass coefficient for a source `distance` metres away.
function audioAtmosphere.toneCoefficient(acoustics, distance)
  return audioAtmosphere.onePoleCoefficient(
    cornerFrequency(acoustics.air, distance), acoustics.sampleRate)
end

function audioAtmosphere.cornerAt(acoustics, distance)
  return cornerFrequency(acoustics.air, distance)
end

-- World profiles are configuration and never mutate, so one acoustic profile
-- per world id is computed once and shared.
local cache = {}

function audioAtmosphere.forProfile(worldProfile, sampleRate)
  sampleRate = sampleRate or 44100
  local key = string.format("%s@%d", worldProfile and worldProfile.id or "earth", sampleRate)
  local cached = cache[key]
  if not cached then
    cached = audioAtmosphere.acoustics(worldProfile, sampleRate)
    cache[key] = cached
  end
  return cached
end

return audioAtmosphere
