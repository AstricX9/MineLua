package.path = "src/?.lua;src/?/init.lua;" .. package.path

local renderDistance = require("render_distance")
local flow = require("ui_flow")
local menu = require("ui_menu")

assert(renderDistance.clamp(-10) == 4)
assert(renderDistance.clamp(200) == 128)
assert(renderDistance.clamp(23.6) == 24)
assert(renderDistance.fullDetailRadius(24, 8) == 8)
assert(renderDistance.fullDetailRadius(4, 8) == 4)

local start4, finish4 = renderDistance.fogRange(4, 48)
local start24, finish24 = renderDistance.fogRange(24, 48)
local _, finish128 = renderDistance.fogRange(128, 48)
assert(start4 == 40 and finish4 == 56)
assert(start24 == 48 and finish24 == 360,
  "the default retains its authored 360-block horizon")
assert(finish128 > finish24,
  "larger render distances expand the visible atmosphere horizon")

local state = {renderDistance = 24}
flow.applySlider(state, "render_distance", 48)
assert(state.renderDistance == 48 and state.renderDistanceRevision == 1)
flow.applySlider(state, "render_distance", 48)
assert(state.renderDistanceRevision == 1, "unchanged slider values do not retrigger updates")

local buttons = menu.buttons("video", 640, 360, state)
local slider
for i = 1, #buttons do
  if buttons[i].id == "render_distance" then slider = buttons[i] break end
end
assert(slider and slider.value == 48 and slider.label == "Horizon" and slider.valueLabel == "48 ch")

print("render distance tests passed")
