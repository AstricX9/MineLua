package.path = "src/?.lua;" .. package.path

local character = require("character")
local texture = require("texture")

local skin = assert(texture.loadPng(character.DEFAULT_SKIN))
assert(skin.w == 64 and skin.h == 64, "the default player uses a modern 64x64 skin")
local transparent, opaque = 0, 0
for index = 3, skin.w * skin.h * 4 - 1, 4 do
  if skin.data[index] == 0 then transparent = transparent + 1 end
  if skin.data[index] == 255 then opaque = opaque + 1 end
end
assert(transparent > 0 and opaque > 0,
  "the skin preserves transparent overlays as well as opaque base pixels")

local vertices = character.buildPlayerMesh({0, 0, 0}, {model = "classic"})
local stride = character.VERTEX_STRIDE_FLOATS
assert(#vertices % stride == 0, "the procedural character mesh must use its declared stride")

local seen, baseVertices, overlayVertices = {}, 0, 0
for offset = 1, #vertices, stride do
  local u, v = vertices[offset + 9], vertices[offset + 10]
  local part = vertices[offset + 11]
  local overlay = vertices[offset + 12]
  assert(u >= 0 and u <= 1 and v >= 0 and v <= 1,
    "all skin UVs stay within the 64x64 texture")
  assert(part >= character.PART.HEAD and part <= character.PART.LEFT_LEG,
    "every vertex belongs to one rigid body part")
  seen[part] = true
  if overlay > 0.5 then overlayVertices = overlayVertices + 1 else baseVertices = baseVertices + 1 end
end
for _, part in pairs(character.PART) do
  assert(seen[part], "every articulated body part is represented in the mesh")
end
assert(baseVertices == overlayVertices,
  "base skin and transparent outer layer cover the same articulated parts")

local standing = character.animationState({
  velocity = {0, 0, 0}, sprintSpeed = 7.2, bobPhase = 1.25, pitch = 30,
  eyeHeight = 1.62, standEyeHeight = 1.62, crouchEyeHeight = 1.24,
  grounded = true, velocityY = 0
}, {}, 5)
assert(standing.anim0[2] == 0 and standing.anim0[4] == 0,
  "an idle standing player has no gait or crouch blend")
assert(math.abs(standing.anim1[1] - math.rad(30)) < 0.0001 and standing.anim1[3] == 1,
  "head aim and grounded state reach the rig")

local active = character.animationState({
  velocity = {7.2, -2, 0}, sprintSpeed = 7.2, bobPhase = 2.5, pitch = -20,
  eyeHeight = 1.24, standEyeHeight = 1.62, crouchEyeHeight = 1.24,
  grounded = false, velocityY = -2
}, {handSwinging = true, handSwing = 0.45}, 8)
assert(active.anim0[2] == 1 and active.anim0[4] == 1,
  "full-speed movement and crouching produce full animation blends")
assert(active.anim1[2] == -2 and active.anim1[3] == 0 and active.anim1[4] == 0.45,
  "airborne and attack state reach the procedural pose")

print("character animation tests passed")
