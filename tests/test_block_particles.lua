package.path = "src/?.lua;" .. package.path

local BlockParticles = require("block_particles")

local definition = {
  uvs = {
    top = {u0 = 0.0, v0 = 0.0, u1 = 0.0625, v1 = 0.0625},
    side = {u0 = 0.0625, v0 = 0.0, u1 = 0.125, v1 = 0.0625}
  },
  colors = {top = {0.4, 0.8, 0.3}, side = {0.7, 0.6, 0.4}}
}

local particles = BlockParticles.new({gpu = false})
math.randomseed(1234)
assert(particles:spawn(definition, 4, 8, 12, "All") == 18)
assert(#particles.particles == 18, "all particles emits a full break burst")

for _, particle in ipairs(particles.particles) do
  assert(particle.uv.u1 > particle.uv.u0 and particle.uv.v1 > particle.uv.v0,
    "each chip samples a non-empty portion of the block atlas")
  assert(particle.uv.u1 - particle.uv.u0 < 0.02,
    "each chip crops the source texture instead of showing its entire face")
end

local world = {}
function world:isSolidBlock() return false end
particles:update(0.1, world)
assert(particles.particles[1].age > 0, "particles advance through their lifetime")

particles:clear()
assert(particles:spawn(definition, 0, 0, 0, "Decreased") == 9)
particles:clear()
assert(particles:spawn(definition, 0, 0, 0, "Minimal") == 4)
for _ = 1, 20 do particles:update(0.1, world) end
assert(#particles.particles == 0, "expired particles are removed")

print("block particle tests passed")
