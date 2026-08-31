local math3d = require("math3d")
local worldProfiles = require("world_profiles")
local ephemeris = require("sky_ephemeris")

local atmosphere = {}

local TWO_PI = math.pi * 2.0

-- The clock, read as a date.
--
-- One turn of the cycle is one day on whichever world the player is standing
-- on, and phase zero is dawn -- the convention `timeOfDayForSimulationTime`
-- already uses. Counting those turns gives a day number, and scaling it by the
-- length of the world's day gives the Earth days that every ephemeris in
-- `sky_ephemeris` is written in: a hundred Martian sols is a hundred and three
-- days of planetary motion, not a hundred.
--
-- The zero point is J2000, so a new world opens at dawn on 1 January 2000 with
-- the solar system arranged as it actually was.
function atmosphere.dateFor(time, cycleSpeed, worldProfile)
  worldProfile = worldProfile or worldProfiles.get("earth")
  local phase = (time or 0.0) * (cycleSpeed or 0.0)
  local dayNumber = phase / TWO_PI
  local hour = (dayNumber * 24.0 + 6.0) % 24.0
  -- Noon of day zero is the epoch itself, and phase zero is six hours before.
  local julianDay = ephemeris.J2000_JULIAN_DAY +
    (dayNumber - 0.25) * (worldProfile.dayLengthScale or 1.0)
  return julianDay, (hour - 12.0) * (math.pi / 12.0), hour
end

-- Where every body in the sky is, at the moment the clock says.
function atmosphere.skyState(time, cycleSpeed, worldProfile)
  worldProfile = worldProfile or worldProfiles.get("earth")
  local julianDay, solarHourAngle, hour = atmosphere.dateFor(time, cycleSpeed, worldProfile)
  local observed = ephemeris.observe(worldProfile.id, julianDay, solarHourAngle)
  observed.hour = hour
  observed.sunDirection = ephemeris.direction(
    observed.sun.rightAscension, observed.sun.declination, observed.siderealTime)
  local moon = observed.moons[1]
  if moon then
    moon.direction = ephemeris.direction(
      moon.rightAscension, moon.declination, observed.siderealTime)
  end
  for _, planet in ipairs(observed.planets) do
    planet.direction = ephemeris.direction(
      planet.rightAscension, planet.declination, observed.siderealTime)
  end
  return observed
end

-- The sun alone, for callers that only need to light the world. Its azimuth is
-- exactly what the old fixed sweep gave -- the hour angle is still the time of
-- day -- but its declination now comes from the season instead of being pinned,
-- so noon climbs and falls across the year the way it does.
function atmosphere.sunDirection(time, cycleSpeed, worldProfile)
  return atmosphere.skyState(time, cycleSpeed, worldProfile).sunDirection
end

function atmosphere.forSun(sunDir, fogStart, fogEnd, observerUp, worldProfile, skyState)
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
  -- When the renderer supplies the ephemeris, moonlight exists only while the
  -- moon is above the horizon and in proportion to its illuminated phase. The
  -- old sun-only fallback remains for callers that do not ask for a full sky.
  if skyState then
    local moon=skyState.moons and skyState.moons[1]
    if moon and moon.direction then
      local altitude=math3d.smoothstep(-0.05,0.12,moon.direction[2])
      moonAmount=moonAmount*altitude*math.sqrt(math.max(0,moon.illuminatedFraction or 0))
    else
      moonAmount=0.0
    end
  end
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
    shadowStrength = math3d.mix(0.02, worldProfile.id == "mars" and 0.58 or 0.50, day) *
      math3d.smoothstep(-0.03, 0.18, sunElevation)
  }
end

return atmosphere
