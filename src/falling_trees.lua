local blocks = require("blocks")

local FallingTrees={}
FallingTrees.__index=FallingTrees

local LOGS={oak_log=true,oak_log_x=true,oak_log_z=true,spruce_log=true,spruce_log_x=true,spruce_log_z=true}
local LEAVES={oak_leaves=true,spruce_leaves=true}
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
function FallingTrees.isLog(definition) return definition and LOGS[definition.key] or false end

local function connectedLogs(world,x,y,z)
  local result,seen,queue={}, {}, {{x=x,y=y,z=z}}
  seen[key(x,y,z)]=true
  local head=1
  while head<=#queue and #result<128 do
    local p=queue[head] head=head+1
    local def=blocks.list[world:blockAt(p.x,p.y,p.z)]
    if def and LOGS[def.key] then
      result[#result+1]={x=p.x,y=p.y,z=p.z,id=def.id,key=def.key}
      for _,d in ipairs(DIRS) do
        local nx,ny,nz=p.x+d[1],p.y+d[2],p.z+d[3]
        local k=key(nx,ny,nz)
        if not seen[k] then seen[k]=true queue[#queue+1]={x=nx,y=ny,z=nz} end
      end
    end
  end
  return result
end

local function attachedLeaves(world,logs,occupied)
  local result={}
  for _,log in ipairs(logs) do
    for dx=-2,2 do for dy=-2,2 do for dz=-2,2 do
      local x,y,z=log.x+dx,log.y+dy,log.z+dz
      local k=key(x,y,z)
      if not occupied[k] then
        local def=blocks.list[world:blockAt(x,y,z)]
        if def and LEAVES[def.key] then
          occupied[k]=true result[#result+1]={x=x,y=y,z=z,id=def.id,key=def.key}
        end
      end
    end end end
  end
  return result
end

local function appendVertex(out,p,n,c,u,v,material)
  local values={p[1],p[2],p[3],n[1],n[2],n[3],c[1],c[2],c[3],u,v,material,0,1}
  for i=1,#values do out[#out+1]=values[i] end
end

local function buildVertices(captured,pivot)
  local occupied={} for _,p in ipairs(captured) do occupied[key(p.x,p.y,p.z)]=true end
  local out={}
  for _,p in ipairs(captured) do
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
            appendVertex(out,{p.x+c[1]-pivot[1],p.y+c[2]-pivot[2],p.z+c[3]-pivot[3]},
              {f[5],f[6],f[7]},color,t[1]==0 and uv.u0 or uv.u1,t[2]==0 and uv.v0 or uv.v1,material)
          end
        end
      end
    end
  end
  return out
end

function FallingTrees.new() return setmetatable({trees={},nextId=1},FallingTrees) end

function FallingTrees:start(world,x,y,z,direction)
  local logs=connectedLogs(world,x,y,z)
  if #logs<2 then return nil,{} end
  local occupied={} for _,p in ipairs(logs) do occupied[key(p.x,p.y,p.z)]=true end
  local leaves=attachedLeaves(world,logs,occupied)
  local captured={} for _,p in ipairs(logs) do captured[#captured+1]=p end
  for _,p in ipairs(leaves) do captured[#captured+1]=p end
  local pivot={x+.5,y,z+.5}
  local dx,dz=(direction and direction[1] or 1),(direction and direction[3] or 0)
  local length=math.sqrt(dx*dx+dz*dz) if length<.001 then dx,dz,length=1,0,1 end
  local entity={id=self.nextId,age=0,duration=1.05,pivot=pivot,direction={dx/length,0,dz/length},
    blocks=captured,logCount=#logs,drop=logs[1].key,vertices=buildVertices(captured,pivot)}
  self.nextId=self.nextId+1 self.trees[#self.trees+1]=entity
  for _,p in ipairs(captured) do world:setBlock(p.x,p.y,p.z,blocks.air or 0) end
  return entity,captured
end

function FallingTrees:update(dt)
  local completed={}
  for i=#self.trees,1,-1 do
    local tree=self.trees[i] tree.age=tree.age+math.max(0,dt or 0)
    if tree.age>=tree.duration then completed[#completed+1]=tree table.remove(self.trees,i) end
  end
  return completed
end

function FallingTrees:model(tree)
  local t=math.min(1,tree.age/tree.duration)
  t=1-(1-t)*(1-t)
  local angle=t*math.pi*.5
  local s,c=math.sin(angle),math.cos(angle)
  local ax,az=tree.direction[3],-tree.direction[1]
  local oc=1-c
  return {
    c+ax*ax*oc, az*s, ax*az*oc, 0,
    -az*s, c, ax*s, 0,
    ax*az*oc, -ax*s, c+az*az*oc, 0,
    tree.pivot[1],tree.pivot[2],tree.pivot[3],1
  }
end

function FallingTrees:clear() self.trees={} end
return FallingTrees
