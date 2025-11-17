local ffi = require("ffi")
local glfw = require("glfw")

if glfw.glfwInit() == 0 then
  error("Failed to init GLFW")
end

local window = glfw.glfwCreateWindow(1280, 720, "MineLua", nil, nil)
if window == nil then
  error("Failed to create window")
end

glfw.glfwMakeContextCurrent(window)

while true do
  glfw.glfwPollEvents()
  glfw.glfwSwapBuffers(window)
end

glfw.glfwTerminate()
