local blocks = require("blocks")

local lighting = {}

local floor, max, min = math.floor, math.max, math.min

-- The six axial neighbours, split into parallel arrays. The old table-of-tables
-- cost an extra table index per component in the innermost loop of every
-- propagation pass.
local NEIGHBOUR_X = { 1, -1,  0,  0,  0,  0}
local NEIGHBOUR_Y = { 0,  0,  1, -1,  0,  0}
local NEIGHBOUR_Z = { 0,  0,  0,  0,  1, -1}

-- How often a propagation pass offers to yield, counted in queue records.
local YIELD_RECORDS = 1024

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

--------------------------------------------------------------------------
-- Chunk access
--------------------------------------------------------------------------

-- World:getChunkAtBlock builds a "chunkX,chunkZ" string on every call, and a
-- propagation pass makes roughly eighteen of those per cell it visits. One
-- accessor per top-level lighting operation resolves each chunk once and then
-- indexes it arithmetically, which is what keeps a relight off the allocator.
--
-- Only successful lookups are cached. A chunk that is missing now may stream in
-- during a yielded pass, and remembering its absence would light the world
-- around a hole that no longer exists.
local CHUNK_SIZE = 16

local function chunkAccessor(world)
  local rows = {}
  local getChunkAtBlock = world.getChunkAtBlock
  local lastX, lastZ, lastEntry

  return function(x, z)
    local chunkX = floor(x / CHUNK_SIZE)
    local chunkZ = floor(z / CHUNK_SIZE)
    local entry

    if lastEntry and chunkX == lastX and chunkZ == lastZ then
      entry = lastEntry
    else
      local row = rows[chunkX]
      entry = row and row[chunkZ]
      if not entry then
        entry = getChunkAtBlock(world, x, z)
        if not entry then
          return nil
        end
        if not row then
          row = {}
          rows[chunkX] = row
        end
        row[chunkZ] = entry
      end
      lastX, lastZ, lastEntry = chunkX, chunkZ, entry
    end

    -- The definition World:localBlockCoord uses, inlined: calling through the
    -- world for it costs a method dispatch on the hottest line in the module.
    return entry, x - chunkX * CHUNK_SIZE, z - chunkZ * CHUNK_SIZE
  end
end

local function blockAt(access, world, x, y, z)
  if y < 0 or y > world.maxHeight then return nil end
  local entry, lx, lz = access(x, z)
  if not entry then return nil end
  return entry.chunk:getBlock(lx, y, lz)
end

local function getLight(access, world, x, y, z)
  if y < 0 or y > world.maxHeight then return 0 end
  local entry, lx, lz = access(x, z)
  if not entry then return 0 end
  return entry.chunk:getSkyLight(lx, y, lz)
end

-- Writes a level and records which chunk it landed in, so callers know exactly
-- which meshes went stale.
local function setLight(access, world, x, y, z, level, touched)
  if y < 0 or y > world.maxHeight then return false end
  local entry, lx, lz = access(x, z)
  if not entry then return false end

  entry.chunk:setSkyLight(lx, y, lz, level)
  if touched then
    touched[entry.chunkX .. "," .. entry.chunkZ] = entry
  end
  return true
end

local function getBlockLight(access, world, x, y, z)
  if y < 0 or y > world.maxHeight then return 0, 0, 0 end
  local entry, lx, lz = access(x, z)
  if not entry then return 0, 0, 0 end
  return entry.chunk:getBlockLight(lx, y, lz)
end

local function setBlockLight(access, world, x, y, z, red, green, blue, touched)
  if y < 0 or y > world.maxHeight then return false end
  local entry, lx, lz = access(x, z)
  if not entry then return false end

  entry.chunk:setBlockLight(lx, y, lz, red, green, blue)
  if touched then
    touched[entry.chunkX .. "," .. entry.chunkZ] = entry
  end
  return true
end

--------------------------------------------------------------------------
-- Flat propagation queues
--------------------------------------------------------------------------

-- A breadth-first light pass visits every cell it brightens, and the previous
-- implementation appended a fresh {x, y, z, level} table for each one while the
-- read cursor only moved forward. Nothing was ever released, so relighting a
-- render distance of terrain retained a table per visited cell -- 220 MB and
-- roughly three seconds for sixty-four chunks. Storing the same records as runs
-- of plain numbers in one array removes the allocation entirely.
local function newQueue()
  return {n = 0}
end

local function pushSky(queue, x, y, z, level)
  local n = queue.n
  queue[n + 1] = x
  queue[n + 2] = y
  queue[n + 3] = z
  queue[n + 4] = level
  queue.n = n + 4
end

local function pushRgb(queue, x, y, z, red, green, blue)
  local n = queue.n
  queue[n + 1] = x
  queue[n + 2] = y
  queue[n + 3] = z
  queue[n + 4] = red
  queue[n + 5] = green
  queue[n + 6] = blue
  queue.n = n + 6
end

local function emission(id)
  local def = id and blocks.list[id]
  local value = def and def.properties and def.properties.emission
  if type(value) == "number" then return value, value, value end
  if type(value) == "table" then
    return tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0
  end
  return 0, 0, 0
end

lighting.emission = emission

-- Carried emissive blocks use the same authored RGB values as placed blocks.
-- Keeping this lookup beside emission() prevents the first-person light from
-- drifting to a different colour or range than its world-block counterpart.
function lighting.heldEmission(stack)
  local definition = stack and stack.item and blocks.mapping[stack.item]
  return emission(definition and definition.id)
end

local function propagateBlockLight(access, world, queue, touched, step)
  local head = 1
  local visited = 0

  while head <= queue.n do
    local x, y, z = queue[head], queue[head + 1], queue[head + 2]
    local red, green, blue = queue[head + 3], queue[head + 4], queue[head + 5]
    head = head + 6

    if red > 1 or green > 1 or blue > 1 then
      for i = 1, 6 do
        local nx, ny, nz = x + NEIGHBOUR_X[i], y + NEIGHBOUR_Y[i], z + NEIGHBOUR_Z[i]
        local id = blockAt(access, world, nx, ny, nz)
        if id ~= nil then
          local transparent, loss = transmission(id)
          if transparent then
            if loss < 1 then loss = 1 end
            local nr, ng, nb = red - loss, green - loss, blue - loss
            if nr < 0 then nr = 0 end
            if ng < 0 then ng = 0 end
            if nb < 0 then nb = 0 end
            local cr, cg, cb = getBlockLight(access, world, nx, ny, nz)
            if nr < cr then nr = cr end
            if ng < cg then ng = cg end
            if nb < cb then nb = cb end
            if nr ~= cr or ng ~= cg or nb ~= cb then
              if setBlockLight(access, world, nx, ny, nz, nr, ng, nb, touched) then
                pushRgb(queue, nx, ny, nz, nr, ng, nb)
              end
            end
          end
        end
      end
    end

    visited = visited + 1
    if step and visited % YIELD_RECORDS == 0 then step() end
  end
end

local function updateBlockLight(access, world, x, y, z, oldRed, oldGreen, oldBlue, touched)
  local sourceRed, sourceGreen, sourceBlue = emission(blockAt(access, world, x, y, z))
  setBlockLight(access, world, x, y, z, sourceRed, sourceGreen, sourceBlue, touched)

  local removals = newQueue()
  pushRgb(removals, x, y, z, oldRed or 0, oldGreen or 0, oldBlue or 0)
  local refill = newQueue()
  local head = 1

  while head <= removals.n do
    local rx, ry, rz = removals[head], removals[head + 1], removals[head + 2]
    local wasRed, wasGreen, wasBlue = removals[head + 3], removals[head + 4], removals[head + 5]
    head = head + 6

    for i = 1, 6 do
      local nx, ny, nz = rx + NEIGHBOUR_X[i], ry + NEIGHBOUR_Y[i], rz + NEIGHBOUR_Z[i]
      local cr, cg, cb = getBlockLight(access, world, nx, ny, nz)
      if cr > 0 or cg > 0 or cb > 0 then
        local er, eg, eb = emission(blockAt(access, world, nx, ny, nz))
        local nr, ng, nb = cr, cg, cb
        if cr > er and cr < wasRed then nr = er end
        if cg > eg and cg < wasGreen then ng = eg end
        if cb > eb and cb < wasBlue then nb = eb end
        if nr ~= cr or ng ~= cg or nb ~= cb then
          if setBlockLight(access, world, nx, ny, nz, nr, ng, nb, touched) then
            pushRgb(removals, nx, ny, nz, cr, cg, cb)
          end
        else
          pushRgb(refill, nx, ny, nz, cr, cg, cb)
        end
      end
    end
  end

  if sourceRed > 0 or sourceGreen > 0 or sourceBlue > 0 then
    pushRgb(refill, x, y, z, sourceRed, sourceGreen, sourceBlue)
  end
  propagateBlockLight(access, world, refill, touched)
end

--------------------------------------------------------------------------
-- Sky light
--------------------------------------------------------------------------

-- Direct sky light for one column: 15 from the top, attenuated by whatever it
-- passes through. This is the vertical rule; the BFS below only spreads sideways.
local function directSkyColumnWith(access, world, x, z, out)
  out = out or {}
  local level = 15
  local maxHeight = world.maxHeight

  for y = maxHeight, 0, -1 do
    local transparent, loss = transmission(blockAt(access, world, x, y, z))
    if transparent and level > 0 then
      out[y] = level
      level = level - loss
      if level < 0 then level = 0 end
    else
      -- Once the column is dark it stays dark: the branch above needs
      -- `level > 0`, so every remaining cell is zero whatever it contains.
      -- Filling them directly skips a block lookup per level, and half a
      -- column is below the surface.
      for below = y, 0, -1 do
        out[below] = 0
      end
      return out
    end
  end

  return out
end

local function directSkyColumn(world, x, z, out)
  return directSkyColumnWith(chunkAccessor(world), world, x, z, out)
end

lighting.directSkyColumn = directSkyColumn

local function propagate(access, world, queue, touched, step)
  local head = 1
  local visited = 0
  local maxHeight = world.maxHeight

  while head <= queue.n do
    local x, y, z, light = queue[head], queue[head + 1], queue[head + 2], queue[head + 3]
    head = head + 4

    if light > 1 then
      for i = 1, 6 do
        local nx, ny, nz = x + NEIGHBOUR_X[i], y + NEIGHBOUR_Y[i], z + NEIGHBOUR_Z[i]
        if ny >= 0 and ny <= maxHeight then
          local entry, lx, lz = access(nx, nz)
          if entry then
            local chunk = entry.chunk
            local transparent, loss = transmission(chunk:getBlock(lx, ny, lz))
            if transparent then
              if loss < 1 then loss = 1 end
              local nextLight = light - loss
              if nextLight > 0 and nextLight > chunk:getSkyLight(lx, ny, lz) then
                chunk:setSkyLight(lx, ny, lz, nextLight)
                if touched then
                  touched[entry.chunkX .. "," .. entry.chunkZ] = entry
                end
                pushSky(queue, nx, ny, nz, nextLight)
              end
            end
          end
        end
      end
    end

    visited = visited + 1
    if step and visited % YIELD_RECORDS == 0 then step() end
  end
end

-- Clears a region that lost its light source. Cells that are still at least as
-- bright as the wave that reached them are handed to `refill` instead, so the
-- following propagate() pass relights the hole from its own boundary.
local function removeLight(access, world, removals, refill, touched, step)
  local head = 1
  local visited = 0
  -- Two-level numeric tables rather than "x,y,z" string keys: sealing a room
  -- one block at a time invalidates a connected region, and building a key
  -- string per neighbour visit was the dominant cost of placing a block.
  local directColumns = {}
  local seen = {}

  local function directLightAt(x, y, z)
    local row = directColumns[x]
    if not row then
      row = {}
      directColumns[x] = row
    end
    local column = row[z]
    if not column then
      column = directSkyColumnWith(access, world, x, z)
      row[z] = column
    end
    return column[y] or 0
  end

  local function markSeen(x, y, z)
    local row = seen[x]
    if not row then
      row = {}
      seen[x] = row
    end
    local plane = row[y]
    if not plane then
      plane = {}
      row[y] = plane
    end
    if plane[z] then return false end
    plane[z] = true
    return true
  end

  while head <= removals.n do
    local x, y, z = removals[head], removals[head + 1], removals[head + 2]
    head = head + 4
    markSeen(x, y, z)

    for i = 1, 6 do
      local nx, ny, nz = x + NEIGHBOUR_X[i], y + NEIGHBOUR_Y[i], z + NEIGHBOUR_Z[i]
      if ny >= 0 and ny <= world.maxHeight then
        local neighbourLight = getLight(access, world, nx, ny, nz)
        if neighbourLight ~= 0 then
          local directLight = directLightAt(nx, ny, nz)
          -- Light is a source only when the current vertical sky column can
          -- justify it. Everything brighter is propagated state: invalidate
          -- the connected region regardless of its relative level, then let
          -- propagate() rebuild it from the surviving direct-sky boundary.
          -- This handles rooms closed one wall/roof block at a time, where a
          -- simple lower-than comparison leaves stale local maxima behind.
          if directLight < neighbourLight then
            if markSeen(nx, ny, nz) then
              if setLight(access, world, nx, ny, nz, directLight, touched) then
                pushSky(removals, nx, ny, nz, neighbourLight)
                if directLight > 0 then
                  pushSky(refill, nx, ny, nz, directLight)
                end
              end
            end
          else
            pushSky(refill, nx, ny, nz, neighbourLight)
          end
        end
      end
    end

    visited = visited + 1
    if step and visited % YIELD_RECORDS == 0 then step() end
  end
end

-- Applies one block change. `beforeColumn` is the direct-sky column captured at
-- (x, z) *before* the block was written; diffing it against the new column tells
-- us which cells gained or lost sky, without disturbing cells that are lit only
-- by sideways spread (caves, overhangs).
function lighting.applyBlockChange(world, x, y, z, beforeColumn, touched,
    oldBlockId, oldRed, oldGreen, oldBlue)
  touched = touched or {}
  local access = chunkAccessor(world)
  local afterColumn = directSkyColumnWith(access, world, x, z)
  local queue, removals = newQueue(), newQueue()

  for cy = 0, world.maxHeight do
    local before = beforeColumn[cy] or 0
    local after = afterColumn[cy] or 0

    if after > before then
      if after > getLight(access, world, x, cy, z) then
        setLight(access, world, x, cy, z, after, touched)
        pushSky(queue, x, cy, z, after)
      end
    elseif after < before then
      local current = getLight(access, world, x, cy, z)
      if current > 0 or before > 0 then
        setLight(access, world, x, cy, z, 0, touched)
        -- Use the light that the edited direct-sky column supplied before the
        -- block was placed. A prior neighbouring edit may already have left
        -- this stored cell artificially low; seeding from that stale value
        -- makes stronger remnants look like valid refill sources.
        pushSky(removals, x, cy, z, max(current, before))
      end
    end
  end

  local oldTransparent, oldLoss = transmission(oldBlockId)
  local editedTransparent, editedLoss = transmission(blockAt(access, world, x, y, z))
  local openedLightPath = editedTransparent and
    (not oldTransparent or editedLoss < oldLoss)
  if openedLightPath then
    -- Digging sideways into a lit cave changes no sky column at all, so seed
    -- the edited cell's neighbours and let light flow in. Do not do this when
    -- placing an opaque block: those neighbours may be precisely the stale
    -- propagated values the removal pass is about to invalidate.
    for i = 1, 6 do
      local nx, ny, nz = x + NEIGHBOUR_X[i], y + NEIGHBOUR_Y[i], z + NEIGHBOUR_Z[i]
      local level = getLight(access, world, nx, ny, nz)
      if level > 1 then
        pushSky(queue, nx, ny, nz, level)
      end
    end
  end

  removeLight(access, world, removals, queue, touched)
  propagate(access, world, queue, touched)
  updateBlockLight(access, world, x, y, z, oldRed, oldGreen, oldBlue, touched)

  return touched
end

--------------------------------------------------------------------------
-- Bulk lighting
--------------------------------------------------------------------------

-- Fills one chunk's sky light from its direct columns and queues only the cells
-- that can actually spread.
--
-- A cell whose four horizontal neighbours all receive at least `level - 1` of
-- direct sky can never brighten any of them, so seeding it only makes the queue
-- longer. Restricting the seed to that frontier -- cliff faces, cave mouths,
-- overhangs -- is what turns an open-sky chunk from sixteen thousand queue
-- records into a few hundred, without changing the result.
local COLUMN_SPAN = 18

-- The chunk-and-skirt column scratch is reused between chunks. Every entry is
-- rewritten from maxHeight down to zero before it is read, and lighting runs on
-- one coroutine at a time, so there is nothing stale to carry across.
local columnScratch = {}
for index = 0, COLUMN_SPAN * COLUMN_SPAN - 1 do
  columnScratch[index] = {}
end

local function fillChunkSkyLight(access, world, entry, queue, step)
  local chunk = entry.chunk
  local offsetX, offsetZ = entry.offsetX, entry.offsetZ
  local maxHeight = world.maxHeight
  local columns = columnScratch

  for lx = -1, 16 do
    for lz = -1, 16 do
      directSkyColumnWith(access, world, offsetX + lx, offsetZ + lz,
        columns[(lx + 1) * COLUMN_SPAN + (lz + 1)])
    end
    if step then step() end
  end

  for lx = 0, 15 do
    for lz = 0, 15 do
      local column = columns[(lx + 1) * COLUMN_SPAN + (lz + 1)]
      local west = columns[lx * COLUMN_SPAN + (lz + 1)]
      local east = columns[(lx + 2) * COLUMN_SPAN + (lz + 1)]
      local north = columns[(lx + 1) * COLUMN_SPAN + lz]
      local south = columns[(lx + 1) * COLUMN_SPAN + (lz + 2)]
      local wx, wz = offsetX + lx, offsetZ + lz

      for y = 0, maxHeight do
        local level = column[y]
        if level > 0 then
          chunk:setSkyLight(lx, y, lz, level)
          if level > 1 then
            local threshold = level - 1
            if west[y] < threshold or east[y] < threshold or
                north[y] < threshold or south[y] < threshold then
              pushSky(queue, wx, y, wz, level)
            end
          end
        end
      end
    end
    if step then step() end
  end
end

-- Lights a freshly generated chunk without touching the rest of the world.
-- A new chunk can only ever *add* light to its neighbours (with it absent, no
-- light propagated out of it at all), so no removal pass is needed here.
function lighting.lightChunk(world, entry, touched, step)
  touched = touched or {}
  local access = chunkAccessor(world)
  local chunk = entry.chunk
  local queue = newQueue()
  local maxHeight = world.maxHeight

  chunk:clearSkyLight()
  chunk:clearBlockLight()

  fillChunkSkyLight(access, world, entry, queue, step)

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
    local neighbourEntry = access(bx, bz)
    if neighbourEntry then
      for offset = 0, 15 do
        local wx, wz = bx + dx * offset, bz + dz * offset
        for y = 0, maxHeight do
          local level = getLight(access, world, wx, y, wz)
          if level > 1 then
            pushSky(queue, wx, y, wz, level)
          end
        end
      end
    end
  end
  if step then step() end

  propagate(access, world, queue, touched, step)

  local blockQueue = newQueue()
  for lx = 0, 15 do
    for lz = 0, 15 do
      for y = 0, maxHeight do
        local red, green, blue = emission(chunk:getBlock(lx, y, lz))
        if red > 0 or green > 0 or blue > 0 then
          chunk:setBlockLight(lx, y, lz, red, green, blue)
          pushRgb(blockQueue, entry.offsetX + lx, y, entry.offsetZ + lz, red, green, blue)
        end
      end
    end
    if step then step() end
  end
  -- Existing neighbour light is a boundary condition for a newly loaded chunk.
  for i = 1, #border do
    local bx, bz, dx, dz = border[i][1], border[i][2], border[i][3], border[i][4]
    if access(bx, bz) then
      for offset = 0, 15 do
        local wx, wz = bx + dx * offset, bz + dz * offset
        for y = 0, maxHeight do
          local red, green, blue = getBlockLight(access, world, wx, y, wz)
          if red > 1 or green > 1 or blue > 1 then
            pushRgb(blockQueue, wx, y, wz, red, green, blue)
          end
        end
      end
    end
  end
  propagateBlockLight(access, world, blockQueue, touched, step)

  return touched
end

-- Full-world relight. Still used for an explicit rebuild; the streaming and
-- edit paths are incremental and never call this.
function lighting.rebuild(world, options)
  options = options or {}
  local step = options.yieldStep
  local access = chunkAccessor(world)
  local queue = newQueue()

  world:eachChunk(function(chunk)
    chunk:clearSkyLight()
    chunk:clearBlockLight()
  end)

  world:eachChunk(function(chunk, entry)
    fillChunkSkyLight(access, world, entry, queue, step)
  end)

  propagate(access, world, queue, nil, step)

  local blockQueue = newQueue()
  world:eachChunk(function(chunk, entry)
    for lx = 0, 15 do
      for lz = 0, 15 do
        for y = 0, world.maxHeight do
          local red, green, blue = emission(chunk:getBlock(lx, y, lz))
          if red > 0 or green > 0 or blue > 0 then
            chunk:setBlockLight(lx, y, lz, red, green, blue)
            pushRgb(blockQueue, entry.offsetX + lx, y, entry.offsetZ + lz, red, green, blue)
          end
        end
      end
      if step then step() end
    end
  end)
  propagateBlockLight(access, world, blockQueue, nil, step)
end

return lighting
