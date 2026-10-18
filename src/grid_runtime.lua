-- Keeps a GridWorld loaded and meshed around the player.
--
-- Generation, meshing and eviction all run on a per-frame budget, so walking
-- into new ground costs a few milliseconds a frame rather than a stall. Uploads
-- are handed back to the caller, because this module knows nothing about GL.

local GridWorld = require("grid_world")
local GridMesher = require("grid_mesher")
local GridTerrain = require("grid_terrain")
local terrain = require("terrain")

local GridRuntime = {}
GridRuntime.__index = GridRuntime

local CHUNK = GridWorld.CHUNK_SIZE
local floor, max, abs = math.floor, math.max, math.abs

function GridRuntime.new(gridWorld, options)
  options = options or {}
  return setmetatable({
    world = gridWorld,
    grid = gridWorld.grid,
    radius = options.radius or 5,
    -- Generating a stack is a few milliseconds; meshing one chunk is about
    -- one. These are per frame.
    -- Budgeted by wall clock, not by count. A column stack is its surface
    -- samples plus about seven chunks, roughly twenty milliseconds, so a
    -- count-based budget of two stacks a frame was a thirty fps hitch every
    -- time the player crossed into new ground.
    budgetSeconds = options.budgetSeconds or 0.004,
    -- Must be high resolution. os.clock on Windows ticks about every 15 ms,
    -- which is three times the budget -- the loop would blow straight past it
    -- and only notice a frame later. The caller passes glfwGetTime.
    clock = options.clock or os.clock,
    workQueue = {},
    workIndex = 1,
    upload = assert(options.upload, "grid runtime needs an upload callback"),
    release = assert(options.release, "grid runtime needs a release callback"),
    renderOrigin = options.renderOrigin or {0.0, 0.0, 0.0},
    meshed = {},
    dirty = {},
    pending = {},
    pendingIndex = 1,
    tintCache = {},
    centreColumn = nil,
    centreRow = nil,
    centreFace = nil
  }, GridRuntime)
end

function GridRuntime:setRenderOrigin(origin)
  if origin[1] == self.renderOrigin[1] and origin[2] == self.renderOrigin[2]
    and origin[3] == self.renderOrigin[3] then return false end
  self.renderOrigin = {origin[1], origin[2], origin[3]}
  -- Every mesh is relative to the origin, so all of them have to be rebuilt.
  for key in pairs(self.meshed) do self.dirty[key] = true end
  return true
end

function GridRuntime:tintFor(face, column, row)
  local key = column .. ":" .. row
  local cached = self.tintCache[key]
  if not cached then
    local samples = self.world:columnSamples(face, floor(column / CHUNK), floor(row / CHUNK))
    local sample = GridTerrain.sampleAt(samples, column % CHUNK, row % CHUNK)
    cached = terrain.grassColorForSample(sample)
    self.tintCache[key] = cached
  end
  return cached[1], cached[2], cached[3]
end

function GridRuntime:meshChunk(entry)
  local world = self.world
  local function blockAt(f, c, r, l)
    return world:blockAtVoxel(f, c, r, l) or 0
  end
  local function tintAt(f, c, r)
    return self:tintFor(f, c, r)
  end
  -- Returns opaque vertices and leaf vertices; leaves are alpha-blended in a
  -- later pass and must not be mixed into the opaque mesh.
  return GridMesher.meshChunk(self.grid, entry.face, entry.chunkColumn, entry.chunkRow,
    entry.chunkLayer, {
      blockAt = blockAt,
      tintAt = tintAt,
      renderOrigin = self.renderOrigin,
      center = self.world.planet.center
    })
end

-- Rebuilds the list of stacks wanted around a position, nearest first.
function GridRuntime:refocus(position)
  local up = self.world.planet:localUp(position)
  local face, column, row = self.grid:locate(up[1], up[2], up[3])
  local centreColumn, centreRow = floor(column / CHUNK), floor(row / CHUNK)
  if face == self.centreFace and centreColumn == self.centreColumn
    and centreRow == self.centreRow then return false end
  self.centreFace, self.centreColumn, self.centreRow = face, centreColumn, centreRow

  local wanted = {}
  local radius = self.radius
  for dr = -radius, radius do
    for dc = -radius, radius do
      if dc * dc + dr * dr <= radius * radius then
        wanted[#wanted + 1] = {column = centreColumn + dc, row = centreRow + dr,
          distance = dc * dc + dr * dr}
      end
    end
  end
  table.sort(wanted, function(a, b) return a.distance < b.distance end)
  self.pending, self.pendingIndex = wanted, 1
  self.workQueue, self.workIndex = {}, 1
  return true
end

-- Drops stacks that have fallen outside the keep radius.
function GridRuntime:evict()
  local keep = self.radius + 1
  local seen = {}
  for _, entry in pairs(self.world.chunks) do
    local key = entry.face .. ":" .. entry.chunkColumn .. ":" .. entry.chunkRow
    if not seen[key] then
      seen[key] = true
      if entry.face ~= self.centreFace or
        abs(entry.chunkColumn - self.centreColumn) > keep or
        abs(entry.chunkRow - self.centreRow) > keep then
        for _, removedKey in ipairs(self.world:releaseStack(entry.face, entry.chunkColumn, entry.chunkRow)) do
          if self.meshed[removedKey] then self.release(removedKey) end
          self.meshed[removedKey] = nil
          self.dirty[removedKey] = nil
        end
      end
    end
  end
end

-- Rebuilds every outstanding mesh at once, ignoring the frame budget.
--
-- Used when the render origin moves: vertices are stored relative to it, so
-- until a mesh is rebuilt it draws hundreds of metres from where it belongs.
-- Doing that a few chunks a frame leaves the world visibly scattered for a
-- second or two, which is worse than one short hitch.
function GridRuntime:rebuildDirty()
  local rebuilt = 0
  for key in pairs(self.dirty) do
    self.dirty[key] = nil
    local entry = self.world.chunks[key]
    if entry then
      local vertices, leaves = self:meshChunk(entry)
      self.upload(key, vertices, leaves)
      self.meshed[key] = #vertices > 0 or #leaves > 0
      rebuilt = rebuilt + 1
    else
      if self.meshed[key] then self.release(key) end
      self.meshed[key] = nil
    end
  end
  return rebuilt
end

function GridRuntime:update(position)
  if self:refocus(position) then self:evict() end

  local deadline = self.clock() + self.budgetSeconds

  -- Generate the nearest outstanding stacks, one chunk at a time so the work
  -- can stop between them rather than mid-stack.
  local generated = 0
  while self.clock() < deadline do
    if self.workIndex > #self.workQueue then
      if self.pendingIndex > #self.pending then break end
      local want = self.pending[self.pendingIndex]
      self.pendingIndex = self.pendingIndex + 1
      self.workQueue, self.workIndex = self.world:stackChunkJobs(
        self.centreFace, want.column, want.row), 1
    else
      local job = self.workQueue[self.workIndex]
      self.workIndex = self.workIndex + 1
      if self.world:generateChunk(job) then generated = generated + 1 end
    end
  end

  -- Mesh anything new or changed, on the same clock.
  local meshedThisFrame = 0
  for key in pairs(self.dirty) do
    if self.clock() >= deadline then break end
    self.dirty[key] = nil
    local entry = self.world.chunks[key]
    if entry then
      local vertices, leaves = self:meshChunk(entry)
      self.upload(key, vertices, leaves)
      self.meshed[key] = #vertices > 0 or #leaves > 0
    elseif self.meshed[key] then
      self.release(key)
      self.meshed[key] = nil
    end
    meshedThisFrame = meshedThisFrame + 1
  end
  for key, entry in pairs(self.world.chunks) do
    if self.clock() >= deadline then break end
    if self.meshed[key] == nil then
      local vertices, leaves = self:meshChunk(entry)
      self.upload(key, vertices, leaves)
      self.meshed[key] = #vertices > 0 or #leaves > 0
      meshedThisFrame = meshedThisFrame + 1
    end
  end

  return generated, meshedThisFrame
end

-- True once the ring around the player is loaded, so spawn can wait for ground.
function GridRuntime:ready()
  return self.pendingIndex > #self.pending and self.workIndex > #self.workQueue
end

function GridRuntime:setBlock(face, column, row, layer, id)
  local touched = self.world:setBlockAtVoxel(face, column, row, layer, id)
  if not touched then return false end
  for key in pairs(touched) do self.dirty[key] = true end
  return true
end

GridRuntime.CHUNK = CHUNK

return GridRuntime
