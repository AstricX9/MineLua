local glfw = require("glfw")

local bindings = {}

bindings.DEFAULTS = {
  attack = "MOUSE1", use = "MOUSE2", pick = "MOUSE3",
  forward = "W", back = "S", left = "A", right = "D",
  jump = "SPACE", sneak = "CTRL", drop = "Q", inventory = "E"
}

bindings.CHOICES = {
  attack = {"MOUSE1", "Q"},
  use = {"MOUSE2", "E"},
  pick = {"MOUSE3", "R"},
  forward = {"W", "UP"},
  back = {"S", "DOWN"},
  left = {"A", "LEFT"},
  right = {"D", "RIGHT"},
  jump = {"SPACE", "R"},
  sneak = {"CTRL", "C"},
  drop = {"Q", "R"},
  inventory = {"E", "R"}
}

local keyCodes = {
  W = glfw.GLFW_KEY_W, A = glfw.GLFW_KEY_A, S = glfw.GLFW_KEY_S, D = glfw.GLFW_KEY_D,
  E = glfw.GLFW_KEY_E, Q = glfw.GLFW_KEY_Q, R = glfw.GLFW_KEY_R, C = glfw.GLFW_KEY_C,
  UP = glfw.GLFW_KEY_UP, DOWN = glfw.GLFW_KEY_DOWN,
  LEFT = glfw.GLFW_KEY_LEFT, RIGHT = glfw.GLFW_KEY_RIGHT,
  SPACE = glfw.GLFW_KEY_SPACE, CTRL = glfw.GLFW_KEY_LEFT_CONTROL
}

local mouseButtons = {
  MOUSE1 = glfw.GLFW_MOUSE_BUTTON_LEFT,
  MOUSE2 = glfw.GLFW_MOUSE_BUTTON_RIGHT,
  MOUSE3 = glfw.GLFW_MOUSE_BUTTON_MIDDLE
}

function bindings.label(controlBindings, action)
  return (controlBindings and controlBindings[action]) or bindings.DEFAULTS[action]
end

function bindings.down(window, label)
  local mouse = mouseButtons[label]
  if mouse then return glfw.glfwGetMouseButton(window, mouse) == glfw.GLFW_PRESS end
  local key = keyCodes[label]
  return key and glfw.glfwGetKey(window, key) == glfw.GLFW_PRESS or false
end

function bindings.actionDown(window, controlBindings, action)
  return bindings.down(window, bindings.label(controlBindings, action))
end

return bindings
