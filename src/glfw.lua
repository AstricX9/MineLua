local ffi = require("ffi")

ffi.cdef[[
typedef void GLFWwindow;
typedef void GLFWmonitor;
typedef void (*GLFWscrollfun)(GLFWwindow* window, double xoffset, double yoffset);
typedef void (*GLFWcharfun)(GLFWwindow* window, unsigned int codepoint);
typedef struct GLFWvidmode {
  int width;
  int height;
  int redBits;
  int greenBits;
  int blueBits;
  int refreshRate;
} GLFWvidmode;
int glfwInit(void);
void glfwTerminate(void);
void glfwPollEvents(void);
void glfwSwapBuffers(GLFWwindow* window);
void glfwMakeContextCurrent(GLFWwindow* window);
GLFWwindow* glfwCreateWindow(int width, int height, const char* title, void* monitor, void* share);
int glfwWindowShouldClose(GLFWwindow* window);
void glfwSetWindowShouldClose(GLFWwindow* window, int value);
void glfwWindowHint(int hint, int value);
int glfwGetKey(GLFWwindow* window, int key);
int glfwGetMouseButton(GLFWwindow* window, int button);
void glfwSetInputMode(GLFWwindow* window, int mode, int value);
int glfwRawMouseMotionSupported(void);
void glfwGetCursorPos(GLFWwindow* window, double* xpos, double* ypos);
void glfwGetWindowPos(GLFWwindow* window, int* xpos, int* ypos);
void glfwGetWindowSize(GLFWwindow* window, int* width, int* height);
void glfwGetFramebufferSize(GLFWwindow* window, int* width, int* height);
GLFWscrollfun glfwSetScrollCallback(GLFWwindow* window, GLFWscrollfun callback);
GLFWcharfun glfwSetCharCallback(GLFWwindow* window, GLFWcharfun callback);
void glfwSetWindowMonitor(GLFWwindow* window, GLFWmonitor* monitor, int xpos, int ypos, int width, int height, int refreshRate);
GLFWmonitor* glfwGetPrimaryMonitor(void);
const GLFWvidmode* glfwGetVideoMode(GLFWmonitor* monitor);
double glfwGetTime(void);
void glfwSwapInterval(int interval);
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
	GLFW_RAW_MOUSE_MOTION = 0x00033005,
	GLFW_TRUE = 1,
	GLFW_FALSE = 0,
	GLFW_PRESS = 1,
	GLFW_RELEASE = 0,
	GLFW_KEY_W = 87,
	GLFW_KEY_A = 65,
	GLFW_KEY_S = 83,
	GLFW_KEY_D = 68,
	GLFW_KEY_F = 70,
	GLFW_KEY_E = 69,
	GLFW_KEY_Q = 81,
	GLFW_KEY_R = 82,
	GLFW_KEY_1 = 49,
	GLFW_KEY_2 = 50,
	GLFW_KEY_3 = 51,
	GLFW_KEY_4 = 52,
	GLFW_KEY_5 = 53,
	GLFW_KEY_6 = 54,
	GLFW_KEY_7 = 55,
	GLFW_KEY_8 = 56,
	GLFW_KEY_9 = 57,
	GLFW_KEY_SPACE = 32,
	GLFW_KEY_C = 67,
	GLFW_KEY_UP = 265,
	GLFW_KEY_DOWN = 264,
	GLFW_KEY_LEFT = 263,
	GLFW_KEY_RIGHT = 262,
	GLFW_KEY_BACKSPACE = 259,
	GLFW_KEY_DELETE = 261,
	GLFW_KEY_HOME = 268,
	GLFW_KEY_END = 269,
	GLFW_KEY_TAB = 258,
	GLFW_KEY_MINUS = 45,
	GLFW_KEY_ESCAPE = 256,
	GLFW_KEY_F1 = 290,
	GLFW_KEY_F2 = 291,
	GLFW_KEY_F3 = 292,
	GLFW_KEY_F4 = 293,
	GLFW_KEY_F5 = 294,
	GLFW_KEY_F11 = 300,
	GLFW_KEY_LEFT_SHIFT = 340,
	GLFW_KEY_LEFT_CONTROL = 341,
	GLFW_KEY_RIGHT_CONTROL = 345,
	GLFW_MOUSE_BUTTON_LEFT = 0,
	GLFW_MOUSE_BUTTON_RIGHT = 1,
	GLFW_MOUSE_BUTTON_MIDDLE = 2,
}, { __index = _lib })

return glfw
