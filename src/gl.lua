local ffi = require("ffi")

ffi.cdef[[
void glClearColor(float r, float g, float b, float a);
void glClear(int mask);
]]

-- Windows ships opengl32.dll by default
local gl = ffi.load("opengl32.dll")

return gl
