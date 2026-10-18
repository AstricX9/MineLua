local filesystem = require("filesystem")
local json = require("json")

local blockDrops = {}

local function stripNamespace(id)
  return type(id) == "string" and id:gsub("^minecraft:", "") or id
end

local function loadFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local decoded = json.decode(file:read("*a"))
  file:close()
  return decoded
end

function blockDrops.load(dataRoot)
  dataRoot = (dataRoot or "data"):gsub("[\\/]+$", "")
  local rules = {}
  for _, namespaceEntry in ipairs(filesystem.entries(dataRoot)) do
    if namespaceEntry.isDirectory and not namespaceEntry.isReparsePoint then
      local root = dataRoot .. "/" .. namespaceEntry.name .. "/drop"
      for _, path in ipairs(filesystem.files(root, ".json")) do
        local definition = loadFile(path)
        local block = definition and stripNamespace(definition.block)
        if not block then error("Invalid block drop definition: " .. path) end
        definition.id = namespaceEntry.name .. ":" .. path:sub(#root + 2):gsub("\\", "/"):gsub("%.json$", "")
        definition.block = block
        rules[block] = definition
      end
    end
  end
  return rules
end

local function toolMatches(condition, tool)
  if not condition then return true end
  if not tool then return false end
  local requiredType = condition.type or condition.toolType
  local minimumTier = tonumber(condition.min_tier or condition.minTier) or 0
  return (not requiredType or tool.toolType == requiredType) and (tool.tier or 0) >= minimumTier
end

function blockDrops.resolve(rules, block, tool, fallback)
  local definition = rules and rules[block]
  if not definition then return fallback and {item = fallback, count = 1} or nil end
  for _, drop in ipairs(definition.drops or {}) do
    if toolMatches(drop.tool, tool) then
      return {item = stripNamespace(drop.item or drop.id), count = math.max(1, math.floor(drop.count or 1))}
    end
  end
  return nil
end

return blockDrops
