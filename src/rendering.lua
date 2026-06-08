local rendering = {}

function rendering.draw(vao, count)
    gl.glBindVertexArray(vao)
    gl.glDrawArrays(gl.GL_TRIANGLES, 0, count)
end

return rendering
