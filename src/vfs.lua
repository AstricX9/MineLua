-- Read-only virtual filesystem over the packed release container.
--
-- A source checkout never mounts anything: every entry point below answers
-- nil/false while unmounted, so the game runs the same code whether it reads
-- loose files from the working tree or entries out of a shipped container.
--
-- The container is XOR-streamed with a key that travels inside the launcher
-- bytecode. That is obfuscation, not protection -- anyone willing to read the
-- bytecode recovers the key. It exists to keep assets out of casual reach
-- (archive browsers, `strings`, thumbnailers, drag-and-drop rippers), which is
-- the only promise a client-side container can honestly make.
--
-- Container layout, all integers little endian:
--
--   0   4   magic "MLPK"
--   4   4   format version
--   8   4   salt low word
--   12  4   salt high word
--   16  4   encrypted index length
--   20  4   entry count
--   24  n   index blob, encrypted with nonce INDEX_NONCE
--   ..      payload region, every entry encrypted with its own offset as nonce
--
-- Index blob, repeated `entry count` times:
--
--   u16 path length | path bytes | u32 offset | u32 length | u8 flags
--
-- Per-entry nonces matter: recovering one entry's keystream by guessing its
-- plaintext (a PNG header, say) reveals nothing about its neighbours.

local ffi = require("ffi")
local bit = require("bit")

local vfs = {}

vfs.MAGIC = "MLPK"
vfs.VERSION = 1
vfs.HEADER_BYTES = 24
vfs.FLAG_RAW = 0

local INDEX_NONCE = 0xA5A5A5A5

-- Captured before install() replaces io.open, so the container itself is
-- always read through the real one and mounting can never recurse.
local rawOpen = io.open

local mounted = nil

--------------------------------------------------------------------------
-- Cipher
--------------------------------------------------------------------------

-- Shifts and xors only. Multiplying two 32-bit values in Lua would round off
-- the low bits through the double mantissa, and the packer and the runtime
-- have to agree on every bit.
local function scramble(value)
  value = bit.bxor(value, bit.lshift(value, 13))
  value = bit.bxor(value, bit.rshift(value, 17))
  value = bit.bxor(value, bit.lshift(value, 5))
  return value
end

local function deriveState(key, salt0, salt1, nonce)
  local s0 = scramble(bit.bxor(key[1], nonce))
  local s1 = scramble(bit.bxor(key[2], salt0, bit.rol(nonce, 7)))
  local s2 = scramble(bit.bxor(key[3], salt1, bit.rol(nonce, 15)))
  local s3 = scramble(bit.bxor(key[4], bit.rol(nonce, 23), 0x9E3779B9))
  -- xorshift128 latches up on the all-zero state.
  if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then s0 = 0x6D2B79F5 end
  return s0, s1, s2, s3
end

-- Encrypts and decrypts in place: the keystream is symmetric.
function vfs.crypt(buffer, length, key, salt0, salt1, nonce)
  local s0, s1, s2, s3 = deriveState(key, salt0, salt1, nonce)
  local words = ffi.cast("uint32_t *", buffer)
  local wordCount = bit.rshift(length, 2)

  for index = 0, wordCount - 1 do
    local t = bit.bxor(s3, bit.lshift(s3, 11))
    t = bit.bxor(t, bit.rshift(t, 8))
    s3, s2, s1 = s2, s1, s0
    s0 = bit.bxor(t, s0, bit.rshift(s0, 19))
    words[index] = bit.bxor(words[index], s0)
  end

  local tail = length - wordCount * 4
  if tail > 0 then
    local t = bit.bxor(s3, bit.lshift(s3, 11))
    t = bit.bxor(t, bit.rshift(t, 8))
    s0 = bit.bxor(t, s0, bit.rshift(s0, 19))
    local bytes = ffi.cast("uint8_t *", buffer) + wordCount * 4
    for index = 0, tail - 1 do
      bytes[index] = bit.bxor(bytes[index], bit.band(bit.rshift(s0, index * 8), 0xFF))
    end
  end
end

-- String front end for the packer and for small runtime reads.
function vfs.cryptString(data, key, salt0, salt1, nonce)
  local length = #data
  if length == 0 then return data end
  local buffer = ffi.new("uint8_t[?]", length)
  ffi.copy(buffer, data, length)
  vfs.crypt(buffer, length, key, salt0, salt1, nonce)
  return ffi.string(buffer, length)
end

--------------------------------------------------------------------------
-- Binary helpers
--------------------------------------------------------------------------

local function packU32(value)
  return string.char(
    bit.band(value, 0xFF),
    bit.band(bit.rshift(value, 8), 0xFF),
    bit.band(bit.rshift(value, 16), 0xFF),
    bit.band(bit.rshift(value, 24), 0xFF))
end

local function packU16(value)
  return string.char(bit.band(value, 0xFF), bit.band(bit.rshift(value, 8), 0xFF))
end

-- Unsigned, so offsets past 2 GiB stay positive.
local function readU32(data, at)
  local a, b, c, d = data:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function readU16(data, at)
  local a, b = data:byte(at, at + 1)
  if not b then return nil end
  return a + b * 256
end

vfs.packU32, vfs.packU16 = packU32, packU16
vfs.readU32, vfs.readU16 = readU32, readU16

--------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------

-- Container paths are stored project-relative with forward slashes. Lookups
-- fold case because the game asks for assets in whatever spelling a JSON file
-- happens to use, and Windows has always let that slide.
local function normalize(path)
  if type(path) ~= "string" then return nil end
  path = path:gsub("\\", "/")
  path = path:gsub("^%./", "")
  path = path:gsub("//+", "/")
  path = path:gsub("/+$", "")
  return path
end

vfs.normalize = normalize

local function lookupKey(path)
  local clean = normalize(path)
  return clean and clean:lower() or nil
end

--------------------------------------------------------------------------
-- Index
--------------------------------------------------------------------------

function vfs.encodeIndex(entries)
  local parts = {}
  for i = 1, #entries do
    local entry = entries[i]
    parts[#parts + 1] = packU16(#entry.path) .. entry.path ..
      packU32(entry.offset) .. packU32(entry.length) ..
      string.char(entry.flags or vfs.FLAG_RAW)
  end
  return table.concat(parts)
end

function vfs.decodeIndex(blob, count)
  local entries = {}
  local at = 1
  for _ = 1, count do
    local pathLength = readU16(blob, at)
    if not pathLength then return nil, "truncated index" end
    local path = blob:sub(at + 2, at + 1 + pathLength)
    if #path ~= pathLength then return nil, "truncated index" end
    local offset = readU32(blob, at + 2 + pathLength)
    local length = readU32(blob, at + 6 + pathLength)
    local flags = blob:byte(at + 10 + pathLength)
    if not flags then return nil, "truncated index" end
    entries[#entries + 1] = {path = path, offset = offset, length = length, flags = flags}
    at = at + 11 + pathLength
  end
  return entries
end

--------------------------------------------------------------------------
-- Mounting
--------------------------------------------------------------------------

local function buildTree(entries)
  local files, directories = {}, {}

  local function ensureDirectory(path)
    if directories[path] then return directories[path] end
    local listing = {}
    directories[path] = listing
    if path ~= "" then
      local parent, name = path:match("^(.*)/([^/]+)$")
      if not parent then parent, name = "", path end
      ensureDirectory(parent)[name:lower()] = {name = name, isDirectory = true}
    end
    return listing
  end

  ensureDirectory("")
  for i = 1, #entries do
    local entry = entries[i]
    files[entry.path:lower()] = entry
    local parent, name = entry.path:match("^(.*)/([^/]+)$")
    if not parent then parent, name = "", entry.path end
    ensureDirectory(parent:lower())[name:lower()] = {name = name, isDirectory = false}
  end

  return files, directories
end

-- `containerKey` is four 32-bit words. Returns true, or false plus a reason.
function vfs.mount(path, containerKey)
  local handle = rawOpen(path, "rb")
  if not handle then return false, "container not found: " .. tostring(path) end

  local header = handle:read(vfs.HEADER_BYTES)
  if not header or #header < vfs.HEADER_BYTES or header:sub(1, 4) ~= vfs.MAGIC then
    handle:close()
    return false, "not a MineLua container: " .. tostring(path)
  end
  if readU32(header, 5) ~= vfs.VERSION then
    handle:close()
    return false, "unsupported container version"
  end

  local salt0, salt1 = readU32(header, 9), readU32(header, 13)
  local indexLength, entryCount = readU32(header, 17), readU32(header, 21)
  local blob = indexLength > 0 and handle:read(indexLength) or ""
  if #blob ~= indexLength then
    handle:close()
    return false, "container index is truncated"
  end

  local entries, err = vfs.decodeIndex(
    vfs.cryptString(blob, containerKey, salt0, salt1, INDEX_NONCE), entryCount)
  if not entries then
    handle:close()
    return false, err or "container index is unreadable"
  end

  local files, directories = buildTree(entries)
  mounted = {
    path = path,
    handle = handle,
    key = containerKey,
    salt0 = salt0,
    salt1 = salt1,
    files = files,
    directories = directories,
    count = #entries
  }
  return true
end

function vfs.unmount()
  if mounted then
    mounted.handle:close()
    mounted = nil
  end
end

function vfs.isMounted()
  return mounted ~= nil
end

function vfs.count()
  return mounted and mounted.count or 0
end

--------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------

local function find(path)
  if not mounted then return nil end
  local key = lookupKey(path)
  return key and mounted.files[key] or nil
end

function vfs.exists(path)
  return find(path) ~= nil
end

function vfs.isDirectory(path)
  if not mounted then return false end
  local key = lookupKey(path)
  return key ~= nil and mounted.directories[key] ~= nil
end

-- Returns the decrypted bytes, or nil when the container holds no such entry.
function vfs.read(path)
  local entry = find(path)
  if not entry then return nil end
  if entry.length == 0 then return "" end

  mounted.handle:seek("set", entry.offset)
  local stored = mounted.handle:read(entry.length)
  if not stored or #stored ~= entry.length then return nil end
  return vfs.cryptString(stored, mounted.key, mounted.salt0, mounted.salt1, entry.offset)
end

-- Every packed path, sorted. Only the unpack tool needs this; the game walks
-- directories through filesystem.entries instead.
function vfs.list()
  local paths = {}
  if not mounted then return paths end
  for _, entry in pairs(mounted.files) do paths[#paths + 1] = entry.path end
  table.sort(paths)
  return paths
end

-- Directory listing in the shape src/filesystem.lua hands out.
function vfs.entries(path)
  local listing = {}
  if not mounted then return listing end
  local children = mounted.directories[lookupKey(path) or ""]
  if not children then return listing end
  for _, child in pairs(children) do
    listing[#listing + 1] = {
      name = child.name,
      isDirectory = child.isDirectory,
      isReparsePoint = false
    }
  end
  table.sort(listing, function(a, b) return a.name:lower() < b.name:lower() end)
  return listing
end

--------------------------------------------------------------------------
-- Virtual file handles
--------------------------------------------------------------------------

-- Enough of the io file interface for the call sites the game actually uses:
-- read("*a"), read("*l"), read(n), seek, lines, close. Writes are refused --
-- everything the game writes (saves, caches, screenshots) lives outside the
-- container and reaches the real io.open untouched.
local VirtualFile = {}
VirtualFile.__index = VirtualFile

local function readFormat(self, format)
  if type(format) == "number" then
    if format == 0 then return self.at > #self.data and nil or "" end
    if self.at > #self.data then return nil end
    local chunk = self.data:sub(self.at, self.at + format - 1)
    self.at = self.at + #chunk
    return chunk
  end

  format = tostring(format):gsub("^%*", "")
  local kind = format:sub(1, 1)
  if kind == "a" then
    local chunk = self.data:sub(self.at)
    self.at = #self.data + 1
    return chunk
  elseif kind == "l" or kind == "L" then
    if self.at > #self.data then return nil end
    local stop = self.data:find("\n", self.at, true)
    local line
    if stop then
      line = self.data:sub(self.at, kind == "L" and stop or stop - 1)
      self.at = stop + 1
    else
      line = self.data:sub(self.at)
      self.at = #self.data + 1
    end
    return (line:gsub("\r$", ""))
  elseif kind == "n" then
    local number, stop = self.data:match("^%s*(%-?%d+%.?%d*)()", self.at)
    if not number then return nil end
    self.at = stop
    return tonumber(number)
  end
  error("unsupported read format: " .. tostring(format), 2)
end

function VirtualFile:read(...)
  if self.closed then return nil, "file is closed" end
  local count = select("#", ...)
  if count == 0 then return readFormat(self, "*l") end
  local results = {}
  for index = 1, count do
    results[index] = readFormat(self, (select(index, ...)))
  end
  return unpack(results, 1, count)
end

function VirtualFile:lines(...)
  local formats = {...}
  return function()
    return readFormat(self, formats[1] or "*l")
  end
end

function VirtualFile:seek(whence, offset)
  whence, offset = whence or "cur", offset or 0
  if whence == "set" then
    self.at = offset + 1
  elseif whence == "cur" then
    self.at = self.at + offset
  elseif whence == "end" then
    self.at = #self.data + 1 + offset
  else
    return nil, "invalid whence"
  end
  if self.at < 1 then self.at = 1 end
  return self.at - 1
end

function VirtualFile:close()
  self.closed = true
  return true
end

function VirtualFile:write()
  return nil, "container entries are read only"
end

function VirtualFile:setvbuf()
  return true
end

function VirtualFile:flush()
  return self
end

function vfs.handle(data)
  return setmetatable({data = data, at = 1, closed = false}, VirtualFile)
end

--------------------------------------------------------------------------
-- Shims
--------------------------------------------------------------------------

local installed = false

-- Container entries stand in only where the working tree has nothing. Loose
-- files keep winning, which is what lets a player drop a replacement texture
-- next to the executable and lets a developer bisect a packed build.
local function openShim(path, mode)
  mode = mode or "r"
  if mode:find("[wa+]") then return rawOpen(path, mode) end

  local file, err, code = rawOpen(path, mode)
  if file then return file end

  local data = vfs.read(path)
  if data then return vfs.handle(data) end
  return nil, err or (tostring(path) .. ": No such file or directory"), code or 2
end

-- Modules resolve to `src/<name>.lua` inside the container, matching the
-- LUA_PATH the launcher sets for a loose build.
local function moduleLoader(name)
  local base = "src/" .. name:gsub("%.", "/")
  local candidates = {base .. ".lua", base .. "/init.lua"}
  for i = 1, #candidates do
    local chunk = vfs.read(candidates[i])
    if chunk then
      local loaded, err = loadstring(chunk, "@" .. candidates[i])
      if not loaded then error(err, 0) end
      return loaded
    end
  end
  return "\n\tno container entry '" .. base .. ".lua'"
end

function vfs.install()
  if installed then return end
  installed = true
  io.open = openShim
  -- Whoever installs the shims owns the mount, so make every later
  -- require("vfs") reach this instance rather than a second, unmounted copy
  -- out of the container.
  package.loaded["vfs"] = vfs
  -- After package.preload, before the loose-file searcher: a working tree
  -- copy of a module should still shadow the packed one during debugging.
  table.insert(package.loaders, 2, moduleLoader)
end

function vfs.isInstalled()
  return installed
end

return vfs
