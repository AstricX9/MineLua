package.path = "src/?.lua;src/?/init.lua;" .. package.path

local ffi = require("ffi")
local audioAtmosphere = require("audio_atmosphere")
local AudioEngine = require("audio_engine")
local worldProfiles = require("world_profiles")

local earth = audioAtmosphere.forProfile(worldProfiles.get("earth"))
local mars = audioAtmosphere.forProfile(worldProfiles.get("mars"))

-- Earth is the calibration point of the model, so it has to come out neutral.
assert(math.abs(earth.gain - 1.0) < 1e-6 and math.abs(earth.reverbScale - 1.0) < 1e-6,
  "Earth air leaves loudness and reverb untouched")
assert(math.abs(earth.densityKgPerM3 - 1.225) < 0.01,
  "sea-level air density falls out of pressure, temperature and composition")
assert(math.abs(earth.speedOfSound - 340.3) < 3.0,
  "the speed of sound in sea-level air falls out of the same numbers")

-- Measured dry-air absorption is about 0.005 dB/m at 1 kHz and 0.025 dB/m at
-- 4 kHz; the derived model has to stay in that neighbourhood or every other
-- world is calibrated against nothing.
local function decibelsPerMeter(acoustics, frequency)
  return audioAtmosphere.absorptionAt(acoustics.air, frequency) * 8.685889
end
assert(decibelsPerMeter(earth, 1000) < 0.02 and decibelsPerMeter(earth, 4000) < 0.06,
  "Earth air is effectively transparent over voxel distances")
assert(audioAtmosphere.cornerAt(earth, 32.0) > 15000.0,
  "Earth keeps its top end across the whole audible range of a block sound")

-- Mars: 0.6 kPa of cold CO2. Quiet, dead rooms, and a hard relaxation knee that
-- eats the highs within metres.
assert(math.abs(mars.densityKgPerM3 - 0.0152) < 0.002, "Martian air density is derived")
assert(math.abs(mars.speedOfSound - 228.0) < 6.0, "sound travels slower in cold CO2")
assert(mars.gain < 0.5 and mars.gain > 0.1,
  "the impedance drop makes Mars audibly quieter without silencing it")
assert(mars.reverbScale < 0.3, "thin air cannot sustain a cave tail")
assert(decibelsPerMeter(mars, 1000) > 20.0 * decibelsPerMeter(earth, 1000),
  "CO2 relaxation absorbs orders of magnitude more than air at 1 kHz")
assert(decibelsPerMeter(mars, 100) * 4.0 < decibelsPerMeter(mars, 1000),
  "the Martian knee spares low frequencies and eats high ones")

-- Absorption is monotonic in frequency and the corner is monotonic in distance;
-- the bisection in the module depends on the first, the mixer on the second.
local previousAbsorption = -1.0
for frequency = 50, 16000, 250 do
  local value = audioAtmosphere.absorptionAt(mars.air, frequency)
  assert(value > previousAbsorption, "absorption rises with frequency")
  previousAbsorption = value
end
local previousCorner = math.huge
for distance = 1, 48 do
  local corner = audioAtmosphere.cornerAt(mars, distance)
  assert(corner <= previousCorner, "the tone corner falls as sound travels further")
  previousCorner = corner
end
assert(audioAtmosphere.cornerAt(mars, 1.0) > 4000.0,
  "a Martian sound at arm's length is still bright")
assert(audioAtmosphere.cornerAt(mars, 16.0) < 600.0,
  "the same sound sixteen metres away arrives muffled")

-- Worlds that declare nothing inherit Earth's air rather than dividing by zero,
-- and an exotic atmosphere stays finite.
local neutral = audioAtmosphere.acoustics({id = "unspecified"})
assert(math.abs(neutral.gain - 1.0) < 1e-6, "an undeclared atmosphere falls back to Earth air")
local thin = audioAtmosphere.acoustics({
  id = "exotic",
  atmosphere = {surfacePressurePa = 0.0, surfaceTemperatureK = 40.0,
    composition = {helium = 1.0}}
})
assert(thin.gain == thin.gain and thin.gain >= 0.0 and thin.gain < 0.05,
  "a near-vacuum world goes quiet without producing NaN")
assert(audioAtmosphere.cornerAt(thin, 8.0) > 0.0, "the corner stays a real frequency")

-- End to end through the mixer: the same block break, in two atmospheres.
-- Brightness is the RMS of the sample-to-sample slope over the RMS of the
-- signal, so it measures tone independently of level.
local function render(worldId, distance)
  local engine = AudioEngine.new({disabled = true, loadAssets = false,
    worldProfile = worldProfiles.get(worldId)})
  -- Voices pick their own pitch and noise seed, so pin them for comparability.
  math.randomseed(4242)
  if distance then engine:play("stone", "break", {distance, 0, 0}, 1.0) end
  local samples = ffi.new("int16_t[?]", 512 * 2)
  local energy, slope, previous, peak = 0.0, 0.0, 0.0, 0
  for _ = 1, 32 do
    engine:mixBuffer(samples)
    for index = 0, 512 * 2 - 1, 2 do
      local value = samples[index]
      peak = math.max(peak, math.abs(value))
      energy = energy + value * value
      slope = slope + (value - previous) * (value - previous)
      previous = value
    end
  end
  return peak, math.sqrt(energy / (32 * 512)), math.sqrt(slope / math.max(energy, 1e-9))
end

local closeEarthPeak, closeEarthLevel, closeEarthTone = render("earth", 1.0)
local farEarthPeak, farEarthLevel, farEarthTone = render("earth", 16.0)
local closeMarsPeak, closeMarsLevel, closeMarsTone = render("mars", 1.0)
local farMarsPeak, farMarsLevel, farMarsTone = render("mars", 16.0)

assert(closeEarthPeak > 100 and closeMarsPeak > 100 and farMarsPeak > 10,
  "every combination still produces audible PCM")
assert(math.abs(farEarthTone - closeEarthTone) < 0.05 * closeEarthTone,
  "Earth air does not colour a block break over sixteen metres")
assert(math.abs(closeMarsLevel / closeEarthLevel - mars.gain) < 0.05,
  "up close, a block break differs from Earth by the impedance gain")
assert(math.abs(closeMarsTone - closeEarthTone) < 0.1 * closeEarthTone,
  "and by nothing else: an arm's length of CO2 barely filters")
assert(farMarsTone < 0.4 * closeMarsTone,
  "the same break sixteen metres away is dramatically darker on Mars")
assert(farMarsLevel / farEarthLevel < 0.25 * (closeMarsLevel / closeEarthLevel),
  "distance costs a Martian sound far more than a terrestrial one")

-- Ambient OGGs stay in the asset pack for future authored ambience, but the
-- current mixer neither synthesizes nor schedules an idle world bed.
local silent = select(2, render("earth", nil))
assert(silent < 1.0, "an idle world has no ambient noise")

-- The source side: what a block sounds like before the trip to the listener.
-- Earth has to be neutral in every one of these terms or it stops being the
-- calibration point.
assert(earth.contactScale == 1.0 and earth.radiationShelfGain == 0.0,
  "Earth weighs and radiates exactly as the unmodified engine did")
for _, conduction in ipairs({0.0, 0.15, 0.85, 1.0}) do
  assert(audioAtmosphere.contactGain(earth, conduction) == 1.0,
    "on Earth the airborne path already wins, so the body path never lifts it")
end

-- Weight: a footfall is the player's mass arriving on the ground.
assert(mars.contactScale < 0.7 and mars.contactScale > 0.4,
  "Martian gravity lands the player on the ground more softly")

-- Conduction: a player's own footsteps still reach them through their legs, so
-- thin air cannot mute them the way it mutes something across the valley.
assert(audioAtmosphere.contactGain(mars, 1.0) > mars.gain,
  "a Martian footstep is floored by the body path")
assert(audioAtmosphere.contactGain(mars, 1.0) > audioAtmosphere.contactGain(mars, 0.15),
  "a block coming apart nearby has no such floor")
assert(audioAtmosphere.contactGain(mars, 0.15) == mars.gain,
  "and falls back to what the air alone carries")

-- Radiation: below ka = 1 a source couples into the air by density over speed
-- rather than density times speed, and that corner moves with the world's speed
-- of sound. Slow air favours the low end, so a low-pitched material keeps more
-- of its level on Mars than a high-pitched one does.
assert(mars.radiationShelfGain > 0.5,
  "slower Martian air lets a block face radiate its low end relatively better")
local function materialRatio(material)
  local function level(worldId)
    local engine = AudioEngine.new({disabled = true, loadAssets = false,
      worldProfile = worldProfiles.get(worldId)})
    math.randomseed(99)
    engine:play(material, "break", {0.5, 0, 0}, 1.0)
    local samples = ffi.new("int16_t[?]", 512 * 2)
    local energy = 0.0
    for _ = 1, 32 do
      engine:mixBuffer(samples)
      for index = 0, 512 * 2 - 1, 2 do energy = energy + samples[index] * samples[index] end
    end
    return math.sqrt(energy / (32 * 512))
  end
  return level("mars") / level("earth")
end
assert(materialRatio("wood") > 1.3 * materialRatio("glass"),
  "a 185 Hz wood break survives Mars far better than a 2.3 kHz glass one")

-- Mars is mostly sandstone, which is rock: it should not walk like loose sand.
assert(AudioEngine.soundMaterial({key = "red_sandstone"}) == "stone" and
  AudioEngine.soundMaterial({key = "red_sand"}) == "sand",
  "sandstone is stone underfoot and sand is not")

-- A running mixer follows the player between worlds.
local engine = AudioEngine.new({disabled = true, loadAssets = false})
assert(engine.acoustics.id == "earth", "the mixer starts in Earth air")
engine:update(0.016, nil, {worldProfile = worldProfiles.get("mars")}, 100)
assert(engine.acoustics.id == "mars", "loading a world re-tunes the filter chain")
engine:play("stone", "break", {8, 0, 0}, 1.0)
assert(engine.voices[1].start > engine.mixTime,
  "distant sources arrive late, at the speed of sound in that world's air")

print("audio atmosphere tests passed")
