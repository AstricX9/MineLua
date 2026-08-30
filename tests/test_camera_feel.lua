package.path = "src/?.lua;" .. package.path

local keys = {}
local cursorX, cursorY = 0.0, 0.0
local glfw = {
  GLFW_PRESS = 1,
  GLFW_RELEASE = 0,
  GLFW_KEY_SPACE = 32,
  GLFW_KEY_W = 87,
  GLFW_KEY_A = 65,
  GLFW_KEY_S = 83,
  GLFW_KEY_D = 68,
  GLFW_KEY_F = 70,
  GLFW_KEY_LEFT_SHIFT = 340,
  GLFW_KEY_LEFT_CONTROL = 341
}
function glfw.glfwGetKey(_, key) return keys[key] and glfw.GLFW_PRESS or glfw.GLFW_RELEASE end
function glfw.glfwGetCursorPos(_, x, y) x[0], y[0] = cursorX, cursorY end
package.loaded.glfw = glfw

local Camera = require("camera")
local camera = Camera.new({position = {0.5, 2.62, 0.5}})
camera.grounded = true

-- Turning the movement input blends momentum across the corner instead of
-- replacing the old direction in a single frame.
keys[glfw.GLFW_KEY_W] = true
camera:applyHorizontalInput(0.05, nil)
assert(camera.velocity[3] < -2.0, "forward input accelerates the player")

keys[glfw.GLFW_KEY_W] = false
keys[glfw.GLFW_KEY_D] = true
camera:applyHorizontalInput(0.05, nil)
assert(camera.velocity[1] > 0.0 and camera.velocity[3] < 0.0,
  "direction changes retain a short, smooth momentum transition")

-- A mouse delta moves immediately, but the filtered view does not consume the
-- entire delta on one frame. It converges closely after a handful of frames.
camera:updateMouse(nil, 1.0 / 60.0)
cursorX = 100.0
camera:updateMouse(nil, 1.0 / 60.0)
assert(camera.yaw > -90.0 and camera.yaw < camera.targetYaw,
  "mouse filtering responds immediately without snapping")
for _ = 1, 12 do camera:updateMouse(nil, 1.0 / 60.0) end
assert(math.abs(camera.yaw - camera.targetYaw) < 0.01, "mouse filtering converges quickly")

-- Visual motion never mutates the collision position.
local physicalX, physicalY, physicalZ = camera.position[1], camera.position[2], camera.position[3]
camera.velocity[1], camera.velocity[3] = 4.0, 0.0
camera:updateViewMotion(1.0 / 60.0, physicalY, true, 0.0)
local viewPosition = camera:getViewPosition()
assert(camera.position[1] == physicalX and camera.position[2] == physicalY and camera.position[3] == physicalZ,
  "camera feel offsets do not alter collision position")
assert(viewPosition[1] ~= physicalX or viewPosition[2] ~= physicalY or viewPosition[3] ~= physicalZ,
  "walking produces a subtle visual camera offset")

-- Each planted foot pulls the view toward its side and rolls into that side;
-- the half-stride also contributes a small weighted pitch lift.
local gait = Camera.new({position = {0.5, 2.62, 0.5}, yaw = -90.0})
gait.grounded = true
gait.velocity[3] = -gait.walkSpeed
gait.bobPhase = -gait.walkSpeed * 0.05 * 1.85
gait:updateViewMotion(0.05, gait.position[2], true, 0.0)
local rightFootX, rightFootRoll = gait.viewBobX, gait.viewRoll
gait.viewBobX, gait.viewRoll = 0.0, 0.0
gait.bobPhase = math.pi - gait.walkSpeed * 0.05 * 1.85
gait:updateViewMotion(0.05, gait.position[2], true, 0.0)
assert(rightFootX * gait.viewBobX < 0.0 and rightFootRoll * gait.viewRoll < 0.0,
  "opposite footsteps should produce opposite weighted sway and roll")
gait.viewBobPitch = 0.0
gait.bobPhase = math.pi * 0.5 - gait.walkSpeed * 0.05 * 1.85
gait:updateViewMotion(0.05, gait.position[2], true, 0.0)
assert(gait.viewBobPitch > 0.05, "the middle of a stride should carry a visible pitch pulse")

-- Interactive developer windows are layered over gameplay. They suppress
-- mouse look, but the same update must still advance movement and view motion
-- so opening the tools never pauses the survival game.
local overlayCamera = Camera.new({position = {0.5, 2.62, 0.5}})
local mouseUpdates, movementUpdates, motionUpdates = 0, 0, 0
function overlayCamera:updateMouse() mouseUpdates = mouseUpdates + 1 end
function overlayCamera:updateMovement() movementUpdates = movementUpdates + 1 end
function overlayCamera:updateViewMotion() motionUpdates = motionUpdates + 1 end
overlayCamera:update(1.0 / 60.0, nil, nil, false)
assert(mouseUpdates == 0, "an interactive overlay should own the mouse")
assert(movementUpdates == 1 and motionUpdates == 1,
  "an interactive overlay must leave gameplay simulation running")
assert(overlayCamera.firstMouse, "mouse look should re-anchor after the overlay closes")
overlayCamera:update(1.0 / 60.0, nil, nil, true)
assert(mouseUpdates == 1 and movementUpdates == 2 and motionUpdates == 2,
  "normal camera updates should resume completely after the overlay closes")

print("camera feel tests passed")
