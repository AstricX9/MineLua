package.path = "src/?.lua;" .. package.path

local keys = {}
local glfw = {
  GLFW_PRESS = 1, GLFW_RELEASE = 0,
  GLFW_KEY_SPACE = 32, GLFW_KEY_W = 87, GLFW_KEY_A = 65,
  GLFW_KEY_S = 83, GLFW_KEY_D = 68, GLFW_KEY_LEFT_CONTROL = 341,
  GLFW_KEY_LEFT_SHIFT = 340
}
function glfw.glfwGetKey(_, key) return keys[key] and glfw.GLFW_PRESS or glfw.GLFW_RELEASE end
package.loaded.glfw = glfw

local Camera = require("camera")
local textInput = require("text_input")
local uiMenu = require("ui_menu")

local perspective = Camera.new({position = {10, 20, 30}, yaw = -90, pitch = 0,
  thirdPersonDistance = 4})
assert(perspective:cyclePerspective() == 1, "F5 first selects the rear third-person view")
local rear = perspective:getViewPosition()
assert(math.abs(rear[3] - 34) < 0.001 and perspective:getViewFront()[3] < -0.99,
  "rear third person looks over the player's back")
assert(perspective:cyclePerspective() == 2, "F5 next selects the front third-person view")
local front = perspective:getViewPosition()
assert(math.abs(front[3] - 26) < 0.001 and perspective:getViewFront()[3] > 0.99,
  "front third person faces the player")
perspective:updatePerspectiveObstruction({raycast = function() return {distance = 1.0} end})
assert(math.abs(perspective.thirdPersonActualDistance - 0.82) < 0.001,
  "third-person camera pulls in before a wall")
assert(perspective:cyclePerspective() == 0, "the third F5 press returns to first person")

local edited, caret = textInput.insert("New World", 3, "ly", 32)
assert(edited == "Newly World" and caret == 5, "text inserts at the clicked caret")
edited, caret = textInput.backspace(edited, caret)
assert(edited == "Newl World" and caret == 4, "backspace edits immediately before the caret")
edited, caret = textInput.delete(edited, caret)
assert(edited == "NewlWorld" and caret == 4, "delete edits immediately after the caret")

local worlds = {}
for index = 1, 12 do worlds[index] = {worldName = "World " .. index} end
local worldButtons = uiMenu.buttons("select_world", 640, 360,
  {savedWorlds = worlds, worldListScroll = 3})
assert(worldButtons[1].worldIndex == 4 and worldButtons[6].worldIndex == 9,
  "world-list scrolling exposes the next continuous run of saves")
for _, button in ipairs(worldButtons) do
  assert(button.id ~= "previous_world_page" and button.id ~= "next_world_page",
    "the world atlas no longer uses page arrows")
end

print("QoL control tests passed")
