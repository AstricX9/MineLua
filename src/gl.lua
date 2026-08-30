local ffi = require("ffi")
local loader = require("gl_loader")

ffi.cdef[[
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned char GLchar;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef intptr_t GLintptr;
typedef intptr_t GLsizeiptr;

// Core OpenGL 1.1 (from opengl32.dll)
void glClearColor(float r, float g, float b, float a);
void glClear(int mask);
void glViewport(GLint x, GLint y, GLint w, GLint h);
void glGenTextures(int n, GLuint *textures);
void glDeleteTextures(GLsizei n, const GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glDepthFunc(GLenum func);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawBuffer(GLenum buf);
void glReadBuffer(GLenum src);
void glCullFace(GLenum mode);
void glPolygonOffset(GLfloat factor, GLfloat units);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glDepthMask(unsigned char flag);
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void* pixels);
void glPixelStorei(GLenum pname, GLint param);
]]

-- Load legacy OpenGL (1.1) from Windows
local _lib = ffi.load("opengl32.dll")

-- We put everything in a proxy table that falls back to core GL
local gl = setmetatable({}, { __index = _lib })

-- Load modern OpenGL function pointers AFTER context is ready
local function loadModernGL()
  ffi.cdef[[
// Shader pipeline
GLuint glCreateShader(GLenum type);
void glShaderSource(GLuint shader, GLsizei count, const char** string, const GLint* length);
void glCompileShader(GLuint shader);
void glGetShaderiv(GLuint shader, GLenum pname, GLint* params);
void glGetShaderInfoLog(GLuint shader, GLsizei maxLen, GLsizei* length, char* infoLog);
GLuint glCreateProgram(void);
void glAttachShader(GLuint program, GLuint shader);
void glLinkProgram(GLuint program);
void glGetProgramiv(GLuint program, GLenum pname, GLint* params);
void glGetProgramInfoLog(GLuint program, GLsizei maxLen, GLsizei* length, char* infoLog);
void glDeleteShader(GLuint shader);
void glDeleteProgram(GLuint program);
void glUseProgram(GLuint program);
void glDispatchCompute(GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z);
void glMemoryBarrier(GLbitfield barriers);

// Uniforms
GLint glGetUniformLocation(GLuint program, const char* name);
void glUniform2f(GLint location, float v0, float v1);
void glUniform3f(GLint location, float v0, float v1, float v2);
void glUniform4f(GLint location, float v0, float v1, float v2, float v3);
void glUniform1f(GLint location, float v0);
void glUniform1i(GLint location, GLint v0);
  void glUniformMatrix3fv(GLint location, GLsizei count, unsigned char transpose, const float* value);
  void glUniformMatrix4fv(GLint location, GLsizei count, unsigned char transpose, const float* value);
  const unsigned char* glGetString(GLenum name);
  void glEnable(GLenum cap);
  void glDisable(GLenum cap);
  void glDepthFunc(GLenum func);
  void glActiveTexture(GLenum texture);
  void glDrawBuffer(GLenum buf);
  void glReadBuffer(GLenum src);
  void glCullFace(GLenum mode);
  void glPolygonOffset(GLfloat factor, GLfloat units);
  void glBlendFunc(GLenum sfactor, GLenum dfactor);
  void glDepthMask(unsigned char flag);

// Framebuffers
void glGenFramebuffers(GLsizei n, GLuint* ids);
void glDeleteFramebuffers(GLsizei n, const GLuint* framebuffers);
void glBindFramebuffer(GLenum target, GLuint framebuffer);
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
void glFramebufferTexture(GLenum target, GLenum attachment, GLuint texture, GLint level);
GLenum glCheckFramebufferStatus(GLenum target);
void glBlitFramebuffer(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1,
  GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1,
  GLbitfield mask, GLenum filter);

// Immutable/3D textures and image load-store (OpenGL 4.x volumetrics)
void glTexImage3D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const void* pixels);
void glTexStorage2D(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height);
void glTexStorage3D(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth);
void glBindImageTexture(GLuint unit, GLuint texture, GLint level, GLboolean layered, GLint layer, GLenum access, GLenum format);
void glGenerateMipmap(GLenum target);

// Buffers
void glGenBuffers(GLsizei n, GLuint* buffers);
void glBindBuffer(GLenum target, GLuint buffer);
void glBufferData(GLenum target, GLsizeiptr size, const void* data, GLenum usage);
void glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, const void* data);
void glBindBufferBase(GLenum target, GLuint index, GLuint buffer);
void glBindBufferRange(GLenum target, GLuint index, GLuint buffer, GLintptr offset, GLsizeiptr size);
void glDeleteBuffers(GLsizei n, const GLuint* buffers);

// Vertex Attributes
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, unsigned char normalized, GLint stride, const void* pointer);
void glEnableVertexAttribArray(GLuint index);

// Draw
void glDrawArrays(GLenum mode, GLint first, GLsizei count);

// VAOs (REQUIRED in core profile)
void glGenVertexArrays(GLsizei n, GLuint* arrays);
void glBindVertexArray(GLuint array);
void glDeleteVertexArrays(GLsizei n, const GLuint* arrays);
  ]]

  -- Shader
  gl.glCreateShader = loader.load("glCreateShader", "GLuint", "GLenum")
  gl.glShaderSource = loader.load("glShaderSource", "void", "GLuint", "GLsizei", "const char**", "const GLint*")
  gl.glCompileShader = loader.load("glCompileShader", "void", "GLuint")
  gl.glGetShaderiv = loader.load("glGetShaderiv", "void", "GLuint", "GLenum", "GLint*")
  gl.glGetShaderInfoLog = loader.load("glGetShaderInfoLog", "void", "GLuint", "GLsizei", "GLsizei*", "char*")
  gl.glCreateProgram = loader.load("glCreateProgram", "GLuint")
  gl.glAttachShader = loader.load("glAttachShader", "void", "GLuint", "GLuint")
  gl.glLinkProgram = loader.load("glLinkProgram", "void", "GLuint")
  gl.glGetProgramiv = loader.load("glGetProgramiv", "void", "GLuint", "GLenum", "GLint*")
  gl.glGetProgramInfoLog = loader.load("glGetProgramInfoLog", "void", "GLuint", "GLsizei", "GLsizei*", "char*")
  gl.glDeleteShader = loader.load("glDeleteShader", "void", "GLuint")
  gl.glDeleteProgram = loader.load("glDeleteProgram", "void", "GLuint")
  gl.glUseProgram = loader.load("glUseProgram", "void", "GLuint")
  gl.glDispatchCompute = loader.load("glDispatchCompute", "void", "GLuint", "GLuint", "GLuint")
  gl.glMemoryBarrier = loader.load("glMemoryBarrier", "void", "GLbitfield")

  -- Uniforms
  gl.glGetUniformLocation = loader.load("glGetUniformLocation", "GLint", "GLuint", "const char*")
  gl.glUniform2f = loader.load("glUniform2f", "void", "GLint", "float", "float")
  gl.glUniform3f = loader.load("glUniform3f", "void", "GLint", "float", "float", "float")
  gl.glUniform4f = loader.load("glUniform4f", "void", "GLint", "float", "float", "float", "float")
  gl.glUniform1f = loader.load("glUniform1f", "void", "GLint", "float")
  gl.glUniform1i = loader.load("glUniform1i", "void", "GLint", "GLint")
  gl.glUniformMatrix3fv = loader.load("glUniformMatrix3fv", "void", "GLint", "GLsizei", "unsigned char", "const float*")
  gl.glUniformMatrix4fv = loader.load("glUniformMatrix4fv", "void", "GLint", "GLsizei", "unsigned char", "const float*")
  gl.glGetString = loader.load("glGetString", "const unsigned char*", "unsigned int")
  gl.glEnable = loader.load("glEnable", "void", "unsigned int")
  gl.glDisable = loader.load("glDisable", "void", "unsigned int")
  gl.glDepthFunc = loader.load("glDepthFunc", "void", "unsigned int")
  gl.glActiveTexture = loader.load("glActiveTexture", "void", "unsigned int")
  gl.glDrawBuffer = loader.load("glDrawBuffer", "void", "GLenum")
  gl.glReadBuffer = loader.load("glReadBuffer", "void", "GLenum")
  gl.glCullFace = loader.load("glCullFace", "void", "GLenum")
  gl.glPolygonOffset = loader.load("glPolygonOffset", "void", "GLfloat", "GLfloat")
  gl.glBlendFunc = loader.load("glBlendFunc", "void", "GLenum", "GLenum")
  gl.glBlendFuncSeparate = loader.load("glBlendFuncSeparate", "void", "GLenum", "GLenum", "GLenum", "GLenum")
  gl.glDepthMask = loader.load("glDepthMask", "void", "unsigned char")

  -- Framebuffers
  gl.glGenFramebuffers = loader.load("glGenFramebuffers", "void", "GLsizei", "GLuint*")
  gl.glDeleteFramebuffers = loader.load("glDeleteFramebuffers", "void", "GLsizei", "const GLuint*")
  gl.glBindFramebuffer = loader.load("glBindFramebuffer", "void", "GLenum", "GLuint")
  gl.glFramebufferTexture2D = loader.load("glFramebufferTexture2D", "void", "GLenum", "GLenum", "GLenum", "GLuint", "GLint")
  gl.glFramebufferTexture = loader.load("glFramebufferTexture", "void", "GLenum", "GLenum", "GLuint", "GLint")
  gl.glCheckFramebufferStatus = loader.load("glCheckFramebufferStatus", "GLenum", "GLenum")
  gl.glBlitFramebuffer = loader.load("glBlitFramebuffer", "void",
    "GLint", "GLint", "GLint", "GLint",
    "GLint", "GLint", "GLint", "GLint", "GLbitfield", "GLenum")

  -- OpenGL 4.x textures and image load-store
  gl.glTexImage3D = loader.load("glTexImage3D", "void", "GLenum", "GLint", "GLint", "GLsizei", "GLsizei", "GLsizei", "GLint", "GLenum", "GLenum", "const void*")
  gl.glTexStorage2D = loader.load("glTexStorage2D", "void", "GLenum", "GLsizei", "GLenum", "GLsizei", "GLsizei")
  gl.glTexStorage3D = loader.load("glTexStorage3D", "void", "GLenum", "GLsizei", "GLenum", "GLsizei", "GLsizei", "GLsizei")
  gl.glBindImageTexture = loader.load("glBindImageTexture", "void", "GLuint", "GLuint", "GLint", "GLboolean", "GLint", "GLenum", "GLenum")
  gl.glGenerateMipmap = loader.load("glGenerateMipmap", "void", "GLenum")

  -- Buffers
  gl.glGenBuffers = loader.load("glGenBuffers", "void", "GLsizei", "GLuint*")
  gl.glBindBuffer = loader.load("glBindBuffer", "void", "GLenum", "GLuint")
  gl.glBufferData = loader.load("glBufferData", "void", "GLenum", "GLsizeiptr", "const void*", "GLenum")
  gl.glBufferSubData = loader.load("glBufferSubData", "void", "GLenum", "GLintptr", "GLsizeiptr", "const void*")
  gl.glBindBufferBase = loader.load("glBindBufferBase", "void", "GLenum", "GLuint", "GLuint")
  gl.glBindBufferRange = loader.load("glBindBufferRange", "void", "GLenum", "GLuint", "GLuint", "GLintptr", "GLsizeiptr")
  gl.glDeleteBuffers = loader.load("glDeleteBuffers", "void", "GLsizei", "const GLuint*")

  -- Vertex attribs
  gl.glVertexAttribPointer = loader.load("glVertexAttribPointer", "void", "GLuint", "GLint", "GLenum", "unsigned char", "GLint", "const void*")
  gl.glEnableVertexAttribArray = loader.load("glEnableVertexAttribArray", "void", "GLuint")

  -- Draw call
  gl.glDrawArrays = loader.load("glDrawArrays", "void", "GLenum", "GLint", "GLsizei")

  -- VAOs
  gl.glGenVertexArrays = loader.load("glGenVertexArrays", "void", "GLsizei", "GLuint*")
  gl.glBindVertexArray = loader.load("glBindVertexArray", "void", "GLuint")
  gl.glDeleteVertexArrays = loader.load("glDeleteVertexArrays", "void", "GLsizei", "const GLuint*")
end

-- Enum values, so callers stop declaring their own copies of them. The name is
-- the GL one without the prefix: GL.TEXTURE_2D is GL_TEXTURE_2D.
return {
  gl = gl,
  loadModernGL = loadModernGL,

  ARRAY_BUFFER = 0x8892,
  PACK_ALIGNMENT = 0x0D05,
  RGB = 0x1907,
  VERSION = 0x1F02,
  BACK = 0x0405,
  BLEND = 0x0BE2,
  CLAMP_TO_EDGE = 0x812F,
  COLOR_ATTACHMENT0 = 0x8CE0,
  COLOR_BUFFER_BIT = 0x00004000,
  COMPILE_STATUS = 0x8B81,
  COMPUTE_SHADER = 0x91B9,
  CULL_FACE = 0x0B44,
  DEPTH_ATTACHMENT = 0x8D00,
  DEPTH_BUFFER_BIT = 0x00000100,
  DEPTH_COMPONENT = 0x1902,
  DEPTH_COMPONENT24 = 0x81A6,
  DEPTH_TEST = 0x0B71,
  DRAW_FRAMEBUFFER = 0x8CA9,
  FLOAT = 0x1406,
  FRAGMENT_SHADER = 0x8B30,
  FRAMEBUFFER = 0x8D40,
  FRAMEBUFFER_COMPLETE = 0x8CD5,
  INFO_LOG_LENGTH = 0x8B84,
  LESS = 0x0201,
  LINEAR = 0x2601,
  LINEAR_MIPMAP_LINEAR = 0x2703,
  LINK_STATUS = 0x8B82,
  NEAREST = 0x2600,
  NEAREST_MIPMAP_LINEAR = 0x2702,
  ONE_MINUS_SRC_ALPHA = 0x0303,
  POLYGON_OFFSET_FILL = 0x8037,
  R32F = 0x822E,
  READ_FRAMEBUFFER = 0x8CA8,
  READ_ONLY = 0x88B8,
  RED = 0x1903,
  REPEAT = 0x2901,
  RG = 0x8227,
  RG32F = 0x8230,
  RGBA = 0x1908,
  RGBA16F = 0x881A,
  RGBA32F = 0x8814,
  SHADER_IMAGE_ACCESS_BARRIER_BIT = 0x00000020,
  SRC_ALPHA = 0x0302,
  STATIC_DRAW = 0x88E4,
  TEXTURE0 = 0x84C0,
  TEXTURE1 = 0x84C1,
  TEXTURE2 = 0x84C2,
  TEXTURE3 = 0x84C3,
  TEXTURE4 = 0x84C4,
  TEXTURE5 = 0x84C5,
  TEXTURE_2D = 0x0DE1,
  TEXTURE_3D = 0x806F,
  TEXTURE_CUBE_MAP = 0x8513,
  TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515,
  TEXTURE_CUBE_MAP_SEAMLESS = 0x884F,
  TEXTURE_FETCH_BARRIER_BIT = 0x00000008,
  TEXTURE_MAG_FILTER = 0x2800,
  TEXTURE_MAX_LEVEL = 0x813D,
  TEXTURE_MIN_FILTER = 0x2801,
  TEXTURE_WRAP_R = 0x8072,
  TEXTURE_WRAP_S = 0x2802,
  TEXTURE_WRAP_T = 0x2803,
  TRIANGLES = 0x0004,
  UNSIGNED_BYTE = 0x1401,
  UNSIGNED_INT = 0x1405,
  VERTEX_SHADER = 0x8B31,
  WRITE_ONLY = 0x88B9,
}
