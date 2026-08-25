local math3d = require("math3d")
local worldProfiles = require("world_profiles")

local atmosphere = {}

function atmosphere.sunDirection(time, cycleSpeed)
  return {
    -0.28,
    math.sin(time * cycleSpeed) * 0.85,
    math.cos(time * cycleSpeed) * 0.85
  }
end

function atmosphere.forSun(sunDir, fogStart, fogEnd, observerUp, worldProfile)
  -- observerUp is optional for the current flat runtime, but keeping lighting
  -- relative to local up also makes this profile interface usable by the
  -- spherical-grid runtime. Accepting a profile in its place is convenient for
  -- callers that do not need an alternate up vector.
  if observerUp and observerUp.atmosphere and not worldProfile then
    worldProfile, observerUp = observerUp, nil
  end
  observerUp = observerUp or {0.0, 1.0, 0.0}
  worldProfile = worldProfile or worldProfiles.get("earth")
  local authored = worldProfile.atmosphere or worldProfiles.get("earth").atmosphere
  local sunElevation = sunDir[1] * observerUp[1] + sunDir[2] * observerUp[2] + sunDir[3] * observerUp[3]
  local daylight = math3d.smoothstep(-0.18, 0.08, sunElevation)
  local day = daylight
  local moonAmount = math3d.smoothstep(-0.05, 0.18, -sunElevation) * (authored.moonAmount or 0.0)
  local night = 1.0 - math3d.smoothstep(-0.26, 0.04, sunElevation)
  local horizon = math3d.smoothstep(0.38, -0.02, math.abs(sunElevation))
  local lowSun = horizon * (1.0 - night)

  local dayFog = authored.dayFog
  local duskFog = authored.duskFog
  local nightFog = authored.nightFog
  local moonFog = authored.moonFog
  local fogColor = math3d.mixColor(nightFog, moonFog, night * moonAmount)
  fogColor = math3d.mixColor(fogColor, dayFog, day)
  fogColor = math3d.mixColor(fogColor, duskFog, lowSun * 0.68)

  local nightSkyLight = authored.nightSkyLight
  local daySkyLight = authored.daySkyLight
  local skyLightColor = math3d.mixColor(nightSkyLight, daySkyLight, daylight)
  local solarIrradiance = authored.solarIrradiance or 1.0
  local skyIntensity = math3d.mix(0.10, 0.85 * math.sqrt(solarIrradiance), daylight)
  local ambientFloor = math3d.mix(0.015, 0.055 * math.sqrt(solarIrradiance), daylight)
  local ambient = {skyLightColor[1] * skyIntensity, skyLightColor[2] * skyIntensity, skyLightColor[3] * skyIntensity}
  ambient = math3d.mixColor(ambient, authored.sunsetAmbient, lowSun * 0.30)

  local sunColor = math3d.mixColor(authored.sunLow, authored.sunDay, day)
  sunColor = math3d.mixColor(sunColor, authored.sunLow, lowSun * 0.55)
  local sunIntensity = 0.45 * solarIrradiance * daylight
  local lightColor = {sunColor[1] * sunIntensity, sunColor[2] * sunIntensity, sunColor[3] * sunIntensity}
  local moonColor = {0.28, 0.34, 0.48}
  local moonLightColor = {
    moonColor[1] * 0.075 * moonAmount,
    moonColor[2] * 0.075 * moonAmount,
    moonColor[3] * 0.075 * moonAmount
  }
  local cloudDayColor = authored.cloudDay
  local cloudNightColor = authored.cloudNight
  local fogDistanceScale = authored.fogDistanceScale or 1.0

  return {
    fogColor = fogColor,
    fogStart = math3d.mix(28.0 * fogDistanceScale, fogStart * fogDistanceScale, day),
    fogEnd = math3d.mix(66.0 * fogDistanceScale, fogEnd * fogDistanceScale, day),
    ambient = ambient,
    lightColor = lightColor,
    moonLightColor = moonLightColor,
    daylight = daylight,
    moonAmount = moonAmount,
    ambientFloor = ambientFloor,
    cloudColor = math3d.mixColor(cloudNightColor, cloudDayColor, daylight),
    skyZenith = math3d.mixColor(authored.zenithNight, authored.zenithDay, day),
    sunAureole = authored.aureole,
    sunElevation = sunElevation,
    shadowStrength = math3d.mix(0.02, worldProfile.id == "mars" and 0.54 or 0.46, day) *
      math3d.smoothstep(-0.03, 0.18, sunElevation)
  }
end

return atmosphere
