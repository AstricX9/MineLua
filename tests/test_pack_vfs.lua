package.path = "src/?.lua;" .. package.path

local packer = dofile("scripts/obfuscate/pack.lua")
local vfs = require("vfs")

local ROOT = "build/test-pack/tree"
local OUT = "build/test-pack/package"
local MARKER = "canary_2f8c1ae6"

local function write(path, data)
  packer.ensureDirectory(path:match("^(.*)/[^/]*$"))
  local file = assert(io.open(path, "wb"))
  file:write(data)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

-- A miniature project: one module, one nested asset, one directory the packer
-- is told to leave loose.
write(ROOT .. "/src/packed_probe.lua",
  "local M = {}\nfunction M.marker() return \"" .. MARKER .. "\" end\nreturn M\n")
write(ROOT .. "/src/main.lua", "return true\n")
write(ROOT .. "/src/chunk_worker.lua", "return true\n")
-- The stubs inline whatever vfs the tree carries, exactly as a release does.
write(ROOT .. "/src/vfs.lua", read("src/vfs.lua"))
write(ROOT .. "/assets/textures/block/" .. MARKER .. ".png", string.rep("\137PNG\r\n\26\n", 64))
write(ROOT .. "/data/minecraft/block/index.json", "[\"air\",\"" .. MARKER .. "\"]")
write(ROOT .. "/data/config/settings.json", "{\"loose\":true}")

local key = packer.parseKey("0123456789abcdef0123456789abcdef")
local summary = assert(packer.build({root = ROOT, out = OUT, key = key, quiet = true}))

assert(summary.luaModules == 4, "every module under src/ should be packed")
assert(summary.assets == 2, "data/config should stay loose, the rest should pack")

-- Nothing readable may survive in the container: not the payloads, not the
-- paths in the index. This is the assertion the whole exercise exists for.
local container = read(OUT .. "/lib/minelua.pak")
assert(not container:find(MARKER, 1, true), "plaintext leaked into the container")
assert(not container:find("PNG", 1, true), "PNG headers leaked into the container")
assert(not container:find("index.json", 1, true), "index paths leaked into the container")
assert(container:sub(1, 4) == "MLPK", "container header should be intact")

-- The entry points ship as stripped bytecode, and the key is not sitting in
-- them as a contiguous run of bytes.
local stub = read(OUT .. "/src/main.lua")
assert(stub:sub(1, 3) == "\27LJ", "the launcher stub should be LuaJIT bytecode")
assert(not stub:find("vfs.mount", 1, true), "the stub should carry no source text")
assert(not stub:find("\1\35\69\103", 1, true), "the container key should not be stored verbatim")

assert(vfs.mount(OUT .. "/lib/minelua.pak", key))

assert(vfs.exists("data/minecraft/block/index.json"), "packed entries should be found")
assert(vfs.exists("DATA/Minecraft/Block/Index.JSON"), "lookups should fold case")
assert(vfs.exists("./data/minecraft/block/index.json"), "lookups should normalize paths")
assert(not vfs.exists("data/config/settings.json"), "excluded paths should not be packed")
assert(vfs.read("data/minecraft/block/index.json") == "[\"air\",\"" .. MARKER .. "\"]",
  "a packed entry should decrypt back to its source bytes")
assert(#vfs.read("assets/textures/block/" .. MARKER .. ".png") == 64 * 8,
  "binary entries should round trip at full length")

-- Directory walking has to work off the index, because the packaged build has
-- no assets/ or data/ trees on disk at all.
local names = {}
for _, entry in ipairs(vfs.entries("data/minecraft/block")) do
  names[#names + 1] = entry.name .. (entry.isDirectory and "/" or "")
end
assert(table.concat(names, ",") == "index.json", "container directory listing is wrong")

local roots = {}
for _, entry in ipairs(vfs.entries("assets")) do roots[#roots + 1] = entry.name end
assert(table.concat(roots, ",") == "textures", "intermediate directories should be synthesized")
assert(vfs.isDirectory("assets/textures/block"), "nested directories should be known")

-- Partial reads, seeks and line reads, the shapes the game asks for.
local handle = vfs.handle("first\nsecond\nthird")
assert(handle:read("*l") == "first")
assert(handle:read(3) == "sec")
assert(handle:read("*a") == "ond\nthird")
assert(handle:read("*a") == "")
assert(handle:seek("set", 0) == 0)
assert(handle:read("*l") == "first")
assert(select(2, handle:write("x")) == "container entries are read only")

vfs.install()

-- After install(), a packed entry stands in where the working tree has no
-- file, and a working tree file still wins where it does. The project's own
-- data/minecraft/block/index.json is the loose one here: the container's copy
-- of that path carries the marker, and the disk copy does not.
local packedFile = assert(io.open("assets/textures/block/" .. MARKER .. ".png", "rb"),
  "io.open should fall through to the container")
assert(#packedFile:read("*a") == 64 * 8, "the container copy should be served whole")
packedFile:close()

local shadowed = assert(io.open("data/minecraft/block/index.json", "r"))
local shadowedText = shadowed:read("*a")
shadowed:close()
assert(not shadowedText:find(MARKER, 1, true), "a loose file must shadow the packed entry")

local loose = assert(io.open("build/test-pack/loose.txt", "wb"))
loose:write("on disk")
loose:close()
local reopened = assert(io.open("build/test-pack/loose.txt", "r"))
assert(reopened:read("*a") == "on disk", "writes and loose reads must bypass the container")
reopened:close()
assert(io.open("build/test-pack/nothing-here.txt", "rb") == nil,
  "a missing file should still be missing")

assert(require("packed_probe").marker() == MARKER,
  "modules should load as bytecode out of the container")

vfs.unmount()
assert(not vfs.isMounted() and not vfs.exists("data/minecraft/block/index.json"),
  "an unmounted container should answer nothing")

print("pack/vfs round trip ok")
