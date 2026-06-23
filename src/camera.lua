local ffi = require("ffi")
local glfw = require("glfw")

local Camera = {}
Camera.__index = Camera

local function normalize(v)
  local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if length == 0 then
    return {0, 0, 0}
  end
  return {v[1] / length, v[2] / length, v[3] / length}
end

function Camera.new(options)
  options = options or {}

  return setmetatable({
    position = options.position or {16.0, 30.0, 16.0},
    yaw = options.yaw or -90.0,
    pitch = options.pitch or 0.0,
    lastX = options.lastX or 640.0,
    lastY = options.lastY or 360.0,
    firstMouse = true,
    velocityY = 0.0,
    eyeHeight = options.eyeHeight or 1.62,
    moveSpeed = options.moveSpeed or 6.0,
    mouseSensitivity = options.mouseSensitivity or 0.1
  }, Camera)
end

function Camera:getFront()
  local radYaw = math.rad(self.yaw)
  local radPitch = math.rad(self.pitch)

  return normalize({
    math.cos(radYaw) * math.cos(radPitch),
    math.sin(radPitch),
    math.sin(radYaw) * math.cos(radPitch)
  })
end

function Camera:getRight(front)
  local up = {0, 1, 0}
  return normalize({
    front[3] * up[2] - front[2] * up[3],
    front[1] * up[3] - front[3] * up[1],
    front[2] * up[1] - front[1] * up[2]
  })
end

function Camera:updateMouse(window)
  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)

  local x = tonumber(xpos[0])
  local y = tonumber(ypos[0])

  if self.firstMouse then
    self.lastX = x
    self.lastY = y
    self.firstMouse = false
  end

  local xoffset = (x - self.lastX) * self.mouseSensitivity
  local yoffset = (self.lastY - y) * self.mouseSensitivity
  self.lastX = x
  self.lastY = y

  self.yaw = self.yaw + xoffset
  self.pitch = self.pitch + yoffset

  if self.pitch > 89.0 then self.pitch = 89.0 end
  if self.pitch < -89.0 then self.pitch = -89.0 end
end

function Camera:updateMovement(dt, window, world)
  local front = self:getFront()
  local right = self:getRight(front)
  local speed = self.moveSpeed * dt
  local pos = self.position
  local oldX = pos[1]
  local oldZ = pos[3]

  if glfw.glfwGetKey(window, glfw.GLFW_KEY_W) == glfw.GLFW_PRESS then
    pos[1] = pos[1] + front[1] * speed
    pos[3] = pos[3] + front[3] * speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_S) == glfw.GLFW_PRESS then
    pos[1] = pos[1] - front[1] * speed
    pos[3] = pos[3] - front[3] * speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_A) == glfw.GLFW_PRESS then
    pos[1] = pos[1] + right[1] * speed
    pos[3] = pos[3] + right[3] * speed
  end
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_D) == glfw.GLFW_PRESS then
    pos[1] = pos[1] - right[1] * speed
    pos[3] = pos[3] - right[3] * speed
  end

  if not world:containsBlock(math.floor(pos[1] + 0.5), math.floor(pos[3] + 0.5)) then
    pos[1] = oldX
    pos[3] = oldZ
  end

  local groundY = self:getGroundY(world)
  if glfw.glfwGetKey(window, glfw.GLFW_KEY_SPACE) == glfw.GLFW_PRESS and pos[2] <= groundY + 0.05 then
    self.velocityY = 5.0
  end

  self.velocityY = self.velocityY - 9.8 * dt
  pos[2] = pos[2] + self.velocityY * dt

  groundY = self:getGroundY(world)
  if pos[2] < groundY then
    pos[2] = groundY
    self.velocityY = 0.0
  end
end

function Camera:getGroundY(world)
  local x = math.floor(self.position[1] + 0.5)
  local z = math.floor(self.position[3] + 0.5)
  local surfaceY = world:surfaceYAt(x, z)

  if not surfaceY then
    return self.position[2]
  end

  return surfaceY + self.eyeHeight
end

function Camera:update(dt, window, world)
  self:updateMouse(window)
  self:updateMovement(dt, window, world)
end

function Camera:getCenter()
  local front = self:getFront()
  return {
    self.position[1] + front[1],
    self.position[2] + front[2],
    self.position[3] + front[3]
  }
end

return Camera
