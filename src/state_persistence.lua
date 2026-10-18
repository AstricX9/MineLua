local persistence = {}

local function normalizedKey(key)
  if type(key) == "string" and key:match("^-?%d+$") then
    return tonumber(key)
  end
  return key
end

local function copySerializable(value, active, exclude)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then
    return value
  end
  if kind == "number" then
    if value == value and value ~= math.huge and value ~= -math.huge then
      return value
    end
    return nil
  end
  if kind ~= "table" or active[value] then
    return nil
  end

  active[value] = true
  local result = {}
  for key, child in pairs(value) do
    if not exclude or not exclude[key] then
      local copied = copySerializable(child, active)
      if copied ~= nil and (type(key) == "string" or type(key) == "number") then
        result[normalizedKey(key)] = copied
      end
    end
  end
  active[value] = nil
  return result
end

function persistence.snapshot(value, options)
  options = options or {}
  return copySerializable(value, {}, options.exclude) or {}
end

local function restoreValue(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do
    result[normalizedKey(key)] = restoreValue(child)
  end
  return result
end

function persistence.restore(target, saved, options)
  if type(target) ~= "table" or type(saved) ~= "table" then
    return target
  end

  options = options or {}
  local exclude = options.exclude
  for key, value in pairs(saved) do
    key = normalizedKey(key)
    if not exclude or not exclude[key] then
      target[key] = restoreValue(value)
    end
  end
  return target
end

return persistence
