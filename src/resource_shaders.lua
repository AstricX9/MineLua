local json = require("json")

local resourceShaders = {}

local function readFile(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return content
end

local function loadJson(path)
  local content = readFile(path)
  if not content then
    return nil
  end
  return json.decode(content)
end

local function shaderPath(kind, name)
  local extension = kind == "vertex" and ".vsh" or ".fsh"
  return "assets/shaders/program/" .. name .. extension
end

function resourceShaders.loadProgram(name)
  local definition = loadJson("assets/shaders/program/" .. name .. ".json")
  if not definition then
    return nil
  end

  definition.name = name
  definition.vertexPath = shaderPath("vertex", definition.vertex or name)
  definition.fragmentPath = shaderPath("fragment", definition.fragment or name)
  definition.vertexSource = readFile(definition.vertexPath)
  definition.fragmentSource = readFile(definition.fragmentPath)
  return definition
end

function resourceShaders.loadPost(name)
  local definition = loadJson("assets/shaders/post/" .. name .. ".json")
  if not definition then
    return nil
  end

  definition.name = name
  return definition
end

function resourceShaders.describeProgram(name)
  local definition = resourceShaders.loadProgram(name)
  if not definition then
    return nil
  end

  return {
    name = definition.name,
    vertex = definition.vertex,
    fragment = definition.fragment,
    attributes = definition.attributes or {},
    samplers = definition.samplers or {},
    uniforms = definition.uniforms or {},
    hasVertexSource = definition.vertexSource ~= nil,
    hasFragmentSource = definition.fragmentSource ~= nil
  }
end

return resourceShaders
