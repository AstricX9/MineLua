local motionBlur = {}

motionBlur.LEVELS = {"Off", "Low", "Medium", "High"}

local strength = {Off = 0.0, Low = 0.28, Medium = 0.58, High = 1.0}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function motionBlur.normalize(value)
  return strength[value] and value or "Off"
end

-- Convert the camera's per-frame angular displacement into a UV trail. This
-- blurs the 3D scene before the HUD is drawn, keeping text and menus crisp.
function motionBlur.vector(level, yaw, pitch, previousYaw, previousPitch, verticalFovDegrees, aspect, enabled)
  level = motionBlur.normalize(level)
  if not enabled or strength[level] == 0.0 or previousYaw == nil or previousPitch == nil then
    return 0.0, 0.0
  end
  local verticalFov = math.max(1.0, tonumber(verticalFovDegrees) or 70.0)
  local horizontalFov = verticalFov * math.max(0.5, tonumber(aspect) or 1.0)
  local scale = strength[level] * 0.72
  local x = -(yaw - previousYaw) / horizontalFov * scale
  local y = (pitch - previousPitch) / verticalFov * scale
  return clamp(x, -0.045, 0.045), clamp(y, -0.045, 0.045)
end

return motionBlur
