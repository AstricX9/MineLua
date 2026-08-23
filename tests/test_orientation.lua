-- Two things that were written for a world whose up is always +Y, and quietly
-- did the wrong thing once the world became a sphere.

package.path = "src/?.lua;" .. package.path

local atmosphere = require("atmosphere")

-- 1. Scene lighting read the sun's height as sunDir[2]. For an observer on the
--    equator, whose up is roughly +Z, that component barely moves all day, so
--    the world sat in permanent dusk: never a blue noon, never a dark midnight.
local equatorUp = {0.0, 0.0, 1.0}
local noonSun = {0.0, 0.0, 1.0}
local midnightSun = {0.0, 0.0, -1.0}
local horizonSun = {1.0, 0.0, 0.0}

local noon = atmosphere.forSun(noonSun, 48.0, 360.0, equatorUp)
local midnight = atmosphere.forSun(midnightSun, 48.0, 360.0, equatorUp)
local dusk = atmosphere.forSun(horizonSun, 48.0, 360.0, equatorUp)

assert(noon.daylight > 0.99,
  string.format("the noon sun overhead is full daylight (saw %.3f)", noon.daylight))
assert(midnight.daylight < 0.01,
  string.format("the midnight sun underfoot is night (saw %.3f)", midnight.daylight))
assert(dusk.daylight > 0.4 and dusk.daylight < 1.0,
  string.format("a sun on the horizon is neither (saw %.3f)", dusk.daylight))

local function luminance(color) return color[1] * 0.2126 + color[2] * 0.7152 + color[3] * 0.0722 end
assert(luminance(noon.ambient) > luminance(midnight.ambient) * 6.0,
  "noon is far brighter than midnight")
assert(noon.fogColor[3] > noon.fogColor[1], "daytime fog is blue")
assert(midnight.fogColor[3] < 0.15, "night fog is dark")

-- The same sun, judged from a pole, has to give a different answer than from
-- the equator, or the observer up is not being used at all.
local poleUp = {0.0, 1.0, 0.0}
local fromPole = atmosphere.forSun(noonSun, 48.0, 360.0, poleUp)
assert(math.abs(fromPole.sunElevation) < 1e-9,
  "the same sun sits on the horizon of an observer a quarter turn away")
assert(fromPole.daylight < noon.daylight - 0.1,
  string.format("and is dimmer there than overhead (%.3f against %.3f)",
    fromPole.daylight, noon.daylight))

-- 2. Face UVs were fixed to a +Y up, so on a planet the grass fringe of a dirt
--    block ran up a vertical edge instead of along the top. The mesher rotates
--    the UV assignment to follow the local up; check the rotation directly.
local file = io.open("src/voxel.lua", "r")
local source = file:read("*a")
file:close()
local voxel = assert(loadstring(
  source:gsub("\nreturn M\n%s*$", "\nM._faceUvRotation = faceUvRotation\nreturn M\n"),
  "voxel_probe"))()
local rotation = assert(voxel._faceUvRotation, "probe hook missing")

-- Face order is +X, -X, +Y, -Y, +Z, -Z.
local UP_Y = {0.0, 1.0, 0.0}
local UP_Z = {0.0, 0.0, 1.0}

-- With the original up, nothing may move: this is the shipped appearance.
for direction = 1, 6 do
  assert(rotation(direction, UP_Y) == 0,
    "a +Y world keeps the original UV assignment on face " .. direction)
end

-- With up along +Z the side faces are the four perpendicular to it. Some of
-- their corner lists already happen to point the right way, so the test is that
-- the answer responds to up at all -- the alignment itself is checked below.
local turned = 0
for direction = 1, 4 do
  if rotation(direction, UP_Z) ~= 0 then turned = turned + 1 end
end
assert(turned > 0, "the UV rotation follows the local up")

-- The rotation must place the texture top on the pair of corners furthest
-- along the local up, which is the property the fringe depends on.
local FACE_CORNERS = {
  {{1,0,1}, {1,0,0}, {1,1,0}, {1,1,1}},
  {{0,0,0}, {0,0,1}, {0,1,1}, {0,1,0}},
  {{0,1,1}, {1,1,1}, {1,1,0}, {0,1,0}},
  {{0,0,0}, {1,0,0}, {1,0,1}, {0,0,1}},
  {{0,0,1}, {1,0,1}, {1,1,1}, {0,1,1}},
  {{1,0,0}, {0,0,0}, {0,1,0}, {1,1,0}}
}
-- Corners 3 and 4 carry v0, the top edge of the texture.
local function topEdgeHeight(direction, up)
  local corners = FACE_CORNERS[direction]
  local r = rotation(direction, up)
  local total, count = 0.0, 0
  for corner = 1, 4 do
    local uv = (corner - 1 + r) % 4 + 1
    if uv == 3 or uv == 4 then
      local c = corners[corner]
      total = total + (c[1] - 0.5) * up[1] + (c[2] - 0.5) * up[2] + (c[3] - 0.5) * up[3]
      count = count + 1
    end
  end
  return total / count
end

for _, up in ipairs({UP_Y, UP_Z, {1.0, 0.0, 0.0}, {0.0, -1.0, 0.0}}) do
  for direction = 1, 6 do
    -- Skip the two faces that are top and bottom for this up: their corners are
    -- all at the same height, so there is nothing to align.
    local normal = ({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}})[direction]
    local alignment = normal[1]*up[1] + normal[2]*up[2] + normal[3]*up[3]
    if math.abs(alignment) < 0.5 then
      assert(topEdgeHeight(direction, up) > 0.0,
        string.format("face %d puts the texture top on its upper edge", direction))
    end
  end
end

print("orientation tests passed")
