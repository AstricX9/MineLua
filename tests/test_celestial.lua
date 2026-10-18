-- Day and night must come out of the planet turning, and the numbers must be
-- the real ones: one astronomical unit, a 696,000 km sun, a 23.44 degree tilt.

package.path = "src/?.lua;" .. package.path

local Celestial = require("celestial")

local function close(actual, expected, tolerance, label)
  assert(math.abs(actual - expected) <= tolerance,
    string.format("%s: expected %.9f, got %.9f", label, expected, actual))
end

local sky = Celestial.new()

-- Real distances, not scene-scale stand-ins.
close(sky.orbitRadiusMeters, 149597870700.0, 0.0, "one astronomical unit")
close(sky.sunRadiusMeters, 695700000.0, 0.0, "solar radius")
close(sky:sunAngularRadius(), 0.004650, 1e-5, "solar angular radius")

-- Thirty minutes of day and thirty of night: one rotation an hour.
close(sky.dayLengthSeconds, 3600.0, 0.0, "one hour per rotation")

local RADIUS = 6371000.0
-- An equatorial observer on the +Z meridian, so local east is +X.
local observer = {0.0, 0.0, RADIUS}
local up = {0.0, 0.0, 1.0}
local east = {1.0, 0.0, 0.0}

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Walk one whole rotation in one-second steps and record the daylight fraction
-- and the two horizon crossings.
local daylightSeconds, sunriseHour, sunsetHour = 0, nil, nil
local previousElevation = sky:sunElevation(up)
local noonElevation, noonHour = -2.0, nil
for _ = 1, 3600 do
  sky:advance(1.0)
  local elevation = sky:sunElevation(up)
  if elevation > 0.0 then daylightSeconds = daylightSeconds + 1 end
  if previousElevation <= 0.0 and elevation > 0.0 then
    sunriseHour = sky:timeOfDayHours(observer)
    assert(dot(sky:sunDirection(), east) > 0.0, "the sun rises in the east")
  end
  if previousElevation > 0.0 and elevation <= 0.0 then
    sunsetHour = sky:timeOfDayHours(observer)
    assert(dot(sky:sunDirection(), east) < 0.0, "the sun sets in the west")
  end
  if elevation > noonElevation then
    noonElevation, noonHour = elevation, sky:timeOfDayHours(observer)
  end
  previousElevation = elevation
end

print(string.format("daylight %.1f min, sunrise %.2f h, sunset %.2f h, peak %.2f h at elevation %.3f",
  daylightSeconds / 60.0, sunriseHour or -1, sunsetHour or -1, noonHour or -1, noonElevation))

assert(sunriseHour and sunsetHour, "the sun crosses the horizon twice per rotation")
close(daylightSeconds, 1800.0, 30.0, "thirty minutes of daylight per hour at the equator")
close(sunriseHour, 6.0, 0.1, "sunrise near 06:00 solar time")
close(sunsetHour, 18.0, 0.1, "sunset near 18:00 solar time")
close(noonHour, 12.0, 0.1, "the sun peaks at local noon")
-- On the equator the noon sun is overhead give or take the seasonal tilt.
assert(noonElevation > math.cos(sky.axialTiltRadians) - 1e-6,
  "the equatorial noon sun is near the zenith")

-- A rotation returns the sun to where it was, apart from the day the orbit has
-- advanced meanwhile: that residual is the difference between a solar and a
-- sidereal day, and it should be about one part in 365.
local before = sky:sunDirection()
sky:advance(sky.dayLengthSeconds)
local after = sky:sunDirection()
local drift = math.acos(math.max(-1.0, math.min(1.0, dot(before, after))))
assert(drift < 0.05, string.format("one rotation returns the sun to itself (drift %.4f rad)", drift))
assert(drift > 0.001, "the orbit advances, so a solar day is not a sidereal day")

-- The dev-menu override has to be exact, or dragging the slider would not
-- match the label next to it.
for _, hour in ipairs({0.0, 5.5, 12.0, 18.25, 23.9}) do
  sky:overrideTimeOfDay(hour, observer)
  close(sky:timeOfDayHours(observer), hour, 1e-6, "time-of-day override round trips")
end
assert(sky:usesTimeOverride(), "the override is reported as active")
sky:clearTimeOverride()
assert(not sky:usesTimeOverride(), "the override can be released")

-- Latitude has to matter, or the tilt is decorative. Compare noon elevation at
-- the equator against a high latitude on the same rotation.
sky:overrideTimeOfDay(12.0, observer)
local equatorNoon = sky:sunElevation(up)
local polarUp = {0.0, math.sin(1.2), math.cos(1.2)}
sky:overrideTimeOfDay(12.0, {0.0, RADIUS * math.sin(1.2), RADIUS * math.cos(1.2)})
local polarNoon = sky:sunElevation(polarUp)
assert(polarNoon < equatorNoon - 0.3,
  string.format("a high latitude gets a lower noon sun (%.3f against %.3f)", polarNoon, equatorNoon))

print("celestial tests passed")
