local ffi = require("ffi")

ffi.cdef[[
typedef void GLFWwindow;
int glfwInit(void);
void glfwTerminate(void);
void glfwPollEvents(void);
void glfwSwapBuffers(GLFWwindow* window);
void glfwMakeContextCurrent(GLFWwindow* window);
GLFWwindow* glfwCreateWindow(int width, int height, const char* title, void* monitor, void* share);
int glfwWindowShouldClose(GLFWwindow* window);
void glfwWindowHint(int hint, int value);
]]

local _lib = ffi.load("glfw3")

local glfw = setmetatable({
	GLFW_CONTEXT_VERSION_MAJOR = 0x00022002,
	GLFW_CONTEXT_VERSION_MINOR = 0x00022003,
	GLFW_OPENGL_PROFILE        = 0x00022008,
	GLFW_OPENGL_CORE_PROFILE   = 0x00032001,
}, { __index = _lib })

return glfw
