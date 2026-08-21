local ffi = require("ffi")
local GL = require("gl")

local shader = {}

local gl = GL.gl

local GL_VERTEX_SHADER = 0x8B31
local GL_FRAGMENT_SHADER = 0x8B30
local GL_COMPUTE_SHADER = 0x91B9
local GL_COMPILE_STATUS = 0x8B81
local GL_LINK_STATUS = 0x8B82
local GL_INFO_LOG_LENGTH = 0x8B84

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
    local logLength = ffi.new("int[1]")
    gl.glGetShaderiv(id, GL_INFO_LOG_LENGTH, logLength)
    local capacity = math.max(tonumber(logLength[0]), 512)
    local log = ffi.new("char[?]", capacity)
    gl.glGetShaderInfoLog(id, capacity, nil, log)
    gl.glDeleteShader(id)
    error("Shader compilation failed: " .. ffi.string(log))
  end

  return id
end

local function link(shaderIds)
  local program = gl.glCreateProgram()
  for _, shaderId in ipairs(shaderIds) do
    gl.glAttachShader(program, shaderId)
  end
  gl.glLinkProgram(program)

  local status = ffi.new("int[1]")
  gl.glGetProgramiv(program, GL_LINK_STATUS, status)
  for _, shaderId in ipairs(shaderIds) do
    gl.glDeleteShader(shaderId)
  end

  if status[0] == 0 then
    local logLength = ffi.new("int[1]")
    gl.glGetProgramiv(program, GL_INFO_LOG_LENGTH, logLength)
    local capacity = math.max(tonumber(logLength[0]), 512)
    local log = ffi.new("char[?]", capacity)
    gl.glGetProgramInfoLog(program, capacity, nil, log)
    gl.glDeleteProgram(program)
    error("Shader link failed: " .. ffi.string(log))
  end

  return program
end

function shader.fromSource(vertexSource, fragmentSource)
  return link({
    compile(GL_VERTEX_SHADER, vertexSource),
    compile(GL_FRAGMENT_SHADER, fragmentSource)
  })
end

function shader.fromComputeSource(computeSource)
  return link({compile(GL_COMPUTE_SHADER, computeSource)})
end

function shader.load(vertexPath, fragmentPath)
  return shader.fromSource(readFile(vertexPath), readFile(fragmentPath))
end

function shader.loadCompute(path)
  return shader.fromComputeSource(readFile(path))
end

return shader
