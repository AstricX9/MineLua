local ffi = require("ffi")
local GL = require("gl")
local rendering = require("rendering")
local shader = require("shader")
local texture = require("texture")

local gl = GL.gl
local overlay = {}
overlay.__index = overlay

local GL_ARRAY_BUFFER, GL_STATIC_DRAW, GL_FLOAT = 0x8892, 0x88E4, 0x1406
local GL_TEXTURE_2D, GL_TEXTURE0 = 0x0DE1, 0x84C0
local GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER = 0x2801, 0x2800
local GL_TEXTURE_WRAP_S, GL_TEXTURE_WRAP_T = 0x2802, 0x2803
local GL_NEAREST, GL_CLAMP_TO_EDGE = 0x2600, 0x812F
local GL_RGBA, GL_UNSIGNED_BYTE = 0x1908, 0x1401
local GL_BLEND, GL_ONE = 0x0BE2, 1

local function createTexture(path)
  local image = assert(texture.loadPng(path), "Failed to load mining texture: " .. path)
  local id = ffi.new("GLuint[1]")
  gl.glGenTextures(1,id)
  gl.glBindTexture(GL_TEXTURE_2D,id[0])
  gl.glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST)
  gl.glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST)
  gl.glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE)
  gl.glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE)
  gl.glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,image.w,image.h,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data)
  return id
end

local function createMesh()
  local e, vertices = 0.002, {}
  local function vertex(x,y,z,u,v)
    for _,n in ipairs({x,y,z,0,0,0,1,1,1,u,v}) do vertices[#vertices+1]=n end
  end
  local function quad(a,b,c,d)
    vertex(a[1],a[2],a[3],0,1); vertex(b[1],b[2],b[3],1,1); vertex(c[1],c[2],c[3],1,0)
    vertex(c[1],c[2],c[3],1,0); vertex(d[1],d[2],d[3],0,0); vertex(a[1],a[2],a[3],0,1)
  end
  local a,b = -e,1+e
  quad({b,a,a},{b,a,b},{b,b,b},{b,b,a}); quad({a,a,b},{a,a,a},{a,b,a},{a,b,b})
  quad({a,b,a},{b,b,a},{b,b,b},{a,b,b}); quad({a,a,b},{b,a,b},{b,a,a},{a,a,a})
  quad({a,a,b},{a,b,b},{b,b,b},{b,a,b}); quad({b,a,a},{b,b,a},{a,b,a},{a,a,a})
  local vao,vbo=ffi.new("GLuint[1]"),ffi.new("GLuint[1]")
  local data=ffi.new("float[?]",#vertices,vertices)
  gl.glGenVertexArrays(1,vao); gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1,vbo); gl.glBindBuffer(GL_ARRAY_BUFFER,vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER,#vertices*4,data,GL_STATIC_DRAW)
  for index,offset in ipairs({0,3,6,9}) do
    local location=index-1
    gl.glVertexAttribPointer(location,location==3 and 2 or 3,GL_FLOAT,0,44,ffi.cast("void*",offset*4))
    gl.glEnableVertexAttribArray(location)
  end
  return {vao=vao,vbo=vbo,data=data,count=36}
end

function overlay.create()
  local program=shader.fromSource([[
#version 460 core
layout(location=0) in vec3 aPos; layout(location=3) in vec2 aTexCoord;
out vec2 uv; uniform mat4 uProjection; uniform mat4 uView; uniform vec3 blockPosition;
void main(){uv=aTexCoord;gl_Position=uProjection*uView*vec4(aPos+blockPosition,1.0);}
]],[[
#version 460 core
in vec2 uv; out vec4 FragColor; uniform sampler2D crackTexture;
void main(){vec4 c=texture(crackTexture,uv);float ink=(1.0-dot(c.rgb,vec3(.2126,.7152,.0722)))*c.a;if(ink<.01)discard;FragColor=vec4(vec3(ink*.38),ink);}
]])
  local self=setmetatable({program=program,mesh=createMesh(),textures={}},overlay)
  self.locations={projection=gl.glGetUniformLocation(program,"uProjection"),view=gl.glGetUniformLocation(program,"uView"),position=gl.glGetUniformLocation(program,"blockPosition"),texture=gl.glGetUniformLocation(program,"crackTexture")}
  for stage=0,9 do self.textures[stage+1]=createTexture("assets/textures/blocks/destroy_stage_"..stage..".png") end
  return self
end

function overlay:draw(state,projection,view)
  local target=state.breakTargetPosition
  if not target or not state.breakDuration or state.breakDuration<=0 then return end
  local stage=math.floor(math.max(0,math.min(.999,state.breakProgress/state.breakDuration))*10)+1
  gl.glUseProgram(self.program)
  gl.glUniformMatrix4fv(self.locations.projection,1,0,ffi.new("float[16]",projection))
  gl.glUniformMatrix4fv(self.locations.view,1,0,ffi.new("float[16]",view))
  gl.glUniform3f(self.locations.position,target.x,target.y,target.z); gl.glUniform1i(self.locations.texture,0)
  gl.glActiveTexture(GL_TEXTURE0); gl.glBindTexture(GL_TEXTURE_2D,self.textures[stage][0])
  gl.glEnable(GL_BLEND); gl.glBlendFunc(GL_ONE,GL_ONE); gl.glDepthMask(0)
  rendering.draw(self.mesh)
  gl.glDepthMask(1); gl.glDisable(GL_BLEND)
end

function overlay:release()
  rendering.release(self.mesh)
  for _,id in ipairs(self.textures) do gl.glDeleteTextures(1,id) end
  if gl.glDeleteProgram then gl.glDeleteProgram(self.program) end
end

return overlay
