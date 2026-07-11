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
  local daylight = math3d.smoothstep(-0.18, 0.08, sunDir[2])
  local day = daylight
  local moonAmount = math3d.smoothstep(-0.05, 0.18, -sunDir[2])
  local night = 1.0 - math3d.smoothstep(-0.26, 0.04, sunDir[2])
  local horizon = math3d.smoothstep(0.38, -0.02, math.abs(sunDir[2]))
  local lowSun = horizon * (1.0 - night)

  local dayFog = {0.72, 0.84, 1.00}
  local duskFog = {0.78, 0.38, 0.24}
  local nightFog = {0.025, 0.040, 0.075}
  local moonFog = {0.055, 0.075, 0.120}
  local fogColor = math3d.mixColor(nightFog, moonFog, night * math3d.smoothstep(0.10, 0.85, -sunDir[2]))
  fogColor = math3d.mixColor(fogColor, dayFog, day)
  fogColor = math3d.mixColor(fogColor, duskFog, lowSun * 0.68)

  local nightSkyLight = {0.07, 0.09, 0.15}
  local daySkyLight = {0.62, 0.72, 0.86}
  local skyLightColor = math3d.mixColor(nightSkyLight, daySkyLight, daylight)
  local skyIntensity = math3d.mix(0.10, 0.85, daylight)
  local ambientFloor = math3d.mix(0.015, 0.055, daylight)
  local ambient = {skyLightColor[1] * skyIntensity, skyLightColor[2] * skyIntensity, skyLightColor[3] * skyIntensity}
  ambient = math3d.mixColor(ambient, {0.42, 0.30, 0.22}, lowSun * 0.30)

  local sunColor = math3d.mixColor({1.0, 0.70, 0.42}, {1.0, 0.96, 0.86}, day)
  sunColor = math3d.mixColor(sunColor, {1.0, 0.55, 0.28}, lowSun * 0.55)
  local sunIntensity = 0.45 * daylight
  local lightColor = {sunColor[1] * sunIntensity, sunColor[2] * sunIntensity, sunColor[3] * sunIntensity}
  local moonColor = {0.28, 0.34, 0.48}
  local moonLightColor = {
    moonColor[1] * 0.075 * moonAmount,
    moonColor[2] * 0.075 * moonAmount,
    moonColor[3] * 0.075 * moonAmount
  }
  local cloudDayColor = {0.95, 0.97, 1.0}
  local cloudNightColor = {0.10, 0.13, 0.20}

  return {
    fogColor = fogColor,
    fogStart = math3d.mix(28.0, fogStart, day),
    fogEnd = math3d.mix(66.0, fogEnd, day),
    ambient = ambient,
    lightColor = lightColor,
    moonLightColor = moonLightColor,
    daylight = daylight,
    moonAmount = moonAmount,
    ambientFloor = ambientFloor,
    cloudColor = math3d.mixColor(cloudNightColor, cloudDayColor, daylight),
    skyZenith = math3d.mixColor({0.02, 0.03, 0.08}, {0.34, 0.58, 0.92}, day),
    shadowStrength = math3d.mix(0.02, 0.46, day) * math3d.smoothstep(-0.03, 0.18, sunDir[2])
  }
end

return atmosphere
