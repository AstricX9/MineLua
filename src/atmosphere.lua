local math3d = require("math3d")

local atmosphere = {}

function atmosphere.sunDirection(time, cycleSpeed)
  return {
    -0.28,
    math.sin(time * cycleSpeed) * 0.85,
    math.cos(time * cycleSpeed) * 0.85
  }
end

-- Transmittance from an observer to the top of the atmosphere along the sun
-- ray, per channel. The sky shader already does this per pixel for its own
-- purposes; the sun mesh is one object, so its extinction is worth computing
-- once on the CPU rather than duplicating the march in another shader.
--
-- This is what makes the sun set instead of hanging white on the horizon: the
-- ray is blocked once it meets the ground, and before that the long slanted
-- path strips the blue out of it.
local PLANET_RADIUS = 6371000.0
local ATMOSPHERE_RADIUS = 6471000.0
local RAYLEIGH_SCALE_HEIGHT = 8000.0
local MIE_SCALE_HEIGHT = 1200.0
local RAYLEIGH_BETA = {5.802e-6, 13.558e-6, 33.100e-6}
local MIE_BETA = 21.0e-6 * 1.1
local TRANSMITTANCE_STEPS = 12

function atmosphere.sunTransmittance(altitudeMeters, sunElevation)
  altitudeMeters = math.max(altitudeMeters or 0.0, 0.0)
  sunElevation = math.max(-1.0, math.min(1.0, sunElevation or 1.0))
  local radius = PLANET_RADIUS + altitudeMeters

  -- The observer sits on the local vertical, so the sun ray is
  -- (sinElevation along up, cosElevation across) and both sphere hits reduce to
  -- a quadratic in the elevation cosine.
  local b = radius * sunElevation
  local function farHit(sphereRadius)
    local discriminant = b * b - (radius * radius - sphereRadius * sphereRadius)
    if discriminant < 0.0 then return nil end
    return -b + math.sqrt(discriminant)
  end
  local function nearHit(sphereRadius)
    local discriminant = b * b - (radius * radius - sphereRadius * sphereRadius)
    if discriminant < 0.0 then return nil end
    local t = -b - math.sqrt(discriminant)
    return t > 0.0 and t or nil
  end

  if nearHit(PLANET_RADIUS) then return {0.0, 0.0, 0.0} end
  local rayLength = farHit(ATMOSPHERE_RADIUS)
  if not rayLength or rayLength <= 0.0 then return {1.0, 1.0, 1.0} end

  local stepSize = rayLength / TRANSMITTANCE_STEPS
  local depthRayleigh, depthMie = 0.0, 0.0
  for i = 0, TRANSMITTANCE_STEPS - 1 do
    local distance = (i + 0.5) * stepSize
    -- Height of a point at `distance` along the ray, from the law of cosines.
    local sampleRadius = math.sqrt(radius * radius + distance * distance + 2.0 * b * distance)
    local height = math.max(sampleRadius - PLANET_RADIUS, 0.0)
    depthRayleigh = depthRayleigh + math.exp(-height / RAYLEIGH_SCALE_HEIGHT) * stepSize
    depthMie = depthMie + math.exp(-height / MIE_SCALE_HEIGHT) * stepSize
  end

  return {
    math.exp(-(RAYLEIGH_BETA[1] * depthRayleigh + MIE_BETA * depthMie)),
    math.exp(-(RAYLEIGH_BETA[2] * depthRayleigh + MIE_BETA * depthMie)),
    math.exp(-(RAYLEIGH_BETA[3] * depthRayleigh + MIE_BETA * depthMie))
  }
end

-- localUp is the observer's radial direction. Every term below wants the sun's
-- height *above their horizon*, and this used to read sunDir[2] for it, which
-- is only the same thing in a flat world whose up is +Y. On a planet an
-- equatorial observer has an up of roughly +Z, so sunDir[2] stayed near zero
-- around the clock: permanent dusk, a sky stuck at mauve, and a midnight lit
-- like late afternoon.
function atmosphere.forSun(sunDir, fogStart, fogEnd, localUp)
  local up = localUp or {0.0, 1.0, 0.0}
  local elevation = sunDir[1] * up[1] + sunDir[2] * up[2] + sunDir[3] * up[3]
  local daylight = math3d.smoothstep(-0.18, 0.08, elevation)
  local day = daylight
  local moonAmount = math3d.smoothstep(-0.05, 0.18, -elevation)
  local night = 1.0 - math3d.smoothstep(-0.26, 0.04, elevation)
  local horizon = math3d.smoothstep(0.38, -0.02, math.abs(elevation))
  local lowSun = horizon * (1.0 - night)

  local dayFog = {0.72, 0.84, 1.00}
  local duskFog = {0.78, 0.38, 0.24}
  local nightFog = {0.025, 0.040, 0.075}
  local moonFog = {0.055, 0.075, 0.120}
  local fogColor = math3d.mixColor(nightFog, moonFog, night * math3d.smoothstep(0.10, 0.85, -elevation))
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
    sunElevation = elevation,
    skyZenith = math3d.mixColor({0.02, 0.03, 0.08}, {0.34, 0.58, 0.92}, day),
    shadowStrength = math3d.mix(0.02, 0.46, day) * math3d.smoothstep(-0.03, 0.18, elevation)
  }
end

return atmosphere
