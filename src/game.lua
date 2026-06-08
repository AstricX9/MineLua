local glfw = require("glfw")
local voxel = require("voxel")
local character = require("character")
local terrain = require("terrain")
local debugger = require("debugger")

local function mainLoop()
    -- Main game loop logic goes here
    while true do
        local currentTime = glfw.glfwGetTime()
        local dt = currentTime - lastTime
        lastTime = currentTime

        gl.glClearColor(0.53, 0.81, 0.92, 1.0)
        gl.glClear(GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT)

        -- Update camera (mouse + movement + gravity)
        updateCamera(dt)

        -- Draw terrain
        gl.glBindVertexArray(vao[0])
        gl.glDrawArrays(0x0004, 0, vcount)

        -- Draw character
        gl.glBindVertexArray(vao2[0])
        gl.glDrawArrays(0x0004, 0, char_count)

        glfw.glfwSwapBuffers(window)
        glfw.glfwPollEvents()
    end
end

local success, err = pcall(mainLoop)
if not success then
    print("Error: " .. err)
end

-- Clean up
 glfw.glfwTerminate()

-- Pause to read any output
print("Press Enter to exit...")
io.read()
