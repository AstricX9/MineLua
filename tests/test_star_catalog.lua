-- The catalogue is hand-entered real data, and the failure mode of hand-entered
-- data is a digit, not a concept. A wrong digit does not look wrong in a list;
-- it looks wrong in the sky, as a constellation that has come apart. So the
-- test checks the shapes: the separations and alignments that only hold if the
-- coordinates are right.

package.path = "src/?.lua;" .. package.path

local catalog = require("star_catalog")
local atmosphere = require("atmosphere")
local earth = require("world_profiles").get("earth")

local DEGREES = 180.0 / math.pi

local byName = {}
for index, star in ipairs(catalog.stars) do
  assert(not byName[star[1]], "duplicate star name: " .. star[1])
  byName[star[1]] = {index = index, ra = star[2], dec = star[3], magnitude = star[4], color = star[5]}
end

local function vector(name)
  local star = byName[name]
  assert(star, "missing star: " .. name)
  local x, y, z = catalog.unitVector(star.ra, star.dec)
  return {x, y, z}
end

local function separation(a, b)
  local u, v = vector(a), vector(b)
  local d = u[1] * v[1] + u[2] * v[2] + u[3] * v[3]
  return math.acos(math.max(-1.0, math.min(1.0, d))) * DEGREES
end

local function close(actual, expected, tolerance, label)
  assert(math.abs(actual - expected) <= tolerance,
    string.format("%s: expected %.2f deg, got %.2f deg", label, expected, actual))
end

-- Every row has to be a plausible star before any shape can be checked.
for _, star in ipairs(catalog.stars) do
  local name, ra, dec, magnitude, colorIndex = star[1], star[2], star[3], star[4], star[5]
  assert(type(name) == "string" and #name > 0, "star needs a name")
  assert(ra >= 0.0 and ra < 24.0, name .. ": right ascension out of range")
  assert(dec >= -90.0 and dec <= 90.0, name .. ": declination out of range")
  assert(magnitude >= -2.0 and magnitude <= 5.0, name .. ": implausible magnitude")
  assert(colorIndex >= -0.4 and colorIndex <= 2.0, name .. ": implausible colour index")
end

-- Two stars closer together than an arcminute are one star entered twice.
for i = 1, #catalog.stars do
  for j = i + 1, #catalog.stars do
    local gap = separation(catalog.stars[i][1], catalog.stars[j][1])
    assert(gap > 0.0167, string.format("%s and %s are the same point",
      catalog.stars[i][1], catalog.stars[j][1]))
  end
end

-- Orion's Belt: three stars 1.35 degrees apart in an almost straight line. The
-- alignment is the strong check -- a wrong digit in any one of the six numbers
-- bends it well past a degree.
close(separation("Mintaka", "Alnilam"), 1.36, 0.10, "Mintaka to Alnilam")
close(separation("Alnilam", "Alnitak"), 1.34, 0.10, "Alnilam to Alnitak")
close(separation("Mintaka", "Alnitak"), 2.70, 0.15, "Mintaka to Alnitak")
assert(separation("Mintaka", "Alnilam") + separation("Alnilam", "Alnitak") -
  separation("Mintaka", "Alnitak") < 0.06, "Orion's Belt is not straight")

-- The rest of Orion around it.
close(separation("Betelgeuse", "Rigel"), 18.55, 0.6, "Betelgeuse to Rigel")
close(separation("Betelgeuse", "Bellatrix"), 7.44, 0.4, "Betelgeuse to Bellatrix")
close(separation("Rigel", "Saiph"), 8.60, 0.4, "Rigel to Saiph")

-- The Plough, end to end, and the pointers that find Polaris: the great circle
-- through Merak and Dubhe passes within a few degrees of the pole star.
close(separation("Dubhe", "Merak"), 5.37, 0.15, "Dubhe to Merak")
close(separation("Merak", "Phecda"), 7.95, 0.30, "Merak to Phecda")
close(separation("Mizar", "Alkaid"), 6.71, 0.30, "Mizar to Alkaid")
close(separation("Alioth", "Mizar"), 4.36, 0.20, "Alioth to Mizar")
close(separation("Dubhe", "Polaris"), 28.60, 0.6, "Dubhe to Polaris")
do
  -- Polaris' distance from the great circle the two pointers define, which is
  -- what "the pointers point at it" actually means.
  local merak, dubhe, polaris = vector("Merak"), vector("Dubhe"), vector("Polaris")
  local normal = {
    merak[2] * dubhe[3] - merak[3] * dubhe[2],
    merak[3] * dubhe[1] - merak[1] * dubhe[3],
    merak[1] * dubhe[2] - merak[2] * dubhe[1]
  }
  local scale = math.sqrt(normal[1] ^ 2 + normal[2] ^ 2 + normal[3] ^ 2)
  local offCircle = math.abs(math.asin(math.max(-1.0, math.min(1.0,
    (normal[1] * polaris[1] + normal[2] * polaris[2] + normal[3] * polaris[3]) / scale))) * DEGREES)
  assert(offCircle < 3.0,
    string.format("the pointers miss Polaris by %.1f deg", offCircle))
  -- ...and on the Dubhe side of Merak, not behind it.
  assert(separation("Merak", "Polaris") > separation("Dubhe", "Polaris"),
    "the pointers point away from Polaris")
end

-- Cassiopeia's W: five stars, each within eight degrees of the next.
local cassiopeia = {"Caph", "Schedar", "Cih", "Ruchbah", "Segin"}
for index = 1, #cassiopeia - 1 do
  local gap = separation(cassiopeia[index], cassiopeia[index + 1])
  assert(gap > 3.0 and gap < 8.5, string.format("Cassiopeia broken at %s to %s: %.2f deg",
    cassiopeia[index], cassiopeia[index + 1], gap))
end

-- The Southern Cross, and the pair that points at it.
close(separation("Acrux", "Gacrux"), 5.99, 0.25, "Acrux to Gacrux")
close(separation("Mimosa", "Delta Crucis"), 4.24, 0.25, "Mimosa to Delta Crucis")
close(separation("Rigil Kentaurus", "Hadar"), 4.40, 0.20, "Alpha to Beta Centauri")

-- The Pleiades are a cluster, so every member sits within about a degree of
-- Alcyone. This is the check that catches a transposed digit hardest.
for _, member in ipairs({"Atlas", "Electra", "Maia", "Merope", "Taygeta"}) do
  local gap = separation("Alcyone", member)
  assert(gap < 1.30, string.format("%s is %.2f deg from Alcyone, too far for the Pleiades",
    member, gap))
end

-- Summer Triangle and Winter Triangle: the two shapes that carry their seasons.
close(separation("Vega", "Altair"), 34.19, 0.8, "Vega to Altair")
close(separation("Vega", "Deneb"), 23.85, 0.8, "Vega to Deneb")
close(separation("Deneb", "Altair"), 38.01, 0.8, "Deneb to Altair")
close(separation("Sirius", "Procyon"), 25.71, 0.8, "Sirius to Procyon")
close(separation("Sirius", "Betelgeuse"), 27.11, 0.8, "Sirius to Betelgeuse")

-- Polaris is within a degree of the pole, which is the only reason it is
-- useful, and the catalogue has to say so.
assert(90.0 - byName["Polaris"].dec < 1.0, "Polaris is not at the pole")

-- The brightest star in the sky, and the only one brighter than magnitude -1.
local brightest, brightestName = 99.0, nil
for _, star in ipairs(catalog.stars) do
  if star[4] < brightest then brightest, brightestName = star[4], star[1] end
end
assert(brightestName == "Sirius", "Sirius should be the brightest star, got " .. tostring(brightestName))

local moonBelow=atmosphere.forSun({0,-1,0},48,360,nil,earth,{
  moons={{direction={0,-1,0},illuminatedFraction=1}}
})
local moonAbove=atmosphere.forSun({0,-1,0},48,360,nil,earth,{
  moons={{direction={0,1,0},illuminatedFraction=1}}
})
assert(moonBelow.moonAmount==0 and moonAbove.moonAmount>0.99 and
    moonAbove.fogColor[3]>moonBelow.fogColor[3],
  "Earth night lighting follows the real moon's altitude instead of assuming it is always up")

-- The galactic centre is in Sagittarius, a few degrees from the spout of the
-- Teapot -- which is what puts the Milky Way's bulge where people expect it.
do
  local centre = catalog.galacticCentre
  local x = math.cos(centre.declination) * math.cos(centre.rightAscension)
  local y = math.cos(centre.declination) * math.sin(centre.rightAscension)
  local z = math.sin(centre.declination)
  local nunki = vector("Kaus Australis")
  local gap = math.acos(math.max(-1.0, math.min(1.0,
    x * nunki[1] + y * nunki[2] + z * nunki[3]))) * DEGREES
  assert(gap < 12.0, string.format("the galactic centre is %.1f deg from Sagittarius", gap))

  -- The galactic pole must be perpendicular to the centre.
  local pole = catalog.galacticPole
  local px = math.cos(pole.declination) * math.cos(pole.rightAscension)
  local py = math.cos(pole.declination) * math.sin(pole.rightAscension)
  local pz = math.sin(pole.declination)
  local perpendicular = math.abs(px * x + py * y + pz * z)
  assert(perpendicular < 0.02,
    string.format("galactic pole is not perpendicular to the centre (cos = %.4f)", perpendicular))
end

print(string.format("star catalogue tests passed (%d stars)", #catalog.stars))
