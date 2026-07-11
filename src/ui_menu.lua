local menu = {}

function menu.buttons(screen, logicalWidth, logicalHeight, menuState)
  menuState = menuState or {}
  local cx = math.floor(logicalWidth * 0.5)

  if screen == "main" then
    local y = math.floor(logicalHeight / 4 + 48)
    return {
      {id = "singleplayer", label = "Singleplayer", x = cx - 100, y = y, w = 200, h = 20},
      {id = "multiplayer", label = "Multiplayer", x = cx - 100, y = y + 24, w = 200, h = 20, enabled = false},
      {id = "texture_packs", label = "Texture Packs", x = cx - 100, y = y + 48, w = 200, h = 20, enabled = false},
      {id = "options", label = "Options...", x = cx - 100, y = y + 84, w = 98, h = 20},
      {id = "quit", label = "Quit Game", x = cx + 2, y = y + 84, w = 98, h = 20}
    }
  elseif screen == "pause" then
    local y = math.floor(logicalHeight / 4 + 24)
    return {
      {id = "back_to_game", label = "Back to game", x = cx - 100, y = y, w = 200, h = 20},
      {id = "noop", label = "Achievements", x = cx - 100, y = y + 24, w = 98, h = 20, enabled = false},
      {id = "noop", label = "Stats", x = cx + 2, y = y + 24, w = 98, h = 20, enabled = false},
      {id = "options", label = "Options...", x = cx - 100, y = y + 72, w = 200, h = 20},
      {id = "quit_to_title", label = "Save and quit to title", x = cx - 100, y = y + 96, w = 200, h = 20}
    }
  elseif screen == "select_world" then
    return {
      {id = "start_survival", label = "Survival World", x = cx - 100, y = 64, w = 200, h = 20},
      {id = "start_creative", label = "Creative World", x = cx - 100, y = 88, w = 200, h = 20},
      {id = "create_world", label = "Create New World", x = cx - 100, y = 124, w = 200, h = 20},
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
      buttons[#buttons + 1] = {id = "toggle_generator", label = generatorLabel, x = cx - 100, y = 124, w = 200, h = 20}
    end

    return buttons
  elseif screen == "options" then
    return {
      {id = "noop", label = "Invert Mouse: OFF", x = cx - 155, y = math.floor(logicalHeight / 6) + 24, w = 150, h = 20},
      {id = "noop", label = "Difficulty: Normal", x = cx + 5, y = math.floor(logicalHeight / 6) + 48, w = 150, h = 20},
      {id = "video", label = "Video Settings...", x = cx - 100, y = math.floor(logicalHeight / 6) + 108, w = 200, h = 20},
      {id = "controls", label = "Controls...", x = cx - 100, y = math.floor(logicalHeight / 6) + 132, w = 200, h = 20},
      {id = "done_options", label = "Done", x = cx - 100, y = math.floor(logicalHeight / 6) + 168, w = 200, h = 20}
    }
  elseif screen == "video" then
    local y0 = math.floor(logicalHeight / 6)
    return {
      {id = "noop", label = "Graphics: Fancy", x = cx - 155, y = y0, w = 150, h = 20},
      {id = "noop", label = "Render Distance: Far", x = cx + 5, y = y0, w = 150, h = 20},
      {id = "noop", label = "Smooth Lighting: ON", x = cx - 155, y = y0 + 24, w = 150, h = 20},
      {id = "noop", label = "Performance: Balanced", x = cx + 5, y = y0 + 24, w = 150, h = 20},
      {id = "noop", label = "3D Anaglyph: OFF", x = cx - 155, y = y0 + 48, w = 150, h = 20},
      {id = "noop", label = "View Bobbing: ON", x = cx + 5, y = y0 + 48, w = 150, h = 20},
      {id = "noop", label = "GUI Scale: Auto", x = cx - 155, y = y0 + 72, w = 150, h = 20},
      {id = "noop", label = "Advanced OpenGL: OFF", x = cx + 5, y = y0 + 72, w = 150, h = 20},
      {id = "noop", label = "Clouds: ON", x = cx + 5, y = y0 + 96, w = 150, h = 20},
      {id = "noop", label = "Particles: All", x = cx - 155, y = y0 + 120, w = 150, h = 20},
      {id = "done_child", label = "Done", x = cx - 100, y = y0 + 168, w = 200, h = 20}
    }
  elseif screen == "controls" then
    local y0 = math.floor(logicalHeight / 6)
    return {
      {id = "noop", label = "Button 1", x = cx - 155, y = y0, w = 70, h = 20},
      {id = "noop", label = "W", x = cx - 155, y = y0 + 24, w = 70, h = 20},
      {id = "noop", label = "S", x = cx - 155, y = y0 + 48, w = 70, h = 20},
      {id = "noop", label = "SPACE", x = cx - 155, y = y0 + 72, w = 70, h = 20},
      {id = "noop", label = "Q", x = cx - 155, y = y0 + 96, w = 70, h = 20},
      {id = "noop", label = "T", x = cx - 155, y = y0 + 120, w = 70, h = 20},
      {id = "noop", label = "Button 3", x = cx - 155, y = y0 + 144, w = 70, h = 20},
      {id = "noop", label = "Button 2", x = cx + 5, y = y0, w = 70, h = 20},
      {id = "noop", label = "A", x = cx + 5, y = y0 + 24, w = 70, h = 20},
      {id = "noop", label = "D", x = cx + 5, y = y0 + 48, w = 70, h = 20},
      {id = "noop", label = "LSHIFT", x = cx + 5, y = y0 + 72, w = 70, h = 20},
      {id = "noop", label = "E", x = cx + 5, y = y0 + 96, w = 70, h = 20},
      {id = "noop", label = "TAB", x = cx + 5, y = y0 + 120, w = 70, h = 20},
      {id = "done_child", label = "Done", x = cx - 100, y = y0 + 168, w = 200, h = 20}
    }
  end

  return {}
end

function menu.stateKey(menuState)
  menuState = menuState or {}
  return table.concat({
    menuState.worldGameMode or "survival",
    menuState.worldGeneratorType or "default",
    menuState.moreWorldOptions and "more" or "simple",
    menuState.worldSeedText or "",
    menuState.menuParentScreen or "none"
  }, "/")
end

return menu
