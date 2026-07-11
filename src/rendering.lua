local GL = require("gl")

local rendering = {}

local gl = GL.gl
local GL_TRIANGLES = 0x0004

function rendering.draw(mesh)
  if not mesh or mesh.released or mesh.count == 0 then
    return
  end

  gl.glBindVertexArray(mesh.vao[0])
  gl.glDrawArrays(GL_TRIANGLES, 0, mesh.count)
end

function rendering.release(mesh)
  if not mesh or mesh.released then
    return
  end

  if mesh.vbo and gl.glDeleteBuffers then
    gl.glDeleteBuffers(1, mesh.vbo)
  end
  if mesh.vao and gl.glDeleteVertexArrays then
    gl.glDeleteVertexArrays(1, mesh.vao)
  end

  mesh.vao = nil
  mesh.vbo = nil
  mesh.data = nil
  mesh.count = 0
  mesh.released = true
end

function rendering.releaseGroup(group)
  if not group then
    return
  end

  for _, mesh in pairs(group) do
    if type(mesh) == "table" and mesh.vao then
      rendering.release(mesh)
    elseif type(mesh) == "table" then
      rendering.releaseGroup(mesh)
    end
  end
end

return rendering
