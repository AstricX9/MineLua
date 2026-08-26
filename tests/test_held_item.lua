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

-- The felling swing crosses the view rather than tapping on the spot: it cocks
-- back to the right first, then sweeps well past centre the other way.
assert(heldItem.isHeavy(items.mapping.wood_axe), "axes swing heavy")
assert(not heldItem.isHeavy(items.mapping.wood_pickaxe), "pickaxes keep the quick tap")
local windup = heldItem.swingPose(0.3, "chop")
local through = heldItem.swingPose(0.6, "chop")
assert(windup.x > 0.2 and windup.roll > 20, "the axe should cock back to the right")
assert(through.x < -0.8 and through.roll < -30, "and sweep the head across to the far side")
assert(math.abs(through.x) > math.abs(heldItem.swingPose(0.6, "quick").x) * 8,
  "the felling sweep travels far further than a tap")
assert(heldItem.swingPose(1.0, "chop").x == 0, "the felling cycle must close too")
assert(heldItem.CHOP_SECONDS > heldItem.SWING_SECONDS * 4, "a felling swing is a slow, heavy thing")

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

-- A held attack lands one blow per cycle, at the impact point rather than the
-- start, and a heavy swing takes the whole chop interval to come round again.
local chopper = {handSwing = 0.0, handSwinging = false}
local step, elapsed, blows = 1 / 60, 0.0, 0
assert(heldItem.updateSwing(chopper, 0.0, true, true) == false, "the blade has not arrived yet")
assert(chopper.handSwingStyle == "chop", "an axe should swing heavy")
local firstBlow = nil
while elapsed < heldItem.CHOP_SECONDS * 3 do
  if heldItem.updateSwing(chopper, step, true, true) then
    blows = blows + 1
    firstBlow = firstBlow or elapsed
  end
  elapsed = elapsed + step
end
assert(blows == 3, "three cycles should land exactly three blows, got " .. blows)
assert(firstBlow > heldItem.CHOP_SECONDS * 0.3, "the first blow lands partway through the swing")

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

-- A yaw that wraps past 180 degrees is a small turn, not a full spin.
motion.yaw, motion.lookX = 179, 0
camera.yaw = -179
heldItem.updateMotion(motion, camera, 1 / 60)
assert(math.abs(motion.lookX) < 200, "wrapping yaw must not read as an enormous turn rate")

print("held item tests passed")
