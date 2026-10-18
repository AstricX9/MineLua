package.path = "src/?.lua;" .. package.path

local stub = {}
setmetatable(stub, {__index = function(_, key)
  if key:match("^GLFW_") then return 0 end
  return function() return 0 end
end})
stub.glfwGetCursorPos = function(_, x, y) x[0] = 0.0 y[0] = 0.0 end
package.loaded.glfw = stub

local Camera = require("camera")
local Inventory = require("inventory")
local saves = require("saves")

local sourceCamera = Camera.new({flying = true, allowFlight = true})
sourceCamera.position = {123.25, 77.5, -456.75}
sourceCamera.velocity = {1.5, -2.25, 3.75}
sourceCamera.velocityY = -2.25
sourceCamera.yaw = 137.5
sourceCamera.pitch = -22.25
sourceCamera.grounded = true
sourceCamera.futureCameraField = {nested = {9, 8, 7}}

local sourceInventory = Inventory.new("survival")
sourceInventory.slots[1] = {item = "stone", count = 63}
sourceInventory.slots[9] = {item = "oak_log", count = 7}
sourceInventory.slots[36] = {item = "stick", count = 2}
sourceInventory.crafting[5] = {item = "oak_planks", count = 3}
sourceInventory.craftingGridSize = 3
sourceInventory.cursor = {item = "dirt", count = 11}
sourceInventory.selected = 9
sourceInventory.search = "oak"
sourceInventory.futureInventoryField = {enabled = true}

local savedCamera = sourceCamera:saveState()
local savedInventory = sourceInventory:saveState()
assert(savedInventory.recipeBook == nil, "shared recipe data is not duplicated into player saves")

local restoredCamera = Camera.new()
restoredCamera:restoreState(savedCamera)
local restoredInventory = Inventory.new("survival")
local runtimeRecipeBook = restoredInventory.recipeBook
restoredInventory:restoreState(savedInventory)

assert(restoredCamera.position[1] == 123.25 and restoredCamera.position[2] == 77.5 and
  restoredCamera.position[3] == -456.75, "location round trips")
assert(restoredCamera.velocity[1] == 1.5 and restoredCamera.velocityY == -2.25 and
  restoredCamera.yaw == 137.5 and restoredCamera.pitch == -22.25 and
  restoredCamera.flying == true and restoredCamera.grounded == true,
  "camera and movement state round trips")
assert(restoredCamera.futureCameraField.nested[3] == 7,
  "new serializable camera fields are captured automatically")
assert(restoredInventory.slots[1].count == 63 and restoredInventory.slots[9].item == "oak_log" and
  restoredInventory.slots[36].item == "stick", "sparse inventory slots round trip")
assert(restoredInventory.crafting[5].count == 3 and restoredInventory.craftingGridSize == 3 and
  restoredInventory.cursor.count == 11 and restoredInventory.selected == 9 and
  restoredInventory.search == "oak", "complete interactive inventory state round trips")
assert(restoredInventory.futureInventoryField.enabled == true,
  "new serializable inventory fields are captured automatically")
assert(restoredInventory.recipeBook == runtimeRecipeBook,
  "runtime recipe data survives restoration")

local temporaryWorld
local atomicSaveOk, atomicSaveError = pcall(function()
  temporaryWorld = saves.createWorld({
    worldName = "MineLua player persistence test " .. tostring(os.time()),
    gameMode = "survival",
    generatorType = "default",
    seed = 456
  })
  local firstSaved, firstError = saves.savePlayer(temporaryWorld, {
    camera = savedCamera,
    inventory = savedInventory,
    sequence = 1
  })
  assert(firstSaved, firstError)
  local secondSaved, secondError = saves.savePlayer(temporaryWorld, {
    camera = savedCamera,
    inventory = savedInventory,
    sequence = 2
  })
  assert(secondSaved, secondError)
  local reloaded = saves.loadPlayer(temporaryWorld)
  assert(reloaded and reloaded.sequence == 2,
    "atomic replacement publishes the complete newest player state")
end)
if temporaryWorld then saves.deleteWorld(temporaryWorld) end
assert(atomicSaveOk, atomicSaveError)

print("player persistence tests passed")
