-- Drawing the real stars and the real planets.
--
-- Stars are points, because that is what they are: no telescope on Earth
-- resolves one as a disc, and neither does the eye. What varies between them is
-- brightness and colour, both of which the catalogue supplies as the real
-- measured quantities -- visual magnitude and B-V colour index -- so nothing
-- here is authored except how bright magnitude zero should look on screen.
--
-- Everything else the pass does is atmosphere:
--
--   * extinction, from the same optical depths the sky shader scatters with, so
--     a star low in the sky is dimmed and reddened by exactly the air that
--     reddens the setting sun. On Mars the dust takes red out preferentially
--     instead, so stars near the Martian horizon go blue;
--   * a raised background, from twilight and from moonlight, subtracted rather
--     than multiplied -- moonlight drowns the faint stars and leaves the bright
--     ones alone, which is what subtracting a floor does and scaling does not;
--   * scintillation, scaled by air mass and by how much atmosphere the world
--     has. Stars twinkle and planets do not, because a planet is an extended
--     source whose parts scintillate out of step; the same is true on Mars for
--     everything, where there is barely any air to do it.
--
-- The catalogue is only bright down to about magnitude 3. Below that the field
-- is filled procedurally, but not uniformly: density follows galactic latitude,
-- because the faint sky is the disc of the galaxy seen from inside it.

local ffi = require("ffi")
local GL = require("gl")
local shaderModule = require("shader")
local catalog = require("star_catalog")

local gl = GL.gl
local GL_POINTS = 0x0000
local GL_ONE = 1
local GL_BLEND = 0x0BE2
local GL_DEPTH_TEST = 0x0B71
local GL_PROGRAM_POINT_SIZE = 0x8642
local GL_ARRAY_BUFFER = GL.ARRAY_BUFFER
local GL_STATIC_DRAW = GL.STATIC_DRAW
local GL_DYNAMIC_DRAW = 0x88E8

local starField = {}

-- direction (3) + magnitude (1) + colour (3) + scintillation (1)
local STRIDE_FLOATS = 8
local MAX_TRACKED_BODIES = 16

-- Ballesteros' relation between B-V and effective temperature, then the
-- Planckian locus. The result is normalised to unit luminance, because how
-- bright the star is comes from its magnitude, not from its colour.
local function colorFromColorIndex(colorIndex)
  local temperature = 4600.0 *
    (1.0 / (0.92 * colorIndex + 1.70) + 1.0 / (0.92 * colorIndex + 0.62))
  temperature = math.max(1700.0, math.min(temperature, 40000.0))
  local t = temperature / 100.0

  local red, green, blue
  if t <= 66.0 then
    red = 255.0
    green = 99.4708025861 * math.log(t) - 161.1195681661
  else
    red = 329.698727446 * (t - 60.0) ^ -0.1332047592
    green = 288.1221695283 * (t - 60.0) ^ -0.0755148492
  end
  if t >= 66.0 then
    blue = 255.0
  elseif t <= 19.0 then
    blue = 0.0
  else
    blue = 138.5177312231 * math.log(t - 10.0) - 305.0447927307
  end

  red = math.max(0.0, math.min(red, 255.0)) / 255.0
  green = math.max(0.0, math.min(green, 255.0)) / 255.0
  blue = math.max(0.0, math.min(blue, 255.0)) / 255.0

  local luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
  if luminance <= 1.0e-4 then return 1.0, 1.0, 1.0 end
  return red / luminance, green / luminance, blue / luminance
end
starField.colorFromColorIndex = colorFromColorIndex

-- A deterministic hash, so the faint field is the same sky every session.
local function hash(seed)
  local x = math.sin(seed * 127.1 + 311.7) * 43758.5453123
  return x - math.floor(x)
end

-- Faint stars, distributed the way the real faint sky is. Density rises toward
-- the galactic plane by roughly a factor of four, and the magnitude
-- distribution follows the observed rise of about three stars for every one a
-- magnitude brighter.
local function appendProceduralStars(vertices, count, faintestMagnitude)
  local poleX, poleY, poleZ = catalog.unitVector(
    catalog.galacticPole.rightAscension * 12.0 / math.pi,
    catalog.galacticPole.declination * 180.0 / math.pi)
  local placed, attempt = 0, 0
  while placed < count and attempt < count * 40 do
    attempt = attempt + 1
    -- Uniform on the sphere before the galactic weighting is applied.
    local z = hash(attempt * 3.7) * 2.0 - 1.0
    local angle = hash(attempt * 5.3 + 19.0) * math.pi * 2.0
    local horizontal = math.sqrt(math.max(1.0 - z * z, 0.0))
    local x, y = horizontal * math.cos(angle), horizontal * math.sin(angle)

    local galacticLatitude = math.abs(x * poleX + y * poleY + z * poleZ)
    -- exp(-|sin b| / 0.32) is the disc seen edge on: four to one between the
    -- plane and the poles.
    local density = 0.25 + 0.75 * math.exp(-galacticLatitude / 0.32)
    if hash(attempt * 7.1 + 41.0) <= density then
      placed = placed + 1
      -- Invert N(<m) proportional to 10^(0.45 m) over the faint range, so most
      -- of them land near the limit rather than being spread evenly.
      local uniform = math.max(hash(attempt * 11.3 + 71.0), 1.0e-4)
      local magnitude = faintestMagnitude + math.log10(uniform) / 0.45
      magnitude = math.max(magnitude, 3.0)
      -- Faint stars are mostly distant and reddened, so the colour spread runs
      -- warm rather than being centred on the sun.
      local colorIndex = 0.20 + hash(attempt * 13.9 + 97.0) * 1.30
      local red, green, blue = colorFromColorIndex(colorIndex)
      local base = #vertices
      vertices[base + 1] = x
      vertices[base + 2] = y
      vertices[base + 3] = z
      vertices[base + 4] = magnitude
      vertices[base + 5] = red
      vertices[base + 6] = green
      vertices[base + 7] = blue
      vertices[base + 8] = 1.0
    end
  end
  return placed
end

function starField.buildVertices(options)
  options = options or {}
  local vertices = {}
  for _, star in ipairs(catalog.stars) do
    local x, y, z = catalog.unitVector(star[2], star[3])
    local red, green, blue = colorFromColorIndex(star[5])
    local base = #vertices
    vertices[base + 1] = x
    vertices[base + 2] = y
    vertices[base + 3] = z
    vertices[base + 4] = star[4]
    vertices[base + 5] = red
    vertices[base + 6] = green
    vertices[base + 7] = blue
    vertices[base + 8] = 1.0
  end
  appendProceduralStars(vertices, options.proceduralCount or 2600,
    options.faintestMagnitude or 6.2)
  return vertices
end

local function configureAttributes()
  local stride = STRIDE_FLOATS * 4
  gl.glVertexAttribPointer(0, 3, GL.FLOAT, 0, stride, nil)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(1, 4, GL.FLOAT, 0, stride, ffi.cast("void*", 3 * 4))
  gl.glEnableVertexAttribArray(1)
  gl.glVertexAttribPointer(2, 1, GL.FLOAT, 0, stride, ffi.cast("void*", 7 * 4))
  gl.glEnableVertexAttribArray(2)
end

function starField.createShader()
  local vertex = [[
#version 460 core
layout (location = 0) in vec3 aDirection;
layout (location = 1) in vec4 aPhotometry;   // magnitude, colour
layout (location = 2) in float aScintillation;

out vec3 vColor;
out float vBrightness;

uniform mat3 skyRotation;      // catalogue frame to the world's body frame
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec2 cameraProjection;
uniform vec2 viewport;
uniform vec3 extinction;       // vertical optical depth per channel
uniform vec4 skyParams;        // reference brightness, background, night amount, time
uniform vec2 twinkle;          // amount, speed

void main() {
  vec3 direction = normalize(skyRotation * aDirection);

  // Air mass: Kasten and Young's fit, which stays finite at the horizon where
  // the plane-parallel 1/sin does not.
  float altitude = degrees(asin(clamp(direction.y, -1.0, 1.0)));
  float airMass = 40.0;
  if (altitude > -0.6) {
    airMass = 1.0 / (max(sin(radians(altitude)), -0.01) +
      0.50572 * pow(altitude + 6.07995, -1.6364));
    airMass = clamp(airMass, 1.0, 40.0);
  }

  // Magnitude to flux, referred to magnitude zero.
  float brightness = skyParams.x * pow(10.0, -0.4 * aPhotometry.x);
  vec3 transmittance = exp(-extinction * airMass);

  // Scintillation grows as roughly the 3/2 power of air mass, and needs air to
  // happen in at all. An extended source averages it away, which is why the
  // planets carry a small value here and the stars carry one.
  float wobble = 1.0;
  if (twinkle.x > 0.001) {
    float phase = dot(aDirection, vec3(91.7, 57.3, 33.1)) * 12.9898;
    float amount = twinkle.x * aScintillation * min(pow(airMass, 1.5) * 0.08, 0.45);
    wobble = 1.0 + amount * (
      sin(skyParams.w * twinkle.y + phase) * 0.6 +
      sin(skyParams.w * twinkle.y * 1.7 + phase * 2.3) * 0.4);
  }

  vec3 flux = aPhotometry.yzw * brightness * transmittance * wobble * skyParams.z;

  // Twilight and moonlight raise the background the star has to stand out of.
  // Subtracting the floor is what makes a full moon take the faint stars away
  // and leave the bright ones; scaling would dim all of them together.
  flux = max(flux - vec3(skyParams.y), vec3(0.0));

  // Below the horizon there is a planet in the way.
  flux *= smoothstep(-0.01, 0.03, direction.y);

  float luminance = dot(flux, vec3(0.2126, 0.7152, 0.0722));
  vColor = luminance > 1.0e-6 ? flux / luminance : vec3(0.0);
  vBrightness = luminance;

  // Bright stars read as larger as well as brighter, which is how the eye sees
  // them; the growth is deliberately slow so magnitude does the work.
  float pointRadius = clamp(0.8 + 0.52 * (4.5 - aPhotometry.x), 0.8, 4.2);
  gl_PointSize = pointRadius * 2.0;

  vec3 view = vec3(
    dot(direction, cameraRight),
    dot(direction, cameraUp),
    dot(direction, cameraForward));
  if (view.z <= 0.001 || luminance <= 1.0e-6) {
    // Behind the camera, or invisible: park it outside clip space.
    gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
    return;
  }
  gl_Position = vec4(
    view.x / (view.z * cameraProjection.x),
    view.y / (view.z * cameraProjection.y),
    0.0, 1.0);
}
]]
  local fragment = [[
#version 460 core
in vec3 vColor;
in float vBrightness;
out vec4 FragColor;
void main() {
  vec2 offset = gl_PointCoord * 2.0 - 1.0;
  float radiusSquared = dot(offset, offset);
  if (radiusSquared > 1.0) discard;
  // A Gaussian core with a soft edge: a hard disc reads as a sprite, and the
  // eye's own point spread function is much closer to this.
  float profile = exp(-radiusSquared * 3.6) * (1.0 - radiusSquared * radiusSquared);
  FragColor = vec4(vColor * vBrightness * profile, 1.0);
}
]]
  return shaderModule.fromSource(vertex, fragment)
end

function starField.createLocations(program)
  local names = {
    "skyRotation", "cameraForward", "cameraRight", "cameraUp", "cameraProjection",
    "viewport", "extinction", "skyParams", "twinkle"
  }
  local locations = {}
  for _, name in ipairs(names) do
    locations[name] = gl.glGetUniformLocation(program, name)
  end
  return locations
end

local function createBuffer(vertices, usage)
  local vao, vbo = ffi.new("GLuint[1]"), ffi.new("GLuint[1]")
  local data = ffi.new("float[?]", math.max(#vertices, 1), vertices)
  gl.glGenVertexArrays(1, vao)
  gl.glBindVertexArray(vao[0])
  gl.glGenBuffers(1, vbo)
  gl.glBindBuffer(GL_ARRAY_BUFFER, vbo[0])
  gl.glBufferData(GL_ARRAY_BUFFER, math.max(#vertices, 1) * 4, data, usage)
  configureAttributes()
  gl.glBindVertexArray(0)
  return {vao = vao, vbo = vbo, data = data, count = math.floor(#vertices / STRIDE_FLOATS)}
end

function starField.create(options)
  local stars = createBuffer(starField.buildVertices(options), GL_STATIC_DRAW)
  local empty = {}
  for index = 1, MAX_TRACKED_BODIES * STRIDE_FLOATS do empty[index] = 0.0 end
  local bodies = createBuffer(empty, GL_DYNAMIC_DRAW)
  bodies.count = 0
  bodies.scratch = ffi.new("float[?]", MAX_TRACKED_BODIES * STRIDE_FLOATS)
  return {stars = stars, bodies = bodies}
end

function starField.release(state)
  if not state then return end
  for _, buffer in pairs(state) do
    if type(buffer) == "table" and buffer.vao then
      gl.glDeleteBuffers(1, buffer.vbo)
      gl.glDeleteVertexArrays(1, buffer.vao)
    end
  end
end

-- Replace the moving bodies with this frame's positions. Directions are already
-- in the world's body frame, so this buffer is drawn with an identity rotation.
function starField.setBodies(state, bodies)
  local buffer = state.bodies
  local count = math.min(#bodies, MAX_TRACKED_BODIES)
  for index = 1, count do
    local body = bodies[index]
    local base = (index - 1) * STRIDE_FLOATS
    buffer.scratch[base + 0] = body.direction[1]
    buffer.scratch[base + 1] = body.direction[2]
    buffer.scratch[base + 2] = body.direction[3]
    buffer.scratch[base + 3] = body.magnitude
    buffer.scratch[base + 4] = body.color[1]
    buffer.scratch[base + 5] = body.color[2]
    buffer.scratch[base + 6] = body.color[3]
    -- A disc a few arcseconds across still averages its own scintillation away.
    buffer.scratch[base + 7] = body.scintillation or 0.12
  end
  buffer.count = count
  if count == 0 then return end
  gl.glBindBuffer(GL_ARRAY_BUFFER, buffer.vbo[0])
  gl.glBufferSubData(GL_ARRAY_BUFFER, 0, count * STRIDE_FLOATS * 4, buffer.scratch)
end

local identityRotation = ffi.new("float[9]", {1, 0, 0, 0, 1, 0, 0, 0, 1})

function starField.draw(program, locations, state, camera, settings)
  if settings.visibility <= 0.001 then return end

  gl.glUseProgram(program)
  gl.glDisable(GL_DEPTH_TEST)
  gl.glEnable(GL_BLEND)
  gl.glEnable(GL_PROGRAM_POINT_SIZE)
  gl.glBlendFunc(GL_ONE, GL_ONE)

  gl.glUniform3f(locations.cameraForward, camera.forward[1], camera.forward[2], camera.forward[3])
  gl.glUniform3f(locations.cameraRight, camera.right[1], camera.right[2], camera.right[3])
  gl.glUniform3f(locations.cameraUp, camera.up[1], camera.up[2], camera.up[3])
  gl.glUniform2f(locations.cameraProjection, camera.projectionX, camera.projectionY)
  gl.glUniform2f(locations.viewport, camera.width, camera.height)
  gl.glUniform3f(locations.extinction,
    settings.extinction[1], settings.extinction[2], settings.extinction[3])
  gl.glUniform4f(locations.skyParams, settings.referenceBrightness,
    settings.background, settings.visibility, settings.time)
  gl.glUniform2f(locations.twinkle, settings.twinkleAmount or 0.0, settings.twinkleSpeed or 5.0)

  gl.glUniformMatrix3fv(locations.skyRotation, 1, 0, settings.rotation)
  gl.glBindVertexArray(state.stars.vao[0])
  gl.glDrawArrays(GL_POINTS, 0, state.stars.count)

  if state.bodies.count > 0 then
    gl.glUniformMatrix3fv(locations.skyRotation, 1, 0, identityRotation)
    gl.glBindVertexArray(state.bodies.vao[0])
    gl.glDrawArrays(GL_POINTS, 0, state.bodies.count)
  end

  gl.glBindVertexArray(0)
  gl.glDisable(GL_BLEND)
  gl.glDisable(GL_PROGRAM_POINT_SIZE)
  gl.glEnable(GL_DEPTH_TEST)
end

-- Vertical optical depth per channel, taken from the same numbers the sky is
-- scattered with so a star is dimmed by the air that reddens the sunset.
function starField.extinctionFor(profileSky)
  local rayleigh = profileSky.rayleighBeta
  local dust = profileSky.dustBeta
  local rayleighHeight = profileSky.rayleighScaleHeightMeters
  local dustHeight = profileSky.dustScaleHeightMeters
  return {
    rayleigh[1] * rayleighHeight + dust[1] * dustHeight,
    rayleigh[2] * rayleighHeight + dust[2] * dustHeight,
    rayleigh[3] * rayleighHeight + dust[3] * dustHeight
  }
end

-- How hard the air can make a star twinkle. It scales with how much of it there
-- is, so Earth twinkles and Mars, at six millibars, essentially does not.
function starField.twinkleFor(profileAtmosphere)
  local pressure = (profileAtmosphere and profileAtmosphere.surfacePressurePa) or 101325.0
  return math.sqrt(math.max(pressure, 0.0) / 101325.0)
end

return starField
