local ffi = require("ffi")
local audioAtmosphere = require("audio_atmosphere")

local AudioEngine = {}
AudioEngine.__index = AudioEngine

local SAMPLE_RATE = 44100
local FRAMES_PER_BUFFER = 512
local BUFFER_COUNT = 4
-- The authored tree-fall recording's main ground strike. Playback is resampled
-- so this point, rather than the quiet tail at the end of the file, meets the
-- animated trunk's first-contact frame.
AudioEngine.TREE_FALL_IMPACT_SECONDS = 8.60
local WHDR_DONE = 0x00000001
local WAVE_MAPPER = 0xffffffff

if ffi.os == "Windows" then
  ffi.cdef[[
    typedef unsigned short WORD;
    typedef unsigned int UINT;
    typedef unsigned long DWORD;
    typedef unsigned long long DWORD_PTR;
    typedef void* HWAVEOUT;
    typedef struct {
      WORD wFormatTag; WORD nChannels; DWORD nSamplesPerSec;
      DWORD nAvgBytesPerSec; WORD nBlockAlign; WORD wBitsPerSample; WORD cbSize;
    } WAVEFORMATEX;
    typedef struct wavehdr_tag {
      char* lpData; DWORD dwBufferLength; DWORD dwBytesRecorded;
      DWORD_PTR dwUser; DWORD dwFlags; DWORD dwLoops;
      struct wavehdr_tag* lpNext; DWORD_PTR reserved;
    } WAVEHDR;
    UINT waveOutOpen(HWAVEOUT* phwo, UINT uDeviceID, const WAVEFORMATEX* pwfx,
      DWORD_PTR dwCallback, DWORD_PTR dwInstance, DWORD fdwOpen);
    UINT waveOutPrepareHeader(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    UINT waveOutUnprepareHeader(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    UINT waveOutWrite(HWAVEOUT hwo, WAVEHDR* pwh, UINT cbwh);
    UINT waveOutReset(HWAVEOUT hwo);
    UINT waveOutClose(HWAVEOUT hwo);
  ]]
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function fract(value)
  return value - math.floor(value)
end

local function noiseAt(time, seed)
  return fract(math.sin((time * 17371.0 + seed * 91.7) * 12.9898) * 43758.5453) * 2.0 - 1.0
end

local function readU16(data, offset)
  local a, b = data:byte(offset, offset + 1)
  if not b then return nil end
  return a + b * 256
end

local function readU32(data, offset)
  local a, b, c, d = data:byte(offset, offset + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function loadWave(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  if #data < 44 or data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WAVE" then
    return nil
  end

  local format, channels, sampleRate, bitsPerSample, pcm
  local offset = 13
  while offset + 7 <= #data do
    local chunkId = data:sub(offset, offset + 3)
    local chunkSize = readU32(data, offset + 4)
    if not chunkSize then break end
    local payload = offset + 8
    if chunkId == "fmt " and chunkSize >= 16 then
      format = readU16(data, payload)
      channels = readU16(data, payload + 2)
      sampleRate = readU32(data, payload + 4)
      bitsPerSample = readU16(data, payload + 14)
    elseif chunkId == "data" then
      pcm = data:sub(payload, math.min(#data, payload + chunkSize - 1))
    end
    offset = payload + chunkSize + chunkSize % 2
  end
  if format ~= 1 or not pcm or not channels or channels < 1 or
      not sampleRate or sampleRate < 1 or bitsPerSample ~= 16 then return nil end

  return {
    -- Keep the Lua string alive for as long as the FFI pointer is in use.
    data = pcm,
    samples = ffi.cast("const int16_t*", pcm),
    channels = channels,
    sampleRate = sampleRate,
    frames = math.floor(#pcm / (channels * 2))
  }
end

AudioEngine.loadWave = loadWave

function AudioEngine.soundMaterial(definition)
  local properties = definition and definition.properties or {}
  if properties.soundMaterial then return properties.soundMaterial end
  local key = (definition and (definition.key or definition.name) or "stone"):lower()
  if properties.glass or properties.ice or key:find("glass") or key:find("ice") then return "glass" end
  if key:find("wool") or key:find("carpet") or key:find("cloth") then return "cloth" end
  if properties.leaves or properties.plant or key:find("grass") or key:find("leaves") then return "grass" end
  if key:find("log") or key:find("plank") or key:find("wood") or key:find("stump") or key:find("crafting") then return "wood" end
  if key:find("gravel") then return "gravel" end
  -- Sandstone is rock, not loose sand, and it is most of what Mars is made of.
  if key:find("sandstone") then return "stone" end
  if key:find("sand") then return "sand" end
  if key:find("snow") then return "snow" end
  return "stone"
end

local MATERIAL = {
  stone = {frequency = 1180, noise = 0.44, duration = 0.13},
  wood = {frequency = 185, noise = 0.24, duration = 0.17},
  grass = {frequency = 310, noise = 0.78, duration = 0.14},
  gravel = {frequency = 520, noise = 0.92, duration = 0.17},
  sand = {frequency = 260, noise = 0.86, duration = 0.18},
  snow = {frequency = 180, noise = 0.62, duration = 0.19},
  cloth = {frequency = 145, noise = 0.72, duration = 0.16},
  glass = {frequency = 2340, noise = 0.18, duration = 0.20}
}

local BANK_VARIANTS = {
  stone = 4, wood = 4, grass = 4, gravel = 4,
  sand = 4, snow = 4, cloth = 4, glass = 3
}

local function loadBank(root)
  local bank = {breakSound = {}, step = {}}
  for material, count in pairs(BANK_VARIANTS) do
    local breakSounds = {}
    for variant = 1, count do
      local sample = loadWave(string.format("%s/break_%s_%d.wav", root, material, variant))
      if sample then breakSounds[#breakSounds + 1] = sample end
    end
    bank.breakSound[material] = breakSounds

    local stepSounds = {}
    if material ~= "glass" then
      for variant = 1, count do
        local sample = loadWave(string.format("%s/step_%s_%d.wav", root, material, variant))
        if sample then stepSounds[#stepSounds + 1] = sample end
      end
    end
    -- Glass has no dedicated step set in the source pack. Its short break
    -- samples work well for placement, while footsteps use the stone bank.
    bank.step[material] = #stepSounds > 0 and stepSounds or nil
  end
  bank.step.glass = bank.step.stone
  return bank
end

local function sampleAt(sample, frame)
  if frame < 0 or frame >= sample.frames - 1 then return 0.0 end
  local index = math.floor(frame)
  local blend = frame - index
  local function mono(frameIndex)
    local base, sum = frameIndex * sample.channels, 0.0
    for channel = 0, sample.channels - 1 do
      sum = sum + sample.samples[base + channel]
    end
    return sum / (sample.channels * 32768.0)
  end
  local a, b = mono(index), mono(index + 1)
  return a + (b - a) * blend
end

local function voiceSample(voice, time)
  if time < 0 then return 0 end
  local material = MATERIAL[voice.material] or MATERIAL.stone
  local duration = voice.duration or material.duration
  if time >= duration then return 0 end
  if voice.sample then
    local attack = math.min(1.0, time / 0.003)
    local release = math.min(1.0, (duration - time) / 0.012)
    local frame = time * voice.sample.sampleRate * (voice.pitch or 1.0)
    return sampleAt(voice.sample, frame) * math.min(attack, release) * voice.gain
  end
  local attack = math.min(1.0, time / 0.006)
  local envelope = attack * (1.0 - time / duration) ^ 2.2
  local frequency = material.frequency * (voice.pitch or 1.0)
  local tonal = math.sin(time * frequency * math.pi * 2.0) *
    (0.72 + 0.28 * math.sin(time * frequency * 0.37))
  local noise = noiseAt(time, voice.seed)
  if voice.material == "grass" or voice.material == "sand" or voice.material == "snow" then
    noise = (noise + noiseAt(time - 0.0017, voice.seed)) * 0.5
  elseif voice.material == "glass" then
    tonal = tonal * 0.65 + math.sin(time * frequency * 1.73 * math.pi * 2.0) * 0.35
  end
  return (tonal * (1.0 - material.noise) + noise * material.noise) * envelope * voice.gain
end

-- A compact Schroeder/Freeverb-style network. Parallel damped combs build a
-- dense decay, then two all-pass stages diffuse it so footsteps smear into the
-- room instead of returning as three obviously repeated copies.
local COMB_LENGTHS = {1116, 1188, 1277, 1356}
local ALLPASS_LENGTHS = {556, 441}

local function delayLine(length)
  return {data = ffi.new("float[?]", length), length = length, index = 0, filtered = 0.0}
end

local function reverbChannel(stereoOffset)
  local channel = {combs = {}, allpasses = {}}
  for index = 1, #COMB_LENGTHS do
    channel.combs[index] = delayLine(COMB_LENGTHS[index] + stereoOffset)
  end
  for index = 1, #ALLPASS_LENGTHS do
    channel.allpasses[index] = delayLine(ALLPASS_LENGTHS[index] + stereoOffset)
  end
  return channel
end

local function createReverb()
  return {left = reverbChannel(0), right = reverbChannel(23)}
end

local function processComb(line, input, feedback, damping)
  local delayed = line.data[line.index]
  line.filtered = delayed * (1.0 - damping) + line.filtered * damping
  line.data[line.index] = input + line.filtered * feedback
  line.index = (line.index + 1) % line.length
  return delayed
end

local function processAllpass(line, input)
  local delayed = line.data[line.index]
  local output = delayed - input
  line.data[line.index] = input + delayed * 0.50
  line.index = (line.index + 1) % line.length
  return output
end

local function processReverbChannel(channel, input, feedback, damping)
  local value = 0.0
  for index = 1, #channel.combs do
    value = value + processComb(channel.combs[index], input, feedback, damping)
  end
  value = value / #channel.combs
  for index = 1, #channel.allpasses do
    value = processAllpass(channel.allpasses[index], value)
  end
  return value
end

local function processReverb(reverb, left, right, amount)
  amount = clamp(amount or 0.0, 0.0, 1.0)
  local feedback = 0.70 + amount * 0.16
  local damping = 0.32 + amount * 0.20
  local inputLeft = (left * 0.76 + right * 0.24) * amount * 0.30
  local inputRight = (right * 0.76 + left * 0.24) * amount * 0.30
  return processReverbChannel(reverb.left, inputLeft, feedback, damping),
    processReverbChannel(reverb.right, inputRight, feedback, damping)
end

AudioEngine.createReverb = createReverb
AudioEngine.processReverb = processReverb

local function enclosureAt(world, position)
  if not world or not position then return 0.0 end
  local x, y, z = math.floor(position[1]), math.floor(position[2]), math.floor(position[3])
  local sky = world.skyLightAt and world:skyLightAt(x, y, z) or 15
  local directions = {
    {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
    {1,0,1}, {-1,0,1}, {1,0,-1}, {-1,0,-1}
  }
  local hits, distanceTotal = 0, 0
  for i = 1, #directions do
    local direction, hitDistance = directions[i], 12
    for distance = 2, 12, 2 do
      local id = world:blockAt(x + direction[1] * distance,
        y + direction[2] * distance, z + direction[3] * distance)
      if id and id ~= 0 then hitDistance = distance break end
    end
    if hitDistance < 12 then hits = hits + 1 end
    distanceTotal = distanceTotal + hitDistance
  end
  local closed = hits / #directions
  local compact = 1.0 - clamp((distanceTotal / #directions - 2.0) / 10.0, 0.0, 1.0)
  local darkness = 1.0 - clamp(sky / 15.0, 0.0, 1.0)
  return clamp(darkness * 0.62 + closed * 0.25 + compact * 0.13, 0.0, 1.0)
end

AudioEngine.enclosureAt = enclosureAt

function AudioEngine.new(options)
  options = options or {}
  -- `x and nil or y` always yields y, so the opt-out needs a real branch.
  local sampleBank = nil
  if options.loadAssets ~= false then
    sampleBank = loadBank(options.soundRoot or "assets/sounds/runtime")
  end
  local treeFallSample = options.loadAssets ~= false and loadWave(
    options.treeFallPath or "assets/sounds/ambient/sfx/tree_fall_sfx.wav") or nil
  local self = setmetatable({
    enabled = false,
    volume = 1.0,
    voices = {},
    mixTime = 0.0,
    caveAmount = 0.0,
    caveTarget = 0.0,
    acoustics = audioAtmosphere.forProfile(options.worldProfile, SAMPLE_RATE),
    previousFootSign = 1,
    previousGrounded = false,
    reverb = createReverb(),
    listener = {position = {0,0,0}, right = {1,0,0}},
    sampleBank = sampleBank,
    treeFallSample = treeFallSample
  }, AudioEngine)
  if options.disabled or ffi.os ~= "Windows" then return self end

  local ok, winmm = pcall(ffi.load, "winmm")
  if not ok then return self end
  self.winmm = winmm
  self.handle = ffi.new("HWAVEOUT[1]")
  local format = ffi.new("WAVEFORMATEX[1]")
  format[0].wFormatTag, format[0].nChannels = 1, 2
  format[0].nSamplesPerSec, format[0].wBitsPerSample = SAMPLE_RATE, 16
  format[0].nBlockAlign = 4
  format[0].nAvgBytesPerSec = SAMPLE_RATE * 4
  if winmm.waveOutOpen(self.handle, WAVE_MAPPER, format, 0, 0, 0) ~= 0 then return self end

  self.buffers = {}
  for index = 1, BUFFER_COUNT do
    local samples = ffi.new("int16_t[?]", FRAMES_PER_BUFFER * 2)
    local header = ffi.new("WAVEHDR[1]")
    header[0].lpData = ffi.cast("char*", samples)
    header[0].dwBufferLength = FRAMES_PER_BUFFER * 4
    if winmm.waveOutPrepareHeader(self.handle[0], header, ffi.sizeof("WAVEHDR")) ~= 0 then
      self:close()
      return self
    end
    self.buffers[index] = {samples = samples, header = header, queued = false}
  end
  self.enabled = true
  return self
end

-- How much of each event reaches the player through their own body rather than
-- only through the air: a footfall entirely, a swing that lands on a block
-- mostly, the block coming apart afterwards hardly at all.
local EVENT_CONDUCTION = {
  step = 1.0, hit = 0.85, place = 0.60, ["break"] = 0.15,
  treeFall = 0.10
}

function AudioEngine:play(material, event, position, gain, sampleOverride, pitchOverride)
  if #self.voices >= 48 then table.remove(self.voices, 1) end
  local preset = MATERIAL[material] or MATERIAL.stone
  local eventGain = event == "treeFall" and 1.0 or (event == "break" and 0.90 or
    (event == "place" and 0.62 or (event == "hit" and 0.24 or 0.34)))
  -- A footfall is the player's weight arriving on the ground, so its energy
  -- follows surface gravity. A swung tool carries the player's arm instead and
  -- is unaffected.
  if event == "step" then eventGain = eventGain * self.acoustics.contactScale end
  local pan, distance = 0.0, 0.0
  if position and self.listener.position then
    local dx, dy, dz = position[1] - self.listener.position[1],
      position[2] - self.listener.position[2], position[3] - self.listener.position[3]
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > 0.001 then
      pan = clamp((dx * self.listener.right[1] + dy * self.listener.right[2] +
        dz * self.listener.right[3]) / distance, -0.85, 0.85)
      eventGain = eventGain / (1.0 + distance * 0.075)
    end
  end
  local samples
  if self.sampleBank then
    if event == "step" or event == "place" then
      samples = self.sampleBank.step[material] or self.sampleBank.step.stone
    else
      samples = self.sampleBank.breakSound[material] or self.sampleBank.breakSound.stone
    end
  end
  local sample = sampleOverride or
    (samples and #samples > 0 and samples[math.random(1, #samples)] or nil)
  local pitch
  if pitchOverride then pitch = pitchOverride
  elseif event == "place" then pitch = 0.78 + math.random() * 0.10
  elseif event == "hit" then pitch = 1.08 + math.random() * 0.16
  else pitch = 0.94 + math.random() * 0.12 end
  local duration = sample and sample.frames / sample.sampleRate / pitch or preset.duration
  -- The world's air decides four things about this voice: how much of it the
  -- source could radiate at all, how that radiation is tilted across the
  -- spectrum, how much of its top end survives the trip, and how long that trip
  -- takes. Sounds the player makes themselves also reach them through their own
  -- body, which no atmosphere can take away.
  local acoustics = self.acoustics
  local conduction = EVENT_CONDUCTION[event] or 0.0
  local shelf = acoustics.radiationShelfGain
  self.voices[#self.voices + 1] = {
    material = material, duration = duration, sample = sample,
    start = self.mixTime + distance / acoustics.speedOfSound,
    gain = eventGain * (gain or 1.0) * audioAtmosphere.contactGain(acoustics, conduction),
    pan = pan,
    tone = audioAtmosphere.toneCoefficient(acoustics, distance), toneState = 0.0,
    shelf = shelf ~= 0.0 and shelf or nil,
    shelfCoefficient = acoustics.radiationShelfCoefficient, shelfState = 0.0,
    pitch = pitch, seed = math.random() * 1000
  }
end

function AudioEngine.treeFallPitch(secondsToImpact)
  local seconds=tonumber(secondsToImpact)
  if not seconds or seconds<=0 then return 1.0 end
  return clamp(AudioEngine.TREE_FALL_IMPACT_SECONDS/seconds,0.5,6.0)
end

function AudioEngine:playTreeFall(position,gain,secondsToImpact)
  if self.treeFallSample then
    self:play("wood","treeFall",position,gain,self.treeFallSample,
      AudioEngine.treeFallPitch(secondsToImpact))
    return true
  end
  self:play("wood","break",position,gain)
  return false
end

-- Worlds change under a running mixer, so the acoustic profile is swapped in
-- place. Voices already in flight keep the air they were born in.
function AudioEngine:setWorldProfile(worldProfile)
  local acoustics = audioAtmosphere.forProfile(worldProfile, SAMPLE_RATE)
  if acoustics == self.acoustics then return end
  self.acoustics = acoustics
end

function AudioEngine:playBlock(definition, event, position, gain)
  self:play(AudioEngine.soundMaterial(definition), event, position, gain)
end

function AudioEngine:mixBuffer(samples)
  local startTime = self.mixTime
  local acoustics = self.acoustics
  -- Reverb is an atmospheric effect too: a room can only ring with the energy
  -- its air carries, so thin worlds lose their caves along with their volume.
  local wetAmount = self.caveAmount * acoustics.reverbScale
  for frame = 0, FRAMES_PER_BUFFER - 1 do
    local time = startTime + frame / SAMPLE_RATE
    local left, right = 0.0, 0.0
    for index = 1, #self.voices do
      local voice = self.voices[index]
      local localTime = time - voice.start
      local dry = voiceSample(voice, localTime)
      -- Source first: the shelf is how well this world's air lets a block-sized
      -- face radiate its low end at all.
      if voice.shelf then
        voice.shelfState = voice.shelfState + (dry - voice.shelfState) * voice.shelfCoefficient
        dry = dry + voice.shelfState * voice.shelf
      end
      -- Then the trip: one pole of atmospheric absorption, at the corner this
      -- voice's own travel distance earned.
      voice.toneState = voice.toneState + (dry - voice.toneState) * voice.tone
      dry = voice.toneState
      left = left + dry * math.sqrt((1.0 - voice.pan) * 0.5)
      right = right + dry * math.sqrt((1.0 + voice.pan) * 0.5)
    end

    local wetLeft, wetRight = processReverb(self.reverb, left, right, wetAmount)
    left = left + wetLeft * wetAmount * 0.72
    right = right + wetRight * wetAmount * 0.72

    local master = self.volume
    samples[frame * 2] = math.floor(clamp(left * master, -1.0, 1.0) * 32767)
    samples[frame * 2 + 1] = math.floor(clamp(right * master, -1.0, 1.0) * 32767)
  end
  self.mixTime = startTime + FRAMES_PER_BUFFER / SAMPLE_RATE

  local alive = {}
  for index = 1, #self.voices do
    local voice = self.voices[index]
    local duration = voice.duration + 0.02
    if self.mixTime - voice.start < duration then alive[#alive + 1] = voice end
  end
  self.voices = alive
end

local function listenerRight(camera)
  if camera and camera.getRight then return camera:getRight() end
  return {1, 0, 0}
end

function AudioEngine:update(deltaTime, camera, world, volumePercent)
  self.volume = clamp((volumePercent or 100) / 100.0, 0.0, 1.0)
  if world and world.worldProfile then self:setWorldProfile(world.worldProfile) end
  if camera then
    self.listener.position = {camera.position[1], camera.position[2], camera.position[3]}
    self.listener.right = listenerRight(camera)
    self.caveTarget = enclosureAt(world, camera.position)
    local blend = 1.0 - math.exp(-math.min(deltaTime or 0, 0.1) * 2.2)
    self.caveAmount = self.caveAmount + (self.caveTarget - self.caveAmount) * blend

    local footSign = math.cos(camera.bobPhase or 0) >= 0 and 1 or -1
    if camera.grounded and not camera.flying and footSign ~= self.previousFootSign then
      local feetY = math.floor(camera.position[2] - (camera.eyeHeight or 1.62) - 0.05)
      local blockId = world and world:blockAt(math.floor(camera.position[1]), feetY,
        math.floor(camera.position[3]))
      local definition = blockId and require("blocks").list[blockId]
      local speed = math.sqrt(camera.velocity[1] ^ 2 + camera.velocity[3] ^ 2)
      if speed > 0.18 then self:playBlock(definition, "step", camera.position,
        clamp(speed / 5.0, 0.35, 1.25)) end
    end
    if camera.grounded and not self.previousGrounded then
      local feetY = math.floor(camera.position[2] - (camera.eyeHeight or 1.62) - 0.05)
      local blockId = world and world:blockAt(math.floor(camera.position[1]), feetY,
        math.floor(camera.position[3]))
      self:playBlock(blockId and require("blocks").list[blockId], "step", camera.position, 0.72)
    end
    self.previousFootSign, self.previousGrounded = footSign, camera.grounded
  end

  if not self.enabled then return end
  for index = 1, #self.buffers do
    local buffer = self.buffers[index]
    if buffer.queued and bit.band(buffer.header[0].dwFlags, WHDR_DONE) ~= 0 then
      buffer.queued = false
    end
    if not buffer.queued then
      self:mixBuffer(buffer.samples)
      buffer.header[0].dwFlags = bit.band(buffer.header[0].dwFlags, bit.bnot(WHDR_DONE))
      if self.winmm.waveOutWrite(self.handle[0], buffer.header, ffi.sizeof("WAVEHDR")) == 0 then
        buffer.queued = true
      end
    end
  end
end

function AudioEngine:close()
  if not self.winmm or not self.handle or self.handle[0] == nil then return end
  self.winmm.waveOutReset(self.handle[0])
  for _, buffer in ipairs(self.buffers or {}) do
    self.winmm.waveOutUnprepareHeader(self.handle[0], buffer.header, ffi.sizeof("WAVEHDR"))
  end
  self.winmm.waveOutClose(self.handle[0])
  self.enabled, self.handle = false, nil
end

return AudioEngine
