local ffi = require("ffi")
local glfw = require("glfw")
local gl = require("gl")

local GL_COLOR_BUFFER_BIT = 0x00004000


if glfw.glfwInit() == 0 then
  error("Failed to init GLFW")
end

local window = glfw.glfwCreateWindow(1280, 720, "MineLua", nil, nil)
if window == nil then
  error("Failed to create window")
end

glfw.glfwMakeContextCurrent(window)

while glfw.glfwWindowShouldClose(window) == 0 do
  gl.glClearColor(0.1, 0.2, 0.3, 1.0)
  gl.glClear(GL_COLOR_BUFFER_BIT)

  glfw.glfwSwapBuffers(window)
  glfw.glfwPollEvents()
end


glfw.glfwTerminate()
