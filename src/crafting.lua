local filesystem = require("filesystem")
local json = require("json")

local crafting = {}

local function loadDataFile(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return json.decode(content)
end

local function copyResult(result)
  return {
    item = result.item,
    count = result.count or 1
  }
end

local function stripNamespace(id)
  if type(id) ~= "string" then
    return id
  end
  return id:gsub("^minecraft:", "")
end

local function normalizeTagId(id)
  if type(id) ~= "string" then
    return nil
  end
  id = id:gsub("^#", "")
  if not id:find(":", 1, true) then
    id = "minecraft:" .. id
  end
  return id
end

local function normalizeIngredient(value)
  if type(value) == "string" then
    if value:sub(1, 1) == "#" then
      return {tag = normalizeTagId(value)}
    end
    return stripNamespace(value)
  end
  if type(value) == "table" then
    if value.tag then
      return {tag = normalizeTagId(value.tag)}
    end
    if value[1] ~= nil then
      local alternatives = {}
      for i = 1, #value do
        alternatives[i] = normalizeIngredient(value[i])
      end
      return {alternatives = alternatives}
    end
    return stripNamespace(value.item or value.id or value.block)
  end
  return value
end

local function normalizeResult(result)
  result = result or {}
  if type(result) == "string" then
    return {item = stripNamespace(result), count = 1}
  end
  return {
    item = stripNamespace(result.item or result.id),
    count = result.count or 1
  }
end

local function normalizeRecipe(recipe)
  if type(recipe) ~= "table" then
    return nil
  end

  local recipeType = recipe.type
  if recipeType == "minecraft:crafting_shaped" then
    recipeType = "shaped"
  elseif recipeType == "minecraft:crafting_shapeless" then
    recipeType = "shapeless"
  end

  local normalized = {
    type = recipeType,
    result = normalizeResult(recipe.result)
  }

  if normalized.type == "shaped" then
    normalized.pattern = recipe.pattern or {}
    normalized.key = {}
    for symbol, value in pairs(recipe.key or {}) do
      normalized.key[symbol] = normalizeIngredient(value)
    end
  elseif normalized.type == "shapeless" then
    normalized.ingredients = {}
    for i, value in ipairs(recipe.ingredients or {}) do
      normalized.ingredients[i] = normalizeIngredient(value)
    end
  end

  if not normalized.result.item then
    return nil
  end

  return normalized
end

local function ingredientMatches(expected, actual, tags)
  actual = normalizeIngredient(actual)
  if type(expected) ~= "table" then
    return expected == actual
  end
  if expected.tag then
    local members = tags and tags[expected.tag]
    return members and members[actual] == true or false
  end
  for _, alternative in ipairs(expected.alternatives or {}) do
    if ingredientMatches(alternative, actual, tags) then
      return true
    end
  end
  return false
end

local function shapelessMatches(recipe, items, tags)
  local actual = {}
  for i = 1, #items do
    local item = normalizeIngredient(items[i])
    if item and item ~= "" then
      actual[#actual + 1] = item
    end
  end
  if #actual ~= #(recipe.ingredients or {}) then
    return false
  end

  local used = {}
  local function assign(ingredientIndex)
    if ingredientIndex > #recipe.ingredients then
      return true
    end
    local expected = recipe.ingredients[ingredientIndex]
    for itemIndex = 1, #actual do
      if not used[itemIndex] and ingredientMatches(expected, actual[itemIndex], tags) then
        used[itemIndex] = true
        if assign(ingredientIndex + 1) then return true end
        used[itemIndex] = nil
      end
    end
    return false
  end

  return assign(1)
end

local function normalizeGrid(grid)
  local minX, minY = nil, nil
  local maxX, maxY = nil, nil

  for y = 1, #grid do
    for x = 1, #(grid[y] or {}) do
      local item = normalizeIngredient(grid[y][x])
      if item and item ~= "" then
        minX = minX and math.min(minX, x) or x
        maxX = maxX and math.max(maxX, x) or x
        minY = minY and math.min(minY, y) or y
        maxY = maxY and math.max(maxY, y) or y
      end
    end
  end

  if not minX then
    return {}
  end

  local normalized = {}
  for y = minY, maxY do
    local row = {}
    for x = minX, maxX do
      row[#row + 1] = normalizeIngredient(grid[y][x]) or ""
    end
    normalized[#normalized + 1] = row
  end

  return normalized
end

local function shapedMatches(recipe, grid, tags)
  local normalized = normalizeGrid(grid)
  if #normalized ~= #recipe.pattern then
    return false
  end

  for y = 1, #recipe.pattern do
    local patternRow = recipe.pattern[y]
    if #normalized[y] ~= #patternRow then
      return false
    end

    for x = 1, #patternRow do
      local symbol = patternRow:sub(x, x)
      local expected = symbol == " " and "" or recipe.key[symbol]
      local actual = normalized[y][x] or ""
      if expected == "" and actual ~= "" then
        return false
      elseif expected ~= "" and not ingredientMatches(expected, actual, tags) then
        return false
      end
    end
  end

  return true
end

local function collectIngredientTags(ingredient, result)
  if type(ingredient) ~= "table" then return end
  if ingredient.tag then
    result[ingredient.tag] = true
  end
  for _, alternative in ipairs(ingredient.alternatives or {}) do
    collectIngredientTags(alternative, result)
  end
end

local function recipeTagIds(recipes)
  local result = {}
  for _, recipe in ipairs(recipes) do
    for _, ingredient in ipairs(recipe.ingredients or {}) do
      collectIngredientTags(ingredient, result)
    end
    for _, ingredient in pairs(recipe.key or {}) do
      collectIngredientTags(ingredient, result)
    end
  end
  return result
end

local function loadTag(tagId, dataRoot, tags, loading)
  tagId = normalizeTagId(tagId)
  if tags[tagId] then return tags[tagId] end
  if loading[tagId] then
    error("Circular crafting item tag: #" .. tagId)
  end
  loading[tagId] = true

  local namespace, path = tagId:match("^([^:]+):(.+)$")
  local decoded = loadDataFile(dataRoot .. "/" .. namespace .. "/tags/item/" .. path .. ".json")
  if type(decoded) ~= "table" then
    error("Missing crafting item tag: #" .. tagId)
  end

  local members = {}
  for _, value in ipairs(decoded.values or decoded) do
    if type(value) == "string" and value:sub(1, 1) == "#" then
      local nested = loadTag(value, dataRoot, tags, loading)
      for item in pairs(nested) do members[item] = true end
    else
      local item = normalizeIngredient(value)
      if type(item) == "string" and item ~= "" then members[item] = true end
    end
  end

  loading[tagId] = nil
  tags[tagId] = members
  return members
end

function crafting.load(dataRoot)
  dataRoot = (dataRoot or "data"):gsub("[\\/]+$", "")
  local recipes = {}

  for _, namespaceEntry in ipairs(filesystem.entries(dataRoot)) do
    if namespaceEntry.isDirectory and not namespaceEntry.isReparsePoint then
      local namespace = namespaceEntry.name
      local recipeRoot = dataRoot .. "/" .. namespace .. "/recipe"
      for _, path in ipairs(filesystem.files(recipeRoot, ".json")) do
        local recipe = normalizeRecipe(loadDataFile(path))
        if not recipe then
          error("Invalid crafting recipe: " .. path)
        end
        local relative = path:sub(#recipeRoot + 2):gsub("\\", "/"):gsub("%.json$", "")
        recipe.id = namespace .. ":" .. relative
        recipes[#recipes + 1] = recipe
      end
    end
  end

  local tags = {}
  for tagId in pairs(recipeTagIds(recipes)) do
    loadTag(tagId, dataRoot, tags, {})
  end

  return {
    recipes = recipes,
    tags = tags
  }
end

function crafting.matchShapeless(recipeBook, items)
  for i = 1, #recipeBook.recipes do
    local recipe = recipeBook.recipes[i]
    if recipe.type == "shapeless" and shapelessMatches(recipe, items, recipeBook.tags) then
      return copyResult(recipe.result)
    end
  end

  return nil
end

function crafting.matchGrid(recipeBook, grid)
  for i = 1, #recipeBook.recipes do
    local recipe = recipeBook.recipes[i]
    if recipe.type == "shaped" and shapedMatches(recipe, grid, recipeBook.tags) then
      return copyResult(recipe.result)
    end
  end

  local flat = {}
  for y = 1, #grid do
    for x = 1, #(grid[y] or {}) do
      flat[#flat + 1] = grid[y][x]
    end
  end

  return crafting.matchShapeless(recipeBook, flat)
end

return crafting
