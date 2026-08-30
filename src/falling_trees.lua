local blocks = require("blocks")

local FallingTrees={}
FallingTrees.__index=FallingTrees

FallingTrees.CHOP_HEIGHT_MIN=0.27
FallingTrees.CHOP_HEIGHT_MAX=0.37
FallingTrees.FALL_DIRECTION_SPREAD=math.rad(8)
FallingTrees.LANDING_HOLD=0.24
FallingTrees.IMPACT_TIME=1.970
FallingTrees.EXTRA_FALL_SECONDS=3.0
-- Keep the crown attached for the whole fall. Releasing it at the old 58-degree
-- keyframe made a healthy tree turn into a bare trunk well before it landed.
FallingTrees.LEAF_RELEASE_TIME=FallingTrees.IMPACT_TIME
FallingTrees.KEYFRAMES={
  {time=0.000,pitch=0.0, yaw=0.0,roll=0.0,x=0.00,y=0.00},
  {time=0.300,pitch=0.8, yaw=0.0,roll=0.2,x=0.00,y=0.00},
  {time=0.600,pitch=2.2, yaw=0.0,roll=0.4,x=0.00,y=0.00},
  {time=0.900,pitch=5.5, yaw=0.0,roll=0.7,x=0.00,y=0.00},
  {time=1.170,pitch=12.0,yaw=0.0,roll=1.0,x=0.00,y=0.00},
  {time=1.400,pitch=23.0,yaw=0.0,roll=1.2,x=0.00,y=0.00},
  {time=1.590,pitch=39.0,yaw=0.0,roll=1.3,x=0.00,y=0.00},
  {time=1.740,pitch=58.0,yaw=0.0,roll=1.1,x=0.00,y=0.00},
  {time=1.850,pitch=76.0,yaw=0.0,roll=0.7,x=0.00,y=0.00},
  {time=1.920,pitch=88.0,yaw=0.0,roll=0.2,x=0.00,y=-0.03},
  {time=1.970,pitch=90.0,yaw=0.0,roll=0.0,x=0.00,y=-0.10},
  {time=2.070,pitch=86.5,yaw=0.0,roll=-0.2,x=0.00,y=0.045},
  {time=2.170,pitch=90.8,yaw=0.0,roll=0.1,x=0.00,y=-0.018},
  {time=2.290,pitch=90.0,yaw=0.0,roll=0.0,x=0.00,y=0.00}
}

local LEAVES={oak_leaves=true,spruce_leaves=true}
local MAX_CONNECTED_LOGS=2048
local CHOP_HEIGHTS={0.27,0.32,0.37}
local STUMP_VARIANTS={
  oak_log={"oak_stump_low","oak_stump","oak_stump_high"},
  oak_log_x={"oak_stump_low","oak_stump","oak_stump_high"},
  oak_log_z={"oak_stump_low","oak_stump","oak_stump_high"},
  spruce_log={"spruce_stump_low","spruce_stump","spruce_stump_high"},
  spruce_log_x={"spruce_stump_low","spruce_stump","spruce_stump_high"},
  spruce_log_z={"spruce_stump_low","spruce_stump","spruce_stump_high"}
}
local DIRS={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
local FACES={
  {{1,0,1},{1,0,0},{1,1,0},{1,1,1},1,0,0,"side"},
  {{0,0,0},{0,0,1},{0,1,1},{0,1,0},-1,0,0,"side"},
  {{0,1,1},{1,1,1},{1,1,0},{0,1,0},0,1,0,"top"},
  {{0,0,0},{1,0,0},{1,0,1},{0,0,1},0,-1,0,"bottom"},
  {{0,0,1},{1,0,1},{1,1,1},{0,1,1},0,0,1,"side"},
  {{1,0,0},{0,0,0},{0,1,0},{1,1,0},0,0,-1,"side"}
}
local ORDER={1,2,3,3,4,1}
local UV={{0,1},{1,1},{1,0},{0,0}}

local function key(x,y,z) return x..":"..y..":"..z end
local function isTreeLog(definition)
  local properties=definition and definition.properties or {}
  return definition and properties.aliveTree==true or false
end
function FallingTrees.isLog(definition) return isTreeLog(definition) end

local function deadLogKey(definition)
  local properties=definition and definition.properties or {}
  return properties.drop or (definition and definition.key) or nil
end

local function connectedLogs(world,x,y,z,minY)
  local result,seen,queue={}, {}, {{x=x,y=y,z=z}}
  seen[key(x,y,z)]=true
  local head=1
  while head<=#queue and #result<MAX_CONNECTED_LOGS do
    local p=queue[head] head=head+1
    local def=blocks.list[world:blockAt(p.x,p.y,p.z)]
    if isTreeLog(def) then
      result[#result+1]={x=p.x,y=p.y,z=p.z,id=def.id,key=def.key}
      for _,d in ipairs(DIRS) do
        local nx,ny,nz=p.x+d[1],p.y+d[2],p.z+d[3]
        local k=key(nx,ny,nz)
        if ny>=minY and not seen[k] then seen[k]=true queue[#queue+1]={x=nx,y=ny,z=nz} end
      end
    end
  end
  return result
end

local function attachedLeaves(world,logs,occupied,minY)
  local result={}
  for _,log in ipairs(logs) do
    local radius=(log.key:match("^ceiba_") and 9) or
      ((log.key:match("^spruce_") or log.key:match("^jungle_")) and 7) or 5
    for dx=-radius,radius do for dy=-radius,radius do for dz=-radius,radius do
      local x,y,z=log.x+dx,log.y+dy,log.z+dz
      local k=key(x,y,z)
      if y>=minY and not occupied[k] then
        local def=blocks.list[world:blockAt(x,y,z)]
        if def and (LEAVES[def.key] or (def.properties and def.properties.leaves)) then
          occupied[k]=true result[#result+1]={x=x,y=y,z=z,id=def.id,key=def.key}
        end
      end
    end end end
  end
  return result
end

local function appendVertex(out,p,n,c,u,v,material)
  local values={p[1],p[2],p[3],n[1],n[2],n[3],c[1],c[2],c[3],u,v,
    material,0,1,0,0,0,1}
  for i=1,#values do out[#out+1]=values[i] end
end

local function buildVertices(captured,pivot,yBounds)
  local occupied={} for _,p in ipairs(captured) do occupied[key(p.x,p.y,p.z)]=true end
  local out={}
  for _,p in ipairs(captured) do
    local y0,y1=0,1
    if yBounds then y0,y1=yBounds(p) end
    local def=blocks.list[p.id]
    local props=def.properties or {}
    local material=props.leaves and 1 or 0
    local colors=def.colors or {}
    for _,f in ipairs(FACES) do
      if not occupied[key(p.x+f[5],p.y+f[6],p.z+f[7])] then
        local faceName=f[8]
        local uv=def.uvs and (def.uvs[faceName] or def.uvs.side or def.uvs.top)
        if uv then
          local color=def.biomeTint and def.color or colors[faceName] or def.color or {1,1,1}
          for _,ci in ipairs(ORDER) do
            local c=f[ci] local t=UV[ci]
            local localY=c[2]==0 and y0 or y1
            local u=t[1]==0 and uv.u0 or uv.u1
            local v=t[2]==0 and uv.v0 or uv.v1
            if faceName=="side" then v=uv.v0+(1-localY)*(uv.v1-uv.v0) end
            appendVertex(out,{p.x+c[1]-pivot[1],p.y+localY-pivot[2],p.z+c[3]-pivot[3]},
              {f[5],f[6],f[7]},color,u,v,material)
          end
        end
      end
    end
  end
  return out
end

function FallingTrees.new(random)
  return setmetatable({trees={},nextId=1,random=random or math.random},FallingTrees)
end

function FallingTrees:start(world,x,y,z,direction)
  local cutDefinition=blocks.list[world:blockAt(x,y,z)]
  if not isTreeLog(cutDefinition) then return nil,{} end
  local logs=connectedLogs(world,x,y,z,y)
  if #logs<2 then return nil,{} end
  local occupied={} for _,p in ipairs(logs) do occupied[key(p.x,p.y,p.z)]=true end
  local leaves=attachedLeaves(world,logs,occupied,y)
  local captured={} for _,p in ipairs(logs) do captured[#captured+1]=p end
  for _,p in ipairs(leaves) do captured[#captured+1]=p end
  local chopIndex=math.min(#CHOP_HEIGHTS,math.floor(self.random()*#CHOP_HEIGHTS)+1)
  local chopHeight=CHOP_HEIGHTS[chopIndex]
  local pivot={x+.5,y+chopHeight,z+.5}
  local dx,dz=(direction and direction[1] or 1),(direction and direction[3] or 0)
  local length=math.sqrt(dx*dx+dz*dz) if length<.001 then dx,dz,length=1,0,1 end
  dx,dz=dx/length,dz/length
  local spread=(self.random()*2-1)*FallingTrees.FALL_DIRECTION_SPREAD
  local spreadSin,spreadCos=math.sin(spread),math.cos(spread)
  dx,dz=dx*spreadCos-dz*spreadSin,dx*spreadSin+dz*spreadCos
  local upperBounds=function(p)
    return p.x==x and p.y==y and p.z==z and chopHeight or 0,1
  end
  local animationDuration=FallingTrees.KEYFRAMES[#FallingTrees.KEYFRAMES].time
  local highestLogY=y
  for _,log in ipairs(logs) do highestLogY=math.max(highestLogY,log.y) end
  local fallLength=highestLogY+1-pivot[2]
  -- A longer lever takes longer to sweep its crown to the ground. Deriving the
  -- scale from actual trunk reach also gives the audio engine a real contact
  -- time instead of treating every species and sapling as the same animation.
  local naturalScale=math.min(1.35,
    math.max(0.95,0.82+math.sqrt(math.max(1,fallLength))*.12))
  local naturalImpactSeconds=FallingTrees.IMPACT_TIME*naturalScale
  local secondsToImpact=naturalImpactSeconds+FallingTrees.EXTRA_FALL_SECONDS
  local timeScale=secondsToImpact/FallingTrees.IMPACT_TIME
  local landingDistance=fallLength*.55
  local dropKey=deadLogKey(blocks.list[logs[1].id])
  local entity={id=self.nextId,age=0,animationDuration=animationDuration,
    timeScale=timeScale,duration=animationDuration*timeScale+FallingTrees.LANDING_HOLD,
    pivot=pivot,direction={dx,0,dz},chopHeight=chopHeight,
    cut={x=x,y=y,z=z},fallLength=fallLength,secondsToImpact=secondsToImpact,
    impactPosition={pivot[1]+dx*landingDistance,pivot[2]+.3,pivot[3]+dz*landingDistance},
    blocks=captured,logs=logs,leaves=leaves,logCount=#logs,
    drop=dropKey,
    vertices=buildVertices(logs,pivot,upperBounds),
    leafVertices=buildVertices(leaves,pivot)}
  self.nextId=self.nextId+1 self.trees[#self.trees+1]=entity
  local variants=STUMP_VARIANTS[dropKey]
  local stumpKey=variants and variants[chopIndex]
  local stumpId=stumpKey and blocks[stumpKey]
  for _,p in ipairs(captured) do
    local replacement=p.x==x and p.y==y and p.z==z and (stumpId or blocks.air or 0) or (blocks.air or 0)
    world:setBlock(p.x,p.y,p.z,replacement)
  end
  return entity,captured
end

function FallingTrees:update(dt)
  local completed,impacts,detachedLeaves={},{},{}
  for i=#self.trees,1,-1 do
    local tree=self.trees[i]
    local previousAge=tree.age
    tree.age=tree.age+math.max(0,dt or 0)
    local leafReleaseAge=FallingTrees.LEAF_RELEASE_TIME*(tree.timeScale or 1)
    if not tree.leavesDetached and #tree.leaves>0 and
        previousAge<leafReleaseAge and tree.age>=leafReleaseAge then
      tree.leavesDetached=true detachedLeaves[#detachedLeaves+1]=tree
    end
    local impactAge=FallingTrees.IMPACT_TIME*(tree.timeScale or 1)
    if not tree.impacted and previousAge<impactAge and tree.age>=impactAge then
      tree.impacted=true impacts[#impacts+1]=tree
    end
    if tree.age>=tree.duration then completed[#completed+1]=tree table.remove(self.trees,i) end
  end
  return completed,impacts,detachedLeaves
end

local axisRotation

local function cardinalDirection(tree)
  local dx,dz=tree.direction[1],tree.direction[3]
  if math.abs(dx)>=math.abs(dz) then return dx>=0 and 1 or -1,0,"x" end
  return 0,dz>=0 and 1 or -1,"z"
end

local function transformedCell(tree,p,rotation)
  local lx=p.x+.5-tree.pivot[1]
  local ly=p.y+.5-tree.pivot[2]
  local lz=p.z+.5-tree.pivot[3]
  return math.floor(tree.pivot[1]+rotation[1]*lx+rotation[2]*ly+rotation[3]*lz),
    math.floor(tree.pivot[2]+rotation[4]*lx+rotation[5]*ly+rotation[6]*lz),
    math.floor(tree.pivot[3]+rotation[7]*lx+rotation[8]*ly+rotation[9]*lz)
end

local function replaceable(world,x,y,z,allowLeaves)
  local id=world:blockAt(x,y,z)
  if id==blocks.air then return true end
  local definition=id and blocks.list[id]
  return allowLeaves and definition and definition.properties and definition.properties.leaves or false
end

-- Once the animated object has stopped moving, turn its two materials back into
-- voxel-world blocks. The trunk is kept as horizontal log blocks so it remains
-- solid, raycastable and individually chop-able; foliage is resolved afterwards
-- and can move upward independently when the crown lands against the ground.
function FallingTrees:settle(world,tree)
  local sx,sz,axis=cardinalDirection(tree)
  local rotation=axisRotation(sz,0,-sx,math.pi*.5)
  local base=tree.logs[1]
  for _,log in ipairs(tree.logs) do
    if log.x==tree.cut.x and log.y==tree.cut.y and log.z==tree.cut.z then base=log break end
  end
  local baseX,baseY,baseZ=transformedCell(tree,base,rotation)
  local offsetX=tree.cut.x+sx-baseX
  local offsetY=tree.cut.y-baseY
  local offsetZ=tree.cut.z+sz-baseZ
  local logTargets={}
  for _,log in ipairs(tree.logs) do
    local x,y,z=transformedCell(tree,log,rotation)
    logTargets[#logTargets+1]={x=x+offsetX,y=y+offsetY,z=z+offsetZ,source=log}
  end

  -- A single lift keeps the trunk connected when it comes down across a rock or
  -- uneven ground, instead of scattering its segments up separate columns.
  local lift=0
  while lift<8 do
    local clear=true
    for _,target in ipairs(logTargets) do
      if not replaceable(world,target.x,target.y+lift,target.z,true) then clear=false break end
    end
    if clear then break end
    lift=lift+1
  end

  local result={logs={},changed={}}
  local occupied={}
  for _,target in ipairs(logTargets) do
    local x,y,z=target.x,target.y+lift,target.z
    local sourceKey=deadLogKey(blocks.list[target.source.id])
    local id=blocks[sourceKey.."_"..axis] or blocks[sourceKey] or target.source.id
    if replaceable(world,x,y,z,true) then
      world:setBlock(x,y,z,id)
      local placed={x=x,y=y,z=z,id=id}
      result.logs[#result.logs+1]=placed result.changed[#result.changed+1]=placed
      occupied[key(x,y,z)]=true
    end
  end

  return result
end

local function poseAt(age)
  local frames=FallingTrees.KEYFRAMES
  if age<=frames[1].time then return frames[1] end
  for i=2,#frames do
    local b=frames[i]
    if age<=b.time then
      local a=frames[i-1]
      local t=(age-a.time)/(b.time-a.time)
      return {pitch=a.pitch+(b.pitch-a.pitch)*t,yaw=a.yaw+(b.yaw-a.yaw)*t,
        roll=a.roll+(b.roll-a.roll)*t,
        x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t}
    end
  end
  return frames[#frames]
end

axisRotation=function(x,y,z,angle)
  local s,c=math.sin(angle),math.cos(angle)
  local oc=1-c
  return {
    c+x*x*oc,x*y*oc-z*s,x*z*oc+y*s,
    y*x*oc+z*s,c+y*y*oc,y*z*oc-x*s,
    z*x*oc-y*s,z*y*oc+x*s,c+z*z*oc
  }
end

local function multiply3(a,b)
  local result={}
  for row=0,2 do for column=0,2 do
    local value=0
    for k=0,2 do value=value+a[row*3+k+1]*b[k*3+column+1] end
    result[row*3+column+1]=value
  end end
  return result
end

function FallingTrees:pose(tree)
  return poseAt(math.min(tree.animationDuration,
    math.max(0,tree.age)/(tree.timeScale or 1)))
end

function FallingTrees:model(tree)
  local pose=self:pose(tree)
  local dx,dz=tree.direction[1],tree.direction[3]
  local pitch=axisRotation(dz,0,-dx,math.rad(pose.pitch))
  local yaw=axisRotation(0,1,0,math.rad(pose.yaw))
  local roll=axisRotation(dx,0,dz,math.rad(pose.roll))
  local rotation=multiply3(yaw,multiply3(pitch,roll))
  return {
    rotation[1],rotation[4],rotation[7],0,
    rotation[2],rotation[5],rotation[8],0,
    rotation[3],rotation[6],rotation[9],0,
    tree.pivot[1]+dx*pose.x,tree.pivot[2]+pose.y,tree.pivot[3]+dz*pose.x,1
  }
end

-- Convert the detached crown into a bounded number of collectible stacks. The
-- positions come from the tree's current animated transform, so the items peel
-- away in mid-fall rather than teleporting to the final horizontal trunk.
function FallingTrees:leafDrops(tree,maxEntities)
  local leaves=tree.leaves or {}
  if #leaves==0 then return {} end
  maxEntities=math.max(1,math.floor(maxEntities or 24))
  local byItem={}
  for _,leaf in ipairs(leaves) do
    local list=byItem[leaf.key]
    if not list then list={} byItem[leaf.key]=list end
    list[#list+1]=leaf
  end
  local model=self:model(tree)
  local drops={}
  for item,list in pairs(byItem) do
    local stackSize=math.max(1,math.ceil(#list/maxEntities))
    local index=1
    while index<=#list do
      local last=math.min(#list,index+stackSize-1)
      local x,y,z=0,0,0
      for leafIndex=index,last do
        local leaf=list[leafIndex]
        local lx=leaf.x+.5-tree.pivot[1]
        local ly=leaf.y+.5-tree.pivot[2]
        local lz=leaf.z+.5-tree.pivot[3]
        x=x+model[1]*lx+model[5]*ly+model[9]*lz+model[13]
        y=y+model[2]*lx+model[6]*ly+model[10]*lz+model[14]
        z=z+model[3]*lx+model[7]*ly+model[11]*lz+model[15]
      end
      local count=last-index+1
      drops[#drops+1]={item=item,count=count,position={x/count,y/count,z/count}}
      index=last+1
    end
  end
  return drops
end

-- Return the centre of the animated trunk in world space. Landing rewards use
-- this point so the full-size tree resolves where the player just watched it
-- land, instead of snapping onto a separately quantized voxel line.
function FallingTrees:dropPosition(tree)
  local logs=tree.logs or {}
  if #logs==0 then return tree.impactPosition or tree.pivot end
  local model=self:model(tree)
  local x,y,z=0,0,0
  for _,log in ipairs(logs) do
    local lx=log.x+.5-tree.pivot[1]
    local ly=log.y+.5-tree.pivot[2]
    local lz=log.z+.5-tree.pivot[3]
    x=x+model[1]*lx+model[5]*ly+model[9]*lz+model[13]
    y=y+model[2]*lx+model[6]*ly+model[10]*lz+model[14]
    z=z+model[3]*lx+model[7]*ly+model[11]*lz+model[15]
  end
  return {x/#logs,y/#logs,z/#logs}
end

function FallingTrees:clear() self.trees={} end
return FallingTrees
