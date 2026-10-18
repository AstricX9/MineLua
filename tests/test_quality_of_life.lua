package.path = "src/?.lua;" .. package.path

local ffi = require("ffi")

-- Camera input is read straight from GLFW, so the movement tests stub it.
local keys = {}
local glfw = {
  GLFW_PRESS = 1,
  GLFW_RELEASE = 0,
  GLFW_KEY_SPACE = 32,
  GLFW_KEY_W = 87,
  GLFW_KEY_A = 65,
  GLFW_KEY_S = 83,
  GLFW_KEY_D = 68,
  GLFW_KEY_LEFT_CONTROL = 341,
  GLFW_KEY_LEFT_SHIFT = 340
}
function glfw.glfwGetKey(_, key) return keys[key] and glfw.GLFW_PRESS or glfw.GLFW_RELEASE end
package.loaded.glfw = glfw

local Camera = require("camera")
local Inventory = require("inventory")
local hud = require("hud")
local texture = require("texture")

-- A single block at the origin column with nothing but void beside it.
local world = {maxHeight = 16}
function world:hasCollisionAtBlock() return true end
function world:containsBlock() return true end
function world:isSolidBlock(x, y, z) return y == 0 and x == 0 and z == 0 end

-- Sneaking refuses to step off the block; walking upright does not.
local function walkEast(crouching)
  local camera = Camera.new({position = {0.5, 1.0 + 1.62, 0.5}})
  camera.grounded = true
  camera.crouching = crouching
  camera.velocity[1] = 4.0
  for _ = 1, 40 do camera:moveHorizontally(1 / 60, world) end
  return camera.position[1]
end

local sneaked = walkEast(true)
local walked = walkEast(false)
assert(sneaked < walked - 1.0, "sneaking should stop well short of where walking ends up")

-- The invariant that matters is not a distance but the ground: sneaking may
-- only ever leave the player somewhere they are still held up, and walking off
-- the same edge must reach somewhere they are not.
local probe = Camera.new({position = {0.5, 1.0 + 1.62, 0.5}})
assert(probe:getSupportY(world, sneaked, 0.5), "a permitted sneak position still has ground under it")
assert(not probe:getSupportY(world, walked, 0.5), "walking upright does carry you past the edge")

-- Sneaking is only protective on the ground; it must not freeze a falling or
-- flying player in mid-air.
local airborne = Camera.new({position = {0.5, 2.62, 0.5}})
airborne.grounded = false
airborne.crouching = true
airborne.velocity[1] = 4.0
airborne:moveHorizontally(0.1, world)
assert(airborne.position[1] > 0.5, "sneaking in mid-air does not stop horizontal movement")

-- Pick block reaches past the hotbar: a stack in the backpack swaps into the
-- slot in hand rather than being ignored.
local inventory = Inventory.new("survival")
inventory.selected = 2
inventory.slots[2] = {item = "dirt", count = 4}
inventory.slots[21] = {item = "cobblestone", count = 9}
assert(inventory:pickBlock("cobblestone") == 2, "picking should land in the held slot")
assert(inventory.slots[2].item == "cobblestone" and inventory.slots[2].count == 9, "the found stack moves to hand")
assert(inventory.slots[21].item == "dirt", "and what was in hand takes its place")
assert(inventory:pickBlock("gold_ore") == nil, "picking something you do not own does nothing")

inventory.slots[5] = {item = "sand", count = 1}
assert(inventory:pickBlock("sand") == 5 and inventory.selected == 5,
  "a stack already on the hotbar is simply selected")

local creative = Inventory.new("creative")
creative.selected = 1
assert(creative:pickBlock("gold_ore") == 1 and creative.slots[1].item == "gold_ore",
  "creative conjures whatever you point at")

-- The message above the hotbar holds, fades, then goes away for good.
local overlay = setmetatable({}, hud)
overlay:setNotice("Cobblestone", 10.0)
assert(overlay:currentNotice(10.0).alpha == 1.0, "a fresh notice is fully opaque")
assert(overlay:currentNotice(10.5).text == "Cobblestone", "and reads back what was set")
local fading = overlay:currentNotice(12.0)
assert(fading and fading.alpha > 0.0 and fading.alpha < 1.0, "it fades rather than blinking out")
assert(overlay:currentNotice(30.0) == nil, "and eventually clears")
assert(overlay:currentNotice(30.0) == nil, "staying cleared once it has expired")

-- Screenshots are written as real PNGs. Re-read the stored deflate blocks to
-- prove the pixels survive the trip, and check the header describes them.
local width, height = 37, 11
local pixels = ffi.new("uint8_t[?]", width * height * 3)
for y = 0, height - 1 do
  for x = 0, width - 1 do
    local i = (y * width + x) * 3
    pixels[i] = (x * 7) % 256
    pixels[i + 1] = (y * 23) % 256
    pixels[i + 2] = (x + y) % 256
  end
end
local path = os.tmpname() .. ".png"
assert(texture.writePng(path, width, height, pixels, true), "the screenshot should be written")

local file = assert(io.open(path, "rb"))
local data = file:read("*a")
file:close()
os.remove(path)

assert(data:sub(1, 8) == "\137PNG\r\n\26\n", "PNG signature")
assert(data:sub(13, 16) == "IHDR", "IHDR comes first")
local function be32(offset)
  local a, b, c, d = data:byte(offset, offset + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end
assert(be32(17) == width and be32(21) == height, "the header carries the real size")
assert(data:byte(25) == 8 and data:byte(26) == 2, "eight bit truecolour")
assert(data:sub(-8) == "IEND\174\066\096\130", "and it ends properly")

-- Walk the stored blocks back into raw scanlines.
local idat = data:find("IDAT", 1, true) + 4
local cursor = idat + 2 -- past the zlib header
local raw = {}
repeat
  local final = data:byte(cursor)
  local low, high = data:byte(cursor + 1), data:byte(cursor + 2)
  local span = low + high * 256
  raw[#raw + 1] = data:sub(cursor + 5, cursor + 4 + span)
  cursor = cursor + 5 + span
until final == 1
raw = table.concat(raw)
assert(#raw == height * (1 + width * 3), "one filter byte plus one row of pixels per line")

for y = 0, height - 1 do
  local rowStart = y * (1 + width * 3)
  assert(raw:byte(rowStart + 1) == 0, "rows are written unfiltered")
  local source = height - 1 - y -- writePng was asked to flip, as OpenGL needs
  for _, x in ipairs({0, 1, 18, width - 1}) do
    local at = rowStart + 1 + x * 3
    assert(raw:byte(at + 1) == (x * 7) % 256 and
      raw:byte(at + 2) == (source * 23) % 256 and
      raw:byte(at + 3) == (x + source) % 256,
      string.format("pixel %d,%d survived the encode", x, y))
  end
end

print("quality of life tests passed")
