local graphics = {}

graphics.window = {
  width = 1280,
  height = 720,
  fovDegrees = 100
}

graphics.world = {
  terrainMaxHeight = 16,
  chunkRenderRadius = 4
}

graphics.atmosphere = {
  fogStart = 42.0,
  fogEnd = 78.0,
  sunCycleSpeed = 0.02,
  skyColor = {0.53, 0.81, 0.92},
  skyExposure = 0.62,
  cloudDensity = 1.35,
  sunGlare = 0.58
}

graphics.terrain = {
  exposure = 1.08,
  topLight = 1.10,
  sideLight = 0.86,
  bottomLight = 0.64
}

graphics.shadows = {
  mapSize = 2048,
  distance = 60.0,
  near = 8.0,
  far = 132.0
}

graphics.water = {
  level = 6.15,
  radius = 136.0
}

return graphics
