local GL = require("gl")

local rendering = {}

local gl = GL.gl
local GL_TRIANGLES = 0x0004

function rendering.draw(mesh)
  gl.glBindVertexArray(mesh.vao[0])
  gl.glDrawArrays(GL_TRIANGLES, 0, mesh.count)
end

return rendering
