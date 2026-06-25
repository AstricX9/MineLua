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

  local dayFog = {0.44, 0.65, 0.76}
  local duskFog = {0.78, 0.38, 0.24}
  local nightFog = {0.025, 0.040, 0.075}
  local moonFog = {0.055, 0.075, 0.120}
  local fogColor = math3d.mixColor(nightFog, moonFog, night * math3d.smoothstep(0.10, 0.85, -sunDir[2]))
  fogColor = math3d.mixColor(fogColor, dayFog, day)
  fogColor = math3d.mixColor(fogColor, duskFog, lowSun * 0.68)

  local ambient = math3d.mixColor({0.055, 0.065, 0.11}, {0.24, 0.27, 0.28}, day)
  ambient = math3d.mixColor(ambient, {0.28, 0.20, 0.15}, lowSun * 0.35)

  local lightColor = math3d.mixColor({0.42, 0.48, 0.66}, {1.0, 0.94, 0.78}, day)
  lightColor = math3d.mixColor(lightColor, {1.0, 0.55, 0.28}, lowSun * 0.55)
  local lightPower = math3d.mix(0.16, 0.78, day)
  lightColor = {lightColor[1] * lightPower, lightColor[2] * lightPower, lightColor[3] * lightPower}

  return {
    fogColor = fogColor,
    fogStart = math3d.mix(28.0, fogStart, day),
    fogEnd = math3d.mix(66.0, fogEnd, day),
    ambient = ambient,
    lightColor = lightColor,
    skyZenith = math3d.mixColor({0.02, 0.03, 0.08}, {0.40, 0.67, 1.0}, day),
    shadowStrength = math3d.mix(0.18, 0.68, day) * math3d.smoothstep(-0.03, 0.18, sunDir[2])
  }
end

return atmosphere
