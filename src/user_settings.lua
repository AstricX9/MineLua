local appPaths = require("app_paths")
local json = require("json")

local settings = {}

-- data/config is packaged content: a release rebuild replaces it, and an
-- install under Program Files is not writable at all. Settings belong with the
-- player's other data. The old location is still read once, so an existing
-- configuration carries over.
settings.PATH = appPaths.configPath("user_settings.json")
settings.LEGACY_PATH = appPaths.legacyConfigPath("user_settings.json")

settings.DEFAULTS = {
  soundVolume = 100,
  sensitivity = 100,
  invertMouse = false,
  fovDegrees = 70,
  renderDistance = 24,
  vsync = true,
  clouds = true,
  bloom = true,
  particles = "All",
  viewBobbing = true,
  motionBlur = "Off",
  fullscreen = false,
  controlBindings = {
    attack = "MOUSE1",
    use = "MOUSE2",
    pick = "MOUSE3",
    forward = "W",
    back = "S",
    left = "A",
    right = "D",
    jump = "SPACE",
    sneak = "CTRL",
    drop = "Q",
    inventory = "E"
  }
}

local particles = {All = true, Decreased = true, Minimal = true}
local motionBlur = {Off = true, Low = true, Medium = true, High = true}

local function clamp(value, minimum, maximum, fallback)
  value = tonumber(value)
  if not value then return fallback end
  return math.max(minimum, math.min(maximum, value))
end

local function copyBindings(source)
  local result = {}
  source = type(source) == "table" and source or {}
  for action, fallback in pairs(settings.DEFAULTS.controlBindings) do
    local value = source[action]
    result[action] = type(value) == "string" and value or fallback
  end
  return result
end

function settings.sanitize(source, defaults)
  source = type(source) == "table" and source or {}
  defaults = defaults or settings.DEFAULTS
  return {
    soundVolume = clamp(source.soundVolume, 0, 100, defaults.soundVolume),
    sensitivity = clamp(source.sensitivity, 25, 200, defaults.sensitivity),
    invertMouse = source.invertMouse == nil and defaults.invertMouse or source.invertMouse == true,
    fovDegrees = clamp(source.fovDegrees, 50, 110, defaults.fovDegrees),
    renderDistance = math.floor(clamp(source.renderDistance, 2, 64, defaults.renderDistance) + 0.5),
    vsync = source.vsync == nil and defaults.vsync or source.vsync == true,
    clouds = source.clouds == nil and defaults.clouds or source.clouds == true,
    bloom = source.bloom == nil and defaults.bloom or source.bloom == true,
    particles = particles[source.particles] and source.particles or defaults.particles,
    viewBobbing = source.viewBobbing == nil and defaults.viewBobbing or source.viewBobbing == true,
    motionBlur = motionBlur[source.motionBlur] and source.motionBlur or defaults.motionBlur,
    fullscreen = source.fullscreen == nil and defaults.fullscreen or source.fullscreen == true,
    controlBindings = copyBindings(source.controlBindings)
  }
end

function settings.capture(state)
  return settings.sanitize(state)
end

function settings.apply(state, saved, defaults)
  local clean = settings.sanitize(saved, defaults)
  for key, value in pairs(clean) do state[key] = value end
  return state
end

local function escapeString(value)
  return value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\b", "\\b")
    :gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

local function encode(value, indent)
  local kind = type(value)
  if kind == "string" then return '"' .. escapeString(value) .. '"' end
  if kind == "number" then return tostring(value) end
  if kind == "boolean" then return value and "true" or "false" end
  if kind ~= "table" then return "null" end

  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  local nextIndent = indent .. "  "
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = nextIndent .. encode(tostring(key), nextIndent) .. ": " ..
      encode(value[key], nextIndent)
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function settings.load(path, defaults)
  local explicit = path ~= nil
  path = path or settings.PATH
  local file = io.open(path, "rb")
  if not file and not explicit and settings.LEGACY_PATH ~= settings.PATH then
    path = settings.LEGACY_PATH
    file = io.open(path, "rb")
  end
  if not file then return settings.sanitize(nil, defaults) end
  local content = file:read("*a")
  file:close()
  local ok, decoded = pcall(json.decode, content)
  if not ok or type(decoded) ~= "table" then
    io.stderr:write("Skipping invalid user settings file: " .. path .. "\n")
    return settings.sanitize(nil, defaults)
  end
  return settings.sanitize(decoded, defaults)
end

function settings.save(state, path)
  path = path or settings.PATH
  local directory = path:match("^(.*)[/\\][^/\\]*$")
  if directory then appPaths.ensureDirectory(directory) end
  local file, err = io.open(path, "wb")
  if not file then return false, err end
  local ok, writeError = file:write(encode(settings.capture(state), "") .. "\n")
  file:close()
  if not ok then return false, writeError end
  return true
end

function settings.stateKey(state)
  return encode(settings.capture(state), "")
end

return settings
