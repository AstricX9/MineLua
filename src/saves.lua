local ffi = require("ffi")
local appPaths = require("app_paths")
local filesystem = require("filesystem")
local json = require("json")
local worldProfiles = require("world_profiles")

local saves = {}

-- Absolute and resolved once. "saves" was relative to the working directory,
-- which put a packaged build's worlds inside the folder the next install
-- deletes, and left them unwritable under Program Files. appPaths keeps an
-- existing ./saves in place for a checkout or a portable install, and otherwise
-- uses the per-user data directory.
local SAVE_ROOT = appPaths.saveRoot()
local VERSION_NAME = "MineLua Pre-alpha"
local VERSION_ID = 100
local PLAYER_DATA_VERSION = 1

if ffi.os == "Windows" then
  ffi.cdef[[
    int _mkdir(const char *dirname);
    int RemoveDirectoryA(const char *pathName);
    int MoveFileExA(const char *existingFileName, const char *newFileName, unsigned long flags);
    unsigned long GetCurrentProcessId(void);
    unsigned long GetLastError(void);
  ]]
else
  ffi.cdef[[
    int mkdir(const char *path, unsigned int mode);
    int getpid(void);
  ]]
end

-- Both create every missing level. The old single-level mkdir quietly did
-- nothing when a parent was absent, and the caller only discovered it when the
-- file write failed later.
local ensureDir = appPaths.ensureDirectory
local mkdir = appPaths.ensureDirectory

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

  local count = 0
  local maximum = 0
  local isArray = true
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      isArray = false
    else
      maximum = math.max(maximum, key)
    end
  end
  isArray = isArray and count > 0 and maximum == count

  local nextIndent = indent + 2
  if isArray then
    local lines = {"["}
    for index = 1, maximum do
      local suffix = index < maximum and "," or ""
      lines[#lines + 1] = string.rep(" ", nextIndent) .. encodeJson(value[index], nextIndent) .. suffix
    end
    lines[#lines + 1] = string.rep(" ", indent) .. "]"
    return table.concat(lines, "\n")
  end

  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

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
  local file, openError = io.open(path, "wb")
  if not file then return false, path .. ": " .. tostring(openError) end

  local wrote, writeError = file:write(content)
  local closed, closeError = file:close()
  if not wrote then return false, path .. ": " .. tostring(writeError) end
  if not closed then return false, path .. ": " .. tostring(closeError) end
  return true
end

local function mustWriteFile(path, content)
  local wrote, writeError = writeFile(path, content)
  if not wrote then error(writeError, 2) end
end

local temporaryWriteCounter = 0

local function processId()
  if ffi.os == "Windows" then return tonumber(ffi.C.GetCurrentProcessId()) end
  return tonumber(ffi.C.getpid())
end

local function replaceFile(from, to)
  if ffi.os == "Windows" then
    -- REPLACE_EXISTING | WRITE_THROUGH: the old valid JSON remains in place
    -- until the complete temporary file has reached the same directory.
    if ffi.C.MoveFileExA(from:gsub("/", "\\"), to:gsub("/", "\\"), 0x9) ~= 0 then
      return true
    end
    return false, "Windows error " .. tostring(tonumber(ffi.C.GetLastError()))
  end

  local replaced, replaceError = os.rename(from, to)
  if replaced then return true end
  return false, replaceError
end

local function atomicWriteFile(path, content)
  temporaryWriteCounter = temporaryWriteCounter + 1
  local temporary = string.format("%s.tmp.%d.%d", path, processId(), temporaryWriteCounter)
  local wrote, writeError = writeFile(temporary, content)
  if not wrote then
    os.remove(temporary)
    return false, writeError
  end

  local replaced, replaceError = replaceFile(temporary, path)
  if not replaced then
    os.remove(temporary)
    return false, path .. ": unable to replace player data: " .. tostring(replaceError)
  end
  return true
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

local pathExists

local function directoryNames(path)
  local names = {}
  for _, entry in ipairs(filesystem.entries(path)) do
    if entry.isDirectory and not entry.isReparsePoint then
      names[#names + 1] = entry.name
    end
  end
  return names
end

local function decodeJsonString(value)
  if not value then return nil end
  return value:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
    :gsub('\\"', '"'):gsub("\\\\", "\\")
end

local function jsonString(content, key)
  return decodeJsonString(content and content:match('"' .. key .. '"%s*:%s*"(.-)"'))
end

local function jsonNumber(content, key)
  return tonumber(content and content:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)'))
end

local function jsonBoolean(content, key)
  local value = content and content:match('"' .. key .. '"%s*:%s*(%a+)')
  if value == "true" then return true end
  if value == "false" then return false end
  return nil
end

pathExists = function(path)
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
  local worldId = worldProfiles.id(options.worldId)

  ensureMinecraftLayout(path)
  mustWriteFile(path .. "/session.lock", tostring(now) .. "\n")
  mustWriteFile(path .. "/levelname.txt", worldName .. "\n")

  local level = {
    Data = {
      LevelName = worldName,
      GameType = gameTypeForMode(options.gameMode),
      MapFeatures = true,
      generatorName = (options.generatorType == "superflat" or options.generatorType == "showcase") and
        "flat" or "default",
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

  mustWriteFile(path .. "/level.dat", encodeJson(level) .. "\n")
  mustWriteFile(path .. "/mineLua.json", encodeJson({
    allowCheats = options.allowCheats == true,
    bonusChest = options.bonusChest == true,
    gameMode = options.gameMode or "survival",
    generateStructures = options.generateStructures ~= false,
    generatorType = options.generatorType or "default",
    lastPlayed = now * 1000,
    seed = options.seed or 1,
    saveFormat = "minecraft-like",
    worldId = worldId,
    worldName = worldName
  }) .. "\n")

  return {
    path = path,
    folderName = folderName,
    seed = options.seed or 1,
    gameMode = options.gameMode or "survival",
    generatorType = options.generatorType or "default",
    worldId = worldId,
    worldName = worldName
  }
end

function saves.listWorlds()
  ensureDir(SAVE_ROOT)
  local worlds = {}

  for _, folderName in ipairs(directoryNames(SAVE_ROOT)) do
    local path = SAVE_ROOT .. "/" .. folderName
    local metadata = readFile(path .. "/mineLua.json")
    local level = readFile(path .. "/level.dat")
    if metadata or level then
      local worldName = jsonString(metadata, "worldName") or jsonString(level, "LevelName") or folderName
      local gameMode = jsonString(metadata, "gameMode")
      if not gameMode then gameMode = jsonNumber(level, "GameType") == 1 and "creative" or "survival" end
      local generatorType = jsonString(metadata, "generatorType")
      if not generatorType then generatorType = jsonString(level, "generatorName") == "flat" and "superflat" or "default" end
      local lastPlayed = jsonNumber(metadata, "lastPlayed") or jsonNumber(level, "LastPlayed") or 0
      local versionName = jsonString(level, "Name") or VERSION_NAME
      local modeLabel = gameMode == "creative" and "Creative Mode" or "Survival Mode"
      local worldId = worldProfiles.id(jsonString(metadata, "worldId"))
      local worldNameLabel = worldProfiles.get(worldId).name

      worlds[#worlds + 1] = {
        path = path,
        folderName = folderName,
        worldName = worldName,
        gameMode = gameMode,
        generatorType = generatorType,
        worldId = worldId,
        seed = jsonNumber(metadata, "seed") or jsonNumber(level, "RandomSeed") or 1,
        generateStructures = jsonBoolean(metadata, "generateStructures") ~= false,
        allowCheats = jsonBoolean(metadata, "allowCheats") == true,
        bonusChest = jsonBoolean(metadata, "bonusChest") == true,
        lastPlayed = lastPlayed,
        lastPlayedText = lastPlayed > 0 and os.date("%d/%m/%Y %I:%M %p", math.floor(lastPlayed / 1000)) or "Unknown date",
        summary = worldNameLabel .. " / " .. modeLabel .. ", Version: " .. versionName
      }
    end
  end

  table.sort(worlds, function(a, b)
    if a.lastPlayed == b.lastPlayed then return a.worldName:lower() < b.worldName:lower() end
    return a.lastPlayed > b.lastPlayed
  end)
  return worlds
end

local function removeDirectory(path)
  if ffi.os == "Windows" then
    return ffi.C.RemoveDirectoryA((path:gsub("/", "\\"))) ~= 0
  end
  return os.remove(path)
end

local function deleteTree(path)
  for _, entry in ipairs(filesystem.entries(path)) do
    local child = path .. "/" .. entry.name
    local ok, err
    if entry.isDirectory and not entry.isReparsePoint then
      ok, err = deleteTree(child)
    elseif entry.isDirectory then
      ok = removeDirectory(child)
      err = ok and nil or "unable to remove directory link"
    else
      ok, err = os.remove(child)
    end
    if not ok then return false, err or ("unable to remove " .. child) end
  end

  if not removeDirectory(path) then
    return false, "unable to remove world folder"
  end
  return true
end

function saves.deleteWorld(worldSave)
  if type(worldSave) ~= "table" then return false, "invalid world" end
  local folderName = tostring(worldSave.folderName or "")
  if folderName == "" or folderName == "." or folderName == ".." or folderName:find("[/\\]") then
    return false, "invalid world folder"
  end

  local expectedPath = SAVE_ROOT .. "/" .. folderName
  local suppliedPath = tostring(worldSave.path or ""):gsub("\\", "/"):gsub("/+$", "")
  if suppliedPath ~= expectedPath then
    return false, "world is outside the saves directory"
  end
  if not readFile(expectedPath .. "/mineLua.json") and not readFile(expectedPath .. "/level.dat") then
    return false, "folder is not a MineLua world"
  end

  return deleteTree(expectedPath)
end

function saves.savePlayer(worldSave, playerState)
  if not worldSave or not worldSave.path then
    return false, "A world save path is required"
  end
  ensureDir(worldSave.path .. "/playerdata")
  return atomicWriteFile(worldSave.path .. "/playerdata/minelua.json", encodeJson({
    format = "minelua-player",
    version = PLAYER_DATA_VERSION,
    savedAt = os.time() * 1000,
    state = playerState or {}
  }) .. "\n")
end

function saves.loadPlayer(worldSave)
  if not worldSave or not worldSave.path then return nil end
  local content = readFile(worldSave.path .. "/playerdata/minelua.json")
  if not content then return nil end

  local ok, document = pcall(json.decode, content)
  if not ok or type(document) ~= "table" or type(document.state) ~= "table" then
    return nil
  end
  return document.state, document.version
end

function saves.folderForWorldName(worldName)
  return SAVE_ROOT .. "/" .. sanitizeFolderName(worldName)
end

-- Exposed so other systems (screenshots, exports) can drop files beside the
-- saves without each one redeclaring the platform mkdir.
function saves.ensureDirectory(path)
  return ensureDir(path)
end

-- Where worlds actually live. The world list shows this so a player who cannot
-- find their saves does not have to guess.
function saves.root()
  return SAVE_ROOT
end

return saves

