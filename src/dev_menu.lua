local ffi = require("ffi")
local glfw = require("glfw")
local graphics = require("graphics_settings")
local heldItem = require("held_item")

ffi.cdef[[
typedef struct MineLuaDevUiState {
  int menu_open;
  int environment_open;
  int generation_open;
  int override_time;
  float time_of_day;
  float fog_strength;
  int generation_dirty;
  int regenerate_requested;
  int export_requested;
  int export_status;
  int seed;
  float continent_scale;
  float biome_scale;
  float region_scale;
  float mountain_scale;
  float river_scale;
  float forest_scale;
  float macro_warp_scale;
  float macro_warp_amount;
  float detail_scale;
  float relief_gain;
  float local_relief_gain;
  float erosion_strength;
  float river_carve_strength;
  float lake_carve_strength;
  float mountain_sharpness;
  float grass_tint_strength;
  float tree_density;
  float shoreline_width;
  float rocky_shore_threshold;
  float biome_climate_influence;
  float snow_temperature;
  float elevation_cooling;
  float freeze_temperature;
  int preview_mode;
  int preview_rebuild_requested;
  int want_capture_mouse;
  int navigation_open;
  int fly_enabled;
  float fly_speed_multiplier;
  int freeze_streaming;
  int teleport_requested;
  int capture_requested;
  float teleport_latitude;
  float teleport_longitude;
  float teleport_altitude;
  float current_latitude;
  float current_longitude;
  float current_altitude;
  float time_scale;
  int held_item_open;
  float held_item_x_inset;
  float held_item_y_inset;
  float held_item_size;
  float held_item_roll;
  float held_item_yaw;
  float held_item_pitch;
  float held_item_thickness;
  float held_item_perspective;
} MineLuaDevUiState;

int ml_imgui_state_size(void);
int ml_imgui_init(void);
void ml_imgui_shutdown(void);
void ml_imgui_new_frame(float width, float height, float delta_time,
  float mouse_x, float mouse_y, int mouse_buttons);
void ml_imgui_draw(MineLuaDevUiState* state);
void ml_imgui_render(void);
]]

local native = ffi.load("lib/minelua_imgui_tools_v4.dll")

local DevMenu = {}
DevMenu.__index = DevMenu

function DevMenu.new()
  local luaStateSize=ffi.sizeof("MineLuaDevUiState")
  local nativeStateSize=tonumber(native.ml_imgui_state_size())
  if luaStateSize~=nativeStateSize then
    error(string.format("Developer UI state mismatch: Lua %d bytes, native %d bytes",luaStateSize,nativeStateSize))
  end
  if native.ml_imgui_init() == 0 then
    error("Failed to initialize Dear ImGui OpenGL renderer")
  end

  local state = ffi.new("MineLuaDevUiState[1]")
  state[0].menu_open = 0
  state[0].environment_open = 1
  state[0].generation_open = 0
  state[0].override_time = 0
  state[0].time_of_day = 6.0
  state[0].fog_strength = 1.0
  state[0].generation_dirty = 0
  state[0].regenerate_requested = 0
  state[0].export_requested = 0
  state[0].export_status = 0
  local generation = graphics.terrainGeneration
  state[0].seed = generation.seed or 1
  state[0].continent_scale = generation.continentScale or 0.00036
  state[0].biome_scale = generation.biomeScale or 0.00092
  state[0].region_scale = generation.regionScale or 0.00125
  state[0].mountain_scale = generation.mountainScale or 0.00078
  state[0].river_scale = generation.riverScale or 0.00115
  state[0].forest_scale = generation.forestScale or 0.00165
  state[0].macro_warp_scale = generation.macroWarpScale or 0.00062
  state[0].macro_warp_amount = generation.macroWarpAmount or 360.0
  state[0].detail_scale = generation.detailScale or 0.026
  state[0].relief_gain = generation.reliefGain or 2.4
  state[0].local_relief_gain = generation.localReliefGain or 2.0
  state[0].erosion_strength = generation.erosionStrength or 0.0
  state[0].river_carve_strength = generation.riverCarveStrength or 0.86
  state[0].lake_carve_strength = generation.lakeCarveStrength or 0.78
  state[0].mountain_sharpness = generation.mountainSharpness or 1.65
  state[0].grass_tint_strength = generation.grassTintStrength or 0.92
  state[0].tree_density = generation.treeDensity or 0.78
  state[0].shoreline_width = generation.shorelineWidth or 5.0
  state[0].rocky_shore_threshold = generation.rockyShoreThreshold or 0.24
  state[0].biome_climate_influence = generation.biomeClimateInfluence or 0.34
  state[0].snow_temperature = generation.snowTemperature or 0.18
  state[0].elevation_cooling = generation.elevationCooling or 0.0045
  state[0].freeze_temperature = generation.freezeTemperature or 0.08
  state[0].preview_mode = 0
  state[0].preview_rebuild_requested = 0
  state[0].want_capture_mouse = 0
  state[0].navigation_open = 0
  state[0].fly_enabled = 0
  state[0].fly_speed_multiplier = 1.0
  state[0].freeze_streaming = 0
  state[0].teleport_requested = 0
  state[0].capture_requested = 0
  state[0].teleport_latitude = 0.0
  state[0].teleport_longitude = 0.0
  state[0].teleport_altitude = 0.0
  state[0].current_latitude = 0.0
  state[0].current_longitude = 0.0
  state[0].current_altitude = 0.0
  state[0].time_scale = 1.0
  -- The panel opens on the authored placement, so "Reset held item" and a
  -- fresh launch agree with what the game ships.
  state[0].held_item_open = 0
  state[0].held_item_x_inset = heldItem.DEFAULTS.xInset
  state[0].held_item_y_inset = heldItem.DEFAULTS.yInset
  state[0].held_item_size = heldItem.DEFAULTS.size
  state[0].held_item_roll = heldItem.DEFAULTS.roll
  state[0].held_item_yaw = heldItem.DEFAULTS.yaw
  state[0].held_item_pitch = heldItem.DEFAULTS.pitch
  state[0].held_item_thickness = heldItem.DEFAULTS.thickness
  state[0].held_item_perspective = heldItem.DEFAULTS.perspective

  return setmetatable({state = state}, DevMenu)
end

function DevMenu:stagedGenerationSettings()
  local state = self.state[0]
  -- Preserve every central pipeline control even when the native tuning panel
  -- does not have a widget for it yet. Exported presets remain complete.
  local staged = {}
  for key, value in pairs(graphics.terrainGeneration) do staged[key] = value end
  staged.seed = tonumber(state.seed)
  staged.seaLevel = graphics.terrainGeneration.seaLevel or 63
  staged.continentScale = tonumber(state.continent_scale)
  staged.biomeScale = tonumber(state.biome_scale)
  staged.regionScale = tonumber(state.region_scale)
  staged.mountainScale = tonumber(state.mountain_scale)
  staged.riverScale = tonumber(state.river_scale)
  staged.forestScale = tonumber(state.forest_scale)
  staged.macroWarpScale = tonumber(state.macro_warp_scale)
  staged.macroWarpAmount = tonumber(state.macro_warp_amount)
  staged.detailScale = tonumber(state.detail_scale)
  staged.reliefGain = tonumber(state.relief_gain)
  staged.localReliefGain = tonumber(state.local_relief_gain)
  staged.terrainVerticalScale = math.max(0.1, staged.reliefGain / 2.4)
  staged.surfaceDetailStrength = math.max(0.0, staged.localReliefGain / 2.0)
  staged.erosionStrength = tonumber(state.erosion_strength)
  staged.riverCarveStrength = tonumber(state.river_carve_strength)
  staged.riverGridSize = math.max(28.0, math.min(112.0,
    56.0 * 0.00115 / math.max(0.0001, staged.riverScale)))
  staged.lakeCarveStrength = tonumber(state.lake_carve_strength)
  staged.mountainSharpness = tonumber(state.mountain_sharpness)
  staged.shorelineWidth = tonumber(state.shoreline_width)
  staged.rockyShoreThreshold = tonumber(state.rocky_shore_threshold)
  staged.biomeClimateInfluence = tonumber(state.biome_climate_influence)
  staged.snowTemperature = tonumber(state.snow_temperature)
  staged.elevationCooling = tonumber(state.elevation_cooling)
  staged.altitudeLapseRate = staged.elevationCooling
  staged.freezeTemperature = tonumber(state.freeze_temperature)
  staged.grassTintStrength = tonumber(state.grass_tint_strength)
  staged.treeDensity = tonumber(state.tree_density)
  return staged
end

function DevMenu:commitGenerationChanges(target)
  local staged = self:stagedGenerationSettings()
  for key, value in pairs(staged) do
    target[key] = value
  end
  self.state[0].generation_dirty = 0
  return staged
end

function DevMenu:setGenerationSeed(seed)
  if self.state[0].generation_dirty == 0 then
    self.state[0].seed = tonumber(seed) or self.state[0].seed
  end
end

function DevMenu:consumeRegenerateRequest()
  if self.state[0].regenerate_requested == 0 then
    return false
  end
  self.state[0].regenerate_requested = 0
  return true
end

function DevMenu:isPreviewMode()
  return self.state[0].preview_mode ~= 0
end

function DevMenu:setPreviewMode(enabled)
  self.state[0].preview_mode = enabled and 1 or 0
end

function DevMenu:consumePreviewRebuildRequest()
  if self.state[0].preview_rebuild_requested == 0 then
    return false
  end
  self.state[0].preview_rebuild_requested = 0
  return true
end

local function generationPresetJson(settings)
  local keys = {}
  for key, value in pairs(settings) do
    if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local lines = {"{", "  \"terrainGeneration\": {"}
  for index, key in ipairs(keys) do
    local value = settings[key]
    local encoded
    if type(value) == "number" then
      encoded = string.format("%.10g", value)
    elseif type(value) == "boolean" then
      encoded = tostring(value)
    else
      encoded = string.format("%q", value)
    end
    lines[#lines + 1] = string.format("    %q: %s%s", key, encoded, index < #keys and "," or "")
  end
  lines[#lines + 1] = "  }"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

function DevMenu:processExportRequest()
  if self.state[0].export_requested == 0 then
    return false
  end
  self.state[0].export_requested = 0
  local file = io.open("data/config/worldgen_tuning.json", "w")
  if not file then
    self.state[0].export_status = -1
    return false
  end
  file:write(generationPresetJson(self:stagedGenerationSettings()))
  file:close()
  self.state[0].export_status = 1
  return true
end

function DevMenu:isOpen()
  return self.state[0].menu_open ~= 0
end

function DevMenu:setOpen(open)
  self.state[0].menu_open = open and 1 or 0
end

function DevMenu:toggle()
  self:setOpen(not self:isOpen())
end

function DevMenu:usesTimeOverride()
  return self.state[0].override_time ~= 0
end

function DevMenu:timeOfDay()
  return tonumber(self.state[0].time_of_day)
end

function DevMenu:setNaturalTimeOfDay(hour)
  if not self:usesTimeOverride() then
    self.state[0].time_of_day = hour
  end
end

function DevMenu:fogStrength()
  return tonumber(self.state[0].fog_strength)
end

function DevMenu:heldItemTransform()
  local state=self.state[0]
  return {
    xInset=tonumber(state.held_item_x_inset),
    yInset=tonumber(state.held_item_y_inset),
    size=tonumber(state.held_item_size),
    roll=tonumber(state.held_item_roll),
    yaw=tonumber(state.held_item_yaw),
    pitch=tonumber(state.held_item_pitch),
    thickness=tonumber(state.held_item_thickness),
    perspective=tonumber(state.held_item_perspective)
  }
end

function DevMenu:wantsMouse()
  return self.state[0].want_capture_mouse ~= 0
end

function DevMenu:draw(window, framebufferWidth, framebufferHeight, deltaTime)
  local mouseX = ffi.new("double[1]")
  local mouseY = ffi.new("double[1]")
  local windowWidth = ffi.new("int[1]")
  local windowHeight = ffi.new("int[1]")
  glfw.glfwGetCursorPos(window, mouseX, mouseY)
  glfw.glfwGetWindowSize(window, windowWidth, windowHeight)

  local scaleX = framebufferWidth / math.max(1, tonumber(windowWidth[0]))
  local scaleY = framebufferHeight / math.max(1, tonumber(windowHeight[0]))
  local buttons = 0
  if glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS then buttons = buttons + 1 end
  if glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_RIGHT) == glfw.GLFW_PRESS then buttons = buttons + 2 end
  if glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_MIDDLE) == glfw.GLFW_PRESS then buttons = buttons + 4 end

  native.ml_imgui_new_frame(
    framebufferWidth,
    framebufferHeight,
    math.min(math.max(deltaTime or 0.0, 1.0 / 1000.0), 0.1),
    tonumber(mouseX[0]) * scaleX,
    tonumber(mouseY[0]) * scaleY,
    buttons
  )
  native.ml_imgui_draw(self.state)
  native.ml_imgui_render()
end

function DevMenu:release()
  native.ml_imgui_shutdown()
end

return DevMenu
