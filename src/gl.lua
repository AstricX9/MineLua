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

return {
  gl = gl,
  loadModernGL = loadModernGL
}
