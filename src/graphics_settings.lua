local graphics = {}

graphics.window = {
  width = 1280,
  height = 720,
  fovDegrees = 70
}

graphics.player = {
  eyeHeight = 1.62,
  crouchEyeHeight = 1.24,
  radius = 0.30,
  walkSpeed = 5.1,
  sprintSpeed = 7.2,
  crouchSpeed = 2.4,
  flySpeed = 9.5,
  acceleration = 34.0,
  airAcceleration = 8.0,
  flyAcceleration = 24.0,
  groundFriction = 38.0,
  airFriction = 2.0,
  flyFriction = 18.0,
  gravity = 19.5,
  jumpSpeed = 6.4,
  stepHeight = 1.08,
  groundSnap = 0.36,
  coyoteTime = 0.10,
  jumpBufferTime = 0.12,
  mouseSensitivity = 0.085,
  reach = 6.0,
  showDebugBody = false
}

graphics.world = {
  terrainMaxHeight = 127,
  chunkRenderRadius = 4,
  visualDistance = 192.0
}

graphics.performance = {
  terrainWorkBudget = 16,
  chunkQueueBudget = 4,
  chunkQueueBacklog = 16,
  lightingStepBudget = 10,
  loadingChunkBudget = 2,
  loadingLightingStepBudget = 14,
  loadingMeshBudget = 2,
  loadingRequiredRadius = 1,
  loadingHaloRadius = 2,
  initialSpawnRadius = 1
}

graphics.atmosphere = {
  fogStart = 220.0,
  fogEnd = 1250.0,
  sunCycleSpeed = 0.005235987755982989,
  skyColor = {0.53, 0.81, 0.92},
  skyExposure = 0.62,
  cloudDensity = 1.35,
  cloudBottom = 132.0,
  cloudTop = 136.0,
  sunGlare = 0.58,
  maxFogAmount = 0.58,
  heightFogDensity = 0.08,
  heightFogFalloff = 0.080,
  horizonFog = 0.10,
  sunScatter = 0.45
}

graphics.terrain = {
  exposure = 1.04,
  topLight = 1.00,
  sideLight = 0.82,
  bottomLight = 0.58
}

graphics.shadows = {
  mapSize = 2048,
  distance = 60.0,
  near = 8.0,
  far = 132.0
}

graphics.water = {
  level = 62.65,
  radius = 1024.0
}

graphics.terrainGeneration = {
  seed = 1,
  seaLevel = 63,
  continentScale = 0.00036,
  biomeScale = 0.00092,
  regionScale = 0.00125,
  mountainScale = 0.00078,
  riverScale = 0.00115,
  forestScale = 0.00165,
  macroWarpScale = 0.00062,
  macroWarpAmount = 360.0,
  detailScale = 0.026,
  grassTintStrength = 0.92,
  treeDensity = 0.78
}

local function isArray(value)
  return type(value) == "table" and value[1] ~= nil
end

local function mergeSettings(target, source)
  if type(source) ~= "table" then
    return target
  end

  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" and not isArray(value) then
      mergeSettings(target[key], value)
    else
      target[key] = value
    end
  end

  return target
end

local function loadSettings(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, decoded = pcall(require("json").decode, content)
  if ok and type(decoded) == "table" then
    return decoded
  end

  io.stderr:write("Skipping invalid settings file: " .. path .. "\n")
  return nil
end

mergeSettings(graphics, loadSettings("data/settings.json"))

return graphics
