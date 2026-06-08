local shader = {}

function shader.load(vertexPath, fragmentPath)
    -- Load and compile shaders from the given paths
    local vertexShader = gl.glCreateShader(gl.GL_VERTEX_SHADER)
    local fragmentShader = gl.glCreateShader(gl.GL_FRAGMENT_SHADER)

    -- Read shader source code from files
    local vertexCode = io.open(vertexPath, "r"):read("*a")
    local fragmentCode = io.open(fragmentPath, "r"):read("*a")

    -- Compile vertex shader
    gl.glShaderSource(vertexShader, 1, ffi.new("const char*[1]", vertexCode), nil)
    gl.glCompileShader(vertexShader)

    -- Check for compilation errors
    local success = ffi.new("int[1]")
    gl.glGetShaderiv(vertexShader, gl.GL_COMPILE_STATUS, success)
    if success[0] == gl.GL_FALSE then
        error("Vertex shader compilation failed")
    end

    -- Compile fragment shader
    gl.glShaderSource(fragmentShader, 1, ffi.new("const char*[1]", fragmentCode), nil)
    gl.glCompileShader(fragmentShader)

    -- Check for compilation errors
    gl.glGetShaderiv(fragmentShader, gl.GL_COMPILE_STATUS, success)
    if success[0] == gl.GL_FALSE then
        error("Fragment shader compilation failed")
    end

    -- Create shader program
    local shaderProgram = gl.glCreateProgram()
    gl.glAttachShader(shaderProgram, vertexShader)
    gl.glAttachShader(shaderProgram, fragmentShader)
    gl.glLinkProgram(shaderProgram)

    -- Delete shaders as they're linked into the program now and no longer necessary
    gl.glDeleteShader(vertexShader)
    gl.glDeleteShader(fragmentShader)

    return shaderProgram
end

return shader
