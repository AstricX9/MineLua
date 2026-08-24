local flow = {}

local function cycleValue(current, values)
  for index = 1, #values do
    if values[index] == current then
      return values[index % #values + 1]
    end
  end
  return values[1]
end

local CONTROL_CHOICES = {
  attack = {"MOUSE1", "Q"},
  use = {"MOUSE2", "E"},
  pick = {"MOUSE3", "R"},
  forward = {"W", "UP"},
  back = {"S", "DOWN"},
  left = {"A", "LEFT"},
  right = {"D", "RIGHT"},
  jump = {"SPACE", "R"},
  sneak = {"CTRL", "C"},
  drop = {"Q", "R"},
  inventory = {"E", "R"}
}

local function queueWorldStart(state, gameMode, generatorType, worldName, existingWorld)
  state.worldGameMode = gameMode or state.worldGameMode or "survival"
  state.worldGeneratorType = generatorType or state.worldGeneratorType or "default"
  state.pendingNewWorldConfig = {
    gameMode = state.worldGameMode,
    generatorType = state.worldGeneratorType,
    seed = tonumber(state.worldSeedText),
    worldName = worldName or "New World",
    generateStructures = state.generateStructures ~= false,
    allowCheats = state.allowCheats == true,
    bonusChest = state.bonusChest == true,
    renderDistance = state.renderDistance,
    existingWorld = existingWorld
  }
  state.hasWorld = false
  state.screen = "loading"
  state.menuParentScreen = nil
end

local function returnFromOptions(state)
  state.screen = state.menuParentScreen or (state.hasWorld and "pause" or "main")
  state.menuParentScreen = nil
end

function flow.back(state)
  if state.screen == nil then
    state.screen = "pause"
  elseif state.screen == "pause" then
    state.screen = nil
  elseif state.screen == "inventory" or state.screen == "creative_inventory" or state.screen == "crafting_table" then
    state.screen = nil
  elseif state.screen == "select_world" or state.screen == "multiplayer" or state.screen == "texture_packs" then
    state.screen = "main"
  elseif state.screen == "options" then
    returnFromOptions(state)
  elseif state.screen == "create_world" then
    state.screen = "select_world"
  elseif state.screen == "confirm_delete_world" then
    state.screen = "select_world"
    state.pendingDeleteWorld = nil
  elseif state.screen == "video" or state.screen == "controls" then
    state.screen = "options"
  elseif state.screen == "achievements" or state.screen == "stats" then
    state.screen = "pause"
  end
end

function flow.applyAction(state, action)
  if not action or action == "noop" then
    return nil
  end

  if action == "singleplayer" then
    state.screen = "select_world"
    state.refreshWorldListRequested = true
  elseif action == "multiplayer" then
    state.screen = "multiplayer"
  elseif action == "texture_packs" then
    state.screen = "texture_packs"
  elseif action == "start_survival" then
    queueWorldStart(state, "survival", "default", "Survival World")
    return "started_world"
  elseif action == "start_creative" then
    queueWorldStart(state, "creative", "default", "Creative World")
    return "started_world"
  elseif action == "create_world" then
    state.screen = "create_world"
    state.moreWorldOptions = false
    state.worldNameText = "New World"
    state.worldNamePristine = true
    state.worldSeedText = ""
    state.generateStructures = true
    state.allowCheats = false
    state.bonusChest = false
  elseif action == "mode_survival" then
    state.worldGameMode = "survival"
  elseif action == "mode_creative" then
    state.worldGameMode = "creative"
  elseif action == "toggle_more_world_options" then
    state.moreWorldOptions = not state.moreWorldOptions
  elseif action == "toggle_generator" then
    state.worldGeneratorType = state.worldGeneratorType == "superflat" and "default" or "superflat"
  elseif action == "toggle_structures" then
    state.generateStructures = not state.generateStructures
  elseif action == "toggle_cheats" then
    state.allowCheats = not state.allowCheats
  elseif action == "toggle_bonus_chest" then
    state.bonusChest = not state.bonusChest
  elseif action == "options" then
    state.menuParentScreen = state.screen == "pause" and "pause" or "main"
    state.screen = "options"
  elseif action == "video" then
    state.screen = "video"
  elseif action == "controls" then
    state.screen = "controls"
  elseif action == "achievements" then
    state.screen = "achievements"
  elseif action == "stats" then
    state.screen = "stats"
  elseif action == "done_options" then
    returnFromOptions(state)
  elseif action == "done_child" then
    state.screen = "options"
  elseif action == "back_main" then
    state.screen = "main"
  elseif action == "back_pause" then
    state.screen = "pause"
  elseif action == "back_select" then
    state.screen = "select_world"
  elseif action == "previous_world_page" then
    state.worldListPage = math.max(1, (state.worldListPage or 1) - 1)
  elseif action == "next_world_page" then
    state.worldListPage = (state.worldListPage or 1) + 1
  elseif action:match("^select_saved_world_%d+$") then
    state.selectedWorldIndex = tonumber(action:match("(%d+)$"))
  elseif action == "play_selected_world" then
    local selected = (state.savedWorlds or {})[state.selectedWorldIndex or 0]
    if selected then
      state.worldSeedText = tostring(selected.seed or 1)
      state.generateStructures = selected.generateStructures ~= false
      state.allowCheats = selected.allowCheats == true
      state.bonusChest = selected.bonusChest == true
      queueWorldStart(state, selected.gameMode, selected.generatorType, selected.worldName, selected)
      return "started_world"
    end
  elseif action == "delete_selected_world" then
    local selected = (state.savedWorlds or {})[state.selectedWorldIndex or 0]
    if selected then
      state.pendingDeleteWorld = selected
      state.screen = "confirm_delete_world"
    end
  elseif action == "confirm_delete_world" then
    if state.pendingDeleteWorld then
      state.deleteWorldRequested = state.pendingDeleteWorld
      state.pendingDeleteWorld = nil
      state.screen = "select_world"
    end
  elseif action == "cancel_delete_world" then
    state.pendingDeleteWorld = nil
    state.screen = "select_world"
  elseif action == "back_to_game" then
    state.screen = nil
    state.menuParentScreen = nil
    return "resume"
  elseif action == "quit_to_title" then
    state.screen = "main"
    state.menuParentScreen = nil
    state.hasWorld = false
    return "quit_to_title"
  elseif action == "start_world" then
    local worldName = tostring(state.worldNameText or "New World"):gsub("^%s+", ""):gsub("%s+$", "")
    if worldName == "" then worldName = "New World" end
    queueWorldStart(state, state.worldGameMode, state.worldGeneratorType, worldName)
    return "started_world"
  elseif action == "quit" then
    return "quit_game"
  elseif action == "toggle_invert_mouse" then
    state.invertMouse = not state.invertMouse
  elseif action == "cycle_music" then
    state.musicVolume = cycleValue(state.musicVolume, {0, 25, 50, 75, 100})
  elseif action == "cycle_sound" then
    state.soundVolume = cycleValue(state.soundVolume, {0, 25, 50, 75, 100})
  elseif action == "cycle_sensitivity" then
    state.sensitivity = cycleValue(state.sensitivity, {50, 75, 100, 125, 150})
  elseif action == "cycle_fov" then
    state.fovDegrees = cycleValue(state.fovDegrees, {60, 70, 80, 90, 100})
  elseif action == "cycle_difficulty" then
    state.difficulty = cycleValue(state.difficulty, {"Peaceful", "Easy", "Normal", "Hard"})
  elseif action == "toggle_graphics" then
    state.graphicsMode = state.graphicsMode == "Fast" and "Fancy" or "Fast"
  elseif action == "toggle_smooth_lighting" then
    state.smoothLighting = not state.smoothLighting
  elseif action == "toggle_vsync" then
    state.vsync = not state.vsync
  elseif action == "toggle_anaglyph" then
    state.anaglyph = not state.anaglyph
  elseif action == "toggle_view_bobbing" then
    state.viewBobbing = not state.viewBobbing
  elseif action == "cycle_gui_scale" then
    state.guiScale = cycleValue(state.guiScale, {0, 1, 2, 3, 4})
  elseif action == "toggle_fullscreen" then
    return "toggle_fullscreen"
  elseif action == "cycle_brightness" then
    state.brightness = cycleValue(state.brightness, {50, 75, 100, 125, 150})
  elseif action == "toggle_clouds" then
    state.clouds = not state.clouds
  elseif action == "toggle_bloom" then
    state.bloom = not state.bloom
  elseif action == "cycle_particles" then
    state.particles = cycleValue(state.particles, {"All", "Decreased", "Minimal"})
  elseif action:sub(1, 5) == "bind_" then
    local name = action:sub(6)
    local choices = CONTROL_CHOICES[name]
    if choices then
      state.controlBindings = state.controlBindings or {}
      state.controlBindings[name] = cycleValue(state.controlBindings[name], choices)
    end
  end

  return nil
end

function flow.applySlider(state, slider, value)
  if slider == "render_distance" then
    state.renderDistance = math.max(4, math.min(128, math.floor((tonumber(value) or 4) + 0.5)))
  end
end

return flow
