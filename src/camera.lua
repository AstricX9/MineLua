local camera = {
  x = 8,
  y = 30,
  z = 40,

  pitch = 0,
  yaw = -0.5
}

function camera.getMatrix()
  local cp = math.cos(camera.pitch)
  local sp = math.sin(camera.pitch)
  local cy = math.cos(camera.yaw)
  local sy = math.sin(camera.yaw)

  -- simple look direction
  return {
    cp * cy,
    sp,
    cp * sy
  }
end

return camera
