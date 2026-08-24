package.path="src/?.lua;"..package.path

local blocks=require("blocks")
local FallingTrees=require("falling_trees")
local cells={}
local function key(x,y,z) return x..":"..y..":"..z end
local world={}
function world:blockAt(x,y,z) return cells[key(x,y,z)] or blocks.air end
function world:setBlock(x,y,z,id) cells[key(x,y,z)]=id end

for y=1,3 do world:setBlock(0,y,0,blocks.oak_log) end
world:setBlock(1,3,0,blocks.oak_leaves)
world:setBlock(-1,3,0,blocks.oak_leaves)

local manager=FallingTrees.new()
local tree,changed=manager:start(world,0,1,0,{1,0,0})
assert(tree and tree.logCount==3,"breaking one trunk block should capture the connected tree")
assert(#changed>=5,"the falling object should include its attached crown")
assert(world:blockAt(0,2,0)==blocks.air and world:blockAt(1,3,0)==blocks.air,
  "captured tree blocks should leave the voxel world immediately")
local midway=manager:model(tree)
assert(midway[13]==.5 and midway[14]==1 and midway[15]==.5,"the fall must rotate around the cut block's base")
local completed=manager:update(2)
assert(#completed==1 and #manager.trees==0,"the visual tree should finish as one object")
print("falling tree tests passed")
