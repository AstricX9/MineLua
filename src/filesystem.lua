local ffi = require("ffi")

local filesystem = {}

if ffi.os == "Windows" then
  ffi.cdef[[
    typedef struct {
      unsigned long dwFileAttributes;
      unsigned long ftCreationTimeLow;
      unsigned long ftCreationTimeHigh;
      unsigned long ftLastAccessTimeLow;
      unsigned long ftLastAccessTimeHigh;
      unsigned long ftLastWriteTimeLow;
      unsigned long ftLastWriteTimeHigh;
      unsigned long nFileSizeHigh;
      unsigned long nFileSizeLow;
      unsigned long dwReserved0;
      unsigned long dwReserved1;
      char cFileName[260];
      char cAlternateFileName[14];
    } MineLuaFileFindDataA;
    void *FindFirstFileA(const char *fileName, MineLuaFileFindDataA *findFileData);
    int FindNextFileA(void *findFile, MineLuaFileFindDataA *findFileData);
    int FindClose(void *findFile);
  ]]
else
  ffi.cdef[[
    typedef struct MineLuaFilesystemDirectory MineLuaFilesystemDirectory;
    typedef struct {
      unsigned long d_ino;
      long d_off;
      unsigned short d_reclen;
      unsigned char d_type;
      char d_name[256];
    } MineLuaFilesystemDirectoryEntry;
    MineLuaFilesystemDirectory *opendir(const char *name);
    MineLuaFilesystemDirectoryEntry *readdir(MineLuaFilesystemDirectory *directory);
    int closedir(MineLuaFilesystemDirectory *directory);
  ]]
end

function filesystem.entries(path)
  local entries = {}

  if ffi.os == "Windows" then
    local data = ffi.new("MineLuaFileFindDataA[1]")
    local handle = ffi.C.FindFirstFileA(((path .. "/*"):gsub("/", "\\")), data)
    if handle == ffi.cast("void *", -1) then return entries end

    repeat
      local name = ffi.string(data[0].cFileName)
      local attributes = tonumber(data[0].dwFileAttributes)
      if name ~= "." and name ~= ".." then
        entries[#entries + 1] = {
          name = name,
          isDirectory = bit.band(attributes, 0x10) ~= 0,
          isReparsePoint = bit.band(attributes, 0x400) ~= 0
        }
      end
    until ffi.C.FindNextFileA(handle, data) == 0
    ffi.C.FindClose(handle)
  else
    local directory = ffi.C.opendir(path)
    if directory == nil then return entries end
    while true do
      local entry = ffi.C.readdir(directory)
      if entry == nil then break end
      local name = ffi.string(entry.d_name)
      if name ~= "." and name ~= ".." then
        entries[#entries + 1] = {
          name = name,
          isDirectory = tonumber(entry.d_type) == 4,
          isReparsePoint = false
        }
      end
    end
    ffi.C.closedir(directory)
  end

  table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  return entries
end

function filesystem.files(root, extension)
  local files = {}
  local suffix = extension and extension:lower() or nil

  local function visit(path)
    for _, entry in ipairs(filesystem.entries(path)) do
      local child = path .. "/" .. entry.name
      if entry.isDirectory and not entry.isReparsePoint then
        visit(child)
      elseif not entry.isDirectory and (not suffix or entry.name:lower():sub(-#suffix) == suffix) then
        files[#files + 1] = child
      end
    end
  end

  visit(root:gsub("[\\/]+$", ""))
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

return filesystem
