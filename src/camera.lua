local ffi = require("ffi")
local glfw = require("glfw")

local Camera = {}
Camera.__index = Camera

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function normalize(v)
  local length = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if length == 0 then
    return {0, 0, 0}
  end
  return {v[1] / length, v[2] / length, v[3] / length}
end

local function moveToward(current, target, amount)
  if current < target then
    return math.min(current + amount, target)
  end
  if current > target then
    return math.max(current - amount, target)
  end
  return current
end

local function isDown(window, key)
  return glfw.glfwGetKey(window, key) == glfw.GLFW_PRESS
end

local EPSILON = 0.0001

function Camera.new(options)
  options = options or {}

  return setmetatable({
    position = options.position or {16.5, 30.0, 16.5},
    yaw = options.yaw or -90.0,
    pitch = options.pitch or 0.0,
    lastX = options.lastX or 640.0,
    lastY = options.lastY or 360.0,
    firstMouse = true,
    velocity = options.velocity or {0.0, 0.0, 0.0},
    velocityY = 0.0,
    grounded = false,
    flying = options.flying or false,
    allowFlight = options.allowFlight or options.flying or false,
    flightToggleWasDown = false,
    jumpWasDown = false,
    jumpBuffer = 0.0,
    coyoteTimer = 0.0,
    eyeHeight = options.eyeHeight or 1.62,
    standEyeHeight = options.eyeHeight or 1.62,
    crouchEyeHeight = options.crouchEyeHeight or 1.24,
    bodyRadius = options.radius or 0.30,
    walkSpeed = options.walkSpeed or 5.1,
    sprintSpeed = options.sprintSpeed or 7.2,
    crouchSpeed = options.crouchSpeed or 2.4,
    flySpeed = options.flySpeed or 9.5,
    acceleration = options.acceleration or 34.0,
    airAcceleration = options.airAcceleration or 8.0,
    flyAcceleration = options.flyAcceleration or 24.0,
    groundFriction = options.groundFriction or 38.0,
    airFriction = options.airFriction or 2.0,
    flyFriction = options.flyFriction or 18.0,
    gravity = options.gravity or 19.5,
    jumpSpeed = options.jumpSpeed or 6.4,
    reach = options.reach or 6.0,
    stepHeight = options.stepHeight or 1.08,
    groundSnap = options.groundSnap or 0.36,
    coyoteTime = options.coyoteTime or 0.10,
    jumpBufferTime = options.jumpBufferTime or 0.12,
    mouseSensitivity = options.mouseSensitivity or 0.085
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

function Camera:getHorizontalFront()
  local front = self:getFront()
  return normalize({front[1], 0.0, front[3]})
end

function Camera:getRight(front)
  front = front or self:getHorizontalFront()
  return normalize({-front[3], 0.0, front[1]})
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
  self.pitch = clamp(self.pitch + yoffset, -88.0, 88.0)
end

function Camera:getBodyHeight()
  return self.eyeHeight + 0.18
end

function Camera:getCollisionSamples(x, z)
  local radius = self.bodyRadius
  return {
    {x, z},
    {x + radius, z},
    {x - radius, z},
    {x, z + radius},
    {x, z - radius}
  }
end

function Camera:getAabbBlockRange(x, z, feetY)
  local radius = self.bodyRadius
  return {
    minX = math.floor(x - radius + EPSILON),
    maxX = math.floor(x + radius - EPSILON),
    minY = math.floor(feetY + EPSILON),
    maxY = math.floor(feetY + self:getBodyHeight() - EPSILON),
    minZ = math.floor(z - radius + EPSILON),
    maxZ = math.floor(z + radius - EPSILON)
  }
end

function Camera:hasCollisionData(world, blockX, blockZ)
  if world.hasCollisionAtBlock then
    return world:hasCollisionAtBlock(blockX, blockZ)
  end
  return world:containsBlock(blockX, blockZ)
end

function Camera:hasBodyClearance(world, x, z, feetY, allowMissingCollision)
  local range = self:getAabbBlockRange(x, z, feetY)

  for blockX = range.minX, range.maxX do
    for blockZ = range.minZ, range.maxZ do
      if not allowMissingCollision and not self:hasCollisionData(world, blockX, blockZ) then
        return false
      end

      if self:hasCollisionData(world, blockX, blockZ) then
        for y = range.minY, range.maxY do
          if world:isSolidBlock(blockX, y, blockZ) then
            return false
          end
        end
      end
    end
  end
  return true
end

-- Flight passes through chunks that have not generated yet, otherwise
-- unstreamed terrain would wall the player in. Outrun the streamer and those
-- chunks materialise around you. The test below is deliberately narrow -- the
-- head being literally inside a solid block, which normal movement never
-- produces -- so ground snap and step-ups cannot trigger it.
local MAX_UNSTICK_RISE = 12

function Camera:isHeadInsideBlock(world)
  local pos = self.position
  local blockX, blockZ = math.floor(pos[1]), math.floor(pos[3])
  if not self:hasCollisionData(world, blockX, blockZ) then
    return false
  end
  return world:isSolidBlock(blockX, math.floor(pos[2]), blockZ) == true
end

function Camera:resolveTerrainOverlap(world)
  if not self:isHeadInsideBlock(world) then
    return false
  end

  local pos = self.position
  local blockX, blockZ = math.floor(pos[1]), math.floor(pos[3])

  for rise = 1, MAX_UNSTICK_RISE do
    local clearBody = self:hasBodyClearance(world, pos[1], pos[3], pos[2] - self.eyeHeight + rise, true)
    local clearHead = not world:isSolidBlock(blockX, math.floor(pos[2] + rise), blockZ)
    if clearBody and clearHead then
      pos[2] = pos[2] + rise
      self.velocityY = 0.0
      self.velocity[2] = 0.0
      return true
    end
  end

  return false
end

function Camera:getSupportY(world, x, z)
  local feetY = self.position[2] - self.eyeHeight
  local range = self:getAabbBlockRange(x, z, feetY)
  local searchTop = math.floor(feetY + self.stepHeight)
  local searchBottom = 0
  local surfaceY = nil

  for blockX = range.minX, range.maxX do
    for blockZ = range.minZ, range.maxZ do
      if not self:hasCollisionData(world, blockX, blockZ) then
        return nil
      end

      local sampleY = nil
      for y = searchTop, searchBottom, -1 do
        if world:isSolidBlock(blockX, y, blockZ) then
          sampleY = y + 1.0
          break
        end
      end

      if sampleY and (not surfaceY or sampleY > surfaceY) then
        surfaceY = sampleY
      end
    end
  end

  if surfaceY and not self:hasBodyClearance(world, x, z, surfaceY, false) then
    return nil
  end

  return surfaceY
end

function Camera:getGroundYAt(world, x, z)
  local surfaceY = self:getSupportY(world, x, z)
  if not surfaceY then
    return nil
  end

  return surfaceY + self.eyeHeight
end

function Camera:getGroundY(world)
  return self:getGroundYAt(world, self.position[1], self.position[3]) or self.position[2]
end

function Camera:findSpawnY(world, x, z)
  local range = self:getAabbBlockRange(x, z, 0.0)
  local maxHeight = world.maxHeight or 255

  for blockX = range.minX, range.maxX do
    for blockZ = range.minZ, range.maxZ do
      if not self:hasCollisionData(world, blockX, blockZ) then
        return nil
      end
    end
  end

  for y = maxHeight, 0, -1 do
    local hasSupport = false
    for blockX = range.minX, range.maxX do
      for blockZ = range.minZ, range.maxZ do
        if world:isSolidBlock(blockX, y, blockZ) then
          hasSupport = true
          break
        end
      end
      if hasSupport then
        break
      end
    end

    if hasSupport then
      local feetY = y + 1.0
      if self:hasBodyClearance(world, x, z, feetY, false) then
        return feetY + self.eyeHeight
      end
    end
  end

  return nil
end

function Camera:placeAtSpawn(world, x, z)
  self.position[1] = x or self.position[1]
  self.position[3] = z or self.position[3]
  self.position[2] = self:findSpawnY(world, self.position[1], self.position[3]) or self.position[2]
  self.velocityY = 0.0
  self.velocity[2] = 0.0
  self.grounded = false
  self.coyoteTimer = 0.0
end

function Camera:canStandAt(world, x, z)
  local groundY = self:getGroundYAt(world, x, z)
  if not groundY then
    return false
  end

  if groundY > self.position[2] + self.stepHeight then
    return false
  end

  return true
end

function Camera:canOccupyAt(world, x, z, eyeY, allowMissingCollision)
  return self:hasBodyClearance(world, x, z, eyeY - self.eyeHeight, allowMissingCollision)
end

function Camera:applyHorizontalInput(dt, window)
  local front = self:getHorizontalFront()
  local right = self:getRight(front)
  local inputX = 0.0
  local inputZ = 0.0
  local forwardInput = 0.0

  if isDown(window, glfw.GLFW_KEY_W) then
    inputX = inputX + front[1]
    inputZ = inputZ + front[3]
    forwardInput = forwardInput + 1.0
  end
  if isDown(window, glfw.GLFW_KEY_S) then
    inputX = inputX - front[1]
    inputZ = inputZ - front[3]
    forwardInput = forwardInput - 1.0
  end
  if isDown(window, glfw.GLFW_KEY_D) then
    inputX = inputX + right[1]
    inputZ = inputZ + right[3]
  end
  if isDown(window, glfw.GLFW_KEY_A) then
    inputX = inputX - right[1]
    inputZ = inputZ - right[3]
  end

  local inputLength = math.sqrt(inputX * inputX + inputZ * inputZ)
  if inputLength > 0.0 then
    inputX = inputX / inputLength
    inputZ = inputZ / inputLength
  end

  local crouching = (isDown(window, glfw.GLFW_KEY_LEFT_CONTROL) or isDown(window, glfw.GLFW_KEY_C)) and not self.flying
  local sprinting = isDown(window, glfw.GLFW_KEY_LEFT_SHIFT) and forwardInput > 0.0 and not crouching
  local targetEyeHeight = crouching and self.crouchEyeHeight or self.standEyeHeight
  self.eyeHeight = moveToward(self.eyeHeight, targetEyeHeight, 5.5 * dt)

  local maxSpeed = self.flying and self.flySpeed or self.walkSpeed
  if self.flying and sprinting then
    maxSpeed = self.flySpeed * 1.65
  elseif crouching then
    maxSpeed = self.crouchSpeed
  elseif sprinting then
    maxSpeed = self.sprintSpeed
  end

  local targetX = inputX * maxSpeed
  local targetZ = inputZ * maxSpeed
  local accel = self.flying and self.flyAcceleration or (self.grounded and self.acceleration or self.airAcceleration)

  if inputLength == 0.0 then
    accel = self.flying and self.flyFriction or (self.grounded and self.groundFriction or self.airFriction)
  end

  self.velocity[1] = moveToward(self.velocity[1], targetX, accel * dt)
  self.velocity[3] = moveToward(self.velocity[3], targetZ, accel * dt)
end

function Camera:updateFlightToggle(window)
  if not self.allowFlight then
    self.flying = false
    self.flightToggleWasDown = isDown(window, glfw.GLFW_KEY_F)
    return
  end

  local flightDown = isDown(window, glfw.GLFW_KEY_F)
  if flightDown and not self.flightToggleWasDown then
    self.flying = not self.flying
    self.grounded = false
    self.velocityY = 0.0
    self.velocity[2] = 0.0
    self.jumpBuffer = 0.0
    self.coyoteTimer = 0.0
  end

  self.flightToggleWasDown = flightDown
end

function Camera:moveHorizontally(dt, world)
  local pos = self.position
  local nextX = pos[1] + self.velocity[1] * dt

  if self.flying and self:canOccupyAt(world, nextX, pos[3], pos[2], true) then
    pos[1] = nextX
  elseif not self.flying and self:canStandAt(world, nextX, pos[3]) then
    pos[1] = nextX
  else
    self.velocity[1] = 0.0
  end

  local nextZ = pos[3] + self.velocity[3] * dt
  if self.flying and self:canOccupyAt(world, pos[1], nextZ, pos[2], true) then
    pos[3] = nextZ
  elseif not self.flying and self:canStandAt(world, pos[1], nextZ) then
    pos[3] = nextZ
  else
    self.velocity[3] = 0.0
  end
end

function Camera:applyVerticalMovement(dt, window, world)
  if self.flying then
    local verticalInput = 0.0
    if isDown(window, glfw.GLFW_KEY_SPACE) then
      verticalInput = verticalInput + 1.0
    end
    if isDown(window, glfw.GLFW_KEY_LEFT_CONTROL) or isDown(window, glfw.GLFW_KEY_C) then
      verticalInput = verticalInput - 1.0
    end

    local targetY = verticalInput * self.flySpeed
    local accel = verticalInput == 0.0 and self.flyFriction or self.flyAcceleration
    self.velocityY = moveToward(self.velocityY, targetY, accel * dt)
    self.velocity[2] = self.velocityY
    local nextY = self.position[2] + self.velocityY * dt
    if self:canOccupyAt(world, self.position[1], self.position[3], nextY, true) then
      self.position[2] = nextY
    else
      self.velocityY = 0.0
      self.velocity[2] = 0.0
    end
    self.grounded = false
    self.jumpWasDown = isDown(window, glfw.GLFW_KEY_SPACE)
    return
  end

  local pos = self.position
  local groundY = self:getGroundY(world)
  local distanceToGround = pos[2] - groundY
  local onGround = distanceToGround <= self.groundSnap and self.velocityY <= 0.0

  if onGround then
    self.grounded = true
    self.coyoteTimer = self.coyoteTime
    if distanceToGround ~= 0.0 then
      pos[2] = moveToward(pos[2], groundY, math.max(18.0 * dt, math.abs(distanceToGround)))
    end
    self.velocityY = 0.0
  else
    self.grounded = false
    self.coyoteTimer = math.max(0.0, self.coyoteTimer - dt)
  end

  local jumpDown = isDown(window, glfw.GLFW_KEY_SPACE)
  if jumpDown then
    self.jumpBuffer = self.jumpBufferTime
  else
    self.jumpBuffer = math.max(0.0, self.jumpBuffer - dt)
  end
  self.jumpWasDown = jumpDown

  if self.jumpBuffer > 0.0 and self.coyoteTimer > 0.0 then
    self.velocityY = self.jumpSpeed
    self.grounded = false
    self.coyoteTimer = 0.0
    self.jumpBuffer = 0.0
  end

  self.velocity[2] = self.velocityY
  self.velocityY = self.velocityY - self.gravity * dt
  pos[2] = pos[2] + self.velocityY * dt

  groundY = self:getGroundY(world)
  if pos[2] < groundY then
    pos[2] = groundY
    self.velocityY = 0.0
    self.velocity[2] = 0.0
    self.grounded = true
    self.coyoteTimer = self.coyoteTime
  end
end

function Camera:updateMovement(dt, window, world)
  dt = math.min(dt, 0.05)
  self:updateFlightToggle(window)
  self:applyHorizontalInput(dt, window)
  self:moveHorizontally(dt, world)
  self:applyVerticalMovement(dt, window, world)
  self:resolveTerrainOverlap(world)
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
