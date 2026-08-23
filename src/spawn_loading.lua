local World = require("world")

local spawnLoading = {}

local function sortedCoords(cx,cy,cz,radius)
  local coords={}
  for dz=-radius,radius do for dy=-radius,radius do for dx=-radius,radius do
    local d=dx*dx+dy*dy+dz*dz
    if d<=radius*radius then coords[#coords+1]={chunkX=cx+dx,chunkY=cy+dy,chunkZ=cz+dz,dx=dx,dy=dy,dz=dz,distanceSquared=d} end
  end end end
  table.sort(coords,function(a,b)
    if a.distanceSquared~=b.distanceSquared then return a.distanceSquared<b.distanceSquared end
    if a.chunkX~=b.chunkX then return a.chunkX<b.chunkX end
    if a.chunkY~=b.chunkY then return a.chunkY<b.chunkY end
    return a.chunkZ<b.chunkZ
  end)
  return coords
end

local function entry(world,x,y,z) return world.chunks[World.chunkKey(x,y,z)] end

local function everyChunk(plan,world,radius,predicate)
  for dz=-radius,radius do for dy=-radius,radius do for dx=-radius,radius do
    if dx*dx+dy*dy+dz*dz<=radius*radius and not predicate(entry(world,plan.centerChunkX+dx,plan.centerChunkY+dy,plan.centerChunkZ+dz)) then return false end
  end end end
  return true
end

function spawnLoading.createPlan(options)
  options=options or {}
  local required=options.requiredRadius or 1
  local halo=math.max(required,options.haloRadius or 2)
  local cx,cy,cz=options.centerChunkX or 0,options.centerChunkY or 0,options.centerChunkZ or 0
  return {centerChunkX=cx,centerChunkY=cy,centerChunkZ=cz,requiredRadius=required,haloRadius=halo,coords=sortedCoords(cx,cy,cz,halo)}
end

function spawnLoading.isCenterChunk(plan,x,y,z) return x==plan.centerChunkX and y==plan.centerChunkY and z==plan.centerChunkZ end
function spawnLoading.centerEntry(plan,world) return entry(world,plan.centerChunkX,plan.centerChunkY,plan.centerChunkZ) end
function spawnLoading.hasTerrainHalo(plan,world) return everyChunk(plan,world,plan.haloRadius,function(e)return e and e.hasTerrain==true end) end
function spawnLoading.hasRequiredCollision(plan,world) return everyChunk(plan,world,plan.requiredRadius,function(e)return e and e.hasTerrain and e.hasCollision end) end

function spawnLoading.isSpawnPlayable(plan,world,meshes)
  if not spawnLoading.hasTerrainHalo(plan,world) or not spawnLoading.hasRequiredCollision(plan,world) then return false end
  local center=spawnLoading.centerEntry(plan,world)
  if not center or not center.hasInitialLight then return false end
  return center.isUploaded==true and meshes[World.chunkKey(plan.centerChunkX,plan.centerChunkY,plan.centerChunkZ)]~=nil
end

function spawnLoading.streamingMeshQueue(plan,world,meshes)
  local queue={}
  for i=1,#plan.coords do local c=plan.coords[i] local key=World.chunkKey(c.chunkX,c.chunkY,c.chunkZ) local e=world.chunks[key]
    if e and not meshes[key] then queue[#queue+1]={chunkX=c.chunkX,chunkY=c.chunkY,chunkZ=c.chunkZ,entry=e,rebuild=true} end
  end
  return queue
end

function spawnLoading.progress(plan,job)
  local terrain=(job.generatedChunks or 0)/math.max(1,#plan.coords)
  local collision=spawnLoading.hasRequiredCollision(plan,job.world) and 1 or terrain
  local light=job.world:lightingReady() and 1 or (job.lightingStarted and 0.2 or 0)
  local mesh=job.spawnMeshComplete and 1 or 0
  local player=spawnLoading.isSpawnPlayable(plan,job.world,job.terrainMeshes) and 1 or 0
  return math.max(0,math.min(0.99,terrain*.45+collision*.15+light*.20+mesh*.15+player*.05))
end

function spawnLoading.message(plan,job)
  if (job.generatedChunks or 0)<#plan.coords then return "Building spherical spawn terrain" end
  if not job.world:lightingReady() then return "Lighting spawn" end
  if not job.spawnMeshComplete then return "Uploading spawn" end
  return "Joining world"
end

return spawnLoading
