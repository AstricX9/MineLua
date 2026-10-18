package.path = "src/?.lua;" .. package.path

local blocks = require("blocks")
local items = require("items")
local texture = require("texture")
local heldItem = require("held_item")

-- The model builders read the atlas UVs blocks pick up at load time.
local atlas = texture.createAtlas()
blocks.initTextures(atlas)
items.initTextures(atlas)

local defaults = heldItem.DEFAULTS
assert(defaults.size > 0 and defaults.perspective > 1.2, "the authored placement must be usable")
assert(math.abs(defaults.xInset - 281.6) < 0.001 and
  math.abs(defaults.yInset - 172.8) < 0.001 and defaults.size == 720.0 and
  defaults.roll == 0.0 and defaults.yaw == -45.0 and defaults.pitch == 0.0 and
  defaults.depth == -0.72,
  "the rest pose should match Minecraft's standard right-hand transform")

-- Tools extrude every opaque texel, so the model is far more than two quads and
-- carries several distinct normals.
local axe = heldItem.model(items.mapping.wood_axe)
assert(axe and axe.sprite, "a tool should build as a sprite model")
assert(axe.source == items.mapping.wood_axe.texture, "a sprite binds its own source image, not the atlas")
assert(#axe.vertices % (heldItem.STRIDE_FLOATS * 3) == 0, "the model must be whole triangles")
assert(#axe.vertices / heldItem.STRIDE_FLOATS > 200, "the pixel perimeter should be extruded")

local normals = {}
for i = 0, #axe.vertices / heldItem.STRIDE_FLOATS - 1 do
  local base = i * heldItem.STRIDE_FLOATS
  normals[table.concat({axe.vertices[base + 4], axe.vertices[base + 5], axe.vertices[base + 6]}, ",")] = true
end
local normalCount = 0
for _ in pairs(normals) do normalCount = normalCount + 1 end
assert(normalCount >= 5, "front, back and side walls all need their own normal")

for i = 1, #axe.vertices, heldItem.STRIDE_FLOATS do
  local x, y, z = axe.vertices[i], axe.vertices[i + 1], axe.vertices[i + 2]
  assert(math.abs(x) <= 0.5001 and math.abs(y) <= 0.5001 and math.abs(z) <= 0.5001,
    "model space is the unit cube; the pose scales it")
end

-- Blocks are cubes off the shared atlas rather than flat cards.
local log = heldItem.model(blocks.mapping.oak_log)
assert(log and not log.sprite and log.atlas, "a block should build as an atlas-textured cube")
assert(#log.vertices / heldItem.STRIDE_FLOATS == 36, "a cube is six quads")
assert(heldItem.BLOCK_SCALE < 1.0, "a cube fills its square, so it needs less nominal size than a tool")

-- Cross-shaped plants are sprites even though they are blocks.
local flower = heldItem.model(blocks.mapping.dandelion)
assert(flower.sprite and flower.source, "flowers should extrude their own texture")

-- Rest pose is the identity: nothing should move before the first swing.
local rest = heldItem.swingPose(0)
assert(rest.roll == 0 and rest.pitch == 0 and rest.x == 0 and rest.y == 0,
  "an idle hand must not be displaced")
local mid = heldItem.swingPose(0.35)
assert(math.abs(mid.roll) > 20 and math.abs(mid.pitch) > 15, "the strike should be a real arc")
assert(heldItem.swingPose(1.0).roll == heldItem.swingPose(0.0).roll, "the cycle must close")

-- The complete 340 ms felling swing passes through all nine supplied tuner
-- poses, including size, depth and perspective rather than just screen motion.
assert(heldItem.isHeavy(items.mapping.wood_axe), "axes swing heavy")
assert(not heldItem.isHeavy(items.mapping.wood_pickaxe), "pickaxes keep the quick tap")
local function close(actual, expected, label)
  assert(math.abs(actual - expected) < 0.001,
    string.format("%s: expected %.3f, got %.3f", label, expected, actual))
end
local supplied = {
  {0,   161.5, 254.7, 526.8,  35.8, -46.1,  -2.0},
  {45,  105.0, 235.0, 535.0,  47.0, -52.0,  -4.0},
  {85,  145.0, 270.0, 545.0,  30.0, -48.0,  -7.0},
  {120, 310.0, 300.0, 560.0,   5.0, -40.0, -11.0},
  {150, 540.0, 290.0, 575.0, -28.0, -28.0, -14.0},
  {180, 720.0, 255.0, 555.0, -48.0, -20.0, -10.0},
  {230, 430.0, 230.0, 535.0, -10.0, -34.0,  -5.0},
  {285, 230.0, 245.0, 528.0,  24.0, -43.0,  -3.0},
  {340, 161.5, 254.7, 526.8,  35.8, -46.1,  -2.0}
}
for index, expected in ipairs(supplied) do
  local pose = heldItem.swingPose(expected[1] / 340, "chop")
  local label = "keyframe " .. index
  local reference = heldItem.CHOP_REFERENCE
  close(defaults.xInset + pose.xInset, defaults.xInset + expected[2] - reference.xInset, label .. " x")
  close(defaults.yInset + pose.yInset, defaults.yInset + expected[3] - reference.yInset, label .. " y")
  close(defaults.size * pose.scale, defaults.size * expected[4] / reference.size, label .. " size")
  close(defaults.roll + pose.roll, defaults.roll + expected[5] - reference.roll, label .. " roll")
  close(defaults.yaw + pose.yaw, defaults.yaw + expected[6] - reference.yaw, label .. " yaw")
  close(defaults.pitch + pose.pitch, defaults.pitch + expected[7] - reference.pitch, label .. " pitch")
  close(pose.thickness, 0.0625, label .. " depth")
  close(pose.perspective, 3.20, label .. " perspective")
end
local farPose = heldItem.swingPose(180 / 340, "chop")
local returnPose = heldItem.swingPose(230 / 340, "chop")
assert(farPose.xInset > returnPose.xInset,
  "the second take should reverse direction after the 180 ms far pose")
assert(heldItem.swingPose(1.0, "chop").xInset == 0 and
  heldItem.swingPose(1.0, "chop").roll == 0,
  "the supplied final frame must return exactly to the starting pose")
assert(heldItem.CHOP_SECONDS == 0.340,
  "the supplied millisecond timing should drive the animation directly")

-- It must pass through a keyframe without pausing there. Matching finite
-- differences on both sides catches the old per-segment easing behaviour.
local keyTime, epsilon = 150 / 340, 0.001
local keyPose = heldItem.swingPose(keyTime, "chop")
local beforeKey = heldItem.swingPose(keyTime - epsilon, "chop")
local afterKey = heldItem.swingPose(keyTime + epsilon, "chop")
local incomingSpeed = (keyPose.xInset - beforeKey.xInset) / epsilon
local outgoingSpeed = (afterKey.xInset - keyPose.xInset) / epsilon
assert(incomingSpeed > 100 and outgoingSpeed > 100 and
  math.abs(incomingSpeed - outgoingSpeed) < math.max(incomingSpeed, outgoingSpeed) * 0.05,
  "the axe should flow smoothly through the middle pose without braking")

-- Equipping lifts the model from below and settles at the authored pose.
assert(heldItem.equipPose(0).y < -0.5, "a new item starts below the frame")
assert(math.abs(heldItem.equipPose(1).y) < 1e-9, "and finishes exactly at rest")

-- The swing cycle repeats while attacking and stops cleanly when released.
local state = {handSwing = 0.0, handSwinging = false}
assert(heldItem.updateSwing(state, 0.0, true) == false, "a swing does not land on the button press")
assert(state.handSwinging and state.handSwingStyle == "quick", "an attack starts a fresh swing")
heldItem.updateSwing(state, heldItem.SWING_SECONDS * 0.5, true)
assert(state.handSwing > 0.4 and state.handSwing < 0.6, "the phase should track real time")
heldItem.updateSwing(state, heldItem.SWING_SECONDS, true)
assert(state.handSwinging and state.handSwing < 1.0, "holding attack keeps swinging")
heldItem.updateSwing(state, heldItem.SWING_SECONDS, false)
assert(not state.handSwinging and state.handSwing == 0.0, "releasing ends the swing at rest")

-- One press completes both takes and lands twice, even when the button is
-- released immediately after its press edge.
local chopper = {handSwing = 0.0, handSwinging = false}
local step, elapsed, blows = 1 / 60, 0.0, 0
assert(heldItem.updateSwing(chopper, 0.0, true, true) == false, "the blade has not arrived yet")
assert(chopper.handSwingStyle == "chop", "an axe should swing heavy")
local firstBlow, secondBlow = nil, nil
while chopper.handSwinging and elapsed < heldItem.CHOP_SECONDS + 0.1 do
  if heldItem.updateSwing(chopper, step, false, true) then
    blows = blows + 1
    if not firstBlow then firstBlow = elapsed else secondBlow = elapsed end
  end
  elapsed = elapsed + step
end
assert(blows == 2, "one axe input should land both takes, got " .. blows)
assert(firstBlow and secondBlow and
  math.abs(firstBlow - heldItem.CHOP_SECONDS * heldItem.CHOP_IMPACT_A) < 2 / 60 and
  math.abs(secondBlow - heldItem.CHOP_SECONDS * heldItem.CHOP_IMPACT_B) < 2 / 60,
  "the 150 ms and 230 ms takes should each have their own impact")
assert(not chopper.handSwinging and chopper.handSwing == 0.0,
  "the two-take action returns to its original rest pose")

-- Sway follows the view and decays back to nothing when the camera settles.
local motion = {lookX = 0, lookY = 0, bob = 0, walkPhase = 0}
local camera = {yaw = 0, pitch = 0, velocity = {0, 0, 0}, grounded = true}
heldItem.updateMotion(motion, camera, 1 / 60)
camera.yaw = 12
heldItem.updateMotion(motion, camera, 1 / 60)
assert(motion.lookX > 0, "turning right should push the hand")
local turned = heldItem.motionOffset(motion)
assert(turned.x < 0, "xInset counts from the right edge, so the hand trails the turn")
for _ = 1, 240 do heldItem.updateMotion(motion, camera, 1 / 60) end
assert(math.abs(heldItem.motionOffset(motion).x) < 1.0, "a still camera should settle back")

-- Held-item sway changes side across the stride, but advances on its own
-- slower cycle so camera-bob tuning cannot make the carried item feel frantic.
camera.velocity = {0, 0, -5.1}
camera.walkSpeed = 5.1
motion.bob = 1.0
motion.walkPhase = 0.0
local phaseBefore = motion.walkPhase
heldItem.updateMotion(motion, camera, 1 / 60)
local phaseAfter = motion.walkPhase
local firstFoot = heldItem.motionOffset({bob = 1.0, walkPhase = 0.0})
local otherFoot = heldItem.motionOffset({bob = 1.0, walkPhase = 0.5})
assert(firstFoot.x * otherFoot.x < 0,
  "the carried item should sway toward opposite sides on opposite footsteps")
assert(phaseAfter > phaseBefore and
  math.abs(phaseAfter - heldItem.WALK_CYCLES_PER_METRE * 5.1 / 60) < 0.0001,
  "held-item gait should advance on its own distance-based cycle")
local highStep = heldItem.motionOffset({bob = 1.0, walkPhase = 0.25})
assert(math.abs(firstFoot.x) >= 17.0 and highStep.y >= 9.0,
  "held-item gait should have a broad, clearly visible excursion")

-- A yaw that wraps past 180 degrees is a small turn, not a full spin.
motion.yaw, motion.lookX = 179, 0
camera.yaw = -179
heldItem.updateMotion(motion, camera, 1 / 60)
assert(math.abs(motion.lookX) < 200, "wrapping yaw must not read as an enormous turn rate")

print("held item tests passed")
