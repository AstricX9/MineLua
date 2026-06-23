local Entity = {}
Entity.__index = Entity

function Entity.new(definition)
  definition = definition or {}
  local components = definition.components or {}
  local transform = components.transform or {}
  local physics = components.physics or {}

  return setmetatable({
    id = definition.id or definition.key or "entity",
    definition = definition,
    components = components,
    position = definition.position or transform.position or {0, 0, 0},
    rotation = definition.rotation or transform.rotation or {0, 0, 0},
    velocity = definition.velocity or physics.velocity or {0, 0, 0},
    meshFactory = definition.meshFactory,
    updateFn = definition.update
  }, Entity)
end

function Entity:update(dt, world)
  if self.updateFn then
    self.updateFn(self, dt, world)
  end
end

function Entity:createMesh()
  if not self.meshFactory then
    return nil
  end

  return self.meshFactory(self)
end

return Entity
