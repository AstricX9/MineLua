-- Opens a MineLua container built by scripts/obfuscate/pack.lua.
--
-- The key is printed when the release is built and kept next to the archive as
-- <package>.container-key.txt, so a shipped build can be reopened for support
-- work: comparing a player's package against the source it came from, checking
-- that an asset really made it in, or diffing two releases.
--
--   lib\luajit.exe scripts\obfuscate\unpack.lua --pack lib\minelua.pak --key <hex> --list
--   lib\luajit.exe scripts\obfuscate\unpack.lua --pack lib\minelua.pak --key <hex> --out extracted
--
-- Extracted Lua modules come out as LuaJIT bytecode, not source: the container
-- never held the source to begin with.

local scriptDirectory = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = table.concat({
  scriptDirectory .. "/../../src/?.lua",
  "src/?.lua",
  package.path
}, ";")

local packer = dofile(scriptDirectory .. "/pack.lua")
local vfs = require("vfs")

local options = {}
local index = 1
while index <= #arg do
  local flag, value = arg[index], arg[index + 1]
  if flag == "--pack" then options.pack = value index = index + 2
  elseif flag == "--key" then options.key = value index = index + 2
  elseif flag == "--out" then options.out = value index = index + 2
  elseif flag == "--list" then options.list = true index = index + 1
  else
    io.stderr:write("unknown option: " .. tostring(flag) .. "\n")
    os.exit(2)
  end
end

if not options.pack or not options.key or not (options.list or options.out) then
  io.stderr:write("usage: luajit scripts/obfuscate/unpack.lua --pack <file> --key <32 hex> [--list] [--out <dir>]\n")
  os.exit(2)
end

local ok, err = vfs.mount(options.pack, packer.parseKey(options.key))
if not ok then
  io.stderr:write("cannot open container: " .. tostring(err) .. "\n")
  os.exit(1)
end

local paths = vfs.list()
local extracted, bytes = 0, 0
for _, path in ipairs(paths) do
  local data = vfs.read(path)
  if not data then
    io.stderr:write("unreadable entry: " .. path .. "\n")
    os.exit(1)
  end
  bytes = bytes + #data

  if options.list then
    print(string.format("%10d  %s", #data, path))
  end

  if options.out then
    local target = options.out:gsub("\\", "/"):gsub("/+$", "") .. "/" .. path
    packer.ensureDirectory(target:match("^(.*)/[^/]*$"))
    local file = assert(io.open(target, "wb"))
    file:write(data)
    file:close()
    extracted = extracted + 1
  end
end

vfs.unmount()
print(string.format("%d entries, %.1f MiB%s", #paths, bytes / 1048576,
  options.out and (", extracted " .. extracted .. " to " .. options.out) or ""))
