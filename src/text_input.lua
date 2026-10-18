local input = {}

local function clampCaret(text, caret)
  return math.max(0, math.min(tonumber(caret) or #text, #text))
end

function input.insert(text, caret, value, limit)
  text = tostring(text or "")
  caret = clampCaret(text, caret)
  value = tostring(value or "")
  local available = math.max(0, (limit or math.huge) - #text)
  if #value > available then value = value:sub(1, available) end
  return text:sub(1, caret) .. value .. text:sub(caret + 1), caret + #value
end

function input.backspace(text, caret)
  text = tostring(text or "")
  caret = clampCaret(text, caret)
  if caret == 0 then return text, caret end
  return text:sub(1, caret - 1) .. text:sub(caret + 1), caret - 1
end

function input.delete(text, caret)
  text = tostring(text or "")
  caret = clampCaret(text, caret)
  if caret >= #text then return text, caret end
  return text:sub(1, caret) .. text:sub(caret + 2), caret
end

function input.move(text, caret, direction)
  text = tostring(text or "")
  caret = clampCaret(text, caret)
  if direction == "home" then return 0 end
  if direction == "end" then return #text end
  if direction == "left" then return math.max(0, caret - 1) end
  if direction == "right" then return math.min(#text, caret + 1) end
  return caret
end

return input
