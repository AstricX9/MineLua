local ffi = require("ffi")
local Chunk = require("chunk")

local storage = {}

local FORMAT_VERSION = 1
-- Bumped when world generation changes shape. Chunks live under a directory
-- named for this, so an existing world regenerates instead of seaming new
-- terrain against chunks the previous generator wrote.
local GENERATOR_REVISION = 2
local CELL_COUNT = 16 * 256 * 16
local WATER_COLUMN_COUNT = 16 * 16
local NIL_WATER = 0xffff
local saveCounter = 0

if ffi.os == "Windows" then
  ffi.cdef[[
    int _mkdir(const char *dirname);
    int MoveFileExA(const char *existingFileName, const char *newFileName, unsigned long flags);
  ]]
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

local function safePart(value)
  local cleaned = tostring(value or "default"):gsub("[^%w_.-]", "_")
  return cleaned
end

local function signature(options)
  return table.concat({
    "g" .. GENERATOR_REVISION,
    safePart(options.worldId),
    safePart(options.generatorType),
    safePart(string.format("%.17g", tonumber(options.seed) or 1)),
    safePart(options.maxHeight or 127)
  }, "_")
end

local function chunkDirectory(savePath, options)
  return savePath .. "/region/minelua/" .. signature(options)
end

function storage.ensureDirectory(savePath, options)
  if not savePath then return nil end
  mkdir(savePath .. "/region")
  mkdir(savePath .. "/region/minelua")
  local path = chunkDirectory(savePath, options)
  mkdir(path)
  return path
end

function storage.path(savePath, chunkX, chunkZ, options)
  if not savePath then return nil end
  return chunkDirectory(savePath, options) .. string.format("/c.%d.%d.mlc", chunkX, chunkZ)
end

function storage.exists(savePath, chunkX, chunkZ, options)
  local path = storage.path(savePath, chunkX, chunkZ, options)
  if not path then return false end
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

local function u16(value)
  value = math.floor(tonumber(value) or 0) % 65536
  return string.char(value % 256, math.floor(value / 256))
end

local function u32(value)
  value = math.floor(tonumber(value) or 0) % 4294967296
  return string.char(
    value % 256,
    math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256
  )
end

local function readU16(content, offset)
  local a, b = content:byte(offset, offset + 1)
  if not b then return nil end
  return a + b * 256
end

local function readU32(content, offset)
  local a, b, c, d = content:byte(offset, offset + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function adler32(content)
  local a, b = 1, 0
  for index = 1, #content do
    a = (a + content:byte(index)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local function encodeBlocks(chunk)
  local runs = {}
  local current = chunk.blocks[1] or 0
  local count = 1

  for index = 2, CELL_COUNT do
    local id = chunk.blocks[index] or 0
    if id == current and count < 65535 then
      count = count + 1
    else
      runs[#runs + 1] = u16(current) .. u16(count)
      current, count = id, 1
    end
  end
  runs[#runs + 1] = u16(current) .. u16(count)
  return table.concat(runs)
end

local function encodeWater(chunk)
  local columns = {}
  for index = 1, WATER_COLUMN_COUNT do
    local height = chunk.waterSurface and chunk.waterSurface[index]
    columns[index] = u16(height and math.floor(height * 100 + 0.5) or NIL_WATER)
  end
  return table.concat(columns)
end

local function encodeEnvironment(environment)
  local keys = {}
  for key, value in pairs(environment or {}) do
    local kind = type(value)
    if type(key) == "string" and (kind == "string" or kind == "number" or kind == "boolean") then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local encoded = {u16(#keys)}
  for i = 1, #keys do
    local key, value = keys[i], environment[keys[i]]
    local kind = type(value)
    local text = kind == "number" and string.format("%.17g", value) or tostring(value)
    local tag = kind == "number" and 1 or (kind == "boolean" and 2 or 3)
    encoded[#encoded + 1] = u16(#key) .. key .. string.char(tag) .. u16(#text) .. text
  end
  return table.concat(encoded)
end

local function decodeEnvironment(content)
  local count = readU16(content, 1)
  if not count then return nil end
  local result, offset = {}, 3
  for _ = 1, count do
    local keyLength = readU16(content, offset)
    if not keyLength then return nil end
    offset = offset + 2
    local key = content:sub(offset, offset + keyLength - 1)
    offset = offset + keyLength
    local tag = content:byte(offset)
    local valueLength = readU16(content, offset + 1)
    if not tag or not valueLength then return nil end
    offset = offset + 3
    local text = content:sub(offset, offset + valueLength - 1)
    if #text ~= valueLength then return nil end
    offset = offset + valueLength
    if tag == 1 then result[key] = tonumber(text)
    elseif tag == 2 then result[key] = text == "true"
    elseif tag == 3 then result[key] = text
    else return nil end
  end
  if offset ~= #content + 1 then return nil end
  return result
end

local function replaceFile(from, to)
  if ffi.os == "Windows" then
    -- MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    return ffi.C.MoveFileExA(from:gsub("/", "\\"), to:gsub("/", "\\"), 0x9) ~= 0
  end
  return os.rename(from, to) ~= nil
end

function storage.save(savePath, chunkX, chunkZ, chunk, options)
  if not savePath or not chunk then return false, "chunk saving is disabled" end
  options = options or {}
  storage.ensureDirectory(savePath, options)
  local path = storage.path(savePath, chunkX, chunkZ, options)
  local blockData = encodeBlocks(chunk)
  local environmentData = encodeEnvironment(chunk.environment)
  local payload = u32(#blockData) .. blockData .. encodeWater(chunk) ..
    u32(#environmentData) .. environmentData .. u32(options.dataRevision or 0)
  local header = table.concat({
    "MLCHUNK", tostring(FORMAT_VERSION), tostring(GENERATOR_REVISION),
    string.format("%.17g", tonumber(options.seed) or 1),
    tostring(options.maxHeight or 127), tostring(options.generatorType or "default"),
    tostring(options.worldId or "earth"), ""
  }, "\n")

  saveCounter = saveCounter + 1
  local temporary = path .. string.format(".tmp.%d.%d", os.time(), saveCounter)
  local file, err = io.open(temporary, "wb")
  if not file then return false, err end
  file:write(header, u32(adler32(payload)), payload)
  file:flush()
  file:close()

  if not replaceFile(temporary, path) then
    os.remove(temporary)
    return false, "could not atomically install chunk file"
  end
  return true
end

local function headerMatches(file, options)
  return file:read("*l") == "MLCHUNK" and
    tonumber(file:read("*l")) == FORMAT_VERSION and
    tonumber(file:read("*l")) == GENERATOR_REVISION and
    tonumber(file:read("*l")) == (tonumber(options.seed) or 1) and
    tonumber(file:read("*l")) == (tonumber(options.maxHeight) or 127) and
    file:read("*l") == tostring(options.generatorType or "default") and
    file:read("*l") == tostring(options.worldId or "earth")
end

function storage.load(savePath, chunkX, chunkZ, options)
  options = options or {}
  local path = storage.path(savePath, chunkX, chunkZ, options)
  if not path then return nil end
  local file = io.open(path, "rb")
  if not file then return nil end
  if not headerMatches(file, options) then
    file:close()
    return nil, "chunk signature mismatch"
  end

  local checksumBytes = file:read(4)
  local payload = file:read("*a")
  file:close()
  local expected = checksumBytes and readU32(checksumBytes, 1)
  if not expected or adler32(payload) ~= expected then
    return nil, "chunk checksum mismatch"
  end

  local blockLength = readU32(payload, 1)
  if not blockLength or blockLength % 4 ~= 0 or blockLength + 4 + 512 + 4 + 4 > #payload then
    return nil, "invalid chunk length"
  end

  local chunk = Chunk.new()
  local outputIndex = 1
  local offset = 5
  local blockEnd = 4 + blockLength
  while offset <= blockEnd do
    local id = readU16(payload, offset)
    local count = readU16(payload, offset + 2)
    if not id or not count or count == 0 or outputIndex + count - 1 > CELL_COUNT then
      return nil, "invalid chunk run"
    end
    if id ~= 0 then
      for index = outputIndex, outputIndex + count - 1 do chunk.blocks[index] = id end
    end
    outputIndex = outputIndex + count
    offset = offset + 4
  end
  if outputIndex ~= CELL_COUNT + 1 then return nil, "incomplete chunk data" end

  chunk.waterSurface = {}
  for index = 1, WATER_COLUMN_COUNT do
    local encoded = readU16(payload, offset)
    if not encoded then return nil, "incomplete water data" end
    if encoded ~= NIL_WATER then chunk.waterSurface[index] = encoded / 100 end
    offset = offset + 2
  end
  local environmentLength = readU32(payload, offset)
  if not environmentLength or offset + 4 + environmentLength + 4 - 1 ~= #payload then
    return nil, "invalid environment data length"
  end
  offset = offset + 4
  chunk.environment = decodeEnvironment(payload:sub(offset, offset + environmentLength - 1))
  if not chunk.environment then return nil, "invalid environment data" end
  offset = offset + environmentLength
  local dataRevision = readU32(payload, offset) or 0
  return chunk, nil, dataRevision
end

function storage.options(world, extra)
  return {
    seed = world.seed,
    maxHeight = world.maxHeight,
    generatorType = world.generatorType,
    worldId = world.worldId,
    dataRevision = extra and extra.dataRevision or 0
  }
end

return storage
