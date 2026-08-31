-- Where the game is allowed to write.
--
-- Everything used to be written relative to the working directory: saves went
-- to ./saves and user settings to ./data/config. That works from a checkout and
-- fails everywhere else. A packaged build runs from its own extracted folder,
-- so each new build got its own empty save list and the previous build's worlds
-- were deleted with the old package; installed under Program Files the writes
-- fail outright; and a relative path silently follows the working directory if
-- anything ever changes it.
--
-- These roots are resolved once, as absolute paths, and every writable file
-- hangs off them.

local ffi = require("ffi")

local appPaths = {}

local WINDOWS = ffi.os == "Windows"

if WINDOWS then
  ffi.cdef[[
    int _mkdir(const char *dirname);
    unsigned long GetCurrentDirectoryA(unsigned long bufferLength, char *buffer);
  ]]
else
  ffi.cdef[[
    int mkdir(const char *path, unsigned int mode);
    char *getcwd(char *buffer, size_t size);
  ]]
end

local function normalize(path)
  return (tostring(path):gsub("\\", "/"):gsub("/+", "/"):gsub("/$", ""))
end

local workingDirectory

local function cwd()
  if workingDirectory then return workingDirectory end

  local buffer = ffi.new("char[?]", 4096)
  if WINDOWS then
    local written = ffi.C.GetCurrentDirectoryA(4096, buffer)
    workingDirectory = written > 0 and normalize(ffi.string(buffer, written)) or "."
  else
    workingDirectory = ffi.C.getcwd(buffer, 4096) ~= nil and
      normalize(ffi.string(buffer)) or "."
  end
  return workingDirectory
end

local function isAbsolute(path)
  path = normalize(path)
  return path:match("^%a:/") ~= nil or path:sub(1, 1) == "/"
end

function appPaths.absolute(path)
  path = normalize(path)
  if path == "" or path == "." then return cwd() end
  if isAbsolute(path) then return path end
  return cwd() .. "/" .. path
end

-- mkdir -p. The single-level version silently did nothing when an intermediate
-- directory was missing, and the caller only found out when the file write
-- failed several frames later.
function appPaths.ensureDirectory(path)
  path = normalize(path)
  local cursor = path:match("^%a:") and 3 or (path:sub(1, 1) == "/" and 2 or 1)

  while true do
    local separator = path:find("/", cursor, true)
    local segment = separator and path:sub(1, separator - 1) or path
    if #segment > 0 then
      if WINDOWS then
        ffi.C._mkdir((segment:gsub("/", "\\")))
      else
        ffi.C.mkdir(segment, tonumber("755", 8))
      end
    end
    if not separator then break end
    cursor = separator + 1
  end

  return path
end

local function exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  -- Directories do not open for reading on every platform, so fall back to the
  -- rename-onto-itself probe.
  return os.rename(path, path) == true
end

appPaths.exists = exists

-- A folder counts as a world directory once it carries either metadata file, so
-- an empty ./saves left behind by an installer does not pin the game to a
-- location it cannot write to.
local function holdsWorlds(root)
  local filesystem = require("filesystem")
  local ok, entries = pcall(filesystem.entries, root)
  if not ok then return false end

  for _, entry in ipairs(entries) do
    if entry.isDirectory and not entry.isReparsePoint then
      local folder = root .. "/" .. entry.name
      if exists(folder .. "/mineLua.json") or exists(folder .. "/level.dat") then
        return true
      end
    end
  end
  return false
end

local dataRoot, saveRoot, portable

-- %APPDATA%\MineLua, or the XDG data directory. Chosen over the install folder
-- because it survives reinstalling, updating, or deleting the game.
local function resolveDataRoot()
  if dataRoot then return dataRoot end

  local base
  if WINDOWS then
    base = os.getenv("APPDATA") or os.getenv("USERPROFILE")
  else
    base = os.getenv("XDG_DATA_HOME")
    if not base then
      local home = os.getenv("HOME")
      base = home and (home .. "/.local/share") or nil
    end
  end

  dataRoot = base and (normalize(base) .. "/MineLua") or appPaths.absolute("userdata")
  return dataRoot
end

-- Portable mode keeps everything beside the executable. It is on when a
-- `portable.txt` marker sits next to the game, and automatically when the
-- working directory already holds worlds -- which is what a development
-- checkout looks like, and means an existing ./saves is never orphaned.
local function resolvePortable()
  if portable ~= nil then return portable end
  portable = exists(appPaths.absolute("portable.txt")) or
    holdsWorlds(appPaths.absolute("saves"))
  return portable
end

function appPaths.portable()
  return resolvePortable()
end

function appPaths.dataRoot()
  if resolvePortable() then
    return appPaths.absolute(".")
  end
  return resolveDataRoot()
end

function appPaths.saveRoot()
  if saveRoot then return saveRoot end

  local override = os.getenv("MINELUA_SAVES")
  if override and #override > 0 then
    saveRoot = appPaths.absolute(override)
  else
    saveRoot = appPaths.dataRoot() .. "/saves"
  end

  appPaths.ensureDirectory(saveRoot)
  return saveRoot
end

-- Writable per-user configuration. A portable install keeps writing beside the
-- game in data/config, which is where a checkout already has it; an installed
-- build writes under the per-user data root instead, and the read side falls
-- back to the packaged copy so existing settings are picked up once.
function appPaths.configPath(name)
  if resolvePortable() then
    return appPaths.legacyConfigPath(name)
  end
  return resolveDataRoot() .. "/config/" .. name
end

function appPaths.legacyConfigPath(name)
  return appPaths.absolute("data/config/" .. name)
end

return appPaths
