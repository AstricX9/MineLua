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

local function blockAt(world, x, y, z)
  if y < 0 or y > world.maxHeight then
    return nil
  end
  return world:blockAt(x, y, z)
end

local function setSkyLight(world, x, y, z, level)
  local entry = world:getChunkAtBlock(x, z)
  if not entry or y < 0 or y > world.maxHeight then
    return false
  end

  local lx, lz = world:localBlockCoord(x, z)
  local old = entry.chunk:getSkyLight(lx, y, lz)
  if level <= old then
    return false
  end

  entry.chunk:setSkyLight(lx, y, lz, level)
  return true
end

function lighting.rebuild(world, options)
  options = options or {}
  local step = options.yieldStep
  local queue = {}
  local head = 1

  world:eachChunk(function(chunk)
    chunk:clearSkyLight()
  end)

  world:eachChunk(function(chunk, entry)
    for lx = 0, 15 do
      for lz = 0, 15 do
        local wx = entry.offsetX + lx
        local wz = entry.offsetZ + lz
        local level = 15

        for y = world.maxHeight, 0, -1 do
          local transparent, loss = transmission(chunk:getBlock(lx, y, lz))
          if transparent and level > 0 then
            chunk:setSkyLight(lx, y, lz, level)
            queue[#queue + 1] = {wx, y, wz, level}
            level = math.max(0, level - loss)
          else
            level = 0
            chunk:setSkyLight(lx, y, lz, 0)
          end
        end
      end
      if step then step() end
    end
  end)

  while head <= #queue do
    local item = queue[head]
    head = head + 1
    local light = item[4]

    if light > 1 then
      for i = 1, #NEIGHBORS do
        local n = NEIGHBORS[i]
        local nx, ny, nz = item[1] + n[1], item[2] + n[2], item[3] + n[3]
        local id = blockAt(world, nx, ny, nz)
        if id ~= nil then
          local transparent, loss = transmission(id)
          if transparent then
            local nextLight = light - math.max(1, loss)
            if nextLight > 0 and setSkyLight(world, nx, ny, nz, nextLight) then
              queue[#queue + 1] = {nx, ny, nz, nextLight}
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

return lighting
