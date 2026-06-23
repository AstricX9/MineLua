local ffi = require("ffi")
local GL = require("gl")

local shader = {}

local gl = GL.gl

local GL_VERTEX_SHADER = 0x8B31
local GL_FRAGMENT_SHADER = 0x8B30
local GL_COMPILE_STATUS = 0x8B81

local function readFile(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

local function compile(shaderType, source)
  local id = gl.glCreateShader(shaderType)
  local sourcePtr = ffi.new("const char*[1]", {[0] = source})

  gl.glShaderSource(id, 1, sourcePtr, nil)
  gl.glCompileShader(id)

  local status = ffi.new("int[1]")
  gl.glGetShaderiv(id, GL_COMPILE_STATUS, status)
  if status[0] == 0 then
    local log = ffi.new("char[512]")
    gl.glGetShaderInfoLog(id, 512, nil, log)
    error("Shader compilation failed: " .. ffi.string(log))
  end

  return id
end

function shader.fromSource(vertexSource, fragmentSource)
  local vertexShader = compile(GL_VERTEX_SHADER, vertexSource)
  local fragmentShader = compile(GL_FRAGMENT_SHADER, fragmentSource)

  local program = gl.glCreateProgram()
  gl.glAttachShader(program, vertexShader)
  gl.glAttachShader(program, fragmentShader)
  gl.glLinkProgram(program)

  return program
end

function shader.load(vertexPath, fragmentPath)
  return shader.fromSource(readFile(vertexPath), readFile(fragmentPath))
end

return shader
