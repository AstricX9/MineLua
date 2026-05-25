local ffi = require("ffi")
local glfw = require("glfw")
local voxel = require("voxel")
local character = require("character")
local terrain = require("terrain")

local GL_COLOR_BUFFER_BIT = 0x00004000
local GL_DEPTH_BUFFER_BIT = 0x00000100
local GL_DEPTH_TEST = 0x0B71

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

-- Load GL
local GL = require("gl")
local gl = GL.gl
GL.loadModernGL()

-- Capture mouse
glfw.glfwSetInputMode(window, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_DISABLED)

-- Print GL version
local ver = ffi.string(gl.glGetString(0x1F02)) -- GL_VERSION = 0x1F02
print("GL_VERSION:", ver)

-- Set viewport
gl.glViewport(0, 0, 1280, 720)

-- Enable depth test
gl.glEnable(GL_DEPTH_TEST)
gl.glDepthFunc(0x0201) -- GL_LESS

-- Compile Texture Atlas
local blocks = require("blocks")
local texture = require("texture")
local atlas = texture.createAtlas()
blocks.initTextures(atlas)

local atlasTex = ffi.new("GLuint[1]")
gl.glGenTextures(1, atlasTex)
gl.glBindTexture(0x0DE1, atlasTex[0]) -- GL_TEXTURE_2D
gl.glTexParameteri(0x0DE1, 0x2801, 0x2600) -- GL_TEXTURE_MIN_FILTER = GL_NEAREST
gl.glTexParameteri(0x0DE1, 0x2800, 0x2600) -- GL_TEXTURE_MAG_FILTER = GL_NEAREST
gl.glTexImage2D(0x0DE1, 0, 0x1908, 256, 256, 0, 0x1908, 0x1401, atlas.pixels) -- 0x1908=GL_RGBA, 0x1401=GL_UNSIGNED_BYTE

-- Create terrain mesh
local chunkModule = require("chunk")
local terrain_w, terrain_d, terrain_maxh = 16, 16, 16
local myChunk = chunkModule.new()
terrain.fillChunk(myChunk, terrain_w, terrain_d, terrain_maxh)
local verts_table = voxel.meshChunk(myChunk, terrain_maxh)
local vcount = #verts_table / 11 -- 11 floats per vertex
local verts = ffi.new("float[?]", #verts_table, verts_table)

-- Upload voxel mesh (VAO + VBO)
local vao = ffi.new("GLuint[1]")
gl.glGenVertexArrays(1, vao)
gl.glBindVertexArray(vao[0])

local vbo = ffi.new("GLuint[1]")
gl.glGenBuffers(1, vbo)
gl.glBindBuffer(0x8892, vbo[0]) -- GL_ARRAY_BUFFER
gl.glBufferData(0x8892, #verts_table * 4, verts, 0x88E4) -- GL_STATIC_DRAW

-- Shaders
local vertSource = ffi.new("const char*[1]", {[1] = [[
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;
out vec3 vColor;
out vec3 vNormal;
out vec3 vFragPos;
out vec2 vTexCoord;
uniform mat4 uProjection;
uniform mat4 uView;
uniform mat4 uModel;
void main() {
  vFragPos = vec3(uModel * vec4(aPos, 1.0));
  vNormal = mat3(transpose(inverse(uModel))) * aNormal;
  vColor = aColor;
  vTexCoord = aTexCoord;
  gl_Position = uProjection * uView * uModel * vec4(aPos, 1.0);
}
]]})

local fragSource = ffi.new("const char*[1]", {[1] = [[
#version 330 core
in vec3 vColor;
in vec3 vNormal;
in vec3 vFragPos;
in vec2 vTexCoord;
out vec4 FragColor;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform sampler2D tex0;
void main() {
  vec3 norm = normalize(vNormal);
  vec3 light = normalize(-lightDir);
  float diff = max(dot(norm, light), 0.0);
  vec3 viewDir = normalize(viewPos - vFragPos);
  vec3 reflectDir = reflect(-light, norm);
  float spec = pow(max(dot(viewDir, reflectDir), 0.0), 16.0);
  vec4 texColor = texture(tex0, vTexCoord);
  vec3 baseColor = vColor * texColor.rgb;
  if(texColor.a < 0.1) discard;
  vec3 ambient = 0.2 * baseColor;
  vec3 diffuse = diff * baseColor * 0.8;
  vec3 specular = vec3(0.3) * spec;
  vec3 result = ambient + diffuse + specular;
  FragColor = vec4(result, texColor.a);
}
]]})

local vert = gl.glCreateShader(0x8B31)
gl.glShaderSource(vert, 1, vertSource, nil)
gl.glCompileShader(vert)
local frag = gl.glCreateShader(0x8B30)
gl.glShaderSource(frag, 1, fragSource, nil)
gl.glCompileShader(frag)
local shader = gl.glCreateProgram()
gl.glAttachShader(shader, vert)
gl.glAttachShader(shader, frag)
gl.glLinkProgram(shader)
gl.glUseProgram(shader)

-- Helper: print shader compile/link logs
local function checkShader(shader, isProgram)
  local status = ffi.new("int[1]")
  if isProgram then
    gl.glGetShaderiv(shader, 0x8B82, status) -- GL_LINK_STATUS
  else
    gl.glGetShaderiv(shader, 0x8B81, status) -- GL_COMPILE_STATUS
  end
  -- Note: we re-use glGetShaderiv for simplicity; errors will show below if present
  local logSize = 512
  local log = ffi.new("char[?]", logSize)
  gl.glGetShaderInfoLog(shader, logSize, nil, log)
  local str = ffi.string(log)
  if #str > 0 then print(str) end
end

-- Check shaders
checkShader(vert, false)
checkShader(frag, false)
checkShader(shader, true)

local stride = 11 * 4
gl.glVertexAttribPointer(0, 3, 0x1406, 0, stride, nil)
gl.glEnableVertexAttribArray(0)
gl.glVertexAttribPointer(1, 3, 0x1406, 0, stride, ffi.cast("void*", 3 * 4))
gl.glEnableVertexAttribArray(1)
gl.glVertexAttribPointer(2, 3, 0x1406, 0, stride, ffi.cast("void*", 6 * 4))
gl.glEnableVertexAttribArray(2)
gl.glVertexAttribPointer(3, 2, 0x1406, 0, stride, ffi.cast("void*", 9 * 4))
gl.glEnableVertexAttribArray(3)

-- Simple matrix helpers
local function perspective(fov, aspect, near, far)
  local f = 1.0 / math.tan(fov / 2)
  local nf = 1 / (near - far)
  local m = {}
  m[1]=f/aspect; m[2]=0; m[3]=0; m[4]=0
  m[5]=0; m[6]=f; m[7]=0; m[8]=0
  m[9]=0; m[10]=0; m[11]=(far+near)*nf; m[12]=-1
  m[13]=0; m[14]=0; m[15]=(2*far*near)*nf; m[16]=0
  return m
end

local function lookAt(eye, center, up)
  local fx = center[1]-eye[1]
  local fy = center[2]-eye[2]
  local fz = center[3]-eye[3]
  local rlf = 1 / math.sqrt(fx*fx + fy*fy + fz*fz)
  fx,fy,fz = fx*rlf, fy*rlf, fz*rlf
  local sx = fy*up[3] - fz*up[2]
  local sy = fz*up[1] - fx*up[3]
  local sz = fx*up[2] - fy*up[1]
  local rls = 1 / math.sqrt(sx*sx + sy*sy + sz*sz)
  sx,sy,sz = sx*rls, sy*rls, sz*rls
  local ux = sy*fz - sz*fy
  local uy = sz*fx - sx*fz
  local uz = sx*fy - sy*fx
  local m = {
    sx, ux, -fx, 0,
    sy, uy, -fy, 0,
    sz, uz, -fz, 0,
    -(sx*eye[1] + sy*eye[2] + sz*eye[3]), -(ux*eye[1] + uy*eye[2] + uz*eye[3]), (fx*eye[1] + fy*eye[2] + fz*eye[3]), 1
  }
  return m
end

local proj = perspective(math.rad(45), 1280/720, 0.1, 100.0)
local view = lookAt({8,6,22}, {8,4,8}, {0,1,0})
local model = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}

-- Send matrices
local locP = gl.glGetUniformLocation(shader, "uProjection")
local locV = gl.glGetUniformLocation(shader, "uView")
local locM = gl.glGetUniformLocation(shader, "uModel")
local locLight = gl.glGetUniformLocation(shader, "lightDir")
local locViewPos = gl.glGetUniformLocation(shader, "viewPos")
local locTex = gl.glGetUniformLocation(shader, "tex0")

gl.glUniformMatrix4fv(locP, 1, 0, ffi.new("float[16]", proj))
gl.glUniformMatrix4fv(locV, 1, 0, ffi.new("float[16]", view))
gl.glUniformMatrix4fv(locM, 1, 0, ffi.new("float[16]", model))
gl.glUniform3f(locLight, -0.3, -1.0, -0.5)
gl.glUniform1i(locTex, 0)

-- Character mesh
local char_verts_table = character.createCharacter()
local char_count = #char_verts_table / 11
local char_verts = ffi.new("float[?]", #char_verts_table, char_verts_table)

local vao2 = ffi.new("GLuint[1]")
gl.glGenVertexArrays(1, vao2)
gl.glBindVertexArray(vao2[0])
local vbo2 = ffi.new("GLuint[1]")
gl.glGenBuffers(1, vbo2)
gl.glBindBuffer(0x8892, vbo2[0])
gl.glBufferData(0x8892, #char_verts_table * 4, char_verts, 0x88E4)
gl.glVertexAttribPointer(0, 3, 0x1406, 0, stride, nil)
gl.glEnableVertexAttribArray(0)
gl.glVertexAttribPointer(1, 3, 0x1406, 0, stride, ffi.cast("void*", 3 * 4))
gl.glEnableVertexAttribArray(1)
gl.glVertexAttribPointer(2, 3, 0x1406, 0, stride, ffi.cast("void*", 6 * 4))
gl.glEnableVertexAttribArray(2)
gl.glVertexAttribPointer(3, 2, 0x1406, 0, stride, ffi.cast("void*", 9 * 4))
gl.glEnableVertexAttribArray(3)

-- Camera state
local camPos = {16.0, 30.0, 16.0}
local yaw = -90.0
local pitch = 0.0
local lastX = 640.0
local lastY = 360.0
local firstMouse = true
local velocityY = 0.0
local lastTime = glfw.glfwGetTime()

local function updateCamera(dt)
  -- mouse
  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)
  local x = tonumber(xpos[0])
  local y = tonumber(ypos[0])
  if firstMouse then lastX, lastY = x, y; firstMouse = false end
  local xoffset = x - lastX; local yoffset = lastY - y
  lastX, lastY = x, y
  local sensitivity = 0.1
  xoffset = xoffset * sensitivity; yoffset = yoffset * sensitivity
  yaw = yaw + xoffset; pitch = pitch + yoffset
  if pitch > 89.0 then pitch = 89.0 end
  if pitch < -89.0 then pitch = -89.0 end
  local radYaw = math.rad(yaw); local radPitch = math.rad(pitch)
  local front = {
    math.cos(radYaw) * math.cos(radPitch),
    math.sin(radPitch),
    math.sin(radYaw) * math.cos(radPitch)
  }
  -- normalize front
  local fl = math.sqrt(front[1]*front[1] + front[2]*front[2] + front[3]*front[3])
  front[1] = front[1]/fl; front[2] = front[2]/fl; front[3] = front[3]/fl
  -- right vector
  local up = {0,1,0}
  local right = { front[3]*up[2] - front[2]*up[3], front[1]*up[3] - front[3]*up[1], front[2]*up[1] - front[1]*up[2] }
  local rl = math.sqrt(right[1]*right[1] + right[2]*right[2] + right[3]*right[3])
  right[1]=right[1]/rl; right[2]=right[2]/rl; right[3]=right[3]/rl
  -- movement
  local speed = 6.0 * dt
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_W) == glfw.GLFW_PRESS then
    camPos[1] = camPos[1] + front[1]*speed; camPos[3] = camPos[3] + front[3]*speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_S) == glfw.GLFW_PRESS then
    camPos[1] = camPos[1] - front[1]*speed; camPos[3] = camPos[3] - front[3]*speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_A) == glfw.GLFW_PRESS then
    camPos[1] = camPos[1] + right[1]*speed; camPos[3] = camPos[3] + right[3]*speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_D) == glfw.GLFW_PRESS then
    camPos[1] = camPos[1] - right[1]*speed; camPos[3] = camPos[3] - right[3]*speed
  end
  -- jump
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_SPACE) == glfw.GLFW_PRESS then
    -- simple jump if near ground
    local pX, pZ = math.floor(camPos[1] + 0.5), math.floor(camPos[3] + 0.5)
    local groundY = 2.0
    if pX >= 0 and pX < terrain_w and pZ >= 0 and pZ < terrain_d then
      groundY = terrain.heightAt(pX, pZ, terrain_maxh) + 1.5
    end
    if camPos[2] <= groundY + 0.05 then velocityY = 5.0 end
  end
  -- gravity
  velocityY = velocityY - 9.8 * dt
  camPos[2] = camPos[2] + velocityY * dt
  
  local colX, colZ = math.floor(camPos[1] + 0.5), math.floor(camPos[3] + 0.5)
  local floorY = 2.0
  if colX >= 0 and colX < terrain_w and colZ >= 0 and colZ < terrain_d then
    floorY = terrain.heightAt(colX, colZ, terrain_maxh) + 1.5
  end

  if camPos[2] < floorY then 
    camPos[2] = floorY
    velocityY = 0 
  end

  -- update view uniform
  local center = { camPos[1] + front[1], camPos[2] + front[2], camPos[3] + front[3] }
  local viewMat = lookAt(camPos, center, up)
  gl.glUniformMatrix4fv(locV, 1, 0, ffi.new("float[16]", viewMat))
  gl.glUniform3f(locViewPos, camPos[1], camPos[2], camPos[3])
end

-- MAIN LOOP
while glfw.glfwWindowShouldClose(window) == 0 do
  local currentTime = glfw.glfwGetTime()
  local dt = currentTime - lastTime
  lastTime = currentTime

  gl.glClearColor(0.53, 0.81, 0.92, 1.0)
  gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)

  -- update camera (mouse + movement + gravity)
  updateCamera(dt)

  -- draw terrain
  gl.glBindVertexArray(vao[0])
  gl.glDrawArrays(0x0004, 0, vcount)

  -- draw character
  gl.glBindVertexArray(vao2[0])
  gl.glDrawArrays(0x0004, 0, char_count)

  glfw.glfwSwapBuffers(window)
  glfw.glfwPollEvents()
end

glfw.glfwTerminate()
