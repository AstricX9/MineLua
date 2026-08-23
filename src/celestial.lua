-- The astronomical model. Day and night are what the planet's own rotation
-- produces, not a sun vector swept around the sky by a tuning constant.
--
-- Frames
-- ------
-- The voxel world is the planet's *body* frame: chunk coordinates are painted
-- on the planet and turn with it. +Y is the spin axis and the terrain generator
-- already treats it as such, using |direction.y| for latitude. The planet spins
-- in the positive sense about +Y, so at a point on the equator the local east
-- is cross(+Y, up) and the sun rises there, exactly as on Earth.
--
-- The sun therefore moves in body coordinates, and everything downstream --
-- lighting, shadows, the sky, the sun mesh -- reads that one direction.
--
-- Distances are real. The sun sits one astronomical unit away and is 696,000 km
-- across, which is an angular radius of 0.00465 rad: about five pixels on a
-- 720p screen at a 70 degree field of view, which is how large the sun is.

local Celestial = {}
Celestial.__index = Celestial

Celestial.ASTRONOMICAL_UNIT_METERS = 149597870700.0
Celestial.SUN_RADIUS_METERS = 695700000.0
Celestial.EARTH_AXIAL_TILT_RADIANS = 0.40910517666747087 -- 23.4392811 degrees

-- A full rotation in an hour: thirty minutes of daylight and thirty of night
-- at the equator, which is what a spin-driven cycle gives when the axis is
-- roughly upright.
Celestial.DEFAULT_DAY_LENGTH_SECONDS = 3600.0

local TWO_PI = math.pi * 2.0

local function wrapPi(angle)
  angle = (angle + math.pi) % TWO_PI
  if angle < 0.0 then angle = angle + TWO_PI end
  return angle - math.pi
end

function Celestial.new(options)
  options = options or {}
  local dayLength = tonumber(options.dayLengthSeconds) or Celestial.DEFAULT_DAY_LENGTH_SECONDS
  assert(dayLength > 0.0, "day length must be positive")
  local self = setmetatable({
    dayLengthSeconds = dayLength,
    -- A year of 365.25 days keeps the seasons in proportion to the day. At the
    -- default speed that is fifteen real hours per year, so the sun's noon
    -- height drifts slowly instead of visibly wobbling.
    yearLengthSeconds = tonumber(options.yearLengthSeconds) or dayLength * 365.25,
    axialTiltRadians = tonumber(options.axialTiltRadians) or Celestial.EARTH_AXIAL_TILT_RADIANS,
    orbitRadiusMeters = tonumber(options.orbitRadiusMeters) or Celestial.ASTRONOMICAL_UNIT_METERS,
    sunRadiusMeters = tonumber(options.sunRadiusMeters) or Celestial.SUN_RADIUS_METERS,
    rotationPhase = tonumber(options.rotationPhase) or 0.0,
    orbitPhase = tonumber(options.orbitPhase) or 0.0,
    timeScale = tonumber(options.timeScale) or 1.0,
    seconds = 0.0,
    elapsed = 0.0,
    rotationOverride = nil
  }, Celestial)
  self.sunAngularRadiusRadians = math.asin(
    math.min(1.0, self.sunRadiusMeters / self.orbitRadiusMeters))
  return self
end

-- Advance by a real-time delta. Kept separate from an absolute clock so the
-- dev-menu time scale can stretch or freeze the cycle without the sun jumping.
function Celestial:advance(deltaSeconds)
  self.elapsed = self.elapsed + (tonumber(deltaSeconds) or 0.0)
  self.seconds = self.seconds + (tonumber(deltaSeconds) or 0.0) * self.timeScale
  return self.seconds
end

function Celestial:setTimeScale(scale)
  self.timeScale = math.max(0.0, tonumber(scale) or 1.0)
end

function Celestial:naturalRotationAngle()
  return TWO_PI * (self.seconds / self.dayLengthSeconds + self.rotationPhase)
end

function Celestial:rotationAngle()
  return self.rotationOverride or self:naturalRotationAngle()
end

function Celestial:orbitAngle()
  return TWO_PI * (self.seconds / self.yearLengthSeconds + self.orbitPhase)
end

-- Unit vector from the planet centre to the sun, in the equatorial *inertial*
-- frame: +X toward the vernal equinox, +Y the spin axis. Obliquity tilts the
-- ecliptic against the equator, which is the whole of the seasons.
function Celestial:sunDirectionInertial()
  local lambda = self:orbitAngle()
  local sinL, cosL = math.sin(lambda), math.cos(lambda)
  local sinTilt, cosTilt = math.sin(self.axialTiltRadians), math.cos(self.axialTiltRadians)
  return cosL, sinTilt * sinL, cosTilt * sinL
end

-- The same vector in body coordinates, which is what the voxel world uses.
function Celestial:sunDirection()
  local ix, iy, iz = self:sunDirectionInertial()
  local theta = self:rotationAngle()
  local sinT, cosT = math.sin(theta), math.cos(theta)
  return {ix * cosT - iz * sinT, iy, ix * sinT + iz * cosT}
end

function Celestial:sunOffsetMeters()
  local direction = self:sunDirection()
  local distance = self.orbitRadiusMeters
  return {direction[1] * distance, direction[2] * distance, direction[3] * distance}
end

function Celestial:sunAngularRadius()
  return self.sunAngularRadiusRadians
end

-- Solar time for one observer: noon is the sun crossing their meridian. It is
-- deliberately a function of where you stand, so the dev menu asking for noon
-- puts the sun over the player rather than over some fixed prime meridian.
local function observerLongitude(position, center)
  center = center or {0.0, 0.0, 0.0}
  local x = position[1] - center[1]
  local z = position[3] - center[3]
  if x == 0.0 and z == 0.0 then return 0.0 end
  return math.atan2(z, x)
end

function Celestial:timeOfDayHours(position, center)
  local direction = self:sunDirection()
  local sunLongitude = math.atan2(direction[3], direction[1])
  local difference = wrapPi(sunLongitude - observerLongitude(position, center))
  return (12.0 + difference * (12.0 / math.pi)) % 24.0
end

-- Pin the rotation so the observer reads the requested hour. Only the spin is
-- overridden; the orbit keeps running, so a held time of day still drifts
-- through the seasons instead of freezing the whole sky.
function Celestial:overrideTimeOfDay(hour, position, center)
  local ix, _, iz = self:sunDirectionInertial()
  local inertialLongitude = math.atan2(iz, ix)
  local wanted = observerLongitude(position, center) + (hour - 12.0) * (math.pi / 12.0)
  self.rotationOverride = wanted - inertialLongitude
end

function Celestial:clearTimeOverride()
  self.rotationOverride = nil
end

function Celestial:usesTimeOverride()
  return self.rotationOverride ~= nil
end

-- Elevation of the sun above the local horizon, in the range [-1, 1]. Handy for
-- callers that only want to know whether it is day.
function Celestial:sunElevation(up)
  local direction = self:sunDirection()
  return direction[1] * up[1] + direction[2] * up[2] + direction[3] * up[3]
end

return Celestial
