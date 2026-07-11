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

local function parentDir(path)
  return (path:gsub("\\", "/"):match("^(.*)/[^/]*$") or "")
end

local function joinPath(base, child)
  if child:match("^%a:[/\\]") or child:sub(1, 1) == "/" or child:sub(1, 1) == "\\" then
    return child
  end
  if base == "" then
    return child
  end
  return base .. "/" .. child
end

local function copyResult(result)
  return {
    item = result.item,
    count = result.count or 1
  }
end

local function isArray(value)
  return type(value) == "table" and value[1] ~= nil
end

local function stripNamespace(id)
  if type(id) ~= "string" then
    return id
  end
  return id:gsub("^minecraft:", "")
end

local function normalizeIngredient(value)
  if type(value) == "string" then
    return stripNamespace(value)
  end
  if type(value) == "table" then
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
    id = recipe.id,
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

local function normalizeRecipes(decoded)
  local source = decoded
  if type(decoded) == "table" and decoded.recipes then
    source = decoded.recipes
  end

  if type(source) ~= "table" then
    return {}
  end

  if not isArray(source) then
    local single = normalizeRecipe(source)
    return single and {single} or {}
  end

  local recipes = {}
  for i = 1, #source do
    local recipe = normalizeRecipe(source[i])
    if recipe then
      recipes[#recipes + 1] = recipe
    end
  end

  return recipes
end

local function sortedCounts(items)
  local counts = {}
  for i = 1, #items do
    local item = normalizeIngredient(items[i])
    if item and item ~= "" then
      counts[item] = (counts[item] or 0) + 1
    end
  end
  return counts
end

local function countsMatch(a, b)
  for key, value in pairs(a) do
    if b[key] ~= value then
      return false
    end
  end

  for key, value in pairs(b) do
    if a[key] ~= value then
      return false
    end
  end

  return true
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

local function shapedMatches(recipe, grid)
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
      if (normalized[y][x] or "") ~= (expected or "") then
        return false
      end
    end
  end

  return true
end

function crafting.load(path)
  path = path or "data/recipes.json"
  local decoded = loadDataFile(path)
  local recipes = {}

  if type(decoded) == "table" and decoded.files then
    local base = parentDir(path)
    for i = 1, #decoded.files do
      local fileRecipes = normalizeRecipes(loadDataFile(joinPath(base, decoded.files[i])))
      for j = 1, #fileRecipes do
        recipes[#recipes + 1] = fileRecipes[j]
      end
    end
  else
    recipes = normalizeRecipes(decoded)
  end

  return {
    recipes = recipes
  }
end

function crafting.normalizeRecipe(recipe)
  return normalizeRecipe(recipe)
end

function crafting.matchShapeless(recipeBook, items)
  local inputCounts = sortedCounts(items)

  for i = 1, #recipeBook.recipes do
    local recipe = recipeBook.recipes[i]
    if recipe.type == "shapeless" and countsMatch(inputCounts, sortedCounts(recipe.ingredients or {})) then
      return copyResult(recipe.result)
    end
  end

  return nil
end

function crafting.matchGrid(recipeBook, grid)
  for i = 1, #recipeBook.recipes do
    local recipe = recipeBook.recipes[i]
    if recipe.type == "shaped" and shapedMatches(recipe, grid) then
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
