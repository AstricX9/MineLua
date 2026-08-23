-- Voxel addressing for a spherical planet.
--
-- A voxel is named by (face, column, row, layer). The first three pick a column
-- of the cube-sphere -- a direction out from the planet centre -- and the layer
-- picks how far along it. Every voxel is a perfect undeformed cube, positioned
-- on its column and rotated so its local up is that direction. Nothing is
-- stretched, tapered or curved.
--
-- Why a cube-sphere: a sphere admits no regular 2D grid. Latitude/longitude
-- collapses to zero column width at the poles. Six warped square grids cost a
-- few percent of spacing variation and eight corner points of valence three,
-- which is the mildest defect available.
--
-- Spacing and gaps
-- ----------------
-- Columns are spaced so that at referenceRadius the top faces of neighbouring
-- cubes meet exactly, which makes the surface seamless. Away from that radius
-- the columns fan, so cubes overlap below it and separate above it, by
-- offset/radius per metre. On Earth that is 1.57e-7 per metre: 157 nm at the
-- base of a surface cube, 157 um after digging a kilometre, 1 cm after 64 km.
-- Overlaps are invisible between opaque cubes; the resolution is deliberately
-- chosen from the *widest* part of a face so the error is always overlap and
-- never gap.

local SphericalGrid = {}
SphericalGrid.__index = SphericalGrid

local QUARTER_PI = math.pi * 0.25
local sqrt, tan, atan, abs = math.sqrt, math.tan, math.atan, math.abs
local floor, max, min = math.floor, math.max, math.min

-- Face frames. `forward` is the face normal, `right` spans the column axis and
-- `up` the row axis. Only consistency between direction() and locate() matters,
-- so these are the plainest set that covers all six.
local FACES = {
  {name = "+X", forward = {1, 0, 0}, right = {0, 1, 0}, up = {0, 0, 1}},
  {name = "-X", forward = {-1, 0, 0}, right = {0, -1, 0}, up = {0, 0, 1}},
  {name = "+Y", forward = {0, 1, 0}, right = {0, 0, 1}, up = {1, 0, 0}},
  {name = "-Y", forward = {0, -1, 0}, right = {0, 0, -1}, up = {1, 0, 0}},
  {name = "+Z", forward = {0, 0, 1}, right = {1, 0, 0}, up = {0, 1, 0}},
  {name = "-Z", forward = {0, 0, -1}, right = {-1, 0, 0}, up = {0, 1, 0}}
}

SphericalGrid.FACES = FACES
SphericalGrid.FACE_COUNT = #FACES

local function normalize(x, y, z)
  local length = sqrt(x * x + y * y + z * z)
  return x / length, y / length, z / length
end

-- Unit direction for a point on a face, with s and t in [-1, 1].
--
-- The tangent warp is what keeps the grid usable: without it the arc covered by
-- one grid step varies by 2.12x between the centre of a face and its corner.
-- With it that falls to about 1.06x.
function SphericalGrid.faceDirection(face, s, t)
  local frame = FACES[face]
  local u, v = tan(s * QUARTER_PI), tan(t * QUARTER_PI)
  local forward, right, up = frame.forward, frame.right, frame.up
  return normalize(
    forward[1] + right[1] * u + up[1] * v,
    forward[2] + right[2] * u + up[2] * v,
    forward[3] + right[3] * u + up[3] * v)
end

-- Inverse: which face a direction belongs to, and where on it.
function SphericalGrid.locateDirection(dx, dy, dz)
  local ax, ay, az = abs(dx), abs(dy), abs(dz)
  local face
  if ax >= ay and ax >= az then
    face = dx >= 0 and 1 or 2
  elseif ay >= az then
    face = dy >= 0 and 3 or 4
  else
    face = dz >= 0 and 5 or 6
  end
  local frame = FACES[face]
  local forward, right, up = frame.forward, frame.right, frame.up
  local depth = dx * forward[1] + dy * forward[2] + dz * forward[3]
  local u = (dx * right[1] + dy * right[2] + dz * right[3]) / depth
  local v = (dx * up[1] + dy * up[2] + dz * up[3]) / depth
  return face, atan(u) / QUARTER_PI, atan(v) / QUARTER_PI
end

-- Widest grid step on a face, per unit of s, in units of radius. The corner is
-- the narrowest point and the centre the widest, so the centre sets the
-- resolution: size for the widest and every other column overlaps slightly
-- rather than leaving a gap.
local function widestStepPerUnitS()
  -- d/ds of normalize(forward + right*tan(s*pi/4)) at s = 0 is pi/4.
  return QUARTER_PI
end

function SphericalGrid.new(options)
  options = options or {}
  local radius = tonumber(options.radiusMeters) or 6371000.0
  local voxelSize = tonumber(options.voxelSizeMeters) or 1.0
  assert(radius > 0.0 and voxelSize > 0.0, "planet radius and voxel size must be positive")
  -- Cubes meet exactly at this radius. Sea level is the natural choice: it puts
  -- the seamless band where the ground is.
  local referenceRadius = radius + (tonumber(options.referenceOffsetMeters) or 0.0)

  -- Columns across one face edge. Two units of s span a face, so the widest
  -- step is 2 * (pi/4) * referenceRadius / resolution; solving that for one
  -- voxel and rounding up guarantees no step is wider than a voxel.
  local exact = 2.0 * widestStepPerUnitS() * referenceRadius / voxelSize
  local alignment = max(1, floor(tonumber(options.resolutionAlignment) or 16))
  local resolution = math.ceil(exact / alignment) * alignment

  local self = setmetatable({
    radiusMeters = radius,
    voxelSizeMeters = voxelSize,
    referenceRadius = referenceRadius,
    resolution = resolution,
    -- Pivot at the top face, so the seam-free band sits at the top of the
    -- surface cube and every divergence is buried. Set "center" to rotate about
    -- the cube centre instead, which matters only on very small planets.
    pivot = options.pivot == "center" and "center" or "top"
  }, SphericalGrid)
  return self
end

-- Grid coordinate of a column centre, in s/t space.
function SphericalGrid:columnParameter(index)
  return (2.0 * index + 1.0) / self.resolution - 1.0
end

function SphericalGrid:columnDirection(face, column, row)
  return SphericalGrid.faceDirection(face,
    self:columnParameter(column), self:columnParameter(row))
end

-- Which column contains a direction. Rows and columns are clamped rather than
-- wrapped: a direction always lands on exactly one face.
function SphericalGrid:locate(dx, dy, dz)
  local face, s, t = SphericalGrid.locateDirection(dx, dy, dz)
  local resolution = self.resolution
  local column = min(resolution - 1, max(0, floor((s + 1.0) * 0.5 * resolution)))
  local row = min(resolution - 1, max(0, floor((t + 1.0) * 0.5 * resolution)))
  return face, column, row
end

-- Radius of the *top* face of a layer. Layer 0 sits directly under the
-- reference radius, so its top face is the seam-free band.
function SphericalGrid:layerTopRadius(layer)
  return self.referenceRadius + layer * self.voxelSizeMeters
end

function SphericalGrid:layerCenterRadius(layer)
  local offset = self.pivot == "top" and 0.5 or 0.0
  return self.referenceRadius + (layer - offset) * self.voxelSizeMeters
end

-- Centre of a voxel, in planet-centred metres.
function SphericalGrid:voxelCenter(face, column, row, layer, center)
  local dx, dy, dz = self:columnDirection(face, column, row)
  local radius = self:layerCenterRadius(layer)
  center = center or {0.0, 0.0, 0.0}
  return center[1] + dx * radius, center[2] + dy * radius, center[3] + dz * radius
end

-- Orientation of a voxel: its local up is the column direction, and the other
-- two axes follow the face frame so neighbouring cubes agree on which way their
-- textures run.
function SphericalGrid:voxelFrame(face, column, row)
  local ux, uy, uz = self:columnDirection(face, column, row)
  local frame = FACES[face]
  local reference = frame.up
  -- Project the face row axis onto the tangent plane for a stable right vector.
  local dot = reference[1] * ux + reference[2] * uy + reference[3] * uz
  local fx, fy, fz = normalize(
    reference[1] - ux * dot, reference[2] - uy * dot, reference[3] - uz * dot)
  local rx, ry, rz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
  return ux, uy, uz, rx, ry, rz, fx, fy, fz
end

-- Neighbouring column, including across a face edge.
--
-- Rather than hand-coding the twenty-four edge transitions and their rotations,
-- this steps one column along the tangent and asks which column that lands in.
-- Face seams then cost nothing to maintain and cannot be got subtly wrong; the
-- step is about 1.6e-7 radians against directions of order one, which doubles
-- resolve with a great deal of room to spare.
function SphericalGrid:neighbour(face, column, row, columnStep, rowStep)
  local nextColumn, nextRow = column + columnStep, row + rowStep
  local resolution = self.resolution
  if nextColumn >= 0 and nextColumn < resolution and nextRow >= 0 and nextRow < resolution then
    -- Inside the face this is pure indexing, with no geometry to get wrong.
    return face, nextColumn, nextRow
  end
  -- Off the edge. columnParameter is happy just past +-1, so take the direction
  -- of the cell that would be there and ask which face really owns it: the
  -- change of face and its rotation both fall out of that.
  local dx, dy, dz = SphericalGrid.faceDirection(face,
    self:columnParameter(nextColumn), self:columnParameter(nextRow))
  return self:locate(dx, dy, dz)
end

-- Angle between the two grid directions at a column, in radians.
--
-- A cube-sphere grid is only square along the centre lines of a face. Towards
-- a corner the cells shear into rhombi, bottoming out near sixty degrees at
-- the eight corners where three faces meet. A cube is orthonormal by
-- definition, so near those corners its side faces cannot point squarely at
-- its grid neighbours. This is what that costs, measured rather than assumed.
function SphericalGrid:gridSkew(face, column, row)
  local s, t = self:columnParameter(column), self:columnParameter(row)
  local delta = 1.0 / self.resolution
  local ax, ay, az = SphericalGrid.faceDirection(face, s, t)
  local bx, by, bz = SphericalGrid.faceDirection(face, s + delta, t)
  local cx, cy, cz = SphericalGrid.faceDirection(face, s, t + delta)
  local sx, sy, sz = normalize(bx - ax, by - ay, bz - az)
  local tx, ty, tz = normalize(cx - ax, cy - ay, cz - az)
  return math.acos(max(-1.0, min(1.0, sx * tx + sy * ty + sz * tz)))
end

-- Arc between the centres of two adjacent columns, in metres at the reference
-- radius. Equals the voxel size where the grid is widest and a little less
-- elsewhere, so cubes overlap rather than separate.
function SphericalGrid:columnSpacing(face, column, row)
  local ax, ay, az = self:columnDirection(face, column, row)
  local nf, nc, nr = self:neighbour(face, column, row, 1, 0)
  local bx, by, bz = self:columnDirection(nf, nc, nr)
  local dx, dy, dz = bx - ax, by - ay, bz - az
  return sqrt(dx * dx + dy * dy + dz * dz) * self.referenceRadius
end

-- Total columns on the planet, for sanity checking a configuration.
function SphericalGrid:columnCount()
  return SphericalGrid.FACE_COUNT * self.resolution * self.resolution
end

return SphericalGrid
