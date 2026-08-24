local blocks = require("blocks")

local lighting = {}

local NEIGHBORS = {
  { 1,  0,  0},
  {-1,  0,  0},
  { 0,  1,  0},
  { 0, -1,  0},
  { 0,  0,  1},
  { 0,  0, -1}
}

local function transmission(id)
  if not id or id == 0 then
    return true, 0
  end

  local def = blocks.list[id]
  local props = def and def.properties
  if not props then
    return false, 15
  end

  if props.leaves then
    return true, 2
  end
  if props.cutout or props.liquid then
    return true, 1
  end

  return not props.solid, props.solid and 15 or 0
end

lighting.transmission = transmission

local function getLight(world, x, y, z)
  if y < 0 or y > world.maxHeight then
    return 0
  end

  local entry = world:getChunkAtBlock(x, z)
  if not entry then
    return 0
  end

  local lx, lz = world:localBlockCoord(x, z)
  return entry.chunk:getSkyLight(lx, y, lz)
end

-- Writes a level and records which chunk it landed in, so callers know exactly
-- which meshes went stale.
local function setLight(world, x, y, z, level, touched)
  if y < 0 or y > world.maxHeight then
    return false
  end

  local entry = world:getChunkAtBlock(x, z)
  if not entry then
    return false
  end

  local lx, lz = world:localBlockCoord(x, z)
  entry.chunk:setSkyLight(lx, y, lz, level)

  if touched then
    touched[entry.chunkX .. "," .. entry.chunkZ] = entry
  end

  return true
end

-- Direct sky light for one column: 15 from the top, attenuated by whatever it
-- passes through. This is the vertical rule; the BFS below only spreads sideways.
local function directSkyColumn(world, x, z, out)
  out = out or {}
  local level = 15

  for y = world.maxHeight, 0, -1 do
    local transparent, loss = transmission(world:blockAt(x, y, z))
    if transparent and level > 0 then
      out[y] = level
      level = math.max(0, level - loss)
    else
      out[y] = 0
      level = 0
    end
  end

  return out
end

lighting.directSkyColumn = directSkyColumn

local function propagate(world, queue, touched, step)
  local head = 1

  while head <= #queue do
    local item = queue[head]
    head = head + 1
    local light = item[4]

    if light > 1 then
      for i = 1, #NEIGHBORS do
        local n = NEIGHBORS[i]
        local nx, ny, nz = item[1] + n[1], item[2] + n[2], item[3] + n[3]
        local id = ny >= 0 and ny <= world.maxHeight and world:blockAt(nx, ny, nz) or nil
        if id ~= nil then
          local transparent, loss = transmission(id)
          if transparent then
            local nextLight = light - math.max(1, loss)
            if nextLight > 0 and nextLight > getLight(world, nx, ny, nz) then
              if setLight(world, nx, ny, nz, nextLight, touched) then
                queue[#queue + 1] = {nx, ny, nz, nextLight}
              end
            end
          end
        end
      end
    end

    if step and head % 256 == 0 then
      step()
    end
  end
end

-- Clears a region that lost its light source. Cells that are still at least as
-- bright as the wave that reached them are handed to `refill` instead, so the
-- following propagate() pass relights the hole from its own boundary.
local function removeLight(world, removals, refill, touched, step)
  local head = 1

  while head <= #removals do
    local item = removals[head]
    head = head + 1
    local level = item[4]

    for i = 1, #NEIGHBORS do
      local n = NEIGHBORS[i]
      local nx, ny, nz = item[1] + n[1], item[2] + n[2], item[3] + n[3]
      if ny >= 0 and ny <= world.maxHeight then
        local neighbourLight = getLight(world, nx, ny, nz)
        if neighbourLight ~= 0 then
          if neighbourLight < level then
            if setLight(world, nx, ny, nz, 0, touched) then
              removals[#removals + 1] = {nx, ny, nz, neighbourLight}
            end
          else
            refill[#refill + 1] = {nx, ny, nz, neighbourLight}
          end
        end
      end
    end

    if step and head % 256 == 0 then
      step()
    end
  end
end

-- Applies one block change. `beforeColumn` is the direct-sky column captured at
-- (x, z) *before* the block was written; diffing it against the new column tells
-- us which cells gained or lost sky, without disturbing cells that are lit only
-- by sideways spread (caves, overhangs).
function lighting.applyBlockChange(world, x, y, z, beforeColumn, touched)
  touched = touched or {}
  local afterColumn = directSkyColumn(world, x, z)
  local queue, removals = {}, {}

  for cy = 0, world.maxHeight do
    local before = beforeColumn[cy] or 0
    local after = afterColumn[cy] or 0

    if after > before then
      if after > getLight(world, x, cy, z) then
        setLight(world, x, cy, z, after, touched)
        queue[#queue + 1] = {x, cy, z, after}
      end
    elseif after < before then
      local current = getLight(world, x, cy, z)
      if current > 0 then
        setLight(world, x, cy, z, 0, touched)
        removals[#removals + 1] = {x, cy, z, current}
      end
    end
  end

  -- Digging sideways into a lit cave changes no sky column at all, so seed the
  -- edited cell's neighbours and let light flow in.
  for i = 1, #NEIGHBORS do
    local n = NEIGHBORS[i]
    local nx, ny, nz = x + n[1], y + n[2], z + n[3]
    local level = getLight(world, nx, ny, nz)
    if level > 1 then
      queue[#queue + 1] = {nx, ny, nz, level}
    end
  end

  removeLight(world, removals, queue, touched)
  propagate(world, queue, touched)

  return touched
end

-- Lights a freshly generated chunk without touching the rest of the world.
-- A new chunk can only ever *add* light to its neighbours (with it absent, no
-- light propagated out of it at all), so no removal pass is needed here.
function lighting.lightChunk(world, entry, touched, step)
  touched = touched or {}
  local chunk = entry.chunk
  local queue = {}
  local column = {}

  chunk:clearSkyLight()

  for lx = 0, 15 do
    for lz = 0, 15 do
      local wx, wz = entry.offsetX + lx, entry.offsetZ + lz
      directSkyColumn(world, wx, wz, column)
      for y = 0, world.maxHeight do
        local level = column[y]
        if level > 0 then
          chunk:setSkyLight(lx, y, lz, level)
          queue[#queue + 1] = {wx, y, wz, level}
        end
      end
    end
    if step then step() end
  end

  touched[entry.chunkX .. "," .. entry.chunkZ] = entry

  -- Seed from the borders of neighbours that are already lit, so light flows
  -- into the new chunk as well as out of it.
  local border = {
    {entry.offsetX - 1, entry.offsetZ, 0, 1},
    {entry.offsetX + 16, entry.offsetZ, 0, 1},
    {entry.offsetX, entry.offsetZ - 1, 1, 0},
    {entry.offsetX, entry.offsetZ + 16, 1, 0}
  }

  for i = 1, #border do
    local bx, bz, dx, dz = border[i][1], border[i][2], border[i][3], border[i][4]
    if world:getChunkAtBlock(bx, bz) then
      for offset = 0, 15 do
        local wx, wz = bx + dx * offset, bz + dz * offset
        for y = 0, world.maxHeight do
          local level = getLight(world, wx, y, wz)
          if level > 1 then
            queue[#queue + 1] = {wx, y, wz, level}
          end
        end
      end
    end
  end
  if step then step() end

  propagate(world, queue, touched, step)

  return touched
end

-- Full-world relight. Still used for an explicit rebuild; the streaming and
-- edit paths are incremental and never call this.
function lighting.rebuild(world, options)
  options = options or {}
  local step = options.yieldStep
  local queue = {}

  world:eachChunk(function(chunk)
    chunk:clearSkyLight()
  end)

  world:eachChunk(function(chunk, entry)
    local column = {}
    for lx = 0, 15 do
      for lz = 0, 15 do
        local wx, wz = entry.offsetX + lx, entry.offsetZ + lz
        directSkyColumn(world, wx, wz, column)
        for y = 0, world.maxHeight do
          local level = column[y]
          if level > 0 then
            chunk:setSkyLight(lx, y, lz, level)
            queue[#queue + 1] = {wx, y, wz, level}
          end
        end
      end
      if step then step() end
    end
  end)

  propagate(world, queue, nil, step)
end

return lighting
