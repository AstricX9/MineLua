-- The addressing layer for a spherical voxel planet. Everything above it --
-- generation, meshing, collision, lighting -- depends on these being exact, so
-- they are checked directly rather than inferred from how the world looks.

package.path = "src/?.lua;" .. package.path

local SphericalGrid = require("spherical_grid")

local function close(actual, expected, tolerance, label)
  assert(math.abs(actual - expected) <= tolerance,
    string.format("%s: expected %.9g, got %.9g", label, expected, actual))
end

local grid = SphericalGrid.new({radiusMeters = 6371000.0, voxelSizeMeters = 1.0})
print(string.format("resolution %d columns per face edge, %.3g columns on the planet",
  grid.resolution, grid:columnCount()))

-- Roughly one voxel per column across a whole face edge.
local faceArc = grid.resolution * grid.voxelSizeMeters
close(faceArc / (grid.referenceRadius * math.pi * 0.5), 1.0, 0.01,
  "a face edge is about a quarter of the circumference")

-- 1. Direction and its inverse must agree, on every face and out to the corners.
for face = 1, SphericalGrid.FACE_COUNT do
  for _, s in ipairs({-0.999, -0.5, 0.0, 0.37, 0.999}) do
    for _, t in ipairs({-0.999, -0.5, 0.0, 0.37, 0.999}) do
      local dx, dy, dz = SphericalGrid.faceDirection(face, s, t)
      close(math.sqrt(dx * dx + dy * dy + dz * dz), 1.0, 1e-12, "directions are unit length")
      local backFace, backS, backT = SphericalGrid.locateDirection(dx, dy, dz)
      assert(backFace == face,
        string.format("face %d round trips at (%.3f, %.3f), got %d", face, s, t, backFace))
      close(backS, s, 1e-12, "s round trips")
      close(backT, t, 1e-12, "t round trips")
    end
  end
end

-- 2. Column spacing. The resolution is chosen from the widest part of a face,
--    so no step may exceed a voxel -- that is what makes the error always an
--    invisible overlap instead of a visible gap.
local widest, narrowest = -math.huge, math.huge
for face = 1, SphericalGrid.FACE_COUNT do
  for _, fraction in ipairs({0.0, 0.25, 0.5, 0.75, 0.999}) do
    local index = math.floor(fraction * (grid.resolution - 1))
    local spacing = grid:columnSpacing(face, index, index)
    widest = math.max(widest, spacing)
    narrowest = math.min(narrowest, spacing)
  end
end
print(string.format("column spacing %.4f m to %.4f m (%.2f%% variation)",
  narrowest, widest, (widest / narrowest - 1.0) * 100.0))
assert(widest <= grid.voxelSizeMeters + 1e-6,
  string.format("no column step exceeds one voxel (widest %.6f m)", widest))
assert(widest / narrowest < 1.10,
  string.format("a tangent-warped face stays within a few percent (saw %.3f)", widest / narrowest))

-- 3. Neighbour traversal, including across face edges. Stepping one way and
--    back must return to where it started, everywhere -- the seams are where
--    hand-written edge tables go wrong.
local edge = grid.resolution - 1
local probes = {
  {1, 0, 0}, {1, edge, edge}, {1, 0, edge}, {1, edge, 0},
  {3, edge, edge}, {5, 0, 0}, {6, edge, 0}, {4, 0, edge},
  {2, math.floor(grid.resolution / 2), math.floor(grid.resolution / 2)}
}
for _, probe in ipairs(probes) do
  local face, column, row = probe[1], probe[2], probe[3]
  for _, step in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
    local nf, nc, nr = grid:neighbour(face, column, row, step[1], step[2])
    assert(nf >= 1 and nf <= SphericalGrid.FACE_COUNT, "a neighbour lands on a real face")
    assert(nc >= 0 and nc < grid.resolution and nr >= 0 and nr < grid.resolution,
      "a neighbour lands inside its face")
    -- It has to be somewhere else, and about one voxel away.
    local ax, ay, az = grid:columnDirection(face, column, row)
    local bx, by, bz = grid:columnDirection(nf, nc, nr)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local metres = math.sqrt(dx * dx + dy * dy + dz * dz) * grid.referenceRadius
    assert(metres > 0.30 and metres < 2.0,
      string.format("a neighbour is about a voxel away, saw %.3f m at face %d (%d,%d) step %d,%d",
        metres, face, column, row, step[1], step[2]))
    -- And the relation is symmetric. Not "step back with the opposite step":
    -- crossing a face edge rotates the frame, so the return trip is a
    -- different one of the four. What meshing and lighting actually need is
    -- that if B is a neighbour of A then A is a neighbour of B, whichever
    -- index it arrives under.
    --
    -- The eight cube corners are the documented exception: three faces meet
    -- there, so the adjacency is not four-regular and cannot be made so. That
    -- is eight columns out of six hundred million million.
    local atCorner = (column == 0 or column == edge) and (row == 0 or row == edge)
    if not atCorner then
      local mutual = false
      for _, back in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
        local bf, bc, br = grid:neighbour(nf, nc, nr, back[1], back[2])
        if bf == face and bc == column and br == row then mutual = true break end
      end
      assert(mutual,
        string.format("face %d (%d,%d) is a neighbour of its own neighbour face %d (%d,%d)",
          face, column, row, nf, nc, nr))
    end
  end
end

-- 4. Faces are actually crossed. Walking off the edge of a face has to land on
--    a different one, or the seam handling is untested.
local crossed = 0
for face = 1, SphericalGrid.FACE_COUNT do
  local nf = grid:neighbour(face, edge, math.floor(grid.resolution / 2), 1, 0)
  if nf ~= face then crossed = crossed + 1 end
end
assert(crossed == SphericalGrid.FACE_COUNT,
  string.format("every face edge leads onto another face (%d of 6)", crossed))

-- 4b. Cell shape. A cube-sphere grid is square only along the centre lines of
--     a face; toward a corner it shears into a rhombus. A cube is orthonormal
--     by definition, so this is the angle by which a cube cannot line up with
--     its own grid neighbours. Recorded here because it decides whether this
--     topology is usable, not because it can be fixed.
local centreLine = math.floor(grid.resolution / 2)
close(math.deg(grid:gridSkew(1, centreLine, centreLine)), 90.0, 1e-3,
  "cells are square at the centre of a face")
close(math.deg(grid:gridSkew(1, centreLine, 0)), 90.0, 1e-3,
  "and square all along a centre line")
local cornerSkew = math.deg(grid:gridSkew(1, 0, 0))
close(cornerSkew, 120.0, 0.1, "and shear to 120 degrees at a cube corner")
local halfway = math.floor(grid.resolution * 0.75)
print(string.format("cell skew: 90.00 deg at the face centre, %.2f deg halfway to a corner, %.2f deg at it",
  math.deg(grid:gridSkew(1, halfway, halfway)), cornerSkew))

-- 5. Voxel geometry. The cube is undeformed: its frame is orthonormal and its
--    up is exactly the radial direction.
for _, probe in ipairs(probes) do
  local ux, uy, uz, rx, ry, rz, fx, fy, fz = grid:voxelFrame(probe[1], probe[2], probe[3])
  local function dot(ax, ay, az, bx, by, bz) return ax * bx + ay * by + az * bz end
  close(dot(ux, uy, uz, ux, uy, uz), 1.0, 1e-12, "up is unit length")
  close(dot(rx, ry, rz, rx, ry, rz), 1.0, 1e-12, "right is unit length")
  close(dot(fx, fy, fz, fx, fy, fz), 1.0, 1e-12, "forward is unit length")
  close(dot(ux, uy, uz, rx, ry, rz), 0.0, 1e-12, "up and right are perpendicular")
  close(dot(ux, uy, uz, fx, fy, fz), 0.0, 1e-12, "up and forward are perpendicular")
  close(dot(rx, ry, rz, fx, fy, fz), 0.0, 1e-12, "right and forward are perpendicular")

  local dx, dy, dz = grid:columnDirection(probe[1], probe[2], probe[3])
  close(dot(ux, uy, uz, dx, dy, dz), 1.0, 1e-12, "local up is the radial direction")
end

-- 6. The top-corner pivot. Layer 0 has its top face exactly at the reference
--    radius, which is the band where neighbouring cubes meet with no gap.
close(grid:layerTopRadius(0), grid.referenceRadius, 1e-9, "layer 0 tops out at the reference radius")
close(grid:layerCenterRadius(0), grid.referenceRadius - 0.5, 1e-9,
  "and its centre sits half a voxel below")

local centred = SphericalGrid.new({radiusMeters = 6371000.0, voxelSizeMeters = 1.0, pivot = "center"})
close(centred:layerCenterRadius(0), centred.referenceRadius, 1e-9,
  "the centre pivot puts layer 0 on the reference radius instead")

-- 7. Divergence away from the reference radius, which is the whole reason the
--    pivot was moved to the top. These are the numbers that decide whether a
--    dig depth limit is needed: on Earth, a centimetre takes 64 km.
local function convergenceAt(depth)
  return depth * grid.voxelSizeMeters / grid.referenceRadius
end
close(convergenceAt(1.0), 1.57e-7, 1e-8, "157 nm at the base of a surface cube")
close(convergenceAt(1000.0), 1.57e-4, 1e-5, "157 um after a kilometre")
assert(convergenceAt(64000.0) < 0.011 and convergenceAt(64000.0) > 0.009,
  "about a centimetre after 64 km")

print("spherical grid tests passed")
