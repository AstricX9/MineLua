-- Builds the obfuscated release container.
--
-- Takes a working tree and produces a package that carries no readable Lua
-- source and no loose assets: every module is stripped LuaJIT bytecode and
-- every texture, sound, model, shader and JSON definition lives inside one
-- encrypted container that src/vfs.lua mounts at startup.
--
-- Usage (from the project root):
--
--   lib\luajit.exe scripts\obfuscate\pack.lua --root . --out build\public\MineLua
--
-- The launcher still starts src\main.lua, but that file is now a bytecode stub
-- that mounts the container, installs the filesystem shims and hands control to
-- the packed `main` module. src\chunk_worker.lua gets the same treatment so the
-- worker processes the chunk pipeline spawns keep working.
--
-- What this does and does not buy you is spelled out in docs/obfuscation.md:
-- the key ships with the game, so this raises the cost of ripping assets and
-- reading the source, and nothing more.

local scriptDirectory = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = table.concat({
  scriptDirectory .. "/../../src/?.lua",
  "src/?.lua",
  package.path
}, ";")

local ffi = require("ffi")
local bit = require("bit")
local vfs = require("vfs")
local filesystem = require("filesystem")

local packer = {}

local WINDOWS = ffi.os == "Windows"

if WINDOWS then
  ffi.cdef[[
    int CreateDirectoryA(const char *pathName, void *securityAttributes);
    int SystemFunction036(void *buffer, unsigned long length);
  ]]
end

--------------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------------

local function normalize(path)
  return (tostring(path):gsub("\\", "/"):gsub("//+", "/"):gsub("/+$", ""))
end

local function join(base, leaf)
  if base == "" or base == "." then return normalize(leaf) end
  return normalize(base) .. "/" .. normalize(leaf)
end

-- Container paths are always project relative, whether the build ran from the
-- project root or handed the packer an absolute --root.
local function relativize(path, root)
  path = normalize(path)
  if root == "" or root == "." then return path end
  local prefix = normalize(root) .. "/"
  if path:lower():sub(1, #prefix) == prefix:lower() then return path:sub(#prefix + 1) end
  return path
end

local function ensureDirectory(path)
  path = normalize(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do parts[#parts + 1] = part end

  local prefix = path:sub(1, 1) == "/" and "/" or ""
  local built = prefix
  for index = 1, #parts do
    built = built == "" and parts[index] or (built == "/" and "/" .. parts[index] or built .. "/" .. parts[index])
    -- A drive letter on its own ("G:") is not a directory anyone can create.
    if not built:match("^%a:$") then
      if WINDOWS then
        ffi.C.CreateDirectoryA(built:gsub("/", "\\"), nil)
      else
        os.execute('mkdir -p "' .. built .. '" 2>/dev/null')
      end
    end
  end
end

packer.ensureDirectory = ensureDirectory

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

local function writeFile(path, data)
  ensureDirectory(path:match("^(.*)/[^/]*$") or ".")
  local file, err = io.open(path, "wb")
  if not file then return nil, err end
  file:write(data)
  file:close()
  return true
end

local function fileSize(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size
end

--------------------------------------------------------------------------
-- Key material
--------------------------------------------------------------------------

-- RtlGenRandom on Windows, and a mix of clock, allocator addresses and the
-- interpreter's own randomness elsewhere. The fallback is not cryptographic;
-- it only needs to make two builds differ.
local function randomWords(count)
  local words = {}

  if WINDOWS then
    -- RtlGenRandom, which advapi32 still exports under its old ordinal name.
    local loaded, advapi = pcall(ffi.load, "advapi32")
    if loaded then
      local buffer = ffi.new("uint32_t[?]", count)
      local ok, filled = pcall(function() return advapi.SystemFunction036(buffer, count * 4) end)
      if ok and filled ~= 0 then
        for index = 1, count do words[index] = tonumber(buffer[index - 1]) end
        return words
      end
    end
  end

  math.randomseed(os.time() + math.floor(os.clock() * 1000000) +
    tonumber(tostring({}):match("0x(%x+)") or "0", 16))
  for index = 1, count do
    words[index] = bit.bxor(math.random(0, 0xFFFF) * 0x10000 + math.random(0, 0xFFFF),
      math.floor(os.clock() * 1000000))
  end
  return words
end

local function parseKey(text)
  local hex = text:gsub("[^%x]", "")
  if #hex ~= 32 then
    error("--key expects 32 hexadecimal digits (128 bits), got " .. #hex, 0)
  end
  local words = {}
  for index = 1, 4 do
    words[index] = tonumber(hex:sub(index * 8 - 7, index * 8), 16)
  end
  return words
end

local function formatKey(words)
  local parts = {}
  for index = 1, #words do
    parts[index] = string.format("%08x", words[index] % 4294967296)
  end
  return table.concat(parts)
end

packer.randomWords = randomWords
packer.parseKey = parseKey
packer.formatKey = formatKey

--------------------------------------------------------------------------
-- Bytecode
--------------------------------------------------------------------------

-- string.dump(chunk, true) is what `luajit -b -s` writes: no line table, no
-- local names, no upvalue names. String constants survive -- they have to, the
-- interpreter needs them -- so a determined reader still sees texture paths.
function packer.compile(sourcePath, chunkName)
  local chunk, err = loadfile(sourcePath)
  if not chunk then return nil, err end
  return string.dump(chunk, true), nil, chunkName
end

function packer.compileSource(source, chunkName)
  local chunk, err = loadstring(source, chunkName)
  if not chunk then return nil, err end
  return string.dump(chunk, true)
end

--------------------------------------------------------------------------
-- Bootstrap stubs
--------------------------------------------------------------------------

-- The stub carries the container key split across two tables that are xored
-- back together at runtime, so neither half is a usable key on its own.
local function stubSource(vfsSource, containerPath, entryModule, containerKey)
  local mask = randomWords(4)
  local shards = {}
  for index = 1, 4 do
    shards[index] = bit.bxor(containerKey[index], mask[index]) % 4294967296
  end

  local function literals(words)
    local parts = {}
    for index = 1, #words do
      parts[index] = string.format("0x%08X", words[index] % 4294967296)
    end
    return table.concat(parts, ", ")
  end

  return table.concat({
    "package.preload[\"vfs\"] = function(...)",
    vfsSource,
    "end",
    "local bit = require(\"bit\")",
    "local mask = {" .. literals(mask) .. "}",
    "local shards = {" .. literals(shards) .. "}",
    "local containerKey = {}",
    "for index = 1, 4 do containerKey[index] = bit.bxor(mask[index], shards[index]) end",
    "local vfs = require(\"vfs\")",
    "local ok, err = vfs.mount(" .. string.format("%q", containerPath) .. ", containerKey)",
    "if not ok then",
    "  io.stderr:write(\"MineLua data files are missing or damaged: \" .. tostring(err) .. \"\\n\")",
    "  os.exit(9)",
    "end",
    "vfs.install()",
    "return require(" .. string.format("%q", entryModule) .. ")"
  }, "\n")
end

packer.stubSource = stubSource

--------------------------------------------------------------------------
-- Container
--------------------------------------------------------------------------

-- `sources` is a list of {path = "assets/x.png", file = "<disk path>"} or
-- {path = "src/x.lua", data = "<bytes>"}. Returns a summary table.
function packer.writeContainer(containerPath, sources, containerKey, salt)
  table.sort(sources, function(a, b) return a.path < b.path end)

  local entries = {}
  local indexBytes = 0
  for index = 1, #sources do
    local source = sources[index]
    local length = source.data and #source.data or fileSize(source.file)
    if not length then
      return nil, "cannot read " .. tostring(source.file)
    end
    entries[index] = {path = source.path, length = length, flags = vfs.FLAG_RAW, offset = 0}
    indexBytes = indexBytes + 11 + #source.path
  end

  local payloadStart = vfs.HEADER_BYTES + indexBytes
  local cursor = payloadStart
  for index = 1, #entries do
    entries[index].offset = cursor
    cursor = cursor + entries[index].length
  end
  if cursor >= 0xFFFFFFFF then
    return nil, "container would exceed the 4 GiB offset limit"
  end

  ensureDirectory(containerPath:match("^(.*)/[^/]*$") or ".")
  local out, err = io.open(containerPath, "wb")
  if not out then return nil, err end

  out:write(vfs.MAGIC)
  out:write(vfs.packU32(vfs.VERSION))
  out:write(vfs.packU32(salt[1]))
  out:write(vfs.packU32(salt[2]))
  out:write(vfs.packU32(indexBytes))
  out:write(vfs.packU32(#entries))
  out:write(vfs.cryptString(vfs.encodeIndex(entries), containerKey, salt[1], salt[2], 0xA5A5A5A5))

  local payloadBytes = 0
  for index = 1, #sources do
    local source = sources[index]
    local entry = entries[index]
    local data = source.data or readFile(source.file)
    if not data then
      out:close()
      return nil, "cannot read " .. tostring(source.file)
    end
    if #data ~= entry.length then
      out:close()
      return nil, "size changed while packing " .. entry.path
    end
    out:write(vfs.cryptString(data, containerKey, salt[1], salt[2], entry.offset))
    payloadBytes = payloadBytes + #data
  end
  out:close()

  return {
    path = containerPath,
    entries = #entries,
    indexBytes = indexBytes,
    payloadBytes = payloadBytes,
    totalBytes = payloadStart + payloadBytes
  }
end

--------------------------------------------------------------------------
-- Collection
--------------------------------------------------------------------------

local function excluded(path, patterns)
  local lower = path:lower()
  for index = 1, #patterns do
    local prefix = patterns[index]:lower()
    if lower == prefix or lower:sub(1, #prefix + 1) == prefix .. "/" then return true end
  end
  return false
end

function packer.collect(options)
  local root = normalize(options.root or ".")
  local sources = {}
  local luaCount, assetCount, assetBytes = 0, 0, 0

  for _, relative in ipairs(options.luaRoots) do
    for _, path in ipairs(filesystem.files(join(root, relative), ".lua")) do
      local packed = relativize(path, root)
      if not excluded(packed, options.excludes) then
        local bytecode, err = packer.compile(path)
        if not bytecode then
          return nil, "cannot compile " .. packed .. ": " .. tostring(err)
        end
        sources[#sources + 1] = {path = packed, data = bytecode}
        luaCount = luaCount + 1
      end
    end
  end

  for _, relative in ipairs(options.assetRoots) do
    for _, path in ipairs(filesystem.files(join(root, relative))) do
      local packed = relativize(path, root)
      if not excluded(packed, options.excludes) then
        sources[#sources + 1] = {path = packed, file = path}
        assetCount = assetCount + 1
        assetBytes = assetBytes + (fileSize(path) or 0)
      end
    end
  end

  return sources, nil, {luaModules = luaCount, assets = assetCount, assetBytes = assetBytes}
end

--------------------------------------------------------------------------
-- Verification
--------------------------------------------------------------------------

-- Mounts what was just written and compares every entry against its source.
-- A release that silently ships a corrupt container is worse than a build that
-- fails, and the whole point of this stage is that nobody can eyeball the
-- output afterwards.
function packer.verify(containerPath, sources, containerKey)
  vfs.unmount()
  local ok, err = vfs.mount(containerPath, containerKey)
  if not ok then return nil, err end

  if vfs.count() ~= #sources then
    vfs.unmount()
    return nil, string.format("container holds %d entries, expected %d", vfs.count(), #sources)
  end

  for index = 1, #sources do
    local source = sources[index]
    local expected = source.data or readFile(source.file)
    local actual = vfs.read(source.path)
    if not actual then
      vfs.unmount()
      return nil, "missing after packing: " .. source.path
    end
    if actual ~= expected then
      vfs.unmount()
      return nil, "content mismatch after packing: " .. source.path
    end
  end

  vfs.unmount()
  return true
end

--------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------

local DEFAULTS = {
  luaRoots = {"src"},
  assetRoots = {"assets", "data"},
  -- Settings stay loose so players can still edit them, and the launcher
  -- writes into data/cache and saves at runtime.
  excludes = {"data/config"},
  entries = {
    {module = "main", stub = "src/main.lua"},
    {module = "chunk_worker", stub = "src/chunk_worker.lua"}
  },
  container = "lib/minelua.pak"
}

function packer.build(options)
  local root = normalize(options.root or ".")
  local out = normalize(assert(options.out, "packer.build needs an output directory"))
  local settings = {
    root = root,
    luaRoots = options.luaRoots or DEFAULTS.luaRoots,
    assetRoots = options.assetRoots or DEFAULTS.assetRoots,
    excludes = options.excludes or DEFAULTS.excludes,
    entries = options.entries or DEFAULTS.entries,
    container = options.container or DEFAULTS.container
  }
  local containerKey = options.key or randomWords(4)
  local salt = options.salt or randomWords(2)
  local log = options.quiet and function() end or function(...) print(...) end

  local sources, err, counts = packer.collect(settings)
  if not sources then return nil, err end
  log(string.format("packing %d modules and %d assets (%.1f MiB)",
    counts.luaModules, counts.assets, counts.assetBytes / 1048576))

  local containerPath = join(out, settings.container)
  local summary, writeError = packer.writeContainer(containerPath, sources, containerKey, salt)
  if not summary then return nil, writeError end
  log(string.format("wrote %s (%.1f MiB, %d entries)",
    containerPath, summary.totalBytes / 1048576, summary.entries))

  if options.verify ~= false then
    local verified, verifyError = packer.verify(containerPath, sources, containerKey)
    if not verified then return nil, "verification failed: " .. tostring(verifyError) end
    log("verified every entry against its source")
  end

  local vfsSource = readFile(join(root, "src/vfs.lua"))
  if not vfsSource then return nil, "cannot read src/vfs.lua" end

  local stubs = {}
  for _, entry in ipairs(settings.entries) do
    local source = stubSource(vfsSource, settings.container, entry.module, containerKey)
    local bytecode, compileError = packer.compileSource(source, "@minelua")
    if not bytecode then return nil, "cannot compile the " .. entry.module .. " stub: " .. tostring(compileError) end
    local stubPath = join(out, entry.stub)
    local written, stubError = writeFile(stubPath, bytecode)
    if not written then return nil, stubError end
    stubs[#stubs + 1] = {path = stubPath, module = entry.module, bytes = #bytecode}
    log(string.format("wrote %s (%d byte bytecode stub -> %s)", stubPath, #bytecode, entry.module))
  end

  -- Runtime write targets have to exist even though nothing loose ships in
  -- them any more: the cloud noise cache and the save browser both expect a
  -- directory to be there.
  for _, directory in ipairs(options.runtimeDirectories or {"data/cache", "saves"}) do
    ensureDirectory(join(out, directory))
  end

  return {
    container = summary,
    stubs = stubs,
    key = formatKey(containerKey),
    salt = formatKey(salt),
    luaModules = counts.luaModules,
    assets = counts.assets
  }
end

--------------------------------------------------------------------------
-- Command line
--------------------------------------------------------------------------

local function parseArguments(argv)
  local options = {excludes = nil, quiet = false}
  local excludes, index = {}, 1
  while index <= #argv do
    local flag = argv[index]
    local value = argv[index + 1]
    if flag == "--root" then options.root = value index = index + 2
    elseif flag == "--out" then options.out = value index = index + 2
    elseif flag == "--pack" then options.container = value index = index + 2
    elseif flag == "--key" then options.key = parseKey(value) index = index + 2
    elseif flag == "--exclude" then excludes[#excludes + 1] = normalize(value) index = index + 2
    elseif flag == "--no-verify" then options.verify = false index = index + 1
    elseif flag == "--quiet" then options.quiet = true index = index + 1
    else error("unknown option: " .. tostring(flag), 0) end
  end
  if #excludes > 0 then
    options.excludes = {}
    for _, pattern in ipairs(DEFAULTS.excludes) do options.excludes[#options.excludes + 1] = pattern end
    for _, pattern in ipairs(excludes) do options.excludes[#options.excludes + 1] = pattern end
  end
  return options
end

-- Only run the command line when this file is the process entry point, so a
-- test or unpack.lua can pull the functions in without packing anything. The
-- basename has to match exactly: "unpack.lua" ends in "pack.lua" too.
if (arg and arg[0] or ""):match("([^/\\]+)$") == "pack.lua" then
  local options = parseArguments(arg)
  if not options.out then
    io.stderr:write("usage: luajit scripts/obfuscate/pack.lua --out <package root> [--root <project root>]\n")
    os.exit(2)
  end
  local summary, buildError = packer.build(options)
  if not summary then
    io.stderr:write("obfuscation failed: " .. tostring(buildError) .. "\n")
    os.exit(1)
  end
  print(string.format("container key %s salt %s", summary.key, summary.salt))
end

return packer
