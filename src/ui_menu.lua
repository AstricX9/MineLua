local menu = {}

local function onOff(value)
  return value == false and "OFF" or "ON"
end

local function percent(value)
  return tostring(math.floor((value or 0) + 0.5)) .. "%"
end

local function bindingLabel(menuState, name, fallback)
  local bindings = menuState.controlBindings or {}
  return bindings[name] or fallback
end

function menu.buttons(screen, logicalWidth, logicalHeight, menuState)
  menuState = menuState or {}
  local cx = math.floor(logicalWidth * 0.5)

  if screen == "main" then
    local y = math.floor(logicalHeight / 4 + 48)
    return {
      {id = "singleplayer", label = "Singleplayer", x = cx - 100, y = y, w = 200, h = 20},
      {id = "multiplayer", label = "Multiplayer", x = cx - 100, y = y + 24, w = 200, h = 20},
      {id = "texture_packs", label = "Texture Packs", x = cx - 100, y = y + 48, w = 200, h = 20},
      {id = "options", label = "Options...", x = cx - 100, y = y + 84, w = 98, h = 20},
      {id = "quit", label = "Quit Game", x = cx + 2, y = y + 84, w = 98, h = 20}
    }
  elseif screen == "pause" then
    local y = math.floor(logicalHeight / 4 + 24)
    return {
      {id = "back_to_game", label = "Back to game", x = cx - 100, y = y, w = 200, h = 20},
      {id = "achievements", label = "Achievements", x = cx - 100, y = y + 24, w = 98, h = 20},
      {id = "stats", label = "Stats", x = cx + 2, y = y + 24, w = 98, h = 20},
      {id = "options", label = "Options...", x = cx - 100, y = y + 72, w = 200, h = 20},
      {id = "quit_to_title", label = "Quit to title", x = cx - 100, y = y + 96, w = 200, h = 20}
    }
  elseif screen == "select_world" then
    return {
      {id = "start_survival", label = "New Survival World", x = cx - 100, y = 64, w = 200, h = 20},
      {id = "start_creative", label = "New Creative World", x = cx - 100, y = 100, w = 200, h = 20},
      {id = "start_space", label = "New Space World", x = cx - 100, y = 136, w = 200, h = 20},
      {id = "create_world", label = "Create New World...", x = cx - 100, y = 172, w = 200, h = 20},
      {id = "back_main", label = "Cancel", x = cx - 100, y = logicalHeight - 28, w = 200, h = 20}
    }
  elseif screen == "create_world" then
    local mode = menuState.worldGameMode or "survival"
    local generator = menuState.worldGeneratorType or "default"
    local modeLabel = mode == "creative" and "Game Mode: Creative" or "Game Mode: Survival"
    local generatorLabel = generator == "superflat" and "World Type: Superflat" or "World Type: Default"
    local moreLabel = menuState.moreWorldOptions and "Done" or "More World Options..."
    local buttons = {
      {id = "start_world", label = "Create New World", x = cx - 155, y = logicalHeight - 28, w = 150, h = 20},
      {id = "back_select", label = "Cancel", x = cx + 5, y = logicalHeight - 28, w = 150, h = 20},
      {id = mode == "creative" and "mode_survival" or "mode_creative", label = modeLabel, x = cx - 100, y = 100, w = 200, h = 20},
      {id = "toggle_more_world_options", label = moreLabel, x = cx - 100, y = 148, w = 200, h = 20}
    }

    if menuState.moreWorldOptions then
      buttons[#buttons + 1] = {id = "toggle_generator", label = generatorLabel, x = cx - 100, y = 172, w = 200, h = 20}
    end

    return buttons
  elseif screen == "options" then
    local y0 = math.floor(logicalHeight / 6)
    return {
      {id = "cycle_music", label = "Music: " .. percent(menuState.musicVolume), x = cx - 155, y = y0, w = 150, h = 20},
      {id = "cycle_sound", label = "Sound: " .. percent(menuState.soundVolume), x = cx + 5, y = y0, w = 150, h = 20},
      {id = "toggle_invert_mouse", label = "Invert Mouse: " .. onOff(menuState.invertMouse), x = cx - 155, y = y0 + 24, w = 150, h = 20},
      {id = "cycle_sensitivity", label = "Sensitivity: " .. percent(menuState.sensitivity), x = cx + 5, y = y0 + 24, w = 150, h = 20},
      {id = "cycle_fov", label = "FOV: " .. tostring(menuState.fovDegrees or 70), x = cx - 155, y = y0 + 48, w = 150, h = 20},
      {id = "cycle_difficulty", label = "Difficulty: " .. (menuState.difficulty or "Normal"), x = cx + 5, y = y0 + 48, w = 150, h = 20},
      {id = "video", label = "Video Settings...", x = cx - 100, y = y0 + 108, w = 200, h = 20},
      {id = "controls", label = "Controls...", x = cx - 100, y = y0 + 132, w = 200, h = 20},
      {id = "done_options", label = "Done", x = cx - 100, y = y0 + 168, w = 200, h = 20}
    }
  elseif screen == "video" then
    local y0 = math.floor(logicalHeight / 6)
    local guiScale = menuState.guiScale == 0 and "Auto" or tostring(menuState.guiScale or "Auto")
    return {
      {id = "toggle_graphics", label = "Graphics: " .. (menuState.graphicsMode or "Fancy"), x = cx - 155, y = y0, w = 150, h = 20},
      {id = "cycle_render_distance", label = "Render Distance: " .. tostring(menuState.renderDistance or 8), x = cx + 5, y = y0, w = 150, h = 20},
      {id = "toggle_smooth_lighting", label = "Smooth Lighting: " .. onOff(menuState.smoothLighting), x = cx - 155, y = y0 + 24, w = 150, h = 20},
      {id = "toggle_vsync", label = "VSync: " .. onOff(menuState.vsync), x = cx + 5, y = y0 + 24, w = 150, h = 20},
      {id = "toggle_anaglyph", label = "3D Anaglyph: " .. onOff(menuState.anaglyph), x = cx - 155, y = y0 + 48, w = 150, h = 20},
      {id = "toggle_view_bobbing", label = "View Bobbing: " .. onOff(menuState.viewBobbing), x = cx + 5, y = y0 + 48, w = 150, h = 20},
      {id = "cycle_gui_scale", label = "GUI Scale: " .. guiScale, x = cx - 155, y = y0 + 72, w = 150, h = 20},
      {id = "toggle_fullscreen", label = "Fullscreen: " .. onOff(menuState.fullscreen), x = cx + 5, y = y0 + 72, w = 150, h = 20},
      {id = "cycle_brightness", label = "Brightness: " .. percent(menuState.brightness), x = cx - 155, y = y0 + 96, w = 150, h = 20},
      {id = "toggle_clouds", label = "Clouds: " .. onOff(menuState.clouds), x = cx + 5, y = y0 + 96, w = 150, h = 20},
      {id = "toggle_bloom", label = "Bloom: " .. onOff(menuState.bloom), x = cx - 155, y = y0 + 120, w = 150, h = 20},
      {id = "cycle_particles", label = "Particles: " .. (menuState.particles or "All"), x = cx + 5, y = y0 + 120, w = 150, h = 20},
      {id = "done_child", label = "Done", x = cx - 100, y = y0 + 168, w = 200, h = 20}
    }
  elseif screen == "controls" then
    local y0 = math.floor(logicalHeight / 6)
    return {
      {id = "bind_attack", label = bindingLabel(menuState, "attack", "MOUSE1"), x = cx - 155, y = y0, w = 70, h = 20},
      {id = "bind_forward", label = bindingLabel(menuState, "forward", "W"), x = cx - 155, y = y0 + 24, w = 70, h = 20},
      {id = "bind_back", label = bindingLabel(menuState, "back", "S"), x = cx - 155, y = y0 + 48, w = 70, h = 20},
      {id = "bind_jump", label = bindingLabel(menuState, "jump", "SPACE"), x = cx - 155, y = y0 + 72, w = 70, h = 20},
      {id = "bind_drop", label = bindingLabel(menuState, "drop", "Q"), x = cx - 155, y = y0 + 96, w = 70, h = 20},
      {id = "unavailable_chat", label = "N/A", x = cx - 155, y = y0 + 120, w = 70, h = 20, enabled = false},
      {id = "bind_pick", label = bindingLabel(menuState, "pick", "MOUSE3"), x = cx - 155, y = y0 + 144, w = 70, h = 20},
      {id = "bind_use", label = bindingLabel(menuState, "use", "MOUSE2"), x = cx + 5, y = y0, w = 70, h = 20},
      {id = "bind_left", label = bindingLabel(menuState, "left", "A"), x = cx + 5, y = y0 + 24, w = 70, h = 20},
      {id = "bind_right", label = bindingLabel(menuState, "right", "D"), x = cx + 5, y = y0 + 48, w = 70, h = 20},
      {id = "bind_sneak", label = bindingLabel(menuState, "sneak", "CTRL"), x = cx + 5, y = y0 + 72, w = 70, h = 20},
      {id = "bind_inventory", label = bindingLabel(menuState, "inventory", "E"), x = cx + 5, y = y0 + 96, w = 70, h = 20},
      {id = "unavailable_players", label = "N/A", x = cx + 5, y = y0 + 120, w = 70, h = 20, enabled = false},
      {id = "done_child", label = "Done", x = cx - 100, y = y0 + 168, w = 200, h = 20}
    }
  elseif screen == "multiplayer" or screen == "texture_packs" then
    return {{id = "back_main", label = "Done", x = cx - 100, y = logicalHeight - 28, w = 200, h = 20}}
  elseif screen == "achievements" or screen == "stats" then
    return {{id = "back_pause", label = "Done", x = cx - 100, y = logicalHeight - 28, w = 200, h = 20}}
  end

  return {}
end

function menu.stateKey(menuState)
  menuState = menuState or {}
  local bindings = menuState.controlBindings or {}
  local stats = menuState.stats or {}
  return table.concat({
    menuState.worldGameMode or "survival", menuState.worldGeneratorType or "default",
    menuState.moreWorldOptions and "more" or "simple", menuState.worldSeedText or "",
    menuState.menuParentScreen or "none", tostring(menuState.musicVolume), tostring(menuState.soundVolume),
    tostring(menuState.invertMouse), tostring(menuState.sensitivity), tostring(menuState.fovDegrees),
    tostring(menuState.difficulty), tostring(menuState.graphicsMode), tostring(menuState.renderDistance),
    tostring(menuState.smoothLighting), tostring(menuState.vsync), tostring(menuState.anaglyph),
    tostring(menuState.viewBobbing), tostring(menuState.guiScale), tostring(menuState.fullscreen),
    tostring(menuState.brightness), tostring(menuState.clouds), tostring(menuState.bloom),
    tostring(menuState.particles), bindings.attack or "", bindings.use or "", bindings.forward or "",
    bindings.back or "", bindings.left or "", bindings.right or "", bindings.jump or "",
    bindings.sneak or "", bindings.pick or "", bindings.drop or "", bindings.inventory or "", tostring(menuState.statusMessage or ""),
    tostring(stats.blocksMined or 0), tostring(stats.blocksPlaced or 0),
    tostring(math.floor((stats.distance or 0) * 10)), tostring(math.floor(stats.playTime or 0))
  }, "/")
end

return menu
