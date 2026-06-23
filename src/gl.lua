local ffi = require("ffi")
local loader = require("gl_loader")

ffi.cdef[[
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned char GLchar;

// Core OpenGL 1.1 (from opengl32.dll)
void glClearColor(float r, float g, float b, float a);
void glClear(int mask);
void glViewport(GLint x, GLint y, GLint w, GLint h);
void glGenTextures(int n, GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glDepthFunc(GLenum func);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
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
void glUseProgram(GLuint program);

// Uniforms
GLint glGetUniformLocation(GLuint program, const char* name);
void glUniform3f(GLint location, float v0, float v1, float v2);
void glUniform1i(GLint location, GLint v0);
  void glUniformMatrix4fv(GLint location, GLsizei count, unsigned char transpose, const float* value);
  const unsigned char* glGetString(GLenum name);
  void glEnable(GLenum cap);
  void glDepthFunc(GLenum func);
  void glActiveTexture(GLenum texture);

// Buffers
void glGenBuffers(GLsizei n, GLuint* buffers);
void glBindBuffer(GLenum target, GLuint buffer);
void glBufferData(GLenum target, GLint size, const void* data, GLenum usage);

// Vertex Attributes
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, unsigned char normalized, GLint stride, const void* pointer);
void glEnableVertexAttribArray(GLuint index);

// Draw
void glDrawArrays(GLenum mode, GLint first, GLsizei count);

// VAOs (REQUIRED in core profile)
void glGenVertexArrays(GLsizei n, GLuint* arrays);
void glBindVertexArray(GLuint array);
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
  gl.glUseProgram = loader.load("glUseProgram", "void", "GLuint")

  -- Uniforms
  gl.glGetUniformLocation = loader.load("glGetUniformLocation", "GLint", "GLuint", "const char*")
  gl.glUniform3f = loader.load("glUniform3f", "void", "GLint", "float", "float", "float")
  gl.glUniform1i = loader.load("glUniform1i", "void", "GLint", "GLint")
  gl.glUniformMatrix4fv = loader.load("glUniformMatrix4fv", "void", "GLint", "GLsizei", "unsigned char", "const float*")
  gl.glGetString = loader.load("glGetString", "const unsigned char*", "unsigned int")
  gl.glEnable = loader.load("glEnable", "void", "unsigned int")
  gl.glDepthFunc = loader.load("glDepthFunc", "void", "unsigned int")
  gl.glActiveTexture = loader.load("glActiveTexture", "void", "unsigned int")

  -- Buffers
  gl.glGenBuffers = loader.load("glGenBuffers", "void", "GLsizei", "GLuint*")
  gl.glBindBuffer = loader.load("glBindBuffer", "void", "GLenum", "GLuint")
  gl.glBufferData = loader.load("glBufferData", "void", "GLenum", "GLint", "const void*", "GLenum")

  -- Vertex attribs
  gl.glVertexAttribPointer = loader.load("glVertexAttribPointer", "void", "GLuint", "GLint", "GLenum", "unsigned char", "GLint", "const void*")
  gl.glEnableVertexAttribArray = loader.load("glEnableVertexAttribArray", "void", "GLuint")

  -- Draw call
  gl.glDrawArrays = loader.load("glDrawArrays", "void", "GLenum", "GLint", "GLsizei")

  -- VAOs
  gl.glGenVertexArrays = loader.load("glGenVertexArrays", "void", "GLsizei", "GLuint*")
  gl.glBindVertexArray = loader.load("glBindVertexArray", "void", "GLuint")
end

return {
  gl = gl,
  loadModernGL = loadModernGL
}
