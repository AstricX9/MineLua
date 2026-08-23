local blocks = require("blocks")

local lighting = {}

local function transmission(id)
  if not id or id == 0 then return true, 0 end
  local def = blocks.list[id]
  local p = def and def.properties
  if not p then return false, 15 end
  if p.leaves then return true, 2 end
  if p.ice or p.cutout or p.liquid then return true, 1 end
  return not p.solid, p.solid and 15 or 0
end

lighting.transmission = transmission

local function key(entry)
  return entry.chunkX .. "," .. entry.chunkY .. "," .. entry.chunkZ
end

-- Radial skylight deliberately has no privileged global axis. Near the surface,
-- transparent cells receive open-sky light; underground transparency retains a
-- small level so caves are readable until a full emissive-light system lands.
-- Surface faces sample their outward air neighbour and therefore receive 15 on
-- every side of the planet, including the poles and opposite hemisphere.
function lighting.lightChunk(world, entry, touched, step)
  touched = touched or {}
  local chunk, planet = entry.chunk, world.planet
  chunk:clearSkyLight()
  local processed = 0
  for x = 0, 15 do
    for y = 0, 15 do
      for z = 0, 15 do
        local id = chunk:getBlock(x, y, z)
        local transparent = transmission(id)
        if transparent then
          local position = {entry.offsetX + x + 0.5, entry.offsetY + y + 0.5, entry.offsetZ + z + 0.5}
          local altitude = planet:altitudeMeters(position)
          chunk:setSkyLight(x, y, z, altitude > planet.minTerrainElevationMeters - 8.0 and 15 or 5)
        end
        processed = processed + 1
        if step and processed % 512 == 0 then step() end
      end
    end
  end
  touched[key(entry)] = entry
  return touched
end

function lighting.directSkyColumn()
  -- Retained only as a compatibility hook for callers written against the old
  -- flat-lighting API. A sphere has no global sky column.
  return {}
end

function lighting.applyBlockChange(world, x, y, z, _, touched)
  touched = touched or {}
  local entry = world:getChunkAtBlock(x, y, z)
  if not entry then return touched end
  lighting.lightChunk(world, entry, touched)
  local lx, ly, lz, cx, cy, cz = world:localBlockCoord(x, y, z)
  local ranges = {
    lx == 0 and -1 or 0, lx == 15 and 1 or 0,
    ly == 0 and -1 or 0, ly == 15 and 1 or 0,
    lz == 0 and -1 or 0, lz == 15 and 1 or 0
  }
  for dz = ranges[5], ranges[6] do
    for dy = ranges[3], ranges[4] do
      for dx = ranges[1], ranges[2] do
        local neighbour = world.chunks[(cx + dx) .. "," .. (cy + dy) .. "," .. (cz + dz)]
        if neighbour then touched[key(neighbour)] = neighbour end
      end
    end
  end
  return touched
end

function lighting.rebuild(world, options)
  options = options or {}
  world:eachChunk(function(_, entry)
    lighting.lightChunk(world, entry, nil, options.yieldStep)
  end)
end

return lighting
