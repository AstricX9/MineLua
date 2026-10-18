package.path = "src/?.lua;" .. package.path

local uv = {u0 = 0.0, v0 = 0.0, u1 = 1.0, v1 = 1.0}
local function definition(properties)
  return {
    properties = properties,
    uvs = {top = uv, bottom = uv, side = uv},
    colors = {
      top = {1.0, 1.0, 1.0},
      bottom = {1.0, 1.0, 1.0},
      side = {1.0, 1.0, 1.0}
    }
  }
end

package.loaded.blocks = {
  list = {
    [0] = definition({solid = false}),
    [1] = definition({solid = true}),
    [2] = definition({solid = true, ice = true}),
    [3] = definition({solid = true, glass = true})
  }
}
package.loaded.terrain = {grassColorAt = function() return {1.0, 1.0, 1.0} end}

local voxel = require("voxel")
local blocksAt = {
  ["0,1,0"] = 1,
  ["2,1,0"] = 2,
  ["4,1,0"] = 3
}
local function blockAt(x, y, z) return blocksAt[x .. "," .. y .. "," .. z] or 0 end
local chunk = {}
function chunk:getBlock(x, y, z) return blockAt(x, y, z) end
function chunk:getSkyLight() return 15 end

local opaque, dielectric = voxel.meshChunk(chunk, 2, 0, 0, {
  blockAt = blockAt,
  skyLightAt = function() return 15 end
})

local stride = voxel.STRIDE_FLOATS
assert(#opaque / stride == 36, "the opaque block remains in the opaque mesh")
assert(#dielectric / stride == 72, "ice and glass move to the dielectric mesh")

local materials = {}
for index = 12, #dielectric, stride do materials[dielectric[index]] = true end
assert(materials[3.0], "ice carries the physical ice material id")
assert(materials[4.0], "glass carries the physical glass material id")

print("dielectric meshing tests passed")
