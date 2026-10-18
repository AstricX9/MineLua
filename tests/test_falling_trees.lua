package.path="src/?.lua;"..package.path

local blocks=require("blocks")
local FallingTrees=require("falling_trees")
local TERRAIN_STRIDE=require("voxel").STRIDE_FLOATS
assert(FallingTrees.isLog(blocks.list[blocks.ceiba_log_alive]) and
    FallingTrees.isLog(blocks.list[blocks.ceiba_log_alive_x]) and
    not FallingTrees.isLog(blocks.list[blocks.ceiba_log]),
  "only living generated trunks participate in whole-tree felling")
local testUv={u0=0,v0=0,u1=1,v1=1}
for _,id in ipairs({blocks.oak_log_alive,blocks.oak_log,blocks.oak_leaves,blocks.oak_stump}) do
  blocks.list[id].uvs={top=testUv,bottom=testUv,side=testUv}
end
local cells={}
local function key(x,y,z) return x..":"..y..":"..z end
local world={}
function world:blockAt(x,y,z) return cells[key(x,y,z)] or blocks.air end
function world:setBlock(x,y,z,id) cells[key(x,y,z)]=id end

for y=1,3 do world:setBlock(0,y,0,blocks.oak_log_alive) end
world:setBlock(1,3,0,blocks.oak_leaves)
world:setBlock(-1,3,0,blocks.oak_leaves)

local randomValues={0.5,0.5}
local manager=FallingTrees.new(function() return table.remove(randomValues,1) end)
local tree,changed=manager:start(world,0,1,0,{1,0,0})
assert(tree and tree.logCount==3,"breaking one trunk block should capture the connected tree")
assert(tree.drop=="oak_log","a felled living trunk should become ordinary dead logs")
assert(#changed>=5,"the falling object should include its attached crown")
assert(world:blockAt(0,2,0)==blocks.air and world:blockAt(1,3,0)==blocks.air,
  "captured tree blocks should leave the voxel world immediately")
local midway=manager:model(tree)
assert(midway[13]==.5 and midway[14]==1.32 and midway[15]==.5,
  "the fall must rotate around the randomized chop point")
local stumpId=world:blockAt(0,1,0)
local stump=blocks.list[stumpId]
local Mining=require("mining")
assert(stumpId==blocks.oak_stump and stump.properties.collisionHeight==0.32 and
    stump.properties.drop=="oak_log" and not FallingTrees.isLog(stump),
  "the cut should leave a collidable, axe-removable stump voxel")
local stumpDrop=Mining.drop(stump,"stone_axe")
assert(Mining.canHarvest(stump,"stone_axe") and stumpDrop and stumpDrop.item=="oak_log",
  "chopping the stump should remove it and recover the remaining log")
local Chunk=require("chunk")
local voxel=require("voxel")
local stumpChunk=Chunk.new()
stumpChunk:setBlock(0,1,0,stumpId)
local stumpVertices=voxel.meshChunk(stumpChunk,2,0,0)
local stumpMaxY=-math.huge
for index=2,#stumpVertices,TERRAIN_STRIDE do stumpMaxY=math.max(stumpMaxY,stumpVertices[index]) end
assert(math.abs(stumpMaxY-1.32)<0.00001,
  "the terrain mesher should draw the stump at its collision height")

local function near(actual,expected) return math.abs(actual-expected)<0.00001 end
assert(near(tree.chopHeight,0.32),"the falling mesh should start at the stump height")
assert(#tree.vertices>0 and #tree.leafVertices>0,
  "the falling trunk and crown should use separate meshes")
local upperMinY=math.huge
for index=2,#tree.vertices,TERRAIN_STRIDE do upperMinY=math.min(upperMinY,tree.vertices[index]) end
assert(near(upperMinY,0),"the falling mesh should begin exactly at the cut surface")
local expected={{0.000,0.0,0.0,0.000},{0.300,0.8,0.2,0.000},
  {0.600,2.2,0.4,0.000},{0.900,5.5,0.7,0.000},{1.170,12.0,1.0,0.000},
  {1.400,23.0,1.2,0.000},{1.590,39.0,1.3,0.000},{1.740,58.0,1.1,0.000},
  {1.850,76.0,0.7,0.000},{1.920,88.0,0.2,-0.030},
  {1.970,90.0,0.0,-0.100},{2.070,86.5,-0.2,0.045},
  {2.170,90.8,0.1,-0.018},{2.290,90.0,0.0,0.000}}
for _,frame in ipairs(expected) do
  tree.age=frame[1]*tree.timeScale
  local pose=manager:pose(tree)
  assert(near(pose.pitch,frame[2]) and near(pose.yaw,0) and
      near(pose.roll,frame[3]) and near(pose.y,frame[4]),
    "tree pose should match its authored keyframe at "..frame[1].." seconds")
end
tree.leavesDetached=nil
tree.age=(FallingTrees.LEAF_RELEASE_TIME-0.01)*tree.timeScale
local notFinished,releaseImpacts,detachedLeaves=manager:update(0.02*tree.timeScale)
assert(#notFinished==0 and #releaseImpacts==1 and releaseImpacts[1]==tree and
    #detachedLeaves==1 and detachedLeaves[1]==tree and tree.leavesDetached,
  "the crown should detach once on the trunk's first-contact frame")
local leafDrops=manager:leafDrops(tree,24)
local droppedLeafCount=0
for _,drop in ipairs(leafDrops) do
  assert(drop.item=="oak_leaves" and drop.count>=1 and #drop.position==3,
    "detached leaves should turn into collectible leaf-block item stacks")
  droppedLeafCount=droppedLeafCount+drop.count
end
assert(droppedLeafCount==#tree.leaves,
  "detaching the crown should preserve every captured leaf as an item")
tree.impacted=nil
tree.age=(FallingTrees.IMPACT_TIME-0.01)*tree.timeScale
local notDone,impacts=manager:update(0.02*tree.timeScale)
assert(#notDone==0 and #impacts==1 and impacts[1]==tree,
  "the crash event should fire at first ground contact, before the rebound settles")

-- Chopping above the root leaves lower trunk blocks in the voxel world instead
-- of attaching them to the rotating crown.
local highCells={}
local highWorld={}
function highWorld:blockAt(x,y,z) return highCells[key(x,y,z)] or blocks.air end
function highWorld:setBlock(x,y,z,id) highCells[key(x,y,z)]=id end
for y=1,4 do highWorld:setBlock(0,y,0,blocks.oak_log_alive) end
local highRandom={0.5,0.5}
local highManager=FallingTrees.new(function() return table.remove(highRandom,1) end)
local highTree=highManager:start(highWorld,0,2,0,{1,0,0})
assert(highTree and highTree.logCount==3,"only the trunk at and above the chop should fall")
assert(highWorld:blockAt(0,1,0)==blocks.oak_log_alive and highWorld:blockAt(0,2,0)==blocks.oak_stump,
  "the trunk below the chop plane must remain in the world")
assert(tree.duration>2.5 and highTree.timeScale>=tree.timeScale,
  "the fall should linger and heavier trunks should never animate faster")
assert(near(tree.secondsToImpact,FallingTrees.IMPACT_TIME*tree.timeScale) and
    near(tree.impactPosition[1],tree.pivot[1]+tree.direction[1]*tree.fallLength*.55),
  "each tree should expose its geometry-derived ground-contact timing and position")
local naturalScale=math.min(1.35,
  math.max(0.95,0.82+math.sqrt(math.max(1,tree.fallLength))*.12))
assert(near(tree.secondsToImpact,
    FallingTrees.IMPACT_TIME*naturalScale+FallingTrees.EXTRA_FALL_SECONDS),
  "the authored tree fall should add three seconds before ground contact")
local completed=manager:update(tree.duration-tree.age+0.01)
assert(#completed==1 and #manager.trees==0,"the visual tree should finish as one object")
local dropPosition=manager:dropPosition(completed[1])
assert(#dropPosition==3 and dropPosition[1]==dropPosition[1] and
    dropPosition[2]==dropPosition[2] and dropPosition[3]==dropPosition[3],
  "the landed tree should expose a finite animated position for its log drop")
local settled=manager:settle(world,completed[1])
assert(#settled.logs==tree.logCount and settled.leaves==nil,
  "only the trunk should settle into the voxel world after the crown detaches")
for _,placed in ipairs(settled.logs) do
  local definition=blocks.list[world:blockAt(placed.x,placed.y,placed.z)]
  assert(definition.properties.logAxis=="x" and definition.properties.drop=="oak_log",
    "the fallen trunk should become horizontal, individually harvestable log blocks")
  local retry=manager:start(world,placed.x,placed.y,placed.z,{1,0,0})
  assert(retry==nil,"chopping a settled log must not trigger another whole-tree fall")
end

local structureCells={}
local structureWorld={}
function structureWorld:blockAt(x,y,z) return structureCells[key(x,y,z)] or blocks.air end
function structureWorld:setBlock(x,y,z,id) structureCells[key(x,y,z)]=id end
for y=1,4 do structureWorld:setBlock(0,y,0,blocks.oak_log) end
local structureManager=FallingTrees.new(function() return 0.5 end)
local structureTree,structureChanged=structureManager:start(structureWorld,0,1,0,{1,0,0})
assert(not structureTree and #structureChanged==0 and
    structureWorld:blockAt(0,2,0)==blocks.oak_log,
  "ordinary vertical logs in houses and player builds must never become falling trees")
print("falling tree tests passed")
