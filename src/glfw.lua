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
int glfwGetKey(GLFWwindow* window, int key);
void glfwSetInputMode(GLFWwindow* window, int mode, int value);
void glfwGetCursorPos(GLFWwindow* window, double* xpos, double* ypos);
double glfwGetTime(void);
]]

local _lib = ffi.load("glfw3")

local glfw = setmetatable({
	GLFW_CONTEXT_VERSION_MAJOR = 0x00022002,
	GLFW_CONTEXT_VERSION_MINOR = 0x00022003,
	GLFW_OPENGL_PROFILE        = 0x00022008,
	GLFW_OPENGL_CORE_PROFILE   = 0x00032001,
	GLFW_CURSOR = 0x00033001,
	GLFW_CURSOR_NORMAL = 0x00034001,
	GLFW_CURSOR_HIDDEN = 0x00034002,
	GLFW_CURSOR_DISABLED = 0x00034003,
	GLFW_PRESS = 1,
	GLFW_RELEASE = 0,
	GLFW_KEY_W = 87,
	GLFW_KEY_A = 65,
	GLFW_KEY_S = 83,
	GLFW_KEY_D = 68,
	GLFW_KEY_SPACE = 32,
	GLFW_KEY_LEFT_SHIFT = 340,
}, { __index = _lib })

return glfw
