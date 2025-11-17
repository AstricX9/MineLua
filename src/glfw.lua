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
]]

local glfw = ffi.load("glfw3")
return glfw
