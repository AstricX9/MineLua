local ffi = require("ffi")

local saves = {}

local SAVE_ROOT = "saves"
local VERSION_NAME = "MineLua Pre-alpha"
local VERSION_ID = 100

if ffi.os == "Windows" then
  ffi.cdef[[int _mkdir(const char *dirname);]]
else
  ffi.cdef[[int mkdir(const char *path, unsigned int mode);]]
end

local function mkdir(path)
  if ffi.os == "Windows" then
    ffi.C._mkdir((path:gsub("/", "\\")))
  else
    ffi.C.mkdir(path, tonumber("755", 8))
  end
end

local function ensureDir(path)
  mkdir(path)
  return path
end

local function escapeJson(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\")
  value = value:gsub("\"", "\\\"")
  value = value:gsub("\n", "\\n")
  value = value:gsub("\r", "\\r")
  value = value:gsub("\t", "\\t")
  return value
end

local function encodeJson(value, indent)
  indent = indent or 0
  local kind = type(value)

  if kind == "string" then
    return "\"" .. escapeJson(value) .. "\""
  elseif kind == "number" or kind == "boolean" then
    return tostring(value)
  elseif kind ~= "table" then
    return "null"
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  local nextIndent = indent + 2
  local lines = {"{"}
  for i = 1, #keys do
    local key = keys[i]
    local suffix = i < #keys and "," or ""
    lines[#lines + 1] = string.rep(" ", nextIndent) .. "\"" .. escapeJson(key) .. "\": " .. encodeJson(value[key], nextIndent) .. suffix
  end
  lines[#lines + 1] = string.rep(" ", indent) .. "}"
  return table.concat(lines, "\n")
end

local function writeFile(path, content)
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
end

local function pathExists(path)
  if os.rename(path, path) then
    return true
  end

  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end

  local probe = io.open(path .. "/level.dat", "rb")
  if probe then
    probe:close()
    return true
  end

  return false
end

local function sanitizeFolderName(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("[<>:\"/\\|%?%*]", "_")
  name = name:gsub("[%.%s]+$", "")
  if name == "" then
    name = "World"
  end
  return name
end

local function reserveWorldFolder(worldName)
  ensureDir(SAVE_ROOT)

  local base = sanitizeFolderName(worldName)
  for index = 0, 999 do
    local folderName = index == 0 and base or (base .. " (" .. index .. ")")
    local path = SAVE_ROOT .. "/" .. folderName
    if not pathExists(path) then
      mkdir(path)
      return path, folderName
    end
  end

  error("Unable to find a free save folder for " .. base)
end

local function ensureMinecraftLayout(path)
  ensureDir(path .. "/region")
  ensureDir(path .. "/data")
  ensureDir(path .. "/playerdata")
  ensureDir(path .. "/advancements")
  ensureDir(path .. "/stats")
  ensureDir(path .. "/generated")
  ensureDir(path .. "/datapacks")
  ensureDir(path .. "/DIM-1")
  ensureDir(path .. "/DIM-1/region")
  ensureDir(path .. "/DIM1")
  ensureDir(path .. "/DIM1/region")
end

local function gameTypeForMode(gameMode)
  return gameMode == "creative" and 1 or 0
end

function saves.createWorld(options)
  options = options or {}
  local worldName = options.worldName or "New World"
  local path, folderName = reserveWorldFolder(worldName)
  local now = os.time()

  ensureMinecraftLayout(path)
  writeFile(path .. "/session.lock", tostring(now) .. "\n")
  writeFile(path .. "/levelname.txt", worldName .. "\n")

  local level = {
    Data = {
      LevelName = worldName,
      GameType = gameTypeForMode(options.gameMode),
      MapFeatures = true,
      generatorName = options.generatorType == "superflat" and "flat" or "default",
      generatorVersion = 1,
      LastPlayed = now * 1000,
      RandomSeed = options.seed or 1,
      SpawnX = 0,
      SpawnY = 64,
      SpawnZ = 0,
      Time = 0,
      DayTime = 0,
      version = VERSION_ID,
      Version = {
        Name = VERSION_NAME,
        Id = VERSION_ID,
        Snapshot = true
      }
    }
  }

  writeFile(path .. "/level.dat", encodeJson(level) .. "\n")
  writeFile(path .. "/mineLua.json", encodeJson({
    gameMode = options.gameMode or "survival",
    generatorType = options.generatorType or "default",
    seed = options.seed or 1,
    saveFormat = "minecraft-like",
    worldName = worldName
  }) .. "\n")

  return {
    path = path,
    folderName = folderName,
    seed = options.seed or 1,
    worldName = worldName
  }
end

function saves.folderForWorldName(worldName)
  return SAVE_ROOT .. "/" .. sanitizeFolderName(worldName)
end

return saves
