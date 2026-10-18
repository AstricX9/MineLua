package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")
local AudioEngine = require("audio_engine")

assert(AudioEngine.soundMaterial({key = "oak_log", properties = {solid = true}}) == "wood")
assert(AudioEngine.soundMaterial({key = "red_sand", properties = {solid = true}}) == "sand")
assert(AudioEngine.soundMaterial({key = "glass", properties = {glass = true}}) == "glass")
assert(AudioEngine.soundMaterial({key = "red_wool", properties = {solid = true}}) == "cloth")

local stoneSample = assert(AudioEngine.loadWave("assets/sounds/runtime/break_stone_1.wav"),
  "the converted runtime SFX bank is present")
assert(stoneSample.sampleRate > 0 and stoneSample.frames > 100 and stoneSample.channels == 1,
  "runtime WAV metadata is decoded")
local treeFallSample = assert(AudioEngine.loadWave(
  "assets/sounds/ambient/sfx/tree_fall_sfx.wav"), "the authored tree-fall SFX is present")
assert(treeFallSample.sampleRate == 48000 and treeFallSample.channels == 2 and
    treeFallSample.frames > treeFallSample.sampleRate,
  "the authored stereo tree-fall WAV is decoded")

local openWorld = {}
function openWorld:skyLightAt() return 15 end
function openWorld:blockAt() return 0 end

local caveWorld = {}
function caveWorld:skyLightAt() return 0 end
function caveWorld:blockAt() return 1 end

local position = {8, 20, 8}
assert(AudioEngine.enclosureAt(openWorld, position) < 0.05,
  "open daylight has no cave response")
assert(AudioEngine.enclosureAt(caveWorld, position) > 0.90,
  "dark enclosed voxels produce a strong cave response")

local engine = AudioEngine.new({disabled = true, loadAssets = false})
engine:play("stone", "break", position)
local samples = ffi.new("int16_t[?]", 512 * 2)
local peak = 0
for _ = 1, 12 do
  engine:mixBuffer(samples)
  for index = 0, 512 * 2 - 1 do peak = math.max(peak, math.abs(samples[index])) end
end
assert(peak > 100, "the software mixer produces audible PCM for block events")

local sampledEngine = AudioEngine.new({disabled = true})
sampledEngine:play("wood", "break", position)
assert(sampledEngine.voices[1].sample, "block events choose a real sample from the runtime bank")
assert(sampledEngine:playTreeFall(position) and
    sampledEngine.voices[2].sample == sampledEngine.treeFallSample and
    sampledEngine.voices[2].pitch == 1.0,
  "tree crashes use the authored tree-fall WAV without random pitch")
local shortFallPitch=AudioEngine.treeFallPitch(2.0)
local tallFallPitch=AudioEngine.treeFallPitch(4.0)
assert(math.abs(shortFallPitch-4.3)<0.00001 and
    math.abs(tallFallPitch-2.15)<0.00001 and shortFallPitch>tallFallPitch,
  "short trees accelerate the SFX more so its crash meets their earlier impact")
local sampled = ffi.new("int16_t[?]", 512 * 2)
local sampledPeak = 0
for _ = 1, 12 do
  sampledEngine:mixBuffer(sampled)
  for index = 0, 512 * 2 - 1 do sampledPeak = math.max(sampledPeak, math.abs(sampled[index])) end
end
assert(sampledPeak > 100, "sample-backed block events produce audible PCM")

local reverb = AudioEngine.createReverb()
local wetFrames, wetPeak = 0, 0
for frame = 1, 9000 do
  local input = frame == 1 and 1.0 or 0.0
  local left, right = AudioEngine.processReverb(reverb, input, input, 1.0)
  local magnitude = math.max(math.abs(left), math.abs(right))
  if magnitude > 1e-7 then wetFrames = wetFrames + 1 end
  wetPeak = math.max(wetPeak, magnitude)
end
assert(wetPeak > 0.01 and wetFrames > 2000,
  "cave acoustics produce a dense decaying reverb tail instead of discrete echoes")

print("audio engine tests passed")
