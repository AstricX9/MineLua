package.path = "src/?.lua;src/?/init.lua;" .. package.path

local terrain = require("terrain")

for _, seed in ipairs({1, 2, 7, 42, 9999}) do
  terrain.setSeed(seed)
  local x, z, column = terrain.findSafeSpawn(16, 16, 127)
  assert(column and not column.waterLevel,
    string.format("seed %d selected a submerged spawn at %.1f, %.1f", seed, x, z))
  assert(column.biome ~= "ocean",
    string.format("seed %d selected an ocean spawn at %.1f, %.1f", seed, x, z))
end

print("dry spawn tests passed")
