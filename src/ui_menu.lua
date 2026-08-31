local menu = {}
local worldProfiles = require("world_profiles")
local renderDistance = require("render_distance")

menu.RENDER_DISTANCE_MIN = renderDistance.MIN_CHUNKS
menu.RENDER_DISTANCE_MAX = renderDistance.MAX_CHUNKS

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

function menu.settingsLayout(logicalWidth, logicalHeight)
  local navX = math.max(16, math.floor(logicalWidth * 0.05))
  local navW = math.min(104, math.max(82, math.floor(logicalWidth * 0.24)))
  local contentX = navX + navW + 12
  return {
    navX = navX,
    navW = navW,
    contentX = contentX,
    contentW = logicalWidth - contentX - 20,
    doneY = logicalHeight - 40
  }
end

local SETTINGS_PAGES = {
  {key = "general", id = "settings_general", label = "General"},
  {key = "visuals", id = "settings_video", label = "Visuals"},
  {key = "controls", id = "settings_controls", label = "Controls"},
  {key = "resources", id = "settings_resources", label = "Resources"}
}

local function settingsButtons(logicalWidth, logicalHeight, active)
  local layout = menu.settingsLayout(logicalWidth, logicalHeight)
  local buttons = {}
  for index = 1, #SETTINGS_PAGES do
    local page = SETTINGS_PAGES[index]
    local selected = page.key == active
    buttons[#buttons + 1] = {
      id = selected and "noop" or page.id,
      label = page.label,
      x = layout.navX,
      y = 52 + (index - 1) * 26,
      w = layout.navW,
      h = 22,
      style = selected and "nav_active" or "nav"
    }
  end
  buttons[#buttons + 1] = {
    id = "settings_done", label = "Done", x = layout.navX, y = layout.doneY,
    w = layout.navW, h = 22, style = "primary"
  }
  return buttons, layout
end

function menu.buttons(screen, logicalWidth, logicalHeight, menuState)
  menuState = menuState or {}
  local cx = math.floor(logicalWidth * 0.5)

  if screen == "main" then
    local panelWidth = math.min(144, math.max(128, math.floor(logicalWidth * 0.36)))
    local x = logicalWidth - panelWidth - 16
    local y = math.max(72, math.floor(logicalHeight * 0.32))
    return {
      {id = "singleplayer", label = "Explore Worlds", x = x, y = y, w = panelWidth, h = 22, style = "primary"},
      {id = "create_world", label = "Create a World", x = x, y = y + 27, w = panelWidth, h = 22},
      {id = "multiplayer", label = "Online Play", x = x, y = y + 54, w = panelWidth, h = 22},
      {id = "texture_packs", label = "Resource Library", x = x, y = y + 81, w = panelWidth, h = 22},
      {id = "options", label = "Settings", x = x, y = y + 116, w = math.floor((panelWidth - 5) * 0.5), h = 20},
      {id = "quit", label = "Exit", x = x + math.ceil((panelWidth + 5) * 0.5), y = y + 116,
        w = math.floor((panelWidth - 5) * 0.5), h = 20, style = "quiet"}
    }
  elseif screen == "pause" then
    local y = math.floor(logicalHeight / 4 + 24)
    return {
      {id = "back_to_game", label = "Return to World", x = cx - 100, y = y, w = 200, h = 22, style = "primary"},
      {id = "achievements", label = "Milestones", x = cx - 100, y = y + 28, w = 98, h = 20},
      {id = "stats", label = "Field Record", x = cx + 2, y = y + 28, w = 98, h = 20},
      {id = "options", label = "Settings", x = cx - 100, y = y + 76, w = 200, h = 20},
      {id = "quit_to_title", label = "Leave World", x = cx - 100, y = y + 102, w = 200, h = 20, style = "quiet"}
    }
  elseif screen == "select_world" then
    local worlds = menuState.savedWorlds or {}
    local listTop = 36
    local listBottom = logicalHeight - 78
    local rowHeight = 36
    local perPage = math.max(1, math.floor((listBottom - listTop) / rowHeight))
    local pageCount = math.max(1, math.ceil(#worlds / perPage))
    local page = math.max(1, math.min(menuState.worldListPage or 1, pageCount))
    local first = (page - 1) * perPage + 1
    local last = math.min(#worlds, first + perPage - 1)
    local buttons = {}
    for index = first, last do
      buttons[#buttons + 1] = {
        id = "select_saved_world_" .. index, label = "", x = cx - 160,
        y = listTop + (index - first) * rowHeight, w = 320, h = 34, worldIndex = index
      }
    end
    if pageCount > 1 then
      buttons[#buttons + 1] = {id = "previous_world_page", label = "<", x = cx - 184, y = listTop, w = 20, h = 20, enabled = page > 1}
      buttons[#buttons + 1] = {id = "next_world_page", label = ">", x = cx + 164, y = listTop, w = 20, h = 20, enabled = page < pageCount}
    end
    buttons[#buttons + 1] = {id = "play_selected_world", label = "Enter Selected World", x = cx - 155, y = logicalHeight - 52, w = 150, h = 20, enabled = worlds[menuState.selectedWorldIndex or 0] ~= nil, style = "primary"}
    buttons[#buttons + 1] = {id = "create_world", label = "Create a World", x = cx + 5, y = logicalHeight - 52, w = 150, h = 20}
    buttons[#buttons + 1] = {id = "delete_selected_world", label = "Delete", x = cx - 155, y = logicalHeight - 28, w = 150, h = 20, enabled = worlds[menuState.selectedWorldIndex or 0] ~= nil}
    buttons[#buttons + 1] = {id = "back_main", label = "Cancel", x = cx + 5, y = logicalHeight - 28, w = 150, h = 20}
    return buttons
  elseif screen == "confirm_delete_world" then
    return {
      {id = "confirm_delete_world", label = "Delete Forever", x = cx - 155, y = logicalHeight - 52, w = 150, h = 20, style = "danger"},
      {id = "cancel_delete_world", label = "Cancel", x = cx + 5, y = logicalHeight - 52, w = 150, h = 20}
    }
  elseif screen == "create_world" then
    local mode = menuState.worldGameMode or "survival"
    local generator = menuState.worldGeneratorType or "default"
    local modeLabel = mode == "creative" and "Play Style: Creative" or "Play Style: Survival"
    local generatorNames = {default = "Natural", superflat = "Superflat", showcase = "Texture Showcase"}
    local generatorLabel = "Terrain Form: " .. (generatorNames[generator] or "Natural")
    local profile = worldProfiles.get(menuState.worldId)
    local worldLabel = "World: " .. profile.name
    local buttons = {
      {id = "start_world", label = "Begin This World", x = cx - 155, y = logicalHeight - 28, w = 150, h = 20, style = "primary"},
      {id = "back_select", label = "Cancel", x = cx + 5, y = logicalHeight - 28, w = 150, h = 20}
    }

    if menuState.moreWorldOptions then
      buttons[#buttons + 1] = {id = "toggle_structures", label = "Settlements: " .. onOff(menuState.generateStructures), x = cx - 155, y = 100, w = 150, h = 20}
      buttons[#buttons + 1] = {id = "toggle_generator", label = generatorLabel, x = cx + 5, y = 100, w = 150, h = 20}
      buttons[#buttons + 1] = {id = "cycle_world", label = worldLabel, x = cx - 100, y = 124, w = 200, h = 20}
      buttons[#buttons + 1] = {id = "toggle_cheats", label = "Allow Cheats: " .. onOff(menuState.allowCheats), x = cx - 155, y = 148, w = 150, h = 20}
      buttons[#buttons + 1] = {id = "toggle_bonus_chest", label = "Bonus Chest: " .. onOff(menuState.bonusChest), x = cx + 5, y = 148, w = 150, h = 20}
      buttons[#buttons + 1] = {id = "toggle_more_world_options", label = "Done", x = cx - 75, y = 176, w = 150, h = 20}
    else
      buttons[#buttons + 1] = {id = mode == "creative" and "mode_survival" or "mode_creative", label = modeLabel, x = cx - 100, y = 100, w = 200, h = 20}
      buttons[#buttons + 1] = {id = "cycle_world", label = worldLabel, x = cx - 100, y = 128, w = 200, h = 20}
      buttons[#buttons + 1] = {id = "toggle_more_world_options", label = "World Details", x = cx - 100, y = 164, w = 200, h = 20}
    end

    return buttons
  elseif screen == "options" then
    local buttons, layout = settingsButtons(logicalWidth, logicalHeight, "general")
    buttons[#buttons + 1] = {id = "cycle_sound", kind = "setting", label = "World Sound", valueLabel = percent(menuState.soundVolume), x = layout.contentX, y = 56, w = layout.contentW, h = 22}
    buttons[#buttons + 1] = {id = "cycle_sensitivity", kind = "setting", label = "Look Speed", valueLabel = percent(menuState.sensitivity), x = layout.contentX, y = 102, w = layout.contentW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_invert_mouse", kind = "setting", label = "Invert Look", valueLabel = onOff(menuState.invertMouse), x = layout.contentX, y = 128, w = layout.contentW, h = 22}
    buttons[#buttons + 1] = {id = "cycle_fov", kind = "setting", label = "View Angle", valueLabel = tostring(menuState.fovDegrees or 70) .. " deg", x = layout.contentX, y = 154, w = layout.contentW, h = 22}
    return buttons
  elseif screen == "video" then
    local selectedRenderDistance = renderDistance.clamp(menuState.renderDistance, 8)
    local buttons, layout = settingsButtons(logicalWidth, logicalHeight, "visuals")
    local gap = 6
    local columnW = math.floor((layout.contentW - gap) * 0.5)
    local left, right = layout.contentX, layout.contentX + columnW + gap
    buttons[#buttons + 1] = {id = "render_distance", kind = "slider", presentation = "setting", label = "Horizon", valueLabel = tostring(selectedRenderDistance) .. " ch", value = selectedRenderDistance, minValue = menu.RENDER_DISTANCE_MIN, maxValue = menu.RENDER_DISTANCE_MAX, x = left, y = 56, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "cycle_particles", kind = "setting", label = "Particles", valueLabel = menuState.particles or "All", x = right, y = 56, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_clouds", kind = "setting", label = "Clouds", valueLabel = onOff(menuState.clouds), x = left, y = 96, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_bloom", kind = "setting", label = "Sky Bloom", valueLabel = onOff(menuState.bloom), x = right, y = 96, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_view_bobbing", kind = "setting", label = "View Motion", valueLabel = onOff(menuState.viewBobbing), x = left, y = 136, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_motion_blur_dropdown", kind = "setting", label = "Motion Blur", valueLabel = menuState.motionBlur or "Off", x = right, y = 136, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_vsync", kind = "setting", label = "VSync", valueLabel = onOff(menuState.vsync), x = left, y = 176, w = columnW, h = 22}
    buttons[#buttons + 1] = {id = "toggle_fullscreen", kind = "setting", label = "Fullscreen", valueLabel = onOff(menuState.fullscreen), x = right, y = 176, w = columnW, h = 22}
    if menuState.openDropdown == "motion_blur" then
      local levels = {"Off", "Low", "Medium", "High"}
      for index, level in ipairs(levels) do
        buttons[#buttons + 1] = {
          id = "set_motion_blur_" .. level:lower(), label = level,
          x = right, y = 46 + (index - 1) * 22, w = columnW, h = 20,
          style = level == menuState.motionBlur and "nav_active" or "quiet"
        }
      end
    end
    return buttons
  elseif screen == "controls" then
    local buttons, layout = settingsButtons(logicalWidth, logicalHeight, "controls")
    local gap = 6
    local columnW = math.floor((layout.contentW - gap) * 0.5)
    local left, right = layout.contentX, layout.contentX + columnW + gap
    local movement = {{"forward", "Forward", "W"}, {"back", "Back", "S"}, {"left", "Left", "A"}, {"right", "Right", "D"}, {"jump", "Jump", "SPACE"}, {"sneak", "Sneak", "CTRL"}, {"inventory", "Field Pack", "E"}}
    local actions = {{"attack", "Primary", "MOUSE1"}, {"use", "Use / Place", "MOUSE2"}, {"pick", "Sample", "MOUSE3"}, {"drop", "Drop Item", "Q"}}
    for index = 1, #movement do
      local entry = movement[index]
      buttons[#buttons + 1] = {id = "bind_" .. entry[1], kind = "setting", label = entry[2], valueLabel = bindingLabel(menuState, entry[1], entry[3]), x = left, y = 52 + (index - 1) * 24, w = columnW, h = 20}
    end
    for index = 1, #actions do
      local entry = actions[index]
      buttons[#buttons + 1] = {id = "bind_" .. entry[1], kind = "setting", label = entry[2], valueLabel = bindingLabel(menuState, entry[1], entry[3]), x = right, y = 52 + (index - 1) * 24, w = columnW, h = 20}
    end
    return buttons
  elseif screen == "texture_packs" then
    local buttons, layout = settingsButtons(logicalWidth, logicalHeight, "resources")
    buttons[#buttons + 1] = {id = "noop", kind = "setting", label = "Tamarton Base Set", valueLabel = "ACTIVE", x = layout.contentX, y = 56, w = layout.contentW, h = 22}
    buttons[#buttons + 1] = {id = "create_texture_showcase", label = "Create Texture Preview World", x = layout.contentX, y = 96, w = layout.contentW, h = 22, style = "primary"}
    return buttons
  elseif screen == "multiplayer" then
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
    worldProfiles.id(menuState.worldId), menuState.worldNameText or "",
    menuState.moreWorldOptions and "more" or "simple", menuState.worldSeedText or "",
    tostring(menuState.generateStructures), tostring(menuState.allowCheats), tostring(menuState.bonusChest),
    tostring(menuState.worldListVersion or 0), tostring(menuState.selectedWorldIndex or 0), tostring(menuState.worldListPage or 1),
    menuState.menuParentScreen or "none", tostring(menuState.soundVolume),
    tostring(menuState.invertMouse), tostring(menuState.sensitivity), tostring(menuState.fovDegrees),
    tostring(menuState.renderDistance), tostring(menuState.vsync),
    tostring(menuState.viewBobbing), tostring(menuState.motionBlur), tostring(menuState.openDropdown),
    tostring(menuState.fullscreen), tostring(menuState.clouds), tostring(menuState.bloom),
    tostring(menuState.particles), bindings.attack or "", bindings.use or "", bindings.forward or "",
    bindings.back or "", bindings.left or "", bindings.right or "", bindings.jump or "",
    bindings.sneak or "", bindings.pick or "", bindings.drop or "", bindings.inventory or "", tostring(menuState.statusMessage or ""),
    tostring(stats.blocksMined or 0), tostring(stats.blocksPlaced or 0),
    tostring(math.floor((stats.distance or 0) * 10)), tostring(math.floor(stats.playTime or 0))
  }, "/")
end

return menu
