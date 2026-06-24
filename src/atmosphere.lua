local math3d = require("math3d")

local atmosphere = {}

function atmosphere.sunDirection(time, cycleSpeed)
  return {
    -0.28,
    math.sin(time * cycleSpeed) * 0.85,
    math.cos(time * cycleSpeed) * 0.85
  }
end

function atmosphere.forSun(sunDir, fogStart, fogEnd)
  local day = math3d.smoothstep(-0.10, 0.25, sunDir[2])
  local night = 1.0 - math3d.smoothstep(-0.26, 0.04, sunDir[2])
  local horizon = math3d.smoothstep(0.38, -0.02, math.abs(sunDir[2]))
  local lowSun = horizon * (1.0 - night)

  local dayFog = {0.53, 0.81, 0.92}
  local duskFog = {0.96, 0.43, 0.24}
  local nightFog = {0.035, 0.045, 0.085}
  local fogColor = math3d.mixColor(math3d.mixColor(nightFog, dayFog, day), duskFog, lowSun * 0.42)

  local ambient = math3d.mixColor({0.055, 0.065, 0.11}, {0.32, 0.35, 0.36}, day)
  ambient = math3d.mixColor(ambient, {0.34, 0.24, 0.18}, lowSun * 0.35)

  local lightColor = math3d.mixColor({0.42, 0.48, 0.66}, {1.0, 0.94, 0.78}, day)
  lightColor = math3d.mixColor(lightColor, {1.0, 0.55, 0.28}, lowSun * 0.55)
  local lightPower = math3d.mix(0.16, 0.88, day)
  lightColor = {lightColor[1] * lightPower, lightColor[2] * lightPower, lightColor[3] * lightPower}

  return {
    fogColor = fogColor,
    fogStart = math3d.mix(26.0, fogStart, day),
    fogEnd = math3d.mix(54.0, fogEnd, day),
    ambient = ambient,
    lightColor = lightColor,
    skyZenith = math3d.mixColor({0.02, 0.03, 0.08}, {0.40, 0.67, 1.0}, day),
    shadowStrength = math3d.mix(0.18, 0.68, day) * math3d.smoothstep(-0.03, 0.18, sunDir[2])
  }
end

return atmosphere
