local ffi = require("ffi")
local glfw = require("glfw")
local persistence = require("state_persistence")

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

-- Approach the desired velocity as a vector. This gives starts, stops and
-- direction changes a short, controllable transition instead of snapping the
-- player's momentum onto a new heading in one frame.
local function approachHorizontalVelocity(x, z, targetX, targetZ, amount)
  local deltaX = targetX - x
  local deltaZ = targetZ - z
  local distance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
  if distance <= amount or distance < EPSILON then return targetX, targetZ end
  local scale = amount / distance
  return x + deltaX * scale, z + deltaZ * scale
end

local function damp(current, target, sharpness, dt)
  if sharpness <= 0.0 then return target end
  return target + (current - target) * math.exp(-sharpness * dt)
end

function Camera.new(options)
  options = options or {}

  return setmetatable({
    position = options.position or {16.5, 30.0, 16.5},
    yaw = options.yaw or -90.0,
    pitch = options.pitch or 0.0,
    targetYaw = options.yaw or -90.0,
    targetPitch = options.pitch or 0.0,
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
    acceleration = options.acceleration or 55.0,
    airAcceleration = options.airAcceleration or 14.0,
    flyAcceleration = options.flyAcceleration or 24.0,
    groundFriction = options.groundFriction or 46.0,
    airFriction = options.airFriction or 2.0,
    flyFriction = options.flyFriction or 18.0,
    gravity = options.gravity or 15.5,
    jumpSpeed = options.jumpSpeed or 6.6,
    reach = options.reach or 6.0,
    -- Vanilla-style step clearance is below a full voxel. A value above one
    -- silently climbed block ledges and felt like forced auto-jump.
    stepHeight = options.stepHeight or 0.60,
    swimUpSpeed = options.swimUpSpeed or 4.6,
    swimSinkSpeed = options.swimSinkSpeed or 0.65,
    swimAcceleration = options.swimAcceleration or 18.0,
    groundSnap = options.groundSnap or 0.36,
    coyoteTime = options.coyoteTime or 0.10,
    jumpBufferTime = options.jumpBufferTime or 0.12,
    mouseSensitivity = options.mouseSensitivity or 0.085,
    mouseSmoothing = options.mouseSmoothing ~= nil and options.mouseSmoothing or 42.0,
    invertMouse = options.invertMouse or false,
    mouseTurnVelocity = 0.0,
    moveInputX = 0.0,
    moveInputZ = 0.0,
    sprinting = false,
    bobPhase = 0.0,
    viewBobX = 0.0,
    viewBobY = 0.0,
    viewBobPitch = 0.0,
    viewRoll = 0.0,
    stepViewOffset = 0.0,
    landingViewOffset = 0.0,
    viewBobbingEnabled = options.viewBobbingEnabled ~= false,
    fovOffset = 0.0
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

function Camera:updateMouse(window, dt)
  local xpos = ffi.new("double[1]")
  local ypos = ffi.new("double[1]")
  glfw.glfwGetCursorPos(window, xpos, ypos)

  local x = tonumber(xpos[0])
  local y = tonumber(ypos[0])

  if self.firstMouse then
    self.lastX = x
    self.lastY = y
    self.targetYaw = self.yaw
    self.targetPitch = self.pitch
    self.firstMouse = false
  end

  local xoffset = (x - self.lastX) * self.mouseSensitivity
  local yoffset = (self.lastY - y) * self.mouseSensitivity
  if self.invertMouse then yoffset = -yoffset end
  self.lastX = x
  self.lastY = y

  self.targetYaw = (self.targetYaw or self.yaw) + xoffset
  self.targetPitch = clamp((self.targetPitch or self.pitch) + yoffset, -88.0, 88.0)

  local frameDt = math.min(dt or (1.0 / 60.0), 0.05)
  local previousYaw = self.yaw
  self.yaw = damp(self.yaw, self.targetYaw, self.mouseSmoothing, frameDt)
  self.pitch = clamp(damp(self.pitch, self.targetPitch, self.mouseSmoothing, frameDt), -88.0, 88.0)
  local turnRate = (self.yaw - previousYaw) / math.max(frameDt, 0.0001)
  self.mouseTurnVelocity = damp(self.mouseTurnVelocity, turnRate, 18.0, frameDt)
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

local function collisionHeightAt(world,x,y,z)
  if world.collisionHeightAt then return world:collisionHeightAt(x,y,z) end
  return world:isSolidBlock(x,y,z) and 1.0 or 0.0
end

function Camera:hasBodyClearance(world, x, z, feetY, allowMissingCollision)
  local range = self:getAabbBlockRange(x, z, feetY)
  local bodyBottom=feetY+EPSILON
  local bodyTop=feetY+self:getBodyHeight()-EPSILON

  for blockX = range.minX, range.maxX do
    for blockZ = range.minZ, range.maxZ do
      if not allowMissingCollision and not self:hasCollisionData(world, blockX, blockZ) then
        return false
      end

      if self:hasCollisionData(world, blockX, blockZ) then
        for y = range.minY, range.maxY do
          local height=collisionHeightAt(world,blockX,y,blockZ)
          if height>0 and y+height>bodyBottom and y<bodyTop then
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
  local blockY=math.floor(pos[2])
  return pos[2]<blockY+collisionHeightAt(world,blockX,blockY,blockZ)
end

function Camera:resolveTerrainOverlap(world)
  if not self:isHeadInsideBlock(world) then
    return false
  end

  local pos = self.position
  local blockX, blockZ = math.floor(pos[1]), math.floor(pos[3])

  for rise = 1, MAX_UNSTICK_RISE do
    local clearBody = self:hasBodyClearance(world, pos[1], pos[3], pos[2] - self.eyeHeight + rise, true)
    local headY=pos[2]+rise
    local headBlockY=math.floor(headY)
    local clearHead = headY>=headBlockY+
      collisionHeightAt(world,blockX,headBlockY,blockZ)
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
        local height=collisionHeightAt(world,blockX,y,blockZ)
        if height>0 then
          sampleY = y + height
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
    local supportHeight = 0.0
    for blockX = range.minX, range.maxX do
      for blockZ = range.minZ, range.maxZ do
        supportHeight=math.max(supportHeight,
          collisionHeightAt(world,blockX,y,blockZ))
      end
    end

    if supportHeight>0 then
      local feetY = y + supportHeight
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

-- Missing chunks are only safe to ignore when the whole player is above the
-- generator's vertical envelope. This is the useful middle ground used by a
-- streamed voxel world: ordinary play cannot enter terrain before collision
-- arrives, while high creative flight is not fenced in by an invisible wall.
function Camera:canFlyThroughUnloaded(world, eyeY)
  if world and world.semiBlockingChunks == false then return true end
  local terrainTop = world and world.maxHeight or 255
  local feetY = eyeY - self.eyeHeight
  return feetY > terrainTop + 1.0
end

-- Whether the body would still be standing on something at this spot. Support
-- is measured over the whole footprint, the same way the ground check is, so a
-- position this accepts is never one the player would fall out of.
function Camera:hasFootingAt(world, x, z)
  local support = self:getSupportY(world, x, z)
  if not support then return false end
  -- A drop deeper than a single step is a ledge, not a slope.
  return support >= (self.position[2] - self.eyeHeight) - self.stepHeight
end

function Camera:isBodyInLiquid(world)
  if not world.isLiquidBlock then return false end
  local pos = self.position
  local feetY = pos[2] - self.eyeHeight
  local blockX, blockZ = math.floor(pos[1]), math.floor(pos[3])
  local bottomY = math.floor(feetY + EPSILON)
  local topY = math.floor(feetY + self:getBodyHeight() - EPSILON)
  for y = bottomY, topY do
    if world:isLiquidBlock(blockX, y, blockZ) then return true end
  end
  return false
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

  local crouching = isDown(window, glfw.GLFW_KEY_LEFT_CONTROL) and not self.flying
  -- Remembered for the movement step, which refuses to walk a crouching player
  -- off a ledge.
  self.crouching = crouching
  local sprinting = isDown(window, glfw.GLFW_KEY_LEFT_SHIFT) and forwardInput > 0.0 and not crouching
  self.sprinting = sprinting
  self.moveInputX = inputX
  self.moveInputZ = inputZ
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

  self.velocity[1], self.velocity[3] =
    approachHorizontalVelocity(self.velocity[1], self.velocity[3], targetX, targetZ, accel * dt)
end

-- Visual motion is intentionally separate from the physical position. The
-- collision body remains exact while small, damped offsets soften block steps,
-- footfalls and landings for the rendered camera.
function Camera:updateViewMotion(dt, previousY, wasGrounded, impactVelocityY)
  dt = math.min(dt, 0.05)
  local speed = math.sqrt(self.velocity[1] * self.velocity[1] + self.velocity[3] * self.velocity[3])
  local moving = self.viewBobbingEnabled and self.grounded and speed > 0.18 and not self.flying
  local intensity = moving and clamp(speed / math.max(self.sprintSpeed, 0.01), 0.0, 1.0) or 0.0

  if moving then self.bobPhase = self.bobPhase + speed * dt * 1.85 end
  -- A single weighted gait drives all of the walk motion.  The stronger ends
  -- of the lateral curve read as weight settling over each foot, while the
  -- eased vertical lift avoids the mechanical speed of a plain sine wave.
  -- This follows ClassiCube's useful coupling of horizontal bob, alternating
  -- roll and a same-phase pitch pulse, with damping added for MineLua.
  local footSide = math.cos(self.bobPhase)
  local weightedSide = footSide * (0.78 + 0.22 * math.abs(footSide))
  local strideLift = math.abs(math.sin(self.bobPhase))
  local weightedLift = strideLift ^ 1.65
  local targetBobX = weightedSide * 0.034 * intensity
  local targetBobY = (weightedLift - 0.42) * 0.056 * intensity
  local targetBobPitch = weightedLift * 0.72 * intensity
  self.viewBobX = damp(self.viewBobX, targetBobX, 13.0, dt)
  self.viewBobY = damp(self.viewBobY, targetBobY, 13.0, dt)
  self.viewBobPitch = damp(self.viewBobPitch, targetBobPitch, 11.0, dt)

  local verticalStep = self.position[2] - previousY
  if self.viewBobbingEnabled and wasGrounded and self.grounded and math.abs(verticalStep) > 0.02 then
    self.stepViewOffset = clamp(self.stepViewOffset - verticalStep, -0.45, 0.45)
  end
  if self.viewBobbingEnabled and not wasGrounded and self.grounded and impactVelocityY < -2.0 then
    self.landingViewOffset = self.landingViewOffset - clamp((-impactVelocityY - 2.0) * 0.012, 0.0, 0.10)
  end
  self.stepViewOffset = damp(self.stepViewOffset, 0.0, 13.0, dt)
  self.landingViewOffset = damp(self.landingViewOffset, 0.0, 10.0, dt)

  local right = self:getRight()
  local lateralSpeed = self.velocity[1] * right[1] + self.velocity[3] * right[3]
  local targetRoll = 0.0
  if self.viewBobbingEnabled then
    local footRoll = moving and (-weightedSide * 0.72 * intensity) or 0.0
    targetRoll = clamp(footRoll - lateralSpeed / math.max(self.sprintSpeed, 0.01) * 0.55 -
      self.mouseTurnVelocity * 0.0025, -1.25, 1.25)
  end
  self.viewRoll = damp(self.viewRoll, targetRoll, 9.5, dt)

  local sprintAmount = self.sprinting and clamp(speed / math.max(self.sprintSpeed, 0.01), 0.0, 1.0) or 0.0
  self.fovOffset = damp(self.fovOffset, sprintAmount * 3.5, 7.0, dt)
end

-- The bob pitch is visual-only. Movement and collision continue to use
-- getFront(), while the rendered view gets the small weighted stride tilt.
function Camera:getViewFront()
  local radYaw = math.rad(self.yaw)
  local radPitch = math.rad(self.pitch + (self.viewBobPitch or 0.0))
  return normalize({
    math.cos(radYaw) * math.cos(radPitch),
    math.sin(radPitch),
    math.sin(radYaw) * math.cos(radPitch)
  })
end

function Camera:getViewPosition()
  local right = self:getRight()
  return {
    self.position[1] + right[1] * self.viewBobX,
    self.position[2] + self.viewBobY + self.stepViewOffset + self.landingViewOffset,
    self.position[3] + right[3] * self.viewBobX
  }
end

function Camera:getViewUp()
  local front = self:getViewFront()
  local right = self:getRight()
  local baseUp = {
    right[2] * front[3] - right[3] * front[2],
    right[3] * front[1] - right[1] * front[3],
    right[1] * front[2] - right[2] * front[1]
  }
  local roll = math.rad(self.viewRoll)
  local cosine, sine = math.cos(roll), math.sin(roll)
  return normalize({
    baseUp[1] * cosine + right[1] * sine,
    baseUp[2] * cosine + right[2] * sine,
    baseUp[3] * cosine + right[3] * sine
  })
end

function Camera:getViewCenter()
  local position = self:getViewPosition()
  local front = self:getViewFront()
  return {position[1] + front[1], position[2] + front[2], position[3] + front[3]}
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
  -- Crouching on the ground also refuses steps that would leave nothing
  -- underfoot, so building out over a drop does not cost you the fall.
  local sneaking = self.crouching and self.grounded and not self.flying

  local function canStepTo(x, z)
    if self.flying then
      return self:canOccupyAt(world, x, z, pos[2], self:canFlyThroughUnloaded(world, pos[2]))
    end
    if not self:canOccupyAt(world, x, z, pos[2], false) then return false end
    return not sneaking or self:hasFootingAt(world, x, z)
  end

  local nextX = pos[1] + self.velocity[1] * dt
  if canStepTo(nextX, pos[3]) then
    pos[1] = nextX
  else
    self.velocity[1] = 0.0
  end

  local nextZ = pos[3] + self.velocity[3] * dt
  if canStepTo(pos[1], nextZ) then
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
    if isDown(window, glfw.GLFW_KEY_LEFT_CONTROL) then
      verticalInput = verticalInput - 1.0
    end

    local targetY = verticalInput * self.flySpeed
    local accel = verticalInput == 0.0 and self.flyFriction or self.flyAcceleration
    self.velocityY = moveToward(self.velocityY, targetY, accel * dt)
    self.velocity[2] = self.velocityY
    local nextY = self.position[2] + self.velocityY * dt
    local allowMissing = self:canFlyThroughUnloaded(world, nextY)
    if self:canOccupyAt(world, self.position[1], self.position[3], nextY, allowMissing) then
      self.position[2] = nextY
    else
      self.velocityY = 0.0
      self.velocity[2] = 0.0
    end
    self.grounded = false
    self.jumpWasDown = isDown(window, glfw.GLFW_KEY_SPACE)
    return
  end

  if self:isBodyInLiquid(world) then
    local jumpDown = isDown(window, glfw.GLFW_KEY_SPACE)
    local descendDown = isDown(window, glfw.GLFW_KEY_LEFT_CONTROL)
    local front = self:getFront()
    local aimIntent = 0.0
    if isDown(window, glfw.GLFW_KEY_W) then aimIntent = aimIntent + front[2] end
    if isDown(window, glfw.GLFW_KEY_S) then aimIntent = aimIntent - front[2] end

    -- Aimed swimming and dedicated rise/dive controls are additive. Looking up
    -- while holding W reinforces Space; looking the other way counteracts it.
    -- The small extra range lets combined input feel meaningfully stronger
    -- without producing an excessive launch at the water surface.
    local verticalIntent = aimIntent + (jumpDown and 1.0 or 0.0) - (descendDown and 1.0 or 0.0)
    local targetY = -self.swimSinkSpeed
    if math.abs(verticalIntent) > 0.02 then
      targetY = clamp(verticalIntent, -1.35, 1.35) * self.swimUpSpeed
    end
    self.velocityY = moveToward(self.velocityY, targetY, self.swimAcceleration * dt)
    self.velocity[2] = self.velocityY

    local nextY = self.position[2] + self.velocityY * dt
    if self:canOccupyAt(world, self.position[1], self.position[3], nextY, false) then
      self.position[2] = nextY
    else
      self.velocityY = 0.0
      self.velocity[2] = 0.0
    end

    self.grounded = false
    self.coyoteTimer = 0.0
    self.jumpBuffer = 0.0
    self.jumpWasDown = jumpDown
    return
  end

  local pos = self.position
  local groundY = self:getGroundY(world)
  local distanceToGround = pos[2] - groundY
  -- Ground snap keeps an already-grounded player attached to small downward
  -- steps. Applying that same tolerance in the air ends every jump early by
  -- teleporting through the last groundSnap metres of the fall.
  local followingGround = self.grounded and distanceToGround <= self.groundSnap
  local touchingGround = distanceToGround <= EPSILON
  local onGround = (followingGround or touchingGround) and self.velocityY <= 0.0

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
  -- Buffer only the press edge. Holding space must not trigger another jump on
  -- the first grounded frame after landing.
  if jumpDown and not self.jumpWasDown then
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
  local nextY = pos[2] + self.velocityY * dt

  -- Vertical motion uses the same complete body AABB as horizontal motion.
  -- This stops a jump from crossing a wall lip or ceiling before the later
  -- ground snap has a chance to notice it.
  if self:canOccupyAt(world, pos[1], pos[3], nextY, false) then
    pos[2] = nextY
  elseif self.velocityY > 0.0 then
    self.velocityY = 0.0
    self.velocity[2] = 0.0
  else
    local landingY = self:getGroundY(world)
    pos[2] = landingY
    self.velocityY = 0.0
    self.velocity[2] = 0.0
    self.grounded = true
    self.coyoteTimer = self.coyoteTime
  end

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
  -- Only flight can enter unloaded terrain and later materialise inside it.
  -- Ground movement must never use the upward unstick teleport, because that
  -- can lift a jumping player through a newly contacted wall.
  if self.flying then
    self:resolveTerrainOverlap(world)
  end
end

function Camera:update(dt, window, world, allowMouseLook)
  local previousY = self.position[2]
  local wasGrounded = self.grounded
  local impactVelocityY = self.velocityY
  if allowMouseLook ~= false then
    self:updateMouse(window, dt)
  else
    -- An interactive overlay needs the desktop cursor, but it must not turn
    -- the player while that cursor is being used. Re-anchor mouse look when
    -- gameplay takes the cursor back so closing the overlay cannot cause a
    -- sudden camera jump.
    self.firstMouse = true
  end
  self:updateMovement(dt, window, world)
  self:updateViewMotion(dt, previousY, wasGrounded, impactVelocityY)
end

function Camera:getCenter()
  local front = self:getFront()
  return {
    self.position[1] + front[1],
    self.position[2] + front[2],
    self.position[3] + front[3]
  }
end

function Camera:saveState()
  return persistence.snapshot(self)
end

function Camera:restoreState(saved)
  persistence.restore(self, saved)
  -- The physical mouse position is process-local. Re-anchor it on the first
  -- gameplay frame while preserving the restored view angles.
  self.firstMouse = true
  self.targetYaw = self.yaw
  self.targetPitch = self.pitch
  self.mouseTurnVelocity = 0.0
  self.viewBobX, self.viewBobY, self.viewBobPitch, self.viewRoll = 0.0, 0.0, 0.0, 0.0
  self.stepViewOffset, self.landingViewOffset, self.fovOffset = 0.0, 0.0, 0.0
  return self
end

return Camera
