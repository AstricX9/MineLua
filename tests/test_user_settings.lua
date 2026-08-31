package.path = "src/?.lua;" .. package.path

local settings = require("user_settings")
local flow = require("ui_flow")
local motionBlur = require("motion_blur")
local menu = require("ui_menu")

local path = "tests/.tmp_user_settings.json"
local state = settings.apply({}, {
  soundVolume = 75,
  sensitivity = 125,
  invertMouse = true,
  fovDegrees = 90,
  renderDistance = 40,
  vsync = false,
  clouds = false,
  bloom = false,
  particles = "Minimal",
  viewBobbing = false,
  motionBlur = "Medium",
  fullscreen = true,
  controlBindings = {forward = "UP", inventory = "R"}
})

assert(settings.save(state, path))
local loaded = settings.load(path)
os.remove(path)

for _, key in ipairs({"soundVolume", "sensitivity", "invertMouse", "fovDegrees",
    "renderDistance", "vsync", "clouds", "bloom", "particles", "viewBobbing",
    "motionBlur", "fullscreen"}) do
  assert(loaded[key] == state[key], key .. " survives save and load")
end
assert(loaded.controlBindings.forward == "UP" and loaded.controlBindings.inventory == "R",
  "control bindings survive save and load")

flow.applyAction(loaded, "toggle_motion_blur_dropdown")
assert(loaded.openDropdown == "motion_blur")
flow.applyAction(loaded, "set_motion_blur_high")
assert(loaded.motionBlur == "High" and loaded.openDropdown == nil)

local lowX = motionBlur.vector("Low", 12, 4, 10, 3, 70, 16 / 9, true)
local highX = motionBlur.vector("High", 12, 4, 10, 3, 70, 16 / 9, true)
assert(math.abs(highX) > math.abs(lowX), "higher intensity produces a longer blur trail")
local offX, offY = motionBlur.vector("Off", 12, 4, 10, 3, 70, 16 / 9, true)
assert(offX == 0 and offY == 0, "off disables motion blur")

flow.applyAction(loaded, "toggle_motion_blur_dropdown")
local visualButtons = menu.buttons("video", 426, 240, loaded)
local ids = {}
for _, button in ipairs(visualButtons) do ids[button.id] = true end
assert(ids.toggle_motion_blur_dropdown and ids.set_motion_blur_high,
  "motion blur is presented as an open intensity dropdown")
assert(not ids.toggle_graphics and not ids.toggle_smooth_lighting and
  not ids.toggle_anaglyph and not ids.cycle_brightness and not ids.cycle_gui_scale,
  "non-functional visual settings are removed")

print("user settings tests passed")
