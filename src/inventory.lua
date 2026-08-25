local blocks = require("blocks")
local crafting = require("crafting")
local items = require("items")
local smelting = require("smelting")
local persistence = require("state_persistence")

local Inventory = {}
Inventory.__index = Inventory
Inventory.HOTBAR_SIZE = 9
Inventory.SLOT_COUNT = 36

local STACK_LIMIT = 64
local DEFAULT_RECIPE_DATA_ROOT = "data"
local defaultRecipeBook
local PERSISTENCE_OPTIONS = {exclude = {recipeBook = true}}

local function recipeBook()
  if not defaultRecipeBook then
    defaultRecipeBook = crafting.load(DEFAULT_RECIPE_DATA_ROOT)
  end
  return defaultRecipeBook
end

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
  for _, item in ipairs(items.catalog()) do result[#result + 1] = item end
  return result
end

function Inventory.new(gameMode, options)
  options = options or {}
  local self = setmetatable({
    gameMode = gameMode or "survival",
    slots = {},
    crafting = {},
    craftingGridSize = 2,
    furnace = {burnTime=0,burnTotal=0,cookTime=0,cookTotal=10},
    recipeBook = options.recipeBook or recipeBook(),
    cursor = nil,
    selected = 1,
    search = "",
    recipeHint = "Break gravel for flint, then gather sticks from leaves or wood."
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

function Inventory:normalizeSelected()
  self.selected = math.max(1, math.min(Inventory.HOTBAR_SIZE,
    math.floor(tonumber(self.selected) or 1)))
  return self.selected
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

  for index = 1, Inventory.SLOT_COUNT do
    local stack = self.slots[index]
    if stack and stack.item == item and stack.count < STACK_LIMIT then
      local added = math.min(count, STACK_LIMIT - stack.count)
      stack.count = stack.count + added
      count = count - added
      if count == 0 then return 0 end
    end
  end
  for index = 1, Inventory.SLOT_COUNT do
    if not self.slots[index] then
      local added = math.min(count, STACK_LIMIT)
      self.slots[index] = {item = item, count = added}
      count = count - added
      if count == 0 then return 0 end
    end
  end
  return count
end

function Inventory:spaceFor(item)
  item = normalizedItem(item)
  if not item then return 0 end
  local space = 0
  for index = 1, Inventory.SLOT_COUNT do
    local stack = self.slots[index]
    if not stack then
      space = space + STACK_LIMIT
    elseif stack.item == item then
      space = space + math.max(0, STACK_LIMIT - stack.count)
    end
  end
  return space
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
  for index = 1, Inventory.SLOT_COUNT do
    if self.slots[index] and self.slots[index].item == item then return index end
  end
  return nil
end

function Inventory:pickBlock(item)
  item = normalizedItem(item)
  if not item then return end
  local found = self:find(item)
  if found and found <= Inventory.HOTBAR_SIZE then
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
  if index < 1 or index > Inventory.SLOT_COUNT then return end
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

function Inventory:collectToCursor()
  if not self.cursor or self.cursor.count >= STACK_LIMIT then return 0 end
  local moved = 0
  for index = 1, Inventory.SLOT_COUNT do
    local slot = self.slots[index]
    if slot and slot.item == self.cursor.item then
      local amount = math.min(slot.count, STACK_LIMIT - self.cursor.count)
      self.cursor.count = self.cursor.count + amount
      slot.count = slot.count - amount
      moved = moved + amount
      if slot.count <= 0 then self.slots[index] = nil end
      if self.cursor.count >= STACK_LIMIT then break end
    end
  end
  return moved
end

function Inventory:distributeSlots(indices)
  if not self.cursor or type(indices) ~= "table" then return 0 end
  local eligible, seen = {}, {}
  for _, index in ipairs(indices) do
    index = math.floor(tonumber(index) or 0)
    local slot = self.slots[index]
    if not seen[index] and index >= 1 and index <= Inventory.SLOT_COUNT and
        (not slot or (slot.item == self.cursor.item and slot.count < STACK_LIMIT)) then
      seen[index] = true
      eligible[#eligible + 1] = index
    end
  end
  if #eligible == 0 then return 0 end

  local share = math.max(1, math.floor(self.cursor.count / #eligible))
  local moved = 0
  for _, index in ipairs(eligible) do
    if not self.cursor then break end
    local slot = self.slots[index]
    local capacity = slot and (STACK_LIMIT - slot.count) or STACK_LIMIT
    local amount = math.min(share, capacity, self.cursor.count)
    if amount > 0 then
      if slot then
        slot.count = slot.count + amount
      else
        self.slots[index] = {item = self.cursor.item, count = amount}
      end
      self.cursor.count = self.cursor.count - amount
      moved = moved + amount
      if self.cursor.count <= 0 then self.cursor = nil end
    end
  end
  return moved
end

function Inventory:rightClickSlot(index)
  if index < 1 or index > Inventory.SLOT_COUNT then return false end
  local slot = self.slots[index]
  if self.cursor then
    if slot and (slot.item ~= self.cursor.item or slot.count >= STACK_LIMIT) then return false end
    if slot then
      slot.count = slot.count + 1
    else
      self.slots[index] = {item = self.cursor.item, count = 1}
    end
    self.cursor.count = self.cursor.count - 1
    if self.cursor.count <= 0 then self.cursor = nil end
    return true
  end
  if not slot then return false end
  local taken = math.ceil(slot.count / 2)
  self.cursor = {item = slot.item, count = taken}
  slot.count = slot.count - taken
  if slot.count <= 0 then self.slots[index] = nil end
  return true
end

local function furnaceSlotName(kind)
  if kind=="furnace_input" then return "input" end
  if kind=="furnace_fuel" then return "fuel" end
  if kind=="furnace_output" then return "output" end
end

function Inventory:swapFurnace(kind)
  local name=furnaceSlotName(kind)
  if not name then return false end
  local furnace=self.furnace
  local slot=furnace[name]
  if name=="output" then
    if not slot then return false end
    if self.cursor and (self.cursor.item~=slot.item or self.cursor.count>=STACK_LIMIT) then return false end
    if self.cursor then
      local moved=math.min(slot.count,STACK_LIMIT-self.cursor.count)
      self.cursor.count=self.cursor.count+moved
      slot.count=slot.count-moved
      if slot.count<=0 then furnace.output=nil end
    else
      self.cursor=slot furnace.output=nil
    end
    return true
  end
  if self.cursor and name=="fuel" and not smelting.fuelTime(self.cursor.item) then return false end
  if self.cursor and name=="input" and not smelting.recipe(self.cursor.item) then return false end
  if not self.cursor then
    self.cursor=slot furnace[name]=nil
  elseif not slot then
    furnace[name]=self.cursor self.cursor=nil
  elseif slot.item==self.cursor.item and slot.count<STACK_LIMIT then
    local moved=math.min(self.cursor.count,STACK_LIMIT-slot.count)
    slot.count=slot.count+moved
    self.cursor.count=self.cursor.count-moved
    if self.cursor.count<=0 then self.cursor=nil end
  else
    furnace[name],self.cursor=self.cursor,slot
  end
  return true
end

function Inventory:rightClickFurnace(kind)
  local name=furnaceSlotName(kind)
  if not name or name=="output" then return self:swapFurnace(kind) end
  local furnace=self.furnace
  local slot=furnace[name]
  if self.cursor then
    if name=="fuel" and not smelting.fuelTime(self.cursor.item) then return false end
    if name=="input" and not smelting.recipe(self.cursor.item) then return false end
    if slot and (slot.item~=self.cursor.item or slot.count>=STACK_LIMIT) then return false end
    if slot then slot.count=slot.count+1 else furnace[name]={item=self.cursor.item,count=1} end
    self.cursor.count=self.cursor.count-1
    if self.cursor.count<=0 then self.cursor=nil end
    return true
  end
  if not slot then return false end
  local taken=math.ceil(slot.count/2)
  self.cursor={item=slot.item,count=taken}
  slot.count=slot.count-taken
  if slot.count<=0 then furnace[name]=nil end
  return true
end

function Inventory:updateSmelting(dt)
  return smelting.update(self.furnace,dt)
end

local function craftGrid(grid, size)
  local result = {}
  for row = 1, size do
    result[row] = {}
    for column = 1, size do
      local stack = grid[(row - 1) * size + column]
      result[row][column] = stack and stack.item or ""
    end
  end
  return result
end

function Inventory:craftResult()
  return crafting.matchGrid(
    self.recipeBook,
    craftGrid(self.crafting, self.craftingGridSize)
  )
end

function Inventory:takeCraftResult()
  local result = self:craftResult()
  if not result then return nil end
  if self:spaceFor(result.item) < result.count then return nil end
  for index = 1, self.craftingGridSize * self.craftingGridSize do
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

function Inventory:craftAll()
  local crafted = 0
  while true do
    local result = self:craftResult()
    if not result or self:spaceFor(result.item) < result.count then break end
    local taken = self:takeCraftResult()
    if not taken then break end
    crafted = crafted + taken.count
  end
  return crafted
end

function Inventory:placeCraftOne(index)
  if index < 1 or index > self.craftingGridSize * self.craftingGridSize or not self.cursor then return false end
  local slot = self.crafting[index]
  if slot and (slot.item ~= self.cursor.item or slot.count >= STACK_LIMIT) then return false end
  if slot then
    slot.count = slot.count + 1
  else
    self.crafting[index] = {item = self.cursor.item, count = 1}
  end
  self.cursor.count = self.cursor.count - 1
  if self.cursor.count <= 0 then self.cursor = nil end
  return true
end

function Inventory:rightClickCraft(index)
  if index < 1 or index > self.craftingGridSize * self.craftingGridSize then return false end
  if self.cursor then return self:placeCraftOne(index) end
  local slot = self.crafting[index]
  if not slot then return false end
  local taken = math.ceil(slot.count / 2)
  self.cursor = {item = slot.item, count = taken}
  slot.count = slot.count - taken
  if slot.count <= 0 then self.crafting[index] = nil end
  return true
end

function Inventory:distributeCraft(indices)
  if not self.cursor or type(indices) ~= "table" then return 0 end
  local eligible, seen = {}, {}
  for _, index in ipairs(indices) do
    index = math.floor(tonumber(index) or 0)
    local slot = self.crafting[index]
    if not seen[index] and index >= 1 and index <= self.craftingGridSize * self.craftingGridSize and
        (not slot or (slot.item == self.cursor.item and slot.count < STACK_LIMIT)) then
      seen[index] = true
      eligible[#eligible + 1] = index
    end
  end
  if #eligible == 0 then return 0 end

  local share = math.max(1, math.floor(self.cursor.count / #eligible))
  local moved = 0
  for _, index in ipairs(eligible) do
    if not self.cursor then break end
    local slot = self.crafting[index]
    local capacity = slot and (STACK_LIMIT - slot.count) or STACK_LIMIT
    local amount = math.min(share, capacity, self.cursor.count)
    if amount > 0 then
      if slot then
        slot.count = slot.count + amount
      else
        self.crafting[index] = {item = self.cursor.item, count = amount}
      end
      self.cursor.count = self.cursor.count - amount
      moved = moved + amount
      if self.cursor.count <= 0 then self.cursor = nil end
    end
  end
  return moved
end

function Inventory:swapCraft(index)
  if index < 1 or index > self.craftingGridSize * self.craftingGridSize then return end
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

function Inventory:setCraftingGridSize(size)
  size = size == 3 and 3 or 2
  if self.craftingGridSize == size then return end
  self:returnCraftingItems()
  self.craftingGridSize = size
end

function Inventory:returnCraftingItems()
  for index = 1, 9 do
    local stack = self.crafting[index]
    if stack then
      self:add(stack.item, stack.count)
      self.crafting[index] = nil
    end
  end
end

function Inventory:saveState()
  return persistence.snapshot(self, PERSISTENCE_OPTIONS)
end

function Inventory:restoreState(saved)
  persistence.restore(self, saved, PERSISTENCE_OPTIONS)
  self.furnace=self.furnace or {burnTime=0,burnTotal=0,cookTime=0,cookTotal=10}
  self:normalizeSelected()
  return self
end

return Inventory
