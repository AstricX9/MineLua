local ffi = require("ffi")
local glfw = require("glfw")

local GL_COLOR_BUFFER_BIT = 0x00004000

-- Init GLFW
if glfw.glfwInit() == 0 then
  error("Failed to init GLFW")
end

-- Request OpenGL 3.3 core
glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3)
glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3)
glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE)

-- Create window
local window = glfw.glfwCreateWindow(1280, 720, "MineLua", nil, nil)
if window == nil then
  error("Failed to create window")
end

-- Activate context
glfw.glfwMakeContextCurrent(window)

-- Load GL after context is ready
local GL = require("gl")
local gl = GL.gl
GL.loadModernGL()

-- Set viewport
gl.glViewport(0, 0, 1280, 720)

-- [IMPORTANT FIX]
-- Create VAO (REQUIRED in core profile!)
local vao = ffi.new("GLuint[1]")
gl.glGenVertexArrays(1, vao)
gl.glBindVertexArray(vao[0])

-- Triangle vertices
local vertices = ffi.new("float[9]", {
   0.0,  0.5, 0.0,
  -0.5, -0.5, 0.0,
   0.5, -0.5, 0.0
})

-- Create VBO
local vbo = ffi.new("GLuint[1]")
gl.glGenBuffers(1, vbo)
gl.glBindBuffer(0x8892, vbo[0]) -- GL_ARRAY_BUFFER
gl.glBufferData(0x8892, ffi.sizeof(vertices), vertices, 0x88E4) -- GL_STATIC_DRAW

-- Vertex shader
local vertSource = ffi.new("const char*[1]", {
[[
#version 330 core
layout (location = 0) in vec3 aPos;
void main() {
  gl_Position = vec4(aPos, 1.0);
}
]]
})

local vert = gl.glCreateShader(0x8B31)
gl.glShaderSource(vert, 1, vertSource, nil)
gl.glCompileShader(vert)

-- Fragment shader
local fragSource = ffi.new("const char*[1]", {
[[
#version 330 core
out vec4 FragColor;
void main() {
  FragColor = vec4(1.0, 0.5, 0.2, 1.0);
}
]]
})

local frag = gl.glCreateShader(0x8B30)
gl.glShaderSource(frag, 1, fragSource, nil)
gl.glCompileShader(frag)

-- Shader program
local shader = gl.glCreateProgram()
gl.glAttachShader(shader, vert)
gl.glAttachShader(shader, frag)
gl.glLinkProgram(shader)
gl.glUseProgram(shader)

-- Vertex attrib pointer
gl.glVertexAttribPointer(
  0,
  3,
  0x1406, -- GL_FLOAT
  0,
  3 * 4,
  nil
)
gl.glEnableVertexAttribArray(0)

-- Main loop
while glfw.glfwWindowShouldClose(window) == 0 do
  gl.glClearColor(0.1, 0.2, 0.3, 1.0)
  gl.glClear(GL_COLOR_BUFFER_BIT)

  gl.glDrawArrays(0x0004, 0, 3) -- GL_TRIANGLES

  glfw.glfwSwapBuffers(window)
  glfw.glfwPollEvents()
end

glfw.glfwTerminate()
