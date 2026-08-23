local blocks = require("blocks")

local Inventory = {}
Inventory.__index = Inventory

local STACK_LIMIT = 64

local function copyStack(stack)
  if not stack then return nil end
  return {item = stack.item, count = stack.count}
end

local function normalizedItem(item)
  if type(item) == "number" then
    local definition = blocks.list[item]
    return definition and definition.key or nil
  end
  if type(item) ~= "string" then return nil end
  return item:gsub("^minecraft:", "")
end

local function usableBlock(definition)
  if not definition or definition.id == (blocks.air or 0) then return false end
  local properties = definition.properties or {}
  if properties.hidden then return false end
  if properties.doublePlant and properties.half == "upper" then return false end
  return definition.key ~= "water" and definition.key ~= "lava"
end

function Inventory.catalog()
  local result = {}
  for id, definition in pairs(blocks.list) do
    if type(id) == "number" and usableBlock(definition) then
      result[#result + 1] = definition.key
    end
  end
  table.sort(result, function(a, b)
    local da, db = blocks.mapping[a], blocks.mapping[b]
    return (da and da.id or 0) < (db and db.id or 0)
  end)
  result[#result + 1] = "stick"
  return result
end

function Inventory.new(gameMode)
  local self = setmetatable({
    gameMode = gameMode or "survival",
    slots = {},
    crafting = {},
    cursor = nil,
    selected = 1,
    search = "",
    recipeHint = "Break a tree, then press E to craft planks."
  }, Inventory)

  if self.gameMode == "creative" then
    local starter = {"grass", "dirt", "stone", "sand", "gravel", "cobblestone", "oak_planks", "oak_log", "oak_leaves"}
    for index, item in ipairs(starter) do self.slots[index] = {item = item, count = STACK_LIMIT} end
  end
  return self
end

function Inventory:setMode(gameMode)
  self.gameMode = gameMode or self.gameMode
end

function Inventory:get(index)
  return self.slots[index]
end

function Inventory:getSelected(index)
  return self.slots[index or self.selected]
end

function Inventory:blockIdFor(stack)
  stack = stack or self:getSelected()
  local definition = stack and blocks.mapping[stack.item]
  return definition and definition.id or nil
end

function Inventory:add(item, count)
  item = normalizedItem(item)
  count = math.max(0, math.floor(count or 1))
  if not item or count == 0 then return 0 end

  for index = 1, 36 do
    local stack = self.slots[index]
    if stack and stack.item == item and stack.count < STACK_LIMIT then
      local added = math.min(count, STACK_LIMIT - stack.count)
      stack.count = stack.count + added
      count = count - added
      if count == 0 then return 0 end
    end
  end
  for index = 1, 36 do
    if not self.slots[index] then
      local added = math.min(count, STACK_LIMIT)
      self.slots[index] = {item = item, count = added}
      count = count - added
      if count == 0 then return 0 end
    end
  end
  return count
end

function Inventory:removeAt(index, count)
  local stack = self.slots[index]
  if not stack then return nil end
  local removed = math.min(stack.count, math.max(1, math.floor(count or 1)))
  local result = {item = stack.item, count = removed}
  stack.count = stack.count - removed
  if stack.count <= 0 then self.slots[index] = nil end
  return result
end

function Inventory:consumeSelected(count)
  if self.gameMode == "creative" then return true end
  return self:removeAt(self.selected, count or 1) ~= nil
end

function Inventory:find(item)
  item = normalizedItem(item)
  for index = 1, 36 do
    if self.slots[index] and self.slots[index].item == item then return index end
  end
  return nil
end

function Inventory:pickBlock(item)
  item = normalizedItem(item)
  if not item then return end
  local found = self:find(item)
  if found and found <= 9 then
    self.selected = found
    return found
  end
  if self.gameMode == "creative" then
    self.slots[self.selected] = {item = item, count = STACK_LIMIT}
    return self.selected
  end
  return found
end

function Inventory:swapOrMerge(index)
  if index < 1 or index > 36 then return end
  local slot = self.slots[index]
  if not self.cursor then
    self.cursor = slot
    self.slots[index] = nil
  elseif not slot then
    self.slots[index] = self.cursor
    self.cursor = nil
  elseif slot.item == self.cursor.item and slot.count < STACK_LIMIT then
    local moved = math.min(self.cursor.count, STACK_LIMIT - slot.count)
    slot.count = slot.count + moved
    self.cursor.count = self.cursor.count - moved
    if self.cursor.count == 0 then self.cursor = nil end
  else
    self.slots[index], self.cursor = self.cursor, slot
  end
end

local function craftGridItems(grid)
  local counts = {}
  for index = 1, 4 do
    local stack = grid[index]
    if stack then counts[stack.item] = (counts[stack.item] or 0) + 1 end
  end
  return counts
end

function Inventory:craftResult()
  local counts = craftGridItems(self.crafting)
  local total = 0
  for _, count in pairs(counts) do total = total + count end
  if total == 1 and counts.oak_log == 1 then return {item = "oak_planks", count = 4} end
  if total == 4 and counts.oak_planks == 4 then return {item = "crafting_table", count = 1} end
  if total == 2 and counts.oak_planks == 2 then
    local vertical = self.crafting[1] and self.crafting[3] or self.crafting[2] and self.crafting[4]
    if vertical then return {item = "stick", count = 4} end
  end
  return nil
end

function Inventory:takeCraftResult()
  local result = self:craftResult()
  if not result then return nil end
  for index = 1, 4 do
    local stack = self.crafting[index]
    if stack then
      stack.count = stack.count - 1
      if stack.count <= 0 then self.crafting[index] = nil end
    end
  end
  self:add(result.item, result.count)
  self.recipeHint = result.item == "oak_planks" and "Arrange four planks in the 2x2 grid for a crafting table." or "Recipe crafted!"
  return copyStack(result)
end

function Inventory:swapCraft(index)
  if index < 1 or index > 4 then return end
  local slot = self.crafting[index]
  if not self.cursor then
    self.cursor = slot
    self.crafting[index] = nil
  elseif not slot then
    self.crafting[index] = {item = self.cursor.item, count = 1}
    self.cursor.count = self.cursor.count - 1
    if self.cursor.count <= 0 then self.cursor = nil end
  elseif slot.item == self.cursor.item and slot.count < STACK_LIMIT then
    slot.count = slot.count + 1
    self.cursor.count = self.cursor.count - 1
    if self.cursor.count <= 0 then self.cursor = nil end
  else
    self.crafting[index], self.cursor = self.cursor, slot
  end
end

return Inventory
