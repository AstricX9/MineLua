local flow = {}

local function queueWorldStart(state, gameMode, generatorType, worldName)
  state.worldGameMode = gameMode or state.worldGameMode or "survival"
  state.worldGeneratorType = generatorType or state.worldGeneratorType or "default"
  state.pendingNewWorldConfig = {
    gameMode = state.worldGameMode,
    generatorType = state.worldGeneratorType,
    seed = tonumber(state.worldSeedText),
    worldName = worldName or "New World"
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
  elseif state.screen == "select_world" then
    state.screen = "main"
  elseif state.screen == "options" then
    returnFromOptions(state)
  elseif state.screen == "create_world" then
    state.screen = "select_world"
  elseif state.screen == "video" or state.screen == "controls" then
    state.screen = "options"
  end
end

function flow.applyAction(state, action)
  if not action or action == "noop" then
    return nil
  end

  if action == "singleplayer" then
    state.screen = "select_world"
  elseif action == "start_survival" then
    queueWorldStart(state, "survival", "default", "Survival World")
    return "started_world"
  elseif action == "start_creative" then
    queueWorldStart(state, "creative", "default", "Creative World")
    return "started_world"
  elseif action == "create_world" then
    state.screen = "create_world"
    state.moreWorldOptions = false
    state.worldSeedText = state.worldSeedText or ""
  elseif action == "mode_survival" then
    state.worldGameMode = "survival"
  elseif action == "mode_creative" then
    state.worldGameMode = "creative"
  elseif action == "toggle_more_world_options" then
    state.moreWorldOptions = not state.moreWorldOptions
  elseif action == "toggle_generator" then
    state.worldGeneratorType = state.worldGeneratorType == "superflat" and "default" or "superflat"
  elseif action == "options" then
    state.menuParentScreen = state.screen == "pause" and "pause" or "main"
    state.screen = "options"
  elseif action == "video" then
    state.screen = "video"
  elseif action == "controls" then
    state.screen = "controls"
  elseif action == "done_options" then
    returnFromOptions(state)
  elseif action == "done_child" then
    state.screen = "options"
  elseif action == "back_main" then
    state.screen = "main"
  elseif action == "back_select" then
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
    queueWorldStart(state, state.worldGameMode, state.worldGeneratorType, "New World")
    return "started_world"
  elseif action == "quit" then
    return "quit_game"
  end

  return nil
end

return flow
