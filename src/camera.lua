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

local ffi = require("ffi")

local camera = {
  x = 8,
  y = 30,
  z = 40,

  pitch = 0,
  yaw = -0.5,
  lastX = 640,
  lastY = 360,
  firstMouse = true
}

function camera.getMatrix()
  local cp = math.cos(camera.pitch)
  local sp = math.sin(camera.pitch)
  local cy = math.cos(camera.yaw)
  local sy = math.sin(camera.yaw)

  return {
    cp * cy,
    sp,
    cp * sy
  }
end

function camera.update(dt, window)
  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)
  local x = tonumber(xpos[0])
  local y = tonumber(ypos[0])

  if camera.firstMouse then
    camera.lastX, camera.lastY = x, y
    camera.firstMouse = false
  end

  local xoffset = x - camera.lastX
  local yoffset = camera.lastY - y
  camera.lastX, camera.lastY = x, y

  local sensitivity = 0.1
  xoffset = xoffset * sensitivity
  yoffset = yoffset * sensitivity

  camera.yaw = camera.yaw + xoffset
  camera.pitch = camera.pitch + yoffset

  if camera.pitch > 89.0 then camera.pitch = 89.0 end
  if camera.pitch < -89.0 then camera.pitch = -89.0 end
end

return camera
