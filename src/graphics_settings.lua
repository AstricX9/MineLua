local graphics = {}

graphics.window = {
  width = 1280,
  height = 720,
  fovDegrees = 100
}

graphics.player = {
  eyeHeight = 1.62,
  crouchEyeHeight = 1.24,
  radius = 0.34,
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
  terrainMaxHeight = 16,
  chunkRenderRadius = 4,
  visualDistance = 4096.0,
  distantTerrain = true,
  distantTerrainCache = "world_cache/distant_lod"
}

graphics.atmosphere = {
  fogStart = 180.0,
  fogEnd = 1250.0,
  sunCycleSpeed = 0.02,
  skyColor = {0.53, 0.81, 0.92},
  skyExposure = 0.62,
  cloudDensity = 1.35,
  sunGlare = 0.58,
  maxFogAmount = 0.76,
  heightFogDensity = 0.22,
  heightFogFalloff = 0.080,
  horizonFog = 0.10,
  sunScatter = 0.45
}

graphics.terrain = {
  exposure = 0.94,
  topLight = 1.00,
  sideLight = 0.78,
  bottomLight = 0.52
}

graphics.shadows = {
  mapSize = 2048,
  distance = 60.0,
  near = 8.0,
  far = 132.0
}

graphics.water = {
  level = 8.65,
  radius = 4096.0
}

return graphics
