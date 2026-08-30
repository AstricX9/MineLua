-- Deterministic, species-specific voxel tree silhouettes.
--
-- This is the world-block counterpart to the reference Three.js generator:
-- it builds a small voxel cloud first (so wood wins canopy overlaps), then
-- emits only the part that belongs to the chunk currently being decorated.

local VoxelTrees = {}

local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min
local pi, cos, sin, sqrt = math.pi, math.cos, math.sin, math.sqrt

local function round(value)
  return value < 0 and ceil(value - 0.5) or floor(value + 0.5)
end

local function clamp(value, low, high)
  return max(low, min(high, value))
end

local function lerp(a, b, amount)
  return a + (b - a) * amount
end

local function makeRng(seed)
  local state = floor(abs(tonumber(seed) or 1)) % 2147483647
  if state == 0 then state = 1 end
  return function()
    state = state * 48271 % 2147483647
    return state / 2147483647
  end
end

local function range(rng, low, high)
  return lerp(low, high, rng())
end

local function integer(rng, low, high)
  return floor(range(rng, low, high + 1))
end

local function chance(rng, probability)
  return rng() < probability
end

local function key(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function newCloud()
  return {wood = {}, leaves = {}, leaves2 = {}}
end

local function add(cloud, kind, x, y, z, axis)
  x, y, z = round(x), round(y), round(z)
  local voxelKey = key(x, y, z)
  if kind == "wood" then
    cloud.wood[voxelKey] = {x = x, y = y, z = z, axis = axis or "y"}
    cloud.leaves[voxelKey] = nil
    cloud.leaves2[voxelKey] = nil
  elseif not cloud.wood[voxelKey] then
    cloud[kind][voxelKey] = {x = x, y = y, z = z}
  end
end

local function sphere(cloud, kind, cx, cy, cz, rx, ry, rz, rng, noise, hollowChance)
  noise, hollowChance = noise or 0.15, hollowChance or 0
  for x = floor(cx - rx - 1), ceil(cx + rx + 1) do
    for y = floor(cy - ry - 1), ceil(cy + ry + 1) do
      for z = floor(cz - rz - 1), ceil(cz + rz + 1) do
        local dx = (x - cx) / max(0.001, rx)
        local dy = (y - cy) / max(0.001, ry)
        local dz = (z - cz) / max(0.001, rz)
        local boundary = 1 + range(rng, -noise, noise)
        if dx * dx + dy * dy + dz * dz <= boundary and not chance(rng, hollowChance) then
          add(cloud, kind, x, y, z)
        end
      end
    end
  end
end

local function disc(cloud, kind, cx, cy, cz, rx, rz, thickness, rng, noise)
  for y = cy, cy + thickness - 1 do
    sphere(cloud, kind, cx, y, cz, rx, 0.7, rz, rng, noise or 0.1, 0)
  end
end

local function line(cloud, kind, a, b, radius)
  radius = radius or 0
  local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
  local steps = max(1, ceil(max(abs(dx), abs(dy), abs(dz)) * 2))
  local axis = abs(dy) >= abs(dx) and abs(dy) >= abs(dz) and "y" or
    (abs(dx) >= abs(dz) and "x" or "z")
  local function stamp(x, y, z)
    for ox = -radius, radius do
      for oy = -radius, radius do
        for oz = -radius, radius do
          if ox * ox + oy * oy + oz * oz <= radius * radius + 0.25 then
            add(cloud, kind, x + ox, y + oy, z + oz, axis)
          end
        end
      end
    end
  end
  local previousX, previousY, previousZ
  for step = 0, steps do
    local amount = step / steps
    local x, y, z = round(lerp(a.x, b.x, amount)), round(lerp(a.y, b.y, amount)),
      round(lerp(a.z, b.z, amount))
    if previousX then
      -- Branches must remain face-connected for MineLua's whole-tree felling.
      -- Add a one-axis-at-a-time stair whenever voxel rounding would otherwise
      -- leave two consecutive samples touching only at an edge or corner.
      while previousX ~= x do
        previousX = previousX + (x > previousX and 1 or -1)
        stamp(previousX, previousY, previousZ)
      end
      while previousY ~= y do
        previousY = previousY + (y > previousY and 1 or -1)
        stamp(previousX, previousY, previousZ)
      end
      while previousZ ~= z do
        previousZ = previousZ + (z > previousZ and 1 or -1)
        stamp(previousX, previousY, previousZ)
      end
    else
      stamp(x, y, z)
    end
    previousX, previousY, previousZ = x, y, z
  end
end

local function trunk(cloud, rng, height, baseRadius, topRadius, wobble)
  local x, z, previousX, previousZ = 0, 0, 0, 0
  local centers = {}
  for y = 0, height do
    if y > 1 and chance(rng, wobble or 0.1) then
      x = clamp(x + integer(rng, -1, 1), -2, 2)
      z = clamp(z + integer(rng, -1, 1), -2, 2)
    end
    local radius = max(0, round(lerp(baseRadius, topRadius or 0, y / max(1, height))))
    line(cloud, "wood", {x = previousX, y = max(0, y - 1), z = previousZ},
      {x = x, y = y, z = z}, radius)
    centers[y] = {x = x, y = y, z = z}
    previousX, previousZ = x, z
  end
  return centers
end

local function horizontalDirection(rng, y)
  local angle = range(rng, 0, pi * 2)
  return {x = cos(angle), y = y or 0.25, z = sin(angle)}
end

local function branch(cloud, rng, start, length, direction, radius, droop, canopy)
  local endpoint = {
    x = start.x + round(direction.x * length),
    y = start.y + round(direction.y * length - (droop or 0)),
    z = start.z + round(direction.z * length)
  }
  line(cloud, "wood", start, endpoint, radius or 0)
  if canopy then
    sphere(cloud, canopy.kind or "leaves", endpoint.x, endpoint.y, endpoint.z,
      canopy.rx, canopy.ry, canopy.rz, rng, canopy.noise or 0.18,
      canopy.hollowChance or 0.03)
  end
  return endpoint
end

local function crown(cloud, rng, center, rx, ry, rz, density, kind)
  sphere(cloud, kind or "leaves", center.x, center.y, center.z, rx, ry, rz,
    rng, 0.2, 1 - (density or 0.97))
end

local function oak(cloud, rng, size)
  local height = round(11 * size)
  local centers = trunk(cloud, rng, height, max(1, round(1.2 * size)), 0, 0.12)
  for index = 1, integer(rng, 7, 11) do
    local y = integer(rng, round(height * 0.52), height - 1)
    local length = range(rng, 4.5, 8) * size
    local endpoint = branch(cloud, rng, centers[y], length,
      horizontalDirection(rng, range(rng, 0.05, 0.45)), chance(rng, 0.18) and 1 or 0, 0,
      {rx = range(rng, 2.6, 4.2) * size, ry = range(rng, 2.1, 3.2) * size,
       rz = range(rng, 2.6, 4.2) * size})
    if chance(rng, 0.55) then
      local start = {x = round(lerp(centers[y].x, endpoint.x, 0.55)),
        y = round(lerp(centers[y].y, endpoint.y, 0.55)),
        z = round(lerp(centers[y].z, endpoint.z, 0.55))}
      branch(cloud, rng, start, length * 0.45,
        horizontalDirection(rng, range(rng, 0.05, 0.35)), 0, 0,
        {rx = 2.2 * size, ry = 1.8 * size, rz = 2.2 * size})
    end
  end
  crown(cloud, rng, {x = 0, y = height + 1, z = 0},
    5.6 * size, 3.2 * size, 5.6 * size, 0.91)
end

local function spruce(cloud, rng, size)
  local height = round(range(rng, 18, 25) * size)
  trunk(cloud, rng, height, max(1, round(0.8 * size)), 0, 0.05)
  local baseY, top = round(height * 0.16), height + 2
  local stride = max(1, round(2 * size))
  for y = baseY, top - 1, stride do
    local radius = lerp(6.6, 1, (y - baseY) / max(1, top - baseY)) * size
    local layers = chance(rng, 0.45) and 2 or 1
    for layer = 0, layers - 1 do
      disc(cloud, layer == 1 and "leaves2" or "leaves", 0, y + layer, 0,
        radius * range(rng, 0.86, 1.05), radius, 1, rng, 0.18)
    end
  end
  sphere(cloud, "leaves", 0, height + 1, 0, 1.4 * size, 2.2 * size,
    1.4 * size, rng, 0.12, 0)
end

local function pine(cloud, rng, size)
  local height = round(range(rng, 17, 24) * size)
  local centers = trunk(cloud, rng, height, 1, 0, 0.04)
  local first = round(height * 0.38)
  local y = first
  while y < height - 1 do
    local count = integer(rng, 3, 6)
    local maximum = lerp(6.5, 2, (y - first) / max(1, height - first)) * size
    for index = 0, count - 1 do
      local angle = pi * 2 * index / count + range(rng, -0.25, 0.25)
      branch(cloud, rng, centers[y], range(rng, maximum * 0.65, maximum),
        {x = cos(angle), y = range(rng, -0.05, 0.22), z = sin(angle)}, 0,
        range(rng, 0, 0.8), {rx = 1.8 * size, ry = 1.1 * size,
          rz = 1.8 * size, noise = 0.2})
    end
    y = y + integer(rng, 2, 4)
  end
  crown(cloud, rng, {x = 0, y = height + 0.5, z = 0},
    2.5 * size, 3 * size, 2.5 * size, 0.92)
end

local function birch(cloud, rng, size)
  local count = chance(rng, 0.35) and 2 or 1
  for stem = 1, count do
    local ox = stem == 1 and 0 or integer(rng, -2, 2)
    local oz = stem == 1 and 0 or integer(rng, -2, 2)
    local height = round(range(rng, 13, 18) * size)
    if stem > 1 then
      line(cloud, "wood", {x = 0, y = 0, z = 0}, {x = ox, y = 0, z = oz}, 0)
    end
    line(cloud, "wood", {x = ox, y = 0, z = oz}, {x = ox, y = height, z = oz}, 0)
    for index = 1, integer(rng, 6, 9) do
      local y = integer(rng, round(height * 0.45), height - 1)
      branch(cloud, rng, {x = ox, y = y, z = oz}, range(rng, 3, 5.5) * size,
        horizontalDirection(rng, range(rng, 0.15, 0.6)), 0, 0,
        {rx = 1.9 * size, ry = 1.7 * size, rz = 1.9 * size, hollowChance = 0.06})
    end
    crown(cloud, rng, {x = ox, y = height + 0.5, z = oz},
      3.2 * size, 3.2 * size, 3.2 * size, 0.9)
  end
end

local function maple(cloud, rng, size)
  local height = round(12 * size)
  local centers = trunk(cloud, rng, height, max(1, round(1.2 * size)), 0, 0.12)
  for index = 1, integer(rng, 8, 12) do
    local y = integer(rng, round(height * 0.48), height)
    branch(cloud, rng, centers[y], range(rng, 4.5, 7.2) * size,
      horizontalDirection(rng, range(rng, 0.15, 0.5)), 0, 0,
      {kind = index % 3 == 0 and "leaves2" or "leaves",
       rx = 3.3 * size, ry = 2.5 * size, rz = 3.3 * size})
  end
  crown(cloud, rng, {x = 0, y = height + 2, z = 0},
    5.2 * size, 3.8 * size, 5.2 * size, 0.9)
end

local function acacia(cloud, rng, size)
  local height = round(range(rng, 9, 13) * size)
  local centers = trunk(cloud, rng, height, 1, 0, 0.18)
  for index = 1, integer(rng, 4, 7) do
    local start = centers[integer(rng, round(height * 0.62), height)]
    local endpoint = branch(cloud, rng, start, range(rng, 4.5, 7) * size,
      horizontalDirection(rng, range(rng, 0.2, 0.55)), 0, 0)
    disc(cloud, "leaves", endpoint.x, endpoint.y, endpoint.z,
      range(rng, 3, 4.8) * size, range(rng, 2.7, 4.4) * size,
      integer(rng, 2, 3), rng, 0.18)
  end
  disc(cloud, "leaves2", 0, height + 1, 0, 5 * size, 4.2 * size, 2, rng, 0.14)
end

local function ceiba(cloud, rng, size)
  local height = round(range(rng, 23, 31) * size)
  trunk(cloud, rng, height, max(2, round(2.2 * size)), 1, 0.03)
  local rootCount = integer(rng, 5, 8)
  for index = 0, rootCount - 1 do
    local angle = pi * 2 * index / rootCount + range(rng, -0.18, 0.18)
    local length = range(rng, 5, 9) * size
    local endpoint = {x = round(cos(angle) * length), y = 0, z = round(sin(angle) * length)}
    line(cloud, "wood", {x = 0, y = round(4 * size), z = 0}, endpoint,
      max(1, round(1.2 * size)))
  end
  local crownBase = round(height * 0.7)
  for index = 1, integer(rng, 8, 12) do
    local y = integer(rng, crownBase, height - 2)
    local length = range(rng, 7.5, 12.5) * size
    branch(cloud, rng, {x = 0, y = y, z = 0}, length,
      horizontalDirection(rng, range(rng, 0.15, 0.42)), chance(rng, 0.35) and 1 or 0, 0,
      {rx = range(rng, 3.4, 5.4) * size, ry = range(rng, 2.5, 4) * size,
       rz = range(rng, 3.4, 5.4) * size, hollowChance = 0.04})
  end
  crown(cloud, rng, {x = 0, y = height + 1, z = 0},
    8 * size, 4.2 * size, 8 * size, 0.87)
end

local function baobab(cloud, rng, size)
  local height = round(range(rng, 10, 15) * size)
  trunk(cloud, rng, height, max(2, round(3.3 * size)),
    max(1, round(1.4 * size)), 0.04)
  for index = 1, integer(rng, 6, 9) do
    local angle = pi * 2 * index / 8 + range(rng, -0.25, 0.25)
    branch(cloud, rng, {x = 0, y = round(height * 0.62), z = 0},
      range(rng, 4, 7) * size,
      {x = cos(angle), y = range(rng, 0.3, 0.75), z = sin(angle)}, 1, 0,
      {rx = 2.4 * size, ry = 1.8 * size, rz = 2.4 * size, hollowChance = 0.12})
  end
end

local function willow(cloud, rng, size)
  local height = round(range(rng, 10, 14) * size)
  local centers = trunk(cloud, rng, height, max(1, round(1.4 * size)), 0, 0.18)
  local endpoints = {}
  for index = 1, integer(rng, 8, 12) do
    local y = integer(rng, round(height * 0.48), height)
    endpoints[#endpoints + 1] = branch(cloud, rng, centers[y], range(rng, 4, 7) * size,
      horizontalDirection(rng, range(rng, 0.15, 0.55)), 0, 0,
      {rx = 2.6 * size, ry = 2.2 * size, rz = 2.6 * size})
  end
  for _, endpoint in ipairs(endpoints) do
    for strand = 1, integer(rng, 2, 5) do
      local x, z = endpoint.x + integer(rng, -2, 2), endpoint.z + integer(rng, -2, 2)
      line(cloud, "leaves2", {x = x, y = endpoint.y + 1, z = z},
        {x = x, y = max(2, endpoint.y - integer(rng, round(3 * size), round(7 * size))), z = z}, 0)
    end
  end
  crown(cloud, rng, {x = 0, y = height, z = 0},
    5.2 * size, 3.3 * size, 5.2 * size, 0.88)
end

local function cypress(cloud, rng, size)
  local height = round(range(rng, 17, 24) * size)
  trunk(cloud, rng, height, 1, 0, 0.03)
  for y = 2, height - 1 do
    local radius = (sin(pi * y / height) * 2.5 + 0.8) * size
    if y / height < 0.25 then radius = radius * 0.8 end
    sphere(cloud, y % 3 == 0 and "leaves2" or "leaves", 0, y, 0,
      radius, 1.2 * size, radius, rng, 0.13, 0.05)
  end
end

local function jungle(cloud, rng, size)
  local height = round(range(rng, 18, 26) * size)
  local centers = trunk(cloud, rng, height, max(1, round(1.5 * size)), 0, 0.12)
  for index = 1, integer(rng, 9, 14) do
    local y = integer(rng, round(height * 0.6), height)
    branch(cloud, rng, centers[y], range(rng, 5, 9) * size,
      horizontalDirection(rng, range(rng, 0.1, 0.45)), chance(rng, 0.25) and 1 or 0, 0,
      {rx = range(rng, 2.8, 4.5) * size, ry = range(rng, 2.3, 3.7) * size,
       rz = range(rng, 2.8, 4.5) * size})
  end
  crown(cloud, rng, {x = 0, y = height + 1, z = 0},
    6.2 * size, 4.2 * size, 6.2 * size, 0.88)
  for vine = 1, integer(rng, 2, 5) do
    local angle, radius = range(rng, 0, pi * 2), range(rng, 2, 5) * size
    local x, z = round(cos(angle) * radius), round(sin(angle) * radius)
    line(cloud, "leaves2", {x = x, y = integer(rng, round(height * 0.7), height), z = z},
      {x = x, y = integer(rng, 1, round(height * 0.35)), z = z}, 0)
  end
end

local function mangrove(cloud, rng, size)
  local height = round(range(rng, 8, 12) * size)
  local centers = trunk(cloud, rng, height, 1, 0, 0.14)
  for root = 1, integer(rng, 6, 10) do
    local angle, length = range(rng, 0, pi * 2), range(rng, 3, 5) * size
    line(cloud, "wood", {x = 0, y = integer(rng, 2, max(3, round(height * 0.35))), z = 0},
      {x = round(cos(angle) * length), y = 0, z = round(sin(angle) * length)}, 0)
  end
  for index = 1, integer(rng, 7, 10) do
    local y = integer(rng, round(height * 0.45), height)
    branch(cloud, rng, centers[y], range(rng, 3.5, 6) * size,
      horizontalDirection(rng, range(rng, 0.08, 0.38)), 0, 0,
      {rx = 2.5 * size, ry = 2 * size, rz = 2.5 * size})
  end
  crown(cloud, rng, {x = 0, y = height + 1, z = 0},
    4.4 * size, 3 * size, 4.4 * size, 0.9)
end

local generators = {
  oak = oak, forest = oak, big = oak,
  spruce = spruce, taiga1 = spruce,
  pine = pine, taiga2 = pine,
  birch = birch, maple = maple, acacia = acacia, ceiba = ceiba,
  baobab = baobab, willow = willow, cypress = cypress,
  jungle = jungle, fig = jungle, mangrove = mangrove
}

VoxelTrees.species = {
  "oak", "spruce", "pine", "birch", "maple", "acacia", "ceiba",
  "baobab", "willow", "cypress", "jungle", "mangrove"
}

function VoxelTrees.generate(species, seed, size)
  local generator = generators[species] or oak
  local cloud, rng = newCloud(), makeRng(seed)
  generator(cloud, rng, size or (species == "big" and 1.2 or 1))
  return cloud
end

function VoxelTrees.emit(cloud, originX, originY, originZ, material, place)
  for _, voxel in pairs(cloud.leaves) do
    place(originX + voxel.x, originY + voxel.y, originZ + voxel.z, material.leaves)
  end
  for _, voxel in pairs(cloud.leaves2) do
    place(originX + voxel.x, originY + voxel.y, originZ + voxel.z,
      material.leaves2 or material.leaves)
  end
  for _, voxel in pairs(cloud.wood) do
    local id = voxel.axis == "x" and material.woodX or
      (voxel.axis == "z" and material.woodZ or material.wood)
    place(originX + voxel.x, originY + voxel.y, originZ + voxel.z, id or material.wood)
  end
end

return VoxelTrees
