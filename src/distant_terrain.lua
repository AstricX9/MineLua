local ffi = require("ffi")
local blocks = require("blocks")
local math3d = require("math3d")
local terrain = require("terrain")

local DistantTerrain = {}
DistantTerrain.__index = DistantTerrain
local CACHE_MAGIC = "MLDT1\n"

local function appendVertex(verts, p, normal, color, uv)
  verts[#verts + 1] = p[1]
  verts[#verts + 1] = p[2]
  verts[#verts + 1] = p[3]
  verts[#verts + 1] = normal[1]
  verts[#verts + 1] = normal[2]
  verts[#verts + 1] = normal[3]
  verts[#verts + 1] = color[1]
  verts[#verts + 1] = color[2]
  verts[#verts + 1] = color[3]
  verts[#verts + 1] = uv[1]
  verts[#verts + 1] = uv[2]
end

local function normalFor(a, b, c)
  local ab = {b[1] - a[1], b[2] - a[2], b[3] - a[3]}
  local ac = {c[1] - a[1], c[2] - a[2], c[3] - a[3]}
  return math3d.normalize(math3d.cross(ab, ac))
end

local function appendTriangle(verts, a, b, c, color, uvA, uvB, uvC)
  local normal = normalFor(a, b, c)
  appendVertex(verts, a, normal, color, uvA)
  appendVertex(verts, b, normal, color, uvB)
  appendVertex(verts, c, normal, color, uvC)
end

local function ensureDirectory(path)
  if not path or path == "" then
    return
  end

  os.execute('mkdir "' .. path .. '" >NUL 2>NUL')
end

local function fileExists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end

  return false
end

local function defaultRings(activeRadius, visualDistance)
  local inner = activeRadius * 16 + 16
  local far = visualDistance or 4096.0
  return {
    {name = "near_lod", tileSize = 64, step = 4, innerRadius = inner, outerRadius = math.min(256.0, far)},
    {name = "mid_lod", tileSize = 128, step = 8, innerRadius = 256.0, outerRadius = math.min(768.0, far)},
    {name = "far_lod", tileSize = 256, step = 16, innerRadius = 768.0, outerRadius = math.min(2048.0, far)},
    {name = "horizon_lod", tileSize = 512, step = 32, innerRadius = 2048.0, outerRadius = far}
  }
end

function DistantTerrain.new(options)
  options = options or {}

  return setmetatable({
    maxHeight = options.maxHeight or 16,
    waterLevel = options.waterLevel or 8.5,
    cacheDir = options.cacheDir or "world_cache/distant_lod",
    cacheEnabled = options.cacheEnabled ~= false,
    rings = options.rings or defaultRings(options.activeChunkRadius or 4, options.visualDistance),
    tiles = {},
    visible = {}
  }, DistantTerrain)
end

function DistantTerrain:tileKey(ring, tileX, tileZ)
  return ring.name .. ":" .. tileX .. "," .. tileZ
end

function DistantTerrain:tilePath(ring, tileX, tileZ)
  return self.cacheDir .. "/" .. ring.name .. "_" .. tileX .. "_" .. tileZ .. ".mlod"
end

function DistantTerrain:saveTile(path, vertices)
  if not self.cacheEnabled then
    return
  end

  ensureDirectory(self.cacheDir)

  local count = #vertices
  local data = ffi.new("float[?]", count, vertices)
  local file = io.open(path, "wb")
  if not file then
    return
  end

  file:write(CACHE_MAGIC)
  file:write(tostring(count))
  file:write("\n")
  file:write(ffi.string(ffi.cast("const char*", data), count * 4))
  file:close()
end

function DistantTerrain:loadTile(path)
  if not self.cacheEnabled or not fileExists(path) then
    return nil
  end

  local file = io.open(path, "rb")
  if not file then
    return nil
  end

  local magic = file:read(#CACHE_MAGIC)
  local count = tonumber(file:read("*l"))
  if magic ~= CACHE_MAGIC or not count then
    file:close()
    return nil
  end

  local bytes = file:read(count * 4)
  file:close()
  if not bytes or #bytes ~= count * 4 then
    return nil
  end

  local data = ffi.new("float[?]", count)
  ffi.copy(data, bytes, #bytes)
  local vertices = {}
  for i = 0, count - 1 do
    vertices[i + 1] = tonumber(data[i])
  end

  return vertices
end

function DistantTerrain:meshTile(ring, tileX, tileZ)
  local verts = {}
  local grass = blocks.list[blocks.grass] or blocks.list[1]
  local color = grass and grass.colors and grass.colors.top or {0.55, 0.72, 0.48}
  local uv = grass and grass.uvs and grass.uvs.top or {u0 = 0.0, v0 = 0.0, u1 = 1.0, v1 = 1.0}
  local x0 = tileX * ring.tileSize
  local z0 = tileZ * ring.tileSize
  local x1 = x0 + ring.tileSize
  local z1 = z0 + ring.tileSize
  local step = ring.step

  local function surfaceY(x, z)
    return terrain.heightAt(x, z, self.maxHeight) + 1.0
  end

  for x = x0, x1 - step, step do
    for z = z0, z1 - step, step do
      local p00 = {x, surfaceY(x, z), z}
      local p10 = {x + step, surfaceY(x + step, z), z}
      local p11 = {x + step, surfaceY(x + step, z + step), z + step}
      local p01 = {x, surfaceY(x, z + step), z + step}

      appendTriangle(verts, p01, p11, p10, color, {uv.u0, uv.v0}, {uv.u1, uv.v0}, {uv.u1, uv.v1})
      appendTriangle(verts, p10, p00, p01, color, {uv.u1, uv.v1}, {uv.u0, uv.v1}, {uv.u0, uv.v0})
    end
  end

  return verts
end

function DistantTerrain:ensureAround(playerX, playerZ)
  local added = {}
  self.visible = {}

  for _, ring in ipairs(self.rings) do
    local minTileX = math.floor((playerX - ring.outerRadius) / ring.tileSize)
    local maxTileX = math.floor((playerX + ring.outerRadius) / ring.tileSize)
    local minTileZ = math.floor((playerZ - ring.outerRadius) / ring.tileSize)
    local maxTileZ = math.floor((playerZ + ring.outerRadius) / ring.tileSize)

    for tileX = minTileX, maxTileX do
      for tileZ = minTileZ, maxTileZ do
        local centerX = tileX * ring.tileSize + ring.tileSize * 0.5
        local centerZ = tileZ * ring.tileSize + ring.tileSize * 0.5
        local dx = centerX - playerX
        local dz = centerZ - playerZ
        local distance = math.sqrt(dx * dx + dz * dz)

        if distance >= ring.innerRadius and distance <= ring.outerRadius then
          local key = self:tileKey(ring, tileX, tileZ)
          local tile = self.tiles[key]
          if not tile then
            local path = self:tilePath(ring, tileX, tileZ)
            local vertices = self:loadTile(path)
            local wasCached = vertices ~= nil
            if not vertices then
              vertices = self:meshTile(ring, tileX, tileZ)
              self:saveTile(path, vertices)
            end

            tile = {
              key = key,
              ring = ring.name,
              tileX = tileX,
              tileZ = tileZ,
              cached = wasCached,
              path = path,
              vertices = vertices
            }
            self.tiles[key] = tile
            added[#added + 1] = tile
          end

          self.visible[#self.visible + 1] = key
        end
      end
    end
  end

  return added
end

return DistantTerrain
