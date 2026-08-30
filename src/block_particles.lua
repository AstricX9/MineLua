local ffi = require("ffi")
local GL = require("gl")

local BlockParticles = {}
BlockParticles.__index = BlockParticles

local gl = GL.gl
local STRIDE_FLOATS = 18
local DYNAMIC_DRAW = 0x88E8
local GRAVITY = 13.5
local MAX_PARTICLES = 256
local FACE_KEYS = {"top", "side", "front", "back", "bottom"}
local ORDER = {1, 2, 3, 3, 4, 1}
local UV_CORNERS = {{0, 1}, {1, 1}, {1, 0}, {0, 0}}
local FACES = {
  {normal={ 1, 0, 0}, corners={{ 1,-1, 1},{ 1,-1,-1},{ 1, 1,-1},{ 1, 1, 1}}},
  {normal={-1, 0, 0}, corners={{-1,-1,-1},{-1,-1, 1},{-1, 1, 1},{-1, 1,-1}}},
  {normal={ 0, 1, 0}, corners={{-1, 1, 1},{ 1, 1, 1},{ 1, 1,-1},{-1, 1,-1}}},
  {normal={ 0,-1, 0}, corners={{-1,-1,-1},{ 1,-1,-1},{ 1,-1, 1},{-1,-1, 1}}},
  {normal={ 0, 0, 1}, corners={{-1,-1, 1},{ 1,-1, 1},{ 1, 1, 1},{-1, 1, 1}}},
  {normal={ 0, 0,-1}, corners={{ 1,-1,-1},{-1,-1,-1},{-1, 1,-1},{ 1, 1,-1}}}
}

local function configureVertexAttributes()
  local stride = STRIDE_FLOATS * 4
  local function attribute(index, size, offset)
    gl.glVertexAttribPointer(index, size, GL.FLOAT, 0, stride, ffi.cast("void*", offset * 4))
    gl.glEnableVertexAttribArray(index)
  end
  attribute(0, 3, 0)
  attribute(1, 3, 3)
  attribute(2, 3, 6)
  attribute(3, 2, 9)
  attribute(4, 3, 11)
  attribute(5, 3, 14)
end

function BlockParticles.countForQuality(quality)
  if quality == "Minimal" then return 4 end
  if quality == "Decreased" then return 9 end
  return 18
end

local function textureChoices(definition)
  local choices = {}
  local uvs = definition and definition.uvs or {}
  for _, key in ipairs(FACE_KEYS) do
    if uvs[key] then choices[#choices + 1] = {key = key, uv = uvs[key]} end
  end
  return choices
end

local function sampledUv(uv)
  -- Each chip shows a random 4x4-ish part of the source tile instead of the
  -- whole block face miniaturised onto every fragment.
  local columns = 4
  local column = math.random(0, columns - 1)
  local row = math.random(0, columns - 1)
  local width = (uv.u1 - uv.u0) / columns
  local height = (uv.v1 - uv.v0) / columns
  local insetU = math.min(0.25 / 256, width * 0.08)
  local insetV = math.min(0.25 / 256, height * 0.08)
  return {
    u0 = uv.u0 + column * width + insetU,
    v0 = uv.v0 + row * height + insetV,
    u1 = uv.u0 + (column + 1) * width - insetU,
    v1 = uv.v0 + (row + 1) * height - insetV
  }
end

function BlockParticles.new(options)
  options = options or {}
  local self = setmetatable({particles = {}, count = 0, gpu = options.gpu ~= false}, BlockParticles)
  if not self.gpu then return self end

  self.vao = ffi.new("GLuint[1]")
  self.vbo = ffi.new("GLuint[1]")
  gl.glGenVertexArrays(1, self.vao)
  gl.glBindVertexArray(self.vao[0])
  gl.glGenBuffers(1, self.vbo)
  gl.glBindBuffer(GL.ARRAY_BUFFER, self.vbo[0])
  gl.glBufferData(GL.ARRAY_BUFFER, 0, nil, DYNAMIC_DRAW)
  configureVertexAttributes()
  return self
end

function BlockParticles:spawn(definition, x, y, z, quality)
  local choices = textureChoices(definition)
  if #choices == 0 then return 0 end

  local amount = BlockParticles.countForQuality(quality)
  for _ = 1, amount do
    if #self.particles >= MAX_PARTICLES then table.remove(self.particles, 1) end
    local choice = choices[math.random(1, #choices)]
    local colors = definition.colors or {}
    local color = definition.biomeTint and definition.color or colors[choice.key] or
      definition.color or {1, 1, 1}
    local px, py, pz = 0.16 + math.random() * 0.68,
      0.16 + math.random() * 0.68, 0.16 + math.random() * 0.68
    local dx, dy, dz = px - 0.5, py - 0.5, pz - 0.5
    local length = math.max(0.08, math.sqrt(dx * dx + dy * dy + dz * dz))
    local speed = 0.55 + math.random() * 0.65
    self.particles[#self.particles + 1] = {
      position = {x + px, y + py, z + pz},
      velocity = {dx / length * speed, dy / length * speed + 0.75, dz / length * speed},
      rotation = {math.random() * 6.2832, math.random() * 6.2832, math.random() * 6.2832},
      angularVelocity = {(math.random() - 0.5) * 5, (math.random() - 0.5) * 5,
        (math.random() - 0.5) * 5},
      halfSize = 0.015 + math.random() * 0.010,
      age = 0.0,
      lifetime = 0.78 + math.random() * 0.48,
      uv = sampledUv(choice.uv),
      color = {color[1] or 1, color[2] or 1, color[3] or 1}
    }
  end
  return amount
end

local function surfaceBelow(world, position, halfSize)
  if not world then return nil end
  local blockX, blockZ = math.floor(position[1]), math.floor(position[3])
  local blockY = math.floor(position[2] - halfSize)
  if not world:isSolidBlock(blockX, blockY, blockZ) then return nil end
  local height = world.collisionHeightAt and world:collisionHeightAt(blockX, blockY, blockZ) or 1.0
  return blockY + height
end

function BlockParticles:update(dt, world)
  dt = math.max(0.0, math.min(dt or 0.0, 0.1))
  local index = 1
  while index <= #self.particles do
    local particle = self.particles[index]
    particle.age = particle.age + dt
    if particle.age >= particle.lifetime then
      table.remove(self.particles, index)
    else
      local position, velocity = particle.position, particle.velocity
      local previousBottom = position[2] - particle.halfSize
      velocity[2] = velocity[2] - GRAVITY * dt
      position[1] = position[1] + velocity[1] * dt
      position[2] = position[2] + velocity[2] * dt
      position[3] = position[3] + velocity[3] * dt

      local surface = velocity[2] <= 0 and surfaceBelow(world, position, particle.halfSize) or nil
      if surface and previousBottom >= surface - 0.08 and position[2] - particle.halfSize <= surface then
        position[2] = surface + particle.halfSize
        velocity[2] = math.abs(velocity[2]) > 0.7 and -velocity[2] * 0.28 or 0.0
        velocity[1], velocity[3] = velocity[1] * 0.64, velocity[3] * 0.64
        for axis = 1, 3 do particle.angularVelocity[axis] = particle.angularVelocity[axis] * 0.68 end
      else
        local drag = math.exp(-0.55 * dt)
        velocity[1], velocity[3] = velocity[1] * drag, velocity[3] * drag
      end
      for axis = 1, 3 do
        particle.rotation[axis] = particle.rotation[axis] + particle.angularVelocity[axis] * dt
      end
      index = index + 1
    end
  end
end

local function rotationMatrix(rotation)
  local sx, cx = math.sin(rotation[1]), math.cos(rotation[1])
  local sy, cy = math.sin(rotation[2]), math.cos(rotation[2])
  local sz, cz = math.sin(rotation[3]), math.cos(rotation[3])
  return {
    cy*cz, sx*sy*cz-cx*sz, cx*sy*cz+sx*sz,
    cy*sz, sx*sy*sz+cx*cz, cx*sy*sz-sx*cz,
    -sy, sx*cy, cx*cy
  }
end

local function rotated(x, y, z, matrix)
  return x*matrix[1]+y*matrix[2]+z*matrix[3],
    x*matrix[4]+y*matrix[5]+z*matrix[6],
    x*matrix[7]+y*matrix[8]+z*matrix[9]
end

local function appendParticle(vertices, particle)
  local remaining = particle.lifetime - particle.age
  local size = particle.halfSize * math.min(1.0, remaining / 0.16)
  local uv, color = particle.uv, particle.color
  local matrix = rotationMatrix(particle.rotation)
  for _, face in ipairs(FACES) do
    local nx, ny, nz = rotated(face.normal[1], face.normal[2], face.normal[3], matrix)
    for _, cornerIndex in ipairs(ORDER) do
      local corner, tex = face.corners[cornerIndex], UV_CORNERS[cornerIndex]
      local rx, ry, rz = rotated(corner[1] * size, corner[2] * size,
        corner[3] * size, matrix)
      local values = {
        particle.position[1] + rx, particle.position[2] + ry, particle.position[3] + rz,
        nx, ny, nz, color[1], color[2], color[3],
        tex[1] == 0 and uv.u0 or uv.u1, tex[2] == 0 and uv.v0 or uv.v1,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0
      }
      for i = 1, #values do vertices[#vertices + 1] = values[i] end
    end
  end
end

function BlockParticles:draw()
  if not self.gpu or #self.particles == 0 then return end
  local vertices = {}
  for _, particle in ipairs(self.particles) do appendParticle(vertices, particle) end
  local data = ffi.new("float[?]", #vertices, vertices)
  gl.glBindVertexArray(self.vao[0])
  gl.glBindBuffer(GL.ARRAY_BUFFER, self.vbo[0])
  gl.glBufferData(GL.ARRAY_BUFFER, #vertices * 4, data, DYNAMIC_DRAW)
  self.count = #vertices / STRIDE_FLOATS
  gl.glDrawArrays(0x0004, 0, self.count)
end

function BlockParticles:clear()
  self.particles = {}
  self.count = 0
end

function BlockParticles:release()
  if self.vbo and gl.glDeleteBuffers then gl.glDeleteBuffers(1, self.vbo) end
  if self.vao and gl.glDeleteVertexArrays then gl.glDeleteVertexArrays(1, self.vao) end
  self.vbo, self.vao, self.particles, self.count = nil, nil, {}, 0
  self.gpu = false
end

return BlockParticles
