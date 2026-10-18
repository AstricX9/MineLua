package.path = "src/?.lua;src/?/init.lua;" .. package.path

local streaming = require("chunk_streaming")
local World = require("world")

local prioritized = {}
local world = {chunks = {}}
function world:prioritizeChunkJob(job)
  prioritized[#prioritized + 1] = job
end

local urgent = {chunkX = 20, chunkZ = 20, entry = {chunkX = 20, chunkZ = 20}, urgent = true}
local stale = {chunkX = -8, chunkZ = -8}
local nearbyMesh = {chunkX = 1, chunkZ = 0, entry = {chunkX = 1, chunkZ = 0}}
local nearbyCollision = {chunkX = 0, chunkZ = 0}
local pending = {stale, nearbyMesh, nearbyCollision, urgent}

streaming.prioritize(world, pending, 0.5, 0.5, 16.5, 0.5)
assert(pending[1] == urgent, "urgent edit remeshes retain queue priority")
assert(pending[2] == nearbyCollision,
  "nearby collision generation runs before a nearby cosmetic mesh")
assert(pending[#pending] == stale, "obsolete far work falls to the back after direction changes")
assert(#prioritized == 4, "worker-process queue receives the same leading priorities")

for dz = -1, 1 do
  for dx = -1, 1 do
    world.chunks[World.chunkKey(dx, dz)] = {hasCollision = true}
  end
end
assert(streaming.collisionRingReady(world, 0.5, 0.5), "complete 3x3 collision ring is ready")
world.chunks[World.chunkKey(1, 1)] = nil
assert(not streaming.collisionRingReady(world, 0.5, 0.5), "a missing collision neighbour is detected")

print("semi-blocking chunk streaming tests passed")
