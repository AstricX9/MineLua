package.path = "src/?.lua;" .. package.path

local saves = require("saves")
local uiFlow = require("ui_flow")
local uiMenu = require("ui_menu")

local created
local ok, err = pcall(function()
  created = saves.createWorld({
    worldName = "MineLua deletion test " .. tostring(os.time()),
    gameMode = "survival",
    generatorType = "default",
    seed = 123
  })

  local state = {
    screen = "select_world",
    savedWorlds = {created},
    selectedWorldIndex = 1
  }

  local hasDeleteButton = false
  for _, button in ipairs(uiMenu.buttons("select_world", 640, 360, state)) do
    if button.id == "delete_selected_world" and button.enabled then hasDeleteButton = true end
  end
  assert(hasDeleteButton, "the world list must expose deletion for the selected world")

  uiFlow.applyAction(state, "delete_selected_world")
  assert(state.screen == "confirm_delete_world", "delete must open a confirmation screen")
  assert(state.pendingDeleteWorld == created, "confirmation must retain the selected world")

  uiFlow.applyAction(state, "cancel_delete_world")
  assert(state.screen == "select_world" and state.pendingDeleteWorld == nil,
    "cancel must return without requesting deletion")

  uiFlow.applyAction(state, "delete_selected_world")
  uiFlow.applyAction(state, "confirm_delete_world")
  assert(state.screen == "select_world" and state.deleteWorldRequested == created,
    "confirmation must request deletion of only the selected world")

  local rejected = saves.deleteWorld({folderName = "..", path = "saves/.."})
  assert(rejected == false, "deletion must reject paths outside the saves directory")

  local deleted, deleteError = saves.deleteWorld(state.deleteWorldRequested)
  assert(deleted, deleteError or "world deletion failed")
  assert(io.open(created.path .. "/mineLua.json", "rb") == nil,
    "confirmed deletion must remove the world contents")
end)

if created then saves.deleteWorld(created) end
assert(ok, err)

print("world deletion tests passed")
