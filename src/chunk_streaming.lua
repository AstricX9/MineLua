local World = require("world")

local streaming = {}

local function pendingChunkCoords(item)
  if item.entry then return item.entry.chunkX, item.entry.chunkZ end
  return item.chunkX, item.chunkZ
end

local function distanceSquared(chunkX, chunkZ, centerX, centerZ)
  local dx, dz = chunkX - centerX, chunkZ - centerZ
  return dx * dx + dz * dz
end

-- Re-rank existing work as well as newly queued work. Turning around should not
-- leave the player waiting behind meshes and generation jobs that are no longer
-- nearby. Urgent edit remeshes retain absolute priority.
function streaming.prioritize(world, pendingEntries, x, z, predictedX, predictedZ)
  local centerX, centerZ = World.chunkCoord(x), World.chunkCoord(z)
  local aheadX = World.chunkCoord(predictedX or x)
  local aheadZ = World.chunkCoord(predictedZ or z)

  for index = 1, #pendingEntries do pendingEntries[index].streamOrder = index end
  table.sort(pendingEntries, function(a, b)
    if (a.urgent == true) ~= (b.urgent == true) then return a.urgent == true end
    local ax, az = pendingChunkCoords(a)
    local bx, bz = pendingChunkCoords(b)
    if not ax or not az then return false end
    if not bx or not bz then return true end

    local aDistance = math.min(
      distanceSquared(ax, az, centerX, centerZ), distanceSquared(ax, az, aheadX, aheadZ))
    local bDistance = math.min(
      distanceSquared(bx, bz, centerX, centerZ), distanceSquared(bx, bz, aheadX, aheadZ))
    -- Collision data matters before a mesh when the player is close. Farther
    -- out, normal distance ordering keeps the visible terrain filling evenly.
    if not a.entry and aDistance <= 2 then aDistance = aDistance - 4 end
    if not b.entry and bDistance <= 2 then bDistance = bDistance - 4 end
    if aDistance == bDistance then return a.streamOrder < b.streamOrder end
    return aDistance < bDistance
  end)

  -- Mirror the same priority into worker jobs that have not launched yet.
  for index = math.min(4, #pendingEntries), 1, -1 do
    world:prioritizeChunkJob(pendingEntries[index])
  end
end

function streaming.collisionRingReady(world, x, z)
  local centerX, centerZ = World.chunkCoord(x), World.chunkCoord(z)
  for dz = -1, 1 do
    for dx = -1, 1 do
      local entry = world.chunks[World.chunkKey(centerX + dx, centerZ + dz)]
      if not entry or not entry.hasCollision then return false end
    end
  end
  return true
end

return streaming
