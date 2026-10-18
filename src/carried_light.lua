-- Occlusion for the light the player is carrying.
--
-- A held torch is not a placed block: it moves every frame, so it cannot be
-- written into the chunk light grid without remeshing everything around the
-- player several times a second. The terrain shader therefore lit it
-- analytically, from distance alone -- which meant the light passed straight
-- through walls. Sealing yourself into a room lit the terrain outside it, and
-- standing beside a wall lit whatever was on the other side.
--
-- This module keeps a small voxel volume centred on the player that records how
-- far light can actually travel from the hand, flood-filled through the world
-- the same way placed block light propagates. The shader multiplies the carried
-- light by it, so a wall stops it.
--
-- The fill only runs when it can change: when the player crosses into a new
-- voxel, when a block is edited, or when an emitter is first taken in hand.

local ffi = require("ffi")
local GL = require("gl")
local lighting = require("lighting")

local gl = GL.gl

local GL_R8 = 0x8229

local carriedLight = {}

-- 15 is the maximum authored emission, so nothing outside this radius can be
-- lit. One extra cell each way keeps the linear filter from clamping a lit
-- edge outward across the volume boundary.
local RADIUS = 15
local SIZE = 32
local PLANE = SIZE * SIZE
local COUNT = SIZE * SIZE * SIZE

-- reach = 15 minus the shortest lit path from the hand, so a value of 15 is the
-- player's own cell and 0 is unreachable. The shader turns it back into a light
-- level with `emission - (15 - reach)`, which is exactly the falloff a placed
-- block of the same emission would produce.
local reach = ffi.new("uint8_t[?]", COUNT)
local upload = ffi.new("uint8_t[?]", COUNT)
local queue = ffi.new("int32_t[?]", COUNT)

local state = {
  texture = nil,
  originX = 0,
  originY = 0,
  originZ = 0,
  cellX = nil,
  cellY = nil,
  cellZ = nil,
  geometryRevision = -1,
  active = false
}

carriedLight.SIZE = SIZE

local function ensureTexture()
  if state.texture then return state.texture end

  local ids = ffi.new("unsigned int[1]")
  gl.glGenTextures(1, ids)
  state.texture = ids[0]

  gl.glBindTexture(GL.TEXTURE_3D, state.texture)
  gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_MIN_FILTER, GL.LINEAR)
  gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_MAG_FILTER, GL.LINEAR)
  gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE)
  gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE)
  gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_WRAP_R, GL.CLAMP_TO_EDGE)
  ffi.fill(upload, COUNT, 0)
  gl.glTexImage3D(GL.TEXTURE_3D, 0, GL_R8, SIZE, SIZE, SIZE, 0,
    GL.RED, GL.UNSIGNED_BYTE, upload)
  gl.glBindTexture(GL.TEXTURE_3D, 0)

  return state.texture
end

-- Breadth-first fill from the player's cell, decrementing by the same
-- transmission loss the placed-block propagation uses. Opaque cells are left at
-- zero; the shader samples half a block along the face normal, so a lit surface
-- reads the air in front of it rather than its own solid interior.
local function fill(world, cellX, cellY, cellZ)
  ffi.fill(reach, COUNT, 0)

  local originX = cellX - RADIUS
  local originY = cellY - RADIUS
  local originZ = cellZ - RADIUS
  state.originX, state.originY, state.originZ = originX, originY, originZ

  local sampleBlock = world:blockSampler(
    math.floor(cellX / 16), math.floor(cellZ / 16))
  local maxHeight = world.maxHeight
  local transmission = lighting.transmission

  local head, tail = 0, 0
  local startIndex = RADIUS + SIZE * (RADIUS + SIZE * RADIUS)
  reach[startIndex] = 15
  queue[tail] = startIndex
  tail = tail + 1

  while head < tail do
    local index = queue[head]
    head = head + 1
    local level = reach[index]
    if level > 1 then
      local ix = index % SIZE
      local iy = math.floor(index / SIZE) % SIZE
      local iz = math.floor(index / PLANE)

      for face = 1, 6 do
        local nx, ny, nz = ix, iy, iz
        if face == 1 then nx = ix + 1
        elseif face == 2 then nx = ix - 1
        elseif face == 3 then ny = iy + 1
        elseif face == 4 then ny = iy - 1
        elseif face == 5 then nz = iz + 1
        else nz = iz - 1 end

        if nx >= 0 and nx < SIZE and ny >= 0 and ny < SIZE and nz >= 0 and nz < SIZE then
          local worldY = originY + ny
          if worldY >= 0 and worldY <= maxHeight then
            local neighbourIndex = nx + SIZE * (ny + SIZE * nz)
            if reach[neighbourIndex] == 0 then
              local transparent, loss = transmission(
                sampleBlock(originX + nx, worldY, originZ + nz))
              if transparent then
                if loss < 1 then loss = 1 end
                local next = level - loss
                if next > 0 then
                  reach[neighbourIndex] = next
                  queue[tail] = neighbourIndex
                  tail = tail + 1
                end
              end
            end
          end
        end
      end
    end
  end

  -- 15 levels across a byte: 15 * 17 == 255, so a full-strength cell survives
  -- the round trip through the texture exactly.
  for index = 0, COUNT - 1 do
    upload[index] = reach[index] * 17
  end

  gl.glBindTexture(GL.TEXTURE_3D, ensureTexture())
  gl.glTexImage3D(GL.TEXTURE_3D, 0, GL_R8, SIZE, SIZE, SIZE, 0,
    GL.RED, GL.UNSIGNED_BYTE, upload)
  gl.glBindTexture(GL.TEXTURE_3D, 0)
end

-- Refreshes the volume if anything it depends on moved, and reports the origin
-- the shader needs to address it. `emitting` is false whenever the player holds
-- nothing that gives off light, which skips the fill entirely.
function carriedLight.update(world, x, y, z, emitting)
  ensureTexture()

  if not emitting or not world then
    state.active = false
    return state
  end

  local cellX, cellY, cellZ = math.floor(x), math.floor(y), math.floor(z)
  local revision = world.geometryRevision or 0

  -- The world is part of the key because a freshly loaded one starts its
  -- geometry revision at zero again, and the player can arrive in the same
  -- voxel they left.
  if state.active and world == state.world and
      cellX == state.cellX and cellY == state.cellY and
      cellZ == state.cellZ and revision == state.geometryRevision then
    return state
  end

  fill(world, cellX, cellY, cellZ)
  state.world = world
  state.cellX, state.cellY, state.cellZ = cellX, cellY, cellZ
  state.geometryRevision = revision
  state.active = true
  return state
end

function carriedLight.texture()
  return state.texture
end

-- How far the carried light reaches one voxel, on the same 0..15 scale the
-- shader reads out of the volume. Outside the volume it is zero.
function carriedLight.reachAt(x, y, z)
  if not state.active then return 0 end
  local ix = math.floor(x) - state.originX
  local iy = math.floor(y) - state.originY
  local iz = math.floor(z) - state.originZ
  if ix < 0 or ix >= SIZE or iy < 0 or iy >= SIZE or iz < 0 or iz >= SIZE then
    return 0
  end
  return reach[ix + SIZE * (iy + SIZE * iz)]
end

function carriedLight.release()
  if not state.texture then return end
  local ids = ffi.new("unsigned int[1]")
  ids[0] = state.texture
  gl.glDeleteTextures(1, ids)
  state.texture = nil
  state.active = false
  state.cellX, state.cellY, state.cellZ = nil, nil, nil
end

return carriedLight
