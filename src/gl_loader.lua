local ffi = require("ffi")

ffi.cdef[[
void* wglGetProcAddress(const char* name);
void* GetProcAddress(void* hModule, const char* name);
void* GetModuleHandleA(const char* lpModuleName);
]]

local opengl = ffi.load("opengl32.dll")
local kernel32 = ffi.load("kernel32.dll")

local opengl_handle = kernel32.GetModuleHandleA("opengl32.dll")

local function load(name, ret, ...)
  local fn = opengl.wglGetProcAddress(name)
  if fn == nil then
    fn = kernel32.GetProcAddress(opengl_handle, name)
  end
  if fn == nil then
    error("Failed to load GL function: " .. name)
  end
  return ffi.cast(ret .. "(*)(" .. table.concat({...}, ",") .. ")", fn)
end

return { load = load }
