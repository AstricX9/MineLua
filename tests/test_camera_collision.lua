package.path = "src/?.lua;" .. package.path

local keys = {}
local glfw = {
  GLFW_PRESS = 1,
  GLFW_RELEASE = 0,
  GLFW_KEY_SPACE = 32,
  GLFW_KEY_W = 87,
  GLFW_KEY_A = 65,
  GLFW_KEY_S = 83,
  GLFW_KEY_D = 68,
  GLFW_KEY_F = 70,
  GLFW_KEY_LEFT_CONTROL = 341,
  GLFW_KEY_LEFT_SHIFT = 340
}
function glfw.glfwGetKey(_, key) return keys[key] and glfw.GLFW_PRESS or glfw.GLFW_RELEASE end
package.loaded.glfw = glfw

local Camera = require("camera")

local world = {maxHeight = 16}
function world:hasCollisionAtBlock() return true end
function world:containsBlock() return true end
function world:isSolidBlock(x, y, z)
  if y == 0 then return true end
  -- Full-height wall immediately east of the spawn column.
  if x == 1 and z == 0 and y >= 1 and y <= 4 then return true end
  -- A ceiling checks upward collision independently of the wall.
  if self.ceiling and x == 0 and z == 0 and y == 3 then return true end
  return false
end

local camera = Camera.new({position = {0.5, 2.62, 0.5}})
assert(camera.stepHeight < 1.0, "a full block cannot be climbed as an automatic step")

camera.velocity[1] = 5.0
camera:moveHorizontally(0.1, world)
assert(math.abs(camera.position[1] - 0.5) < 1e-9,
  "horizontal body collision blocks a jump through the wall")

-- Stumps occupy only their visible lower slice. They support the player at
-- that exact height and remain a small automatic step rather than an invisible
-- full-block wall.
function world:collisionHeightAt(x,y,z)
  if y==0 then return 1.0 end
  if self.stump and x==0 and y==1 and z==0 then return 0.32 end
  return self:isSolidBlock(x,y,z) and 1.0 or 0.0
end
world.stump=true
local stumpGround=camera:getGroundYAt(world,0.5,0.5)
assert(math.abs(stumpGround-(1.32+camera.eyeHeight))<1e-9,
  "partial-height stump collision should match the rendered stump top")
world.stump=false

world.ceiling = true
camera.velocityY = 6.4
camera:applyVerticalMovement(0.05, nil, world)
assert(camera.position[2] < 3.0 and camera.velocityY == 0.0,
  "vertical body collision stops the player at the ceiling")
world.ceiling = false

-- Jumping is press-edge triggered. Holding space after landing cannot queue a
-- second automatic jump.
camera.position[2] = 2.62
camera.velocityY = 0.0
camera.grounded = true
camera.jumpWasDown = false
keys[glfw.GLFW_KEY_SPACE] = true
camera:applyVerticalMovement(1.0 / 60.0, nil, world)
assert(camera.velocityY > 0.0, "the initial space press jumps")

camera.position[2] = 2.62
camera.velocityY = 0.0
camera.grounded = true
camera.coyoteTimer = camera.coyoteTime
camera.jumpBuffer = 0.0
camera:applyVerticalMovement(1.0 / 60.0, nil, world)
assert(camera.velocityY <= 0.0, "holding space does not auto-jump after landing")

-- Ground-following tolerance must not shorten an airborne fall. The old check
-- treated anything within groundSnap as landed and teleported the camera over
-- the entire remaining gap in one frame.
keys[glfw.GLFW_KEY_SPACE] = false
camera.position[2] = 2.62 + camera.groundSnap * 0.8
camera.velocityY = -1.0
camera.velocity[2] = camera.velocityY
camera.grounded = false
local beforeFall = camera.position[2]
camera:applyVerticalMovement(1.0 / 60.0, nil, world)
assert(not camera.grounded, "an airborne player remains airborne above the contact surface")
assert(camera.position[2] < beforeFall and camera.position[2] > 2.62,
  "the end of a fall advances under gravity instead of snapping to the ground")

print("camera collision tests passed")

-- Unloaded terrain is semi-blocking: low flight waits for collision data, but
-- high creative flight above the generator envelope can keep travelling while
-- the renderer catches up.
local frontier = {maxHeight = 127}
function frontier:hasCollisionAtBlock() return false end
function frontier:containsBlock() return false end
function frontier:isSolidBlock() return false end
local lowFlight = Camera.new({position = {0.5, 80.0, 0.5}})
lowFlight.flying = true
lowFlight.velocity[1] = 4.0
lowFlight:moveHorizontally(0.1, frontier)
assert(lowFlight.position[1] == 0.5, "unloaded terrain blocks flight inside the terrain envelope")
local highFlight = Camera.new({position = {0.5, 150.0, 0.5}})
highFlight.flying = true
highFlight.velocity[1] = 4.0
highFlight:moveHorizontally(0.1, frontier)
assert(highFlight.position[1] > 0.5, "flight above terrain remains non-blocking")

-- A manual jump needs enough discrete-time clearance to get the player's feet
-- above a full voxel before horizontal wall collision can release.
keys[glfw.GLFW_KEY_SPACE] = false
camera.position = {0.5, 2.62, 0.5}
camera.velocityY = 0.0
camera.grounded = true
camera.jumpWasDown = false
keys[glfw.GLFW_KEY_SPACE] = true
camera:applyVerticalMovement(1.0 / 60.0, nil, world)
keys[glfw.GLFW_KEY_SPACE] = false
local peak = camera.position[2]
local airborneFrames = 0
for _ = 1, 90 do
  camera:applyVerticalMovement(1.0 / 60.0, nil, world)
  peak = math.max(peak, camera.position[2])
  if not camera.grounded then airborneFrames = airborneFrames + 1 end
end
assert(peak - 2.62 > 1.20, "manual jump clears a full voxel with margin")
assert(airborneFrames >= 45,
  string.format("manual jump keeps a relaxed, non-snappy arc (saw %d frames)", airborneFrames))

-- Holding jump in water must provide sustained buoyancy rather than leaving the
-- player pinned to the bed.
function world:isLiquidBlock(_, y) return self.liquid and y >= 1 and y <= 2 end
world.liquid = true
camera.position = {0.5, 2.62, 0.5}
camera.velocityY = 0.0
camera.jumpWasDown = false
keys[glfw.GLFW_KEY_SPACE] = true
local swimPeak = camera.position[2]
for _ = 1, 90 do
  camera:applyVerticalMovement(1.0 / 60.0, nil, world)
  swimPeak = math.max(swimPeak, camera.position[2])
end
assert(swimPeak > 4.62, "swimming can carry the player above a two-block water column")

print("jump height and swimming tests passed")

-- Forward swimming follows view pitch, and explicit vertical controls combine
-- with it rather than switching that behaviour off.
function world:isLiquidBlock() return self.liquid end
camera.position = {0.5, 3.0, 0.5}
camera.velocityY = 0.0
camera.pitch = 60.0
keys[glfw.GLFW_KEY_SPACE] = false
keys[glfw.GLFW_KEY_W] = true
keys[glfw.GLFW_KEY_LEFT_CONTROL] = false
camera:applyVerticalMovement(0.1, nil, world)
assert(camera.velocityY > 0.0, "looking up while swimming forward climbs")

camera.velocityY = 0.0
camera.pitch = -60.0
camera:applyVerticalMovement(0.1, nil, world)
assert(camera.velocityY < 0.0, "looking down while swimming forward dives")

camera.velocityY = 0.0
camera.pitch = 90.0
keys[glfw.GLFW_KEY_SPACE] = true
for _ = 1, 30 do camera:applyVerticalMovement(1.0 / 30.0, nil, world) end
assert(camera.velocityY > camera.swimUpSpeed,
  "Space and upward aimed swimming reinforce one another")

camera.velocityY = 0.0
keys[glfw.GLFW_KEY_SPACE] = false
keys[glfw.GLFW_KEY_LEFT_CONTROL] = true
camera:applyVerticalMovement(0.1, nil, world)
assert(camera.velocityY <= 0.0, "Ctrl combines with aim to drive swimming downward")

print("aimed swimming controls passed")
