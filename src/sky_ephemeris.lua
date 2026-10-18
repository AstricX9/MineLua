-- Where the other bodies of the solar system actually are.
--
-- The sky the player looks at is not decoration generated from the clock; it is
-- the clock. One turn of the world is one day, and the same number that turns it
-- advances a date, so the sun's declination walks through the seasons, the moon
-- runs its own month against that, and the planets creep along the ecliptic at
-- the rates their orbits give them.
--
-- Frames
-- ------
-- Everything is computed heliocentrically in the J2000 ecliptic frame, rotated
-- into the J2000 equatorial (ICRF) frame by the obliquity, and finally into the
-- *observer planet's* equatorial frame using that planet's pole. The last step
-- is what gives each world its own seasons and its own circumpolar stars: on
-- Mars the pole is tipped 25.19 degrees to its orbit rather than Earth's 23.44,
-- and it points at a different part of the sky, so the Martian sky turns about
-- a different star.
--
-- The game's body frame -- the one chunk coordinates are painted on -- is the
-- last conversion, in `direction`. Its convention is fixed by the sun the
-- renderer already draws: +Y is up, +Z is east, and the celestial pole lies on
-- the horizon at +X, which is to say the player stands on the equator.
--
-- Accuracy
-- --------
-- Planets use the JPL approximate elements for 1800-2050, good to roughly an
-- arcminute for the inner planets and a few arcminutes for the outer ones. The
-- moon uses the classical abridged lunar theory, good to a couple of arcminutes
-- in longitude. Both are far below what a voxel sky can show.

local ephemeris = {}

local RADIANS = math.pi / 180.0
local TWO_PI = math.pi * 2.0
local ARCSECONDS = RADIANS / 3600.0

-- 2000 January 1.5 TT, the epoch every element below is referred to.
ephemeris.J2000_JULIAN_DAY = 2451545.0
ephemeris.OBLIQUITY_RADIANS = 23.43928 * RADIANS
ephemeris.ASTRONOMICAL_UNIT_METERS = 149597870700.0

local function wrapTwoPi(angle)
  angle = angle % TWO_PI
  if angle < 0.0 then angle = angle + TWO_PI end
  return angle
end

-- JPL's approximate elements: value at J2000 and change per Julian century.
-- Semi-major axis in au, angles in degrees.
--
--   a  semi-major axis          e  eccentricity        i  inclination
--   L  mean longitude           p  longitude of perihelion
--   n  longitude of ascending node
local ELEMENTS = {
  mercury = {
    a = {0.38709927,  0.00000037}, e = {0.20563593,  0.00001906},
    i = {7.00497902, -0.00594749}, L = {252.25032350, 149472.67411175},
    p = {77.45779628, 0.16047689}, n = {48.33076593, -0.12534081}
  },
  venus = {
    a = {0.72333566,  0.00000390}, e = {0.00677672, -0.00004107},
    i = {3.39467605, -0.00078890}, L = {181.97909950, 58517.81538729},
    p = {131.60246718, 0.00268329}, n = {76.67984255, -0.27769418}
  },
  -- The Earth-Moon barycentre. The moon is added separately below.
  earth = {
    a = {1.00000261,  0.00000562}, e = {0.01671123, -0.00004392},
    i = {-0.00001531, -0.01294668}, L = {100.46457166, 35999.37244981},
    p = {102.93768193, 0.32327364}, n = {0.0, 0.0}
  },
  mars = {
    a = {1.52371034,  0.00001847}, e = {0.09339410,  0.00007882},
    i = {1.84969142, -0.00813131}, L = {-4.55343205, 19140.30268499},
    p = {-23.94362959, 0.44441088}, n = {49.55953891, -0.29257343}
  },
  jupiter = {
    a = {5.20288700, -0.00011607}, e = {0.04838624, -0.00013253},
    i = {1.30439695, -0.00183714}, L = {34.39644051, 3034.74612775},
    p = {14.72847983, 0.21252668}, n = {100.47390909, 0.20469106}
  },
  saturn = {
    a = {9.53667594, -0.00125060}, e = {0.05386179, -0.00050991},
    i = {2.48599187,  0.00193609}, L = {49.95424423, 1222.49362201},
    p = {92.59887831, -0.41897216}, n = {113.66242448, -0.28867794}
  },
  uranus = {
    a = {19.18916464, -0.00196176}, e = {0.04725744, -0.00004397},
    i = {0.77263783, -0.00242939}, L = {313.23810451, 428.48202785},
    p = {170.95427630, 0.40805281}, n = {74.01692503, 0.04240589}
  },
  neptune = {
    a = {30.06992276,  0.00026291}, e = {0.00859048,  0.00005105},
    i = {1.77004347,  0.00035372}, L = {-55.12002969, 218.45945325},
    p = {44.96476227, -0.32241464}, n = {131.78422574, -0.00508664}
  }
}

-- Equatorial radius in metres, the reference magnitude at unit distance and
-- zero phase, and the disc colour. Reference magnitudes are the Astronomical
-- Almanac's V(1,0); the phase terms that go with them are in `apparentMagnitude`.
local BODIES = {
  mercury = {radius = 2439700.0,  referenceMagnitude = -0.36, color = {1.00, 0.95, 0.88}, name = "Mercury"},
  venus   = {radius = 6051800.0,  referenceMagnitude = -4.34, color = {1.00, 0.98, 0.90}, name = "Venus"},
  earth   = {radius = 6371000.0,  referenceMagnitude = -3.99, color = {0.62, 0.78, 1.00}, name = "Earth"},
  mars    = {radius = 3389500.0,  referenceMagnitude = -1.51, color = {1.00, 0.62, 0.42}, name = "Mars"},
  jupiter = {radius = 69911000.0, referenceMagnitude = -9.25, color = {1.00, 0.93, 0.82}, name = "Jupiter"},
  saturn  = {radius = 58232000.0, referenceMagnitude = -8.88, color = {1.00, 0.94, 0.74}, name = "Saturn"},
  uranus  = {radius = 25362000.0, referenceMagnitude = -7.19, color = {0.70, 0.92, 0.96}, name = "Uranus"},
  neptune = {radius = 24622000.0, referenceMagnitude = -6.87, color = {0.58, 0.70, 1.00}, name = "Neptune"}
}
ephemeris.bodies = BODIES

-- IAU pole of rotation in ICRF coordinates, and the tilt of the equator to the
-- orbit. Earth is the identity by construction: the ICRF equator *is* Earth's.
local POLES = {
  earth = nil,
  mars = {rightAscension = 317.68143 * RADIANS, declination = 52.88650 * RADIANS}
}

-- Kepler's equation by Newton's method. Three iterations settle every orbit in
-- the table to well below a milliarcsecond; the loop guards the rest.
local function eccentricAnomaly(meanAnomaly, eccentricity)
  local E = meanAnomaly + eccentricity * math.sin(meanAnomaly)
  for _ = 1, 12 do
    local delta = (E - eccentricity * math.sin(E) - meanAnomaly) /
      (1.0 - eccentricity * math.cos(E))
    E = E - delta
    if math.abs(delta) < 1.0e-12 then break end
  end
  return E
end

-- Heliocentric position in the J2000 ecliptic frame, in au.
function ephemeris.heliocentric(bodyId, centuries)
  local element = ELEMENTS[bodyId]
  if not element then return nil end
  local a = element.a[1] + element.a[2] * centuries
  local e = element.e[1] + element.e[2] * centuries
  local inclination = (element.i[1] + element.i[2] * centuries) * RADIANS
  local meanLongitude = (element.L[1] + element.L[2] * centuries) * RADIANS
  local perihelion = (element.p[1] + element.p[2] * centuries) * RADIANS
  local node = (element.n[1] + element.n[2] * centuries) * RADIANS

  local argumentOfPerihelion = perihelion - node
  local meanAnomaly = wrapTwoPi(meanLongitude - perihelion + math.pi) - math.pi
  local E = eccentricAnomaly(meanAnomaly, e)

  -- Position in the orbital plane, x toward perihelion.
  local orbitalX = a * (math.cos(E) - e)
  local orbitalY = a * math.sqrt(math.max(1.0 - e * e, 0.0)) * math.sin(E)

  local cosW, sinW = math.cos(argumentOfPerihelion), math.sin(argumentOfPerihelion)
  local cosN, sinN = math.cos(node), math.sin(node)
  local cosI, sinI = math.cos(inclination), math.sin(inclination)

  return {
    (cosW * cosN - sinW * sinN * cosI) * orbitalX +
      (-sinW * cosN - cosW * sinN * cosI) * orbitalY,
    (cosW * sinN + sinW * cosN * cosI) * orbitalX +
      (-sinW * sinN + cosW * cosN * cosI) * orbitalY,
    (sinW * sinI) * orbitalX + (cosW * sinI) * orbitalY
  }
end

-- The abridged lunar theory is written against 1999 December 31.0 TT rather
-- than J2000, and the moon covers thirteen degrees a day, so getting this
-- offset wrong puts the phase three days out.
ephemeris.LUNAR_EPOCH_JULIAN_DAY = 2451543.5

-- Geocentric position of the moon in the J2000 ecliptic frame, in au. The
-- abridged theory: mean elements, then the perturbations large enough to see --
-- the evection and the variation between them move the moon by two degrees, so
-- a mean-element moon would show the wrong phase at the wrong place.
function ephemeris.moonGeocentric(julianDay)
  local days = julianDay - ephemeris.LUNAR_EPOCH_JULIAN_DAY
  local node = (125.1228 - 0.0529538083 * days) * RADIANS
  local inclination = 5.1454 * RADIANS
  local argument = (318.0634 + 0.1643573223 * days) * RADIANS
  local semiMajorAxis = 60.2666           -- Earth radii
  local eccentricity = 0.054900
  local meanAnomaly = (115.3654 + 13.0649929509 * days) * RADIANS

  local E = eccentricAnomaly(meanAnomaly, eccentricity)
  local orbitalX = semiMajorAxis * (math.cos(E) - eccentricity)
  local orbitalY = semiMajorAxis * math.sqrt(1.0 - eccentricity * eccentricity) * math.sin(E)
  local distance = math.sqrt(orbitalX * orbitalX + orbitalY * orbitalY)
  local trueAnomaly = math.atan2(orbitalY, orbitalX)

  local cosW, sinW = math.cos(argument + trueAnomaly), math.sin(argument + trueAnomaly)
  local cosN, sinN = math.cos(node), math.sin(node)
  local cosI, sinI = math.cos(inclination), math.sin(inclination)
  local x = distance * (cosN * cosW - sinN * sinW * cosI)
  local y = distance * (sinN * cosW + cosN * sinW * cosI)
  local z = distance * (sinW * sinI)

  local longitude = math.atan2(y, x)
  local latitude = math.atan2(z, math.sqrt(x * x + y * y))

  -- Solar mean elements, needed for the perturbations that involve the sun.
  local solarAnomaly = (356.0470 + 0.9856002585 * days) * RADIANS
  local solarPerihelion = (282.9404 + 4.70935e-5 * days) * RADIANS
  local solarLongitude = solarAnomaly + solarPerihelion
  local moonLongitude = node + argument + meanAnomaly
  local elongation = moonLongitude - solarLongitude
  local latitudeArgument = moonLongitude - node

  local sin = math.sin
  longitude = longitude
    - 1.274 * RADIANS * sin(meanAnomaly - 2.0 * elongation)      -- evection
    + 0.658 * RADIANS * sin(2.0 * elongation)                    -- variation
    - 0.186 * RADIANS * sin(solarAnomaly)                        -- yearly equation
    - 0.059 * RADIANS * sin(2.0 * meanAnomaly - 2.0 * elongation)
    - 0.057 * RADIANS * sin(meanAnomaly - 2.0 * elongation + solarAnomaly)
    + 0.053 * RADIANS * sin(meanAnomaly + 2.0 * elongation)
    + 0.046 * RADIANS * sin(2.0 * elongation - solarAnomaly)
    + 0.041 * RADIANS * sin(meanAnomaly - solarAnomaly)
    - 0.035 * RADIANS * sin(elongation)                          -- parallactic
    - 0.031 * RADIANS * sin(meanAnomaly + solarAnomaly)
    - 0.015 * RADIANS * sin(2.0 * latitudeArgument - 2.0 * elongation)
    + 0.011 * RADIANS * sin(meanAnomaly - 4.0 * elongation)

  latitude = latitude
    - 0.173 * RADIANS * sin(latitudeArgument - 2.0 * elongation)
    - 0.055 * RADIANS * sin(meanAnomaly - latitudeArgument - 2.0 * elongation)
    - 0.046 * RADIANS * sin(meanAnomaly + latitudeArgument - 2.0 * elongation)
    + 0.033 * RADIANS * sin(latitudeArgument + 2.0 * elongation)
    + 0.017 * RADIANS * sin(2.0 * meanAnomaly + latitudeArgument)

  distance = distance
    - 0.58 * math.cos(meanAnomaly - 2.0 * elongation)
    - 0.46 * math.cos(2.0 * elongation)

  -- Earth radii to au.
  local scale = distance * 6378137.0 / ephemeris.ASTRONOMICAL_UNIT_METERS
  local cosLatitude = math.cos(latitude)
  return {
    scale * cosLatitude * math.cos(longitude),
    scale * cosLatitude * math.sin(longitude),
    scale * math.sin(latitude)
  }
end

local function eclipticToEquatorial(v)
  local cosE, sinE = math.cos(ephemeris.OBLIQUITY_RADIANS), math.sin(ephemeris.OBLIQUITY_RADIANS)
  return {v[1], v[2] * cosE - v[3] * sinE, v[2] * sinE + v[3] * cosE}
end

-- Basis of the observer planet's equator, expressed in ICRF. The x axis is the
-- ascending node of that equator on the ICRF equator, which the IAU places 90
-- degrees ahead of the pole's right ascension.
function ephemeris.equatorialBasis(observerId)
  local pole = POLES[observerId]
  if not pole then
    return {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}
  end
  local cosD, sinD = math.cos(pole.declination), math.sin(pole.declination)
  local cosA, sinA = math.cos(pole.rightAscension), math.sin(pole.rightAscension)
  local axisZ = {cosD * cosA, cosD * sinA, sinD}
  local axisX = {-sinA, cosA, 0.0}
  local axisY = {
    axisZ[2] * axisX[3] - axisZ[3] * axisX[2],
    axisZ[3] * axisX[1] - axisZ[1] * axisX[3],
    axisZ[1] * axisX[2] - axisZ[2] * axisX[1]
  }
  return axisX, axisY, axisZ
end

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

local function length(v) return math.sqrt(dot(v, v)) end

-- Right ascension and declination of an ICRF vector in the observer's own
-- equatorial frame.
local function sphericalIn(basisX, basisY, basisZ, v)
  local x, y, z = dot(v, basisX), dot(v, basisY), dot(v, basisZ)
  local horizontal = math.sqrt(x * x + y * y)
  return wrapTwoPi(math.atan2(y, x)), math.atan2(z, horizontal)
end

-- Apparent visual magnitude. `sunDistance` and `observerDistance` are in au and
-- `phaseAngle` is the sun-body-observer angle in radians. The phase terms are
-- the Astronomical Almanac's fits; Saturn's rings are not modelled, so it runs
-- up to about half a magnitude faint when they are open.
local function apparentMagnitude(bodyId, reference, sunDistance, observerDistance, phaseAngle)
  local phase = phaseAngle / RADIANS
  local hundredths = phase / 100.0
  local correction = 0.0
  if bodyId == "mercury" then
    correction = 3.80 * hundredths - 2.73 * hundredths * hundredths +
      2.00 * hundredths * hundredths * hundredths
  elseif bodyId == "venus" then
    correction = 0.09 * hundredths + 2.39 * hundredths * hundredths -
      0.65 * hundredths * hundredths * hundredths
  elseif bodyId == "earth" then
    correction = -1.060e-3 * phase + 2.054e-4 * phase * phase
  elseif bodyId == "mars" then
    correction = 0.016 * phase
  elseif bodyId == "jupiter" then
    correction = 0.005 * phase
  end
  return reference + 5.0 * math.log10(math.max(sunDistance * observerDistance, 1.0e-6)) +
    correction
end

-- Everything the renderer needs about one body: where it is, how bright it is,
-- how large it is, and how much of it the sun is lighting.
local function observation(bodyId, definition, relative, sunRelative, sunDistance,
    basisX, basisY, basisZ)
  local distance = length(relative)
  if distance <= 0.0 then return nil end
  local phaseAngle = 0.0
  if sunRelative then
    -- Angle at the body between the sun and the observer.
    local toSun = {
      sunRelative[1] - relative[1], sunRelative[2] - relative[2], sunRelative[3] - relative[3]
    }
    local toObserver = {-relative[1], -relative[2], -relative[3]}
    local denominator = length(toSun) * length(toObserver)
    if denominator > 0.0 then
      phaseAngle = math.acos(math.max(-1.0, math.min(1.0, dot(toSun, toObserver) / denominator)))
    end
  end
  local rightAscension, declination = sphericalIn(basisX, basisY, basisZ, relative)
  return {
    id = bodyId,
    name = definition.name,
    rightAscension = rightAscension,
    declination = declination,
    distanceMeters = distance * ephemeris.ASTRONOMICAL_UNIT_METERS,
    angularRadius = math.asin(math.min(1.0,
      definition.radius / (distance * ephemeris.ASTRONOMICAL_UNIT_METERS))),
    phaseAngle = phaseAngle,
    illuminatedFraction = (1.0 + math.cos(phaseAngle)) * 0.5,
    magnitude = apparentMagnitude(bodyId, definition.referenceMagnitude,
      sunDistance or distance, distance, phaseAngle),
    color = definition.color
  }
end

local SUN = {
  radius = 695700000.0,
  -- Apparent magnitude at one au, which is what the 5 log(r d) term is
  -- referred to for a self-luminous body seen from distance d = r.
  referenceMagnitude = -26.74,
  color = {1.0, 0.97, 0.92},
  name = "Sun"
}
ephemeris.sun = SUN

-- The whole sky at one instant, for one observer planet.
--
-- `julianDay` is the date; `solarHourAngle` is the local hour angle of the sun
-- in radians, which is the game's own time of day and the only thing tying this
-- to the renderer's clock. Sidereal time is then whatever it has to be for the
-- ephemeris sun to be where the game already draws it, so the stars keep step
-- with the sun rather than being wound independently.
function ephemeris.observe(observerId, julianDay, solarHourAngle)
  observerId = ELEMENTS[observerId] and observerId or "earth"
  local days = julianDay - ephemeris.J2000_JULIAN_DAY
  local centuries = days / 36525.0
  local basisX, basisY, basisZ = ephemeris.equatorialBasis(observerId)

  local observerHelio = ephemeris.heliocentric(observerId, centuries)
  if observerId == "earth" then
    -- The elements give the barycentre; the observer is on the other side of it
    -- from the moon, by the mass ratio.
    local moon = ephemeris.moonGeocentric(julianDay)
    local ratio = 1.0 / 82.30
    for index = 1, 3 do
      observerHelio[index] = observerHelio[index] - moon[index] * ratio
    end
  end

  local sunRelative = eclipticToEquatorial({
    -observerHelio[1], -observerHelio[2], -observerHelio[3]
  })
  local sunDistance = length(sunRelative)
  local sunRightAscension, sunDeclination = sphericalIn(basisX, basisY, basisZ, sunRelative)

  local result = {
    julianDay = julianDay,
    observer = observerId,
    -- Local sidereal time in the observer's own equatorial frame.
    siderealTime = wrapTwoPi(solarHourAngle + sunRightAscension),
    sun = {
      id = "sun",
      name = SUN.name,
      rightAscension = sunRightAscension,
      declination = sunDeclination,
      distanceMeters = sunDistance * ephemeris.ASTRONOMICAL_UNIT_METERS,
      angularRadius = math.asin(SUN.radius / (sunDistance * ephemeris.ASTRONOMICAL_UNIT_METERS)),
      magnitude = SUN.referenceMagnitude + 5.0 * math.log10(sunDistance),
      illuminatedFraction = 1.0,
      phaseAngle = 0.0,
      color = SUN.color
    },
    planets = {},
    moons = {}
  }

  for bodyId, definition in pairs(BODIES) do
    if bodyId ~= observerId then
      local helio = ephemeris.heliocentric(bodyId, centuries)
      local relative = eclipticToEquatorial({
        helio[1] - observerHelio[1],
        helio[2] - observerHelio[2],
        helio[3] - observerHelio[3]
      })
      local entry = observation(bodyId, definition, relative, sunRelative,
        length(helio), basisX, basisY, basisZ)
      if entry then result.planets[#result.planets + 1] = entry end
    end
  end
  table.sort(result.planets, function(a, b) return a.magnitude < b.magnitude end)

  if observerId == "earth" then
    local geocentric = eclipticToEquatorial(ephemeris.moonGeocentric(julianDay))
    local entry = observation("moon", {
      radius = 1737400.0, referenceMagnitude = 0.21, color = {0.94, 0.92, 0.88}, name = "Moon"
    }, geocentric, sunRelative, sunDistance, basisX, basisY, basisZ)
    -- The moon's own magnitude law, which the planetary fit does not cover.
    entry.magnitude = 0.21 + 5.0 * math.log10(
      (entry.distanceMeters / ephemeris.ASTRONOMICAL_UNIT_METERS) * sunDistance) +
      0.026 * (entry.phaseAngle / RADIANS) +
      4.0e-9 * (entry.phaseAngle / RADIANS) ^ 4
    result.moons[1] = entry
  end

  return result
end

-- Direction in the game's body frame: +X celestial north on the horizon, +Y up,
-- +Z east, observer on the equator. This is the convention the renderer's sun
-- already uses, so a body handed back here lands in the same sky as the sun.
function ephemeris.direction(rightAscension, declination, siderealTime)
  local hourAngle = siderealTime - rightAscension
  local cosDeclination = math.cos(declination)
  return {
    math.sin(declination),
    cosDeclination * math.cos(hourAngle),
    -cosDeclination * math.sin(hourAngle)
  }
end

-- The same conversion as a matrix, for the star field: it turns an ICRF unit
-- vector straight into a body-frame direction, folding in both the observer
-- planet's pole and the current sidereal time. Returned column-major, which is
-- what glUniformMatrix3fv wants.
function ephemeris.skyMatrix(observerId, siderealTime)
  local basisX, basisY, basisZ = ephemeris.equatorialBasis(observerId)
  local cosT, sinT = math.cos(siderealTime), math.sin(siderealTime)
  -- Row i of the body-frame result, as a combination of the equatorial basis.
  local rows = {
    basisZ,
    {
      cosT * basisX[1] + sinT * basisY[1],
      cosT * basisX[2] + sinT * basisY[2],
      cosT * basisX[3] + sinT * basisY[3]
    },
    {
      cosT * basisY[1] - sinT * basisX[1],
      cosT * basisY[2] - sinT * basisX[2],
      cosT * basisY[3] - sinT * basisX[3]
    }
  }
  return {
    rows[1][1], rows[2][1], rows[3][1],
    rows[1][2], rows[2][2], rows[3][2],
    rows[1][3], rows[2][3], rows[3][3]
  }
end

-- Days elapsed on the observer's own world, converted to the Earth days the
-- element tables are written in. A Martian sol is 2.7% longer than a day, so a
-- player who watches a hundred sols go by has seen a hundred and three days of
-- planetary motion.
function ephemeris.julianDayFor(dayNumber, dayLengthScale)
  return ephemeris.J2000_JULIAN_DAY + dayNumber * (dayLengthScale or 1.0)
end

return ephemeris
