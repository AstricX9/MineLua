local ffi = require("ffi")
local glfw = require("glfw")
local math3d = require("math3d")

local Camera = {}
Camera.__index = Camera

local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function moveToward(current, target, amount)
  if current < target then return math.min(current + amount, target) end
  if current > target then return math.max(current - amount, target) end
  return current
end
local function isDown(window, key) return glfw.glfwGetKey(window, key) == glfw.GLFW_PRESS end

local BINDING_KEYS = {
  W=glfw.GLFW_KEY_W,A=glfw.GLFW_KEY_A,S=glfw.GLFW_KEY_S,D=glfw.GLFW_KEY_D,
  Q=glfw.GLFW_KEY_Q,E=glfw.GLFW_KEY_E,R=glfw.GLFW_KEY_R,C=glfw.GLFW_KEY_C,
  SPACE=glfw.GLFW_KEY_SPACE,CTRL=glfw.GLFW_KEY_LEFT_CONTROL,
  UP=glfw.GLFW_KEY_UP,DOWN=glfw.GLFW_KEY_DOWN,LEFT=glfw.GLFW_KEY_LEFT,RIGHT=glfw.GLFW_KEY_RIGHT
}

local function bindingDown(window, binding, fallback)
  binding = binding or fallback
  if binding == "MOUSE1" then return glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_LEFT) == glfw.GLFW_PRESS end
  if binding == "MOUSE2" then return glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_RIGHT) == glfw.GLFW_PRESS end
  if binding == "MOUSE3" then return glfw.glfwGetMouseButton(window, glfw.GLFW_MOUSE_BUTTON_MIDDLE) == glfw.GLFW_PRESS end
  local key = BINDING_KEYS[binding]
  return key and isDown(window, key) or false
end

local function rotateAroundAxis(v, axis, angle)
  local c, s = math.cos(angle), math.sin(angle)
  local cross = math3d.cross(axis, v)
  local dot = math3d.dot(axis, v)
  return {
    v[1] * c + cross[1] * s + axis[1] * dot * (1.0 - c),
    v[2] * c + cross[2] * s + axis[2] * dot * (1.0 - c),
    v[3] * c + cross[3] * s + axis[3] * dot * (1.0 - c)
  }
end

local function approachVector(current, target, amount)
  local delta = {target[1]-current[1], target[2]-current[2], target[3]-current[3]}
  local length = math3d.length(delta)
  if length <= amount or length < 1e-8 then return {target[1], target[2], target[3]} end
  local scale = amount / length
  return {current[1]+delta[1]*scale,current[2]+delta[2]*scale,current[3]+delta[3]*scale}
end

function Camera.new(options)
  options = options or {}
  local position = options.position or {0.5, 6371164.0, 0.5}
  return setmetatable({
    position={position[1],position[2],position[3]}, planet=options.planet,
    yaw=options.yaw or -90.0,pitch=options.pitch or 0.0,
    heading=options.heading and math3d.normalize(options.heading) or {0.0,0.0,-1.0},
    lastX=options.lastX or 640.0,lastY=options.lastY or 360.0,firstMouse=true,
    velocity=options.velocity or {0.0,0.0,0.0},velocityY=0.0,radialVelocity=0.0,
    grounded=false,flying=options.flying or false,allowFlight=options.allowFlight or options.flying or false,
    flightToggleWasDown=false,jumpWasDown=false,jumpBuffer=0.0,coyoteTimer=0.0,
    eyeHeight=options.eyeHeight or 1.62,standEyeHeight=options.eyeHeight or 1.62,
    crouchEyeHeight=options.crouchEyeHeight or 1.24,bodyRadius=options.radius or 0.30,
    walkSpeed=options.walkSpeed or 5.1,sprintSpeed=options.sprintSpeed or 7.2,crouchSpeed=options.crouchSpeed or 2.4,
    flySpeed=options.flySpeed or 9.5,flySpeedMultiplier=options.flySpeedMultiplier or 1.0,acceleration=options.acceleration or 55.0,
    airAcceleration=options.airAcceleration or 14.0,flyAcceleration=options.flyAcceleration or 24.0,
    groundFriction=options.groundFriction or 46.0,airFriction=options.airFriction or 2.0,flyFriction=options.flyFriction or 18.0,
    gravity=options.gravity or 9.81,jumpSpeed=options.jumpSpeed or 6.4,reach=options.reach or 6.0,
    stepHeight=options.stepHeight or 1.08,groundSnap=options.groundSnap or 0.36,
    coyoteTime=options.coyoteTime or 0.10,jumpBufferTime=options.jumpBufferTime or 0.12,
    mouseSensitivity=options.mouseSensitivity or 0.085,invertMouse=options.invertMouse==true,
    controlBindings=options.controlBindings or {}
  },Camera)
end

function Camera:setPlanet(planet) self.planet = planet end
function Camera:controlDown(window,name,fallback) return bindingDown(window,self.controlBindings[name],fallback) end

function Camera:getLocalUp(position)
  position = position or self.position
  if self.planet then return self.planet:localUp(position) end
  return {0.0,1.0,0.0}
end

function Camera:stabilizeHeading()
  local up = self:getLocalUp()
  local tangent = math3d.projectOnPlane(self.heading, up)
  if math3d.length(tangent) < 1e-7 then
    if self.planet then
      local east, _, north = self.planet:tangentFrame(self.position)
      tangent = north or east
    else
      tangent = {0,0,-1}
    end
  end
  self.heading = math3d.normalize(tangent)
  return up
end

function Camera:getHorizontalFront() self:stabilizeHeading() return {self.heading[1],self.heading[2],self.heading[3]} end
function Camera:getRight(front)
  front = front or self:getHorizontalFront()
  return math3d.normalize(math3d.cross(front,self:getLocalUp()))
end
function Camera:getFront()
  local up = self:stabilizeHeading()
  local pitch = math.rad(self.pitch)
  return math3d.normalize({
    self.heading[1]*math.cos(pitch)+up[1]*math.sin(pitch),
    self.heading[2]*math.cos(pitch)+up[2]*math.sin(pitch),
    self.heading[3]*math.cos(pitch)+up[3]*math.sin(pitch)
  })
end

function Camera:updateMouse(window)
  local xpos,ypos=ffi.new("double[1]"),ffi.new("double[1]")
  glfw.glfwGetCursorPos(window,xpos,ypos)
  local x,y=tonumber(xpos[0]),tonumber(ypos[0])
  if self.firstMouse then self.lastX,self.lastY,self.firstMouse=x,y,false end
  local xo=(x-self.lastX)*self.mouseSensitivity
  local yo=(self.lastY-y)*self.mouseSensitivity
  if self.invertMouse then yo=-yo end
  self.lastX,self.lastY=x,y
  local up=self:stabilizeHeading()
  self.heading=math3d.normalize(rotateAroundAxis(self.heading,up,math.rad(-xo)))
  self.yaw=(self.yaw+xo)%360.0
  self.pitch=clamp(self.pitch+yo,-88.0,88.0)
end

function Camera:getBodyHeight() return self.eyeHeight+0.18 end

local function sampleSolid(world,point)
  return world:isSolidBlock(math.floor(point[1]),math.floor(point[2]),math.floor(point[3]))
end

function Camera:hasBodyClearance(world, eyePosition, allowMissingCollision)
  local up=self:getLocalUp(eyePosition)
  local forward=math3d.normalize(math3d.projectOnPlane(self.heading,up))
  local right=math3d.normalize(math3d.cross(forward,up))
  local feet={eyePosition[1]-up[1]*self.eyeHeight,eyePosition[2]-up[2]*self.eyeHeight,eyePosition[3]-up[3]*self.eyeHeight}
  local heights={0.08,self:getBodyHeight()*0.50,self:getBodyHeight()-0.05}
  local rings={{0,0},{1,0},{-1,0},{0,1},{0,-1}}
  for i=1,#heights do
    for j=1,#rings do
      local a,b=rings[j][1]*self.bodyRadius,rings[j][2]*self.bodyRadius
      local point={feet[1]+up[1]*heights[i]+right[1]*a+forward[1]*b,feet[2]+up[2]*heights[i]+right[2]*a+forward[2]*b,feet[3]+up[3]*heights[i]+right[3]*a+forward[3]*b}
      local bx,by,bz=math.floor(point[1]),math.floor(point[2]),math.floor(point[3])
      if not allowMissingCollision and not world:hasCollisionAtBlock(bx,by,bz) then return false end
      if world:hasCollisionAtBlock(bx,by,bz) and sampleSolid(world,point) then return false end
    end
  end
  return true
end

-- Distance from the eye down to the ground, refined past the scan step.
--
-- This used to return the last air sample of a 0.04 m scan, so the answer was
-- quantised to 0.04 m. Standing still, gravity pulled the eye down about 2.7 mm
-- per frame while the snap only ever pushed it back in whole 0.04 m steps: the
-- player rose 4 cm, sank for thirteen frames, and rose again -- a 4.6 Hz
-- sawtooth, which is the bobbing seen while doing nothing. Bisecting the
-- bracketing interval takes the residual to well under a millimetre.
local GROUND_SCAN_STEP=0.04
local GROUND_REFINE_STEPS=8

function Camera:groundDistance(world,maxDistance)
  local down=self.planet and self.planet:localDown(self.position) or {0,-1,0}
  maxDistance=maxDistance or self.eyeHeight+self.stepHeight+0.5
  local px,py,pz=self.position[1],self.position[2],self.position[3]
  local function solidAt(distance)
    return world:isSolidBlock(
      math.floor(px+down[1]*distance),
      math.floor(py+down[2]*distance),
      math.floor(pz+down[3]*distance))
  end
  local low=self.eyeHeight-0.20
  local air=nil
  for distance=low,maxDistance,GROUND_SCAN_STEP do
    if solidAt(distance) then
      -- The very first sample being solid means the eye is already inside the
      -- ground; resolveTerrainOverlap owns that case, so report the scan floor
      -- and let it push upward.
      if not air then return low-GROUND_SCAN_STEP end
      local solid=distance
      for _=1,GROUND_REFINE_STEPS do
        local middle=(air+solid)*0.5
        if solidAt(middle) then solid=middle else air=middle end
      end
      return air
    end
    air=distance
  end
  return nil
end

function Camera:resolveTerrainOverlap(world)
  if self:hasBodyClearance(world,self.position,true) then return false end
  local up=self:getLocalUp()
  for rise=0.1,12.0,0.1 do
    local candidate={self.position[1]+up[1]*rise,self.position[2]+up[2]*rise,self.position[3]+up[3]*rise}
    if self:hasBodyClearance(world,candidate,true) then
      self.position=candidate self.radialVelocity=0 self.velocityY=0 return true
    end
  end
  return false
end

function Camera:findSpawnPosition(world,direction)
  direction=math3d.normalize(direction or world.spawnDirection or {0,0,1})
  local orbitalOffset=(world.spawnAltitudeMeters or 0.0)/(world.planet.voxelSizeMeters or 1.0)
  local surface=world:surfacePosition(direction,self.eyeHeight+1.0+orbitalOffset)
  return surface
end

function Camera:placeAtSpawn(world,x,z)
  self.planet=world.planet
  local direction=world.spawnDirection or {0,0,1}
  if type(x)=="table" then direction=x end
  self.position=self:findSpawnPosition(world,direction)
  self.heading=select(3,self.planet:tangentFrame(self.position))
  self.velocity={0,0,0} self.velocityY=0 self.radialVelocity=0 self.grounded=false self.coyoteTimer=0
end

function Camera:updateFlightToggle(window)
  if not self.allowFlight then self.flying=false self.flightToggleWasDown=isDown(window,glfw.GLFW_KEY_F) return end
  local down=isDown(window,glfw.GLFW_KEY_F)
  if down and not self.flightToggleWasDown then
    self.flying=not self.flying self.grounded=false self.radialVelocity=0 self.velocityY=0 self.jumpBuffer=0 self.coyoteTimer=0
  end
  self.flightToggleWasDown=down
end

function Camera:effectiveFlySpeed()
  local speed=self.flySpeed*(self.flySpeedMultiplier or 1.0)
  if self.flying and self.planet then
    local altitude=math.max(0.0,self.planet:altitudeMeters(self.position))
    speed=math.max(speed,math.min(25000.0,altitude*0.05))
  end
  return speed
end

-- Latitude and longitude in degrees against the +Y spin axis, altitude in
-- metres above sea level. Below the local ground the surface wins, so asking
-- for zero puts you on the ground rather than inside it.
function Camera:teleportTo(world,latitudeDegrees,longitudeDegrees,altitudeMeters)
  local planet=world.planet
  self.planet=planet
  local latitude=math.rad(math.max(-89.999,math.min(89.999,latitudeDegrees or 0.0)))
  local longitude=math.rad(longitudeDegrees or 0.0)
  local c=math.cos(latitude)
  local direction={c*math.cos(longitude),math.sin(latitude),c*math.sin(longitude)}
  local surface,sample=world:surfacePosition(direction,self.eyeHeight+1.5)
  local surfaceRadius=planet:distanceVoxels(surface)
  local wantedRadius=planet.radiusVoxels+(altitudeMeters or 0.0)/planet.voxelSizeMeters
  local radius=math.max(wantedRadius,surfaceRadius)
  self.position={
    planet.center[1]+direction[1]*radius,
    planet.center[2]+direction[2]*radius,
    planet.center[3]+direction[3]*radius
  }
  self.velocity={0,0,0} self.velocityY=0 self.radialVelocity=0
  self.grounded=false self.coyoteTimer=0 self.jumpBuffer=0
  self.heading=select(3,planet:tangentFrame(self.position))
  self:stabilizeHeading()
  return self.position,sample
end

-- Where the camera is, in the same terms the teleport takes.
function Camera:geodeticPosition()
  if not self.planet then return 0.0,0.0,0.0 end
  local relative=self.planet:relative(self.position)
  local distance=math.sqrt(relative[1]^2+relative[2]^2+relative[3]^2)
  if distance<=0.0 then return 0.0,0.0,0.0 end
  local latitude=math.deg(math.asin(math.max(-1.0,math.min(1.0,relative[2]/distance))))
  local longitude=math.deg(math.atan2(relative[3],relative[1]))
  return latitude,longitude,self.planet:altitudeMeters(self.position)
end

function Camera:movementInput(dt,window)
  local forward,right=self:getHorizontalFront(),self:getRight()
  local input={0,0,0} local forwardAmount=0
  local function add(v,s) input[1]=input[1]+v[1]*s input[2]=input[2]+v[2]*s input[3]=input[3]+v[3]*s end
  if self:controlDown(window,"forward","W") then add(forward,1) forwardAmount=1 end
  if self:controlDown(window,"back","S") then add(forward,-1) forwardAmount=-1 end
  if self:controlDown(window,"right","D") then add(right,1) end
  if self:controlDown(window,"left","A") then add(right,-1) end
  if math3d.length(input)>0 then input=math3d.normalize(input) end
  local crouching=self:controlDown(window,"sneak","CTRL") and not self.flying
  local sprinting=isDown(window,glfw.GLFW_KEY_LEFT_SHIFT) and forwardAmount>0 and not crouching
  self.eyeHeight=moveToward(self.eyeHeight,crouching and self.crouchEyeHeight or self.standEyeHeight,5.5*dt)
  local baseFlySpeed=self:effectiveFlySpeed()
  local speed=self.flying and baseFlySpeed or (crouching and self.crouchSpeed or (sprinting and self.sprintSpeed or self.walkSpeed))
  if self.flying and sprinting then speed=baseFlySpeed*1.65 end
  local target={input[1]*speed,input[2]*speed,input[3]*speed}
  local accel=math3d.length(input)==0 and (self.flying and self.flyFriction or (self.grounded and self.groundFriction or self.airFriction)) or (self.flying and self.flyAcceleration or (self.grounded and self.acceleration or self.airAcceleration))
  if self.flying and baseFlySpeed>self.flySpeed then accel=math.max(accel,baseFlySpeed*1.8) end
  local up=self:getLocalUp()
  local radial=math3d.dot(self.velocity,up)
  local tangent=math3d.projectOnPlane(self.velocity,up)
  tangent=approachVector(tangent,target,accel*dt)
  self.velocity={tangent[1]+up[1]*radial,tangent[2]+up[2]*radial,tangent[3]+up[3]*radial}
end

function Camera:updateRadialMovement(dt,window,world)
  local up=self:getLocalUp()
  if self.flying then
    local input=(self:controlDown(window,"jump","SPACE") and 1 or 0)-(self:controlDown(window,"sneak","CTRL") and 1 or 0)
    local flySpeed=self:effectiveFlySpeed()
    local radialAcceleration=input==0 and math.max(self.flyFriction,flySpeed*1.2) or math.max(self.flyAcceleration,flySpeed*1.8)
    self.radialVelocity=moveToward(self.radialVelocity,input*flySpeed,radialAcceleration*dt)
    self.grounded=false
  else
    local distance=self:groundDistance(world,self.eyeHeight+self.groundSnap+self.stepHeight)
    local onGround=distance and distance<=self.eyeHeight+self.groundSnap and self.radialVelocity<=0
    if onGround then
      local correction=self.eyeHeight-distance
      self.position={self.position[1]+up[1]*correction,self.position[2]+up[2]*correction,self.position[3]+up[3]*correction}
      self.radialVelocity=0 self.grounded=true self.coyoteTimer=self.coyoteTime
    else self.grounded=false self.coyoteTimer=math.max(0,self.coyoteTimer-dt) end
    local jump=self:controlDown(window,"jump","SPACE")
    if jump and not self.jumpWasDown then self.jumpBuffer=self.jumpBufferTime else self.jumpBuffer=math.max(0,self.jumpBuffer-dt) end
    self.jumpWasDown=jump
    if self.jumpBuffer>0 and self.coyoteTimer>0 then self.radialVelocity=self.jumpSpeed self.grounded=false self.jumpBuffer=0 self.coyoteTimer=0 end
    -- Gravity used to be integrated even on the frames the snap had just zeroed
    -- the radial velocity, so a standing player sank a few millimetres every
    -- frame and the snap kept catching them. Nothing is lost by skipping it:
    -- stepping off a ledge clears grounded, and the next frame accelerates.
    if not self.grounded then
      self.radialVelocity=self.radialVelocity-(self.planet and self.planet.gravityAcceleration or self.gravity)*dt
    end
  end
  self.velocityY=self.radialVelocity
  local tangent=math3d.projectOnPlane(self.velocity,up)
  self.velocity={tangent[1]+up[1]*self.radialVelocity,tangent[2]+up[2]*self.radialVelocity,tangent[3]+up[3]*self.radialVelocity}
end

function Camera:updateMovement(dt,window,world)
  dt=math.min(dt,0.05) self.planet=world.planet self:updateFlightToggle(window) self:movementInput(dt,window) self:updateRadialMovement(dt,window,world)
  local candidate={self.position[1]+self.velocity[1]*dt,self.position[2]+self.velocity[2]*dt,self.position[3]+self.velocity[3]*dt}
  if self:hasBodyClearance(world,candidate,self.flying) then self.position=candidate else
    local up=self:getLocalUp() local tangent=math3d.projectOnPlane(self.velocity,up)
    local radialOnly={self.position[1]+up[1]*self.radialVelocity*dt,self.position[2]+up[2]*self.radialVelocity*dt,self.position[3]+up[3]*self.radialVelocity*dt}
    if self:hasBodyClearance(world,radialOnly,self.flying) then self.position=radialOnly else self.radialVelocity=0 self.velocityY=0 end
    self.velocity={up[1]*self.radialVelocity,up[2]*self.radialVelocity,up[3]*self.radialVelocity}
  end
  self:resolveTerrainOverlap(world) self:stabilizeHeading()
end

function Camera:update(dt,window,world) self:updateMouse(window) self:updateMovement(dt,window,world) end
function Camera:getCenter() local f=self:getFront() return {self.position[1]+f[1],self.position[2]+f[2],self.position[3]+f[3]} end

return Camera
