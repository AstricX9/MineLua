local ffi = require("ffi")
local glfw = require("glfw")
local graphics = require("graphics_settings")

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
} MineLuaDevUiState;

int ml_imgui_init(void);
void ml_imgui_shutdown(void);
void ml_imgui_new_frame(float width, float height, float delta_time,
  float mouse_x, float mouse_y, int mouse_buttons);
void ml_imgui_draw(MineLuaDevUiState* state);
void ml_imgui_render(void);
]]

local native = ffi.load("lib/minelua_imgui_tools_v2.dll")

local DevMenu = {}
DevMenu.__index = DevMenu

function DevMenu.new()
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

  return setmetatable({state = state}, DevMenu)
end

function DevMenu:stagedGenerationSettings()
  local state = self.state[0]
  return {
    seed = tonumber(state.seed),
    seaLevel = graphics.terrainGeneration.seaLevel or 63,
    continentScale = tonumber(state.continent_scale),
    biomeScale = tonumber(state.biome_scale),
    regionScale = tonumber(state.region_scale),
    mountainScale = tonumber(state.mountain_scale),
    riverScale = tonumber(state.river_scale),
    forestScale = tonumber(state.forest_scale),
    macroWarpScale = tonumber(state.macro_warp_scale),
    macroWarpAmount = tonumber(state.macro_warp_amount),
    detailScale = tonumber(state.detail_scale),
    reliefGain = tonumber(state.relief_gain),
    localReliefGain = tonumber(state.local_relief_gain),
    erosionStrength = tonumber(state.erosion_strength),
    riverCarveStrength = tonumber(state.river_carve_strength),
    lakeCarveStrength = tonumber(state.lake_carve_strength),
    mountainSharpness = tonumber(state.mountain_sharpness),
    shorelineWidth = tonumber(state.shoreline_width),
    rockyShoreThreshold = tonumber(state.rocky_shore_threshold),
    biomeClimateInfluence = tonumber(state.biome_climate_influence),
    snowTemperature = tonumber(state.snow_temperature),
    elevationCooling = tonumber(state.elevation_cooling),
    freezeTemperature = tonumber(state.freeze_temperature),
    grassTintStrength = tonumber(state.grass_tint_strength),
    treeDensity = tonumber(state.tree_density)
  }
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
  return string.format([[{
  "terrainGeneration": {
    "seed": %d,
    "seaLevel": %d,
    "continentScale": %.8g,
    "biomeScale": %.8g,
    "regionScale": %.8g,
    "mountainScale": %.8g,
    "riverScale": %.8g,
    "forestScale": %.8g,
    "macroWarpScale": %.8g,
    "macroWarpAmount": %.8g,
    "detailScale": %.8g,
    "reliefGain": %.8g,
    "localReliefGain": %.8g,
    "erosionStrength": %.8g,
    "riverCarveStrength": %.8g,
    "lakeCarveStrength": %.8g,
    "mountainSharpness": %.8g,
    "shorelineWidth": %.8g,
    "rockyShoreThreshold": %.8g,
    "biomeClimateInfluence": %.8g,
    "snowTemperature": %.8g,
    "elevationCooling": %.8g,
    "freezeTemperature": %.8g,
    "grassTintStrength": %.8g,
    "treeDensity": %.8g
  }
}
]], settings.seed, settings.seaLevel or 63, settings.continentScale,
    settings.biomeScale, settings.regionScale, settings.mountainScale,
    settings.riverScale, settings.forestScale, settings.macroWarpScale,
    settings.macroWarpAmount, settings.detailScale, settings.reliefGain,
    settings.localReliefGain, settings.erosionStrength,
    settings.riverCarveStrength, settings.lakeCarveStrength,
    settings.mountainSharpness, settings.shorelineWidth,
    settings.rockyShoreThreshold, settings.biomeClimateInfluence,
    settings.snowTemperature, settings.elevationCooling,
    settings.freezeTemperature, settings.grassTintStrength, settings.treeDensity)
end

function DevMenu:processExportRequest()
  if self.state[0].export_requested == 0 then
    return false
  end
  self.state[0].export_requested = 0
  local file = io.open("data/worldgen_tuning.json", "w")
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
