-- First-person held-item model and pose.
--
-- The model is built once per item in a fixed unit space and never rebuilt for
-- animation: swinging, equipping and camera sway are a rotation, a pivot and a
-- translation that the vertex shader applies.  That keeps a ~1000 vertex
-- pixel-extruded tool free to animate every frame without re-uploading it.
--
-- Model space is a unit square centred on the origin. X grows to the right of
-- the screen and Y upwards, and the texture is laid into it flipped across X:
-- read the sheet unflipped and a tool's cutting edge ends up pointing back at
-- the player rather than at whatever they are swinging it into.
local texture = require("texture")
local itemMesh = require("item_mesh")

local HeldItem = {}

-- Authored first-person placement.  Position and size are in pixels against a
-- 720p viewport and scale with the drawable; the angles are degrees.
HeldItem.DEFAULTS = {
  xInset = 161.5,
  yInset = 254.7,
  size = 526.8,
  -- Roll is positive because the model is laid in flipped: mirroring the sheet
  -- reverses which way a screen-plane rotation stands the tool up.
  roll = 35.8,
  yaw = -46.1,
  pitch = -7.2,
  thickness = 1.0 / 16.0,
  perspective = 3.2
}

-- A cube fills its unit square where a tool sprite is mostly transparent, so
-- the same nominal size reads much heavier as a block.  Scale it down until a
-- held cube carries about as much of the frame as a held tool does.
HeldItem.BLOCK_SCALE = 0.42

-- Blocks ignore the tool orientation.  Roll tips a cube like a lozenge instead
-- of turning it, so they keep the three-quarter view generated item models use.
HeldItem.BLOCK_POSE = {roll = 0.0, yaw = -40.0, pitch = 22.0}

-- Swings pivot around a joint outside the model rather than its texture centre,
-- which would just spin the tool on the spot. A tap turns at the wrist; a
-- felling swing comes from the shoulder, so its pivot sits further out.
HeldItem.SWING_PIVOT = {0.22, -0.36, 0.0}
HeldItem.CHOP_PIVOT = {0.10, -0.30, 0.0}

-- A tap is over before you notice it. A felling swing is the whole point of
-- carrying an axe, so it takes as long as the chop cadence it drives.
HeldItem.SWING_SECONDS = 0.28
HeldItem.CHOP_SECONDS = 2.0

-- Where in the swing the blow actually connects. Damage is applied here, not
-- on the button press, so the hit and the animation that sold it are one event.
HeldItem.SWING_IMPACT = 0.42
HeldItem.CHOP_IMPACT = 0.55

-- Axes are two-handed enough to be worth animating differently: everything else
-- keeps the quick overhead tap.
function HeldItem.isHeavy(definition)
  return (definition and definition.toolType == "axe") and true or false
end

function HeldItem.styleFor(definition)
  return HeldItem.isHeavy(definition) and "chop" or "quick"
end

function HeldItem.pivotFor(style)
  return style == "chop" and HeldItem.CHOP_PIVOT or HeldItem.SWING_PIVOT
end

HeldItem.STRIDE_FLOATS = 8

local ATLAS_HALF_TEXEL = 0.5 / 256

function HeldItem.sourceTexture(definition)
  local value = definition and definition.texture
  if type(value) == "table" then
    value = value.top or value.side
    if type(value) == "table" then value = value[1] end
  end
  return type(value) == "string" and value or nil
end

function HeldItem.isSprite(definition)
  return itemMesh.isSprite(definition)
end

local function vertex(out, x, y, z, nx, ny, nz, u, v)
  out[#out + 1] = x
  out[#out + 1] = y
  out[#out + 1] = z
  out[#out + 1] = nx
  out[#out + 1] = ny
  out[#out + 1] = nz
  out[#out + 1] = u
  out[#out + 1] = v
end

local function quad(out, points, normal, uvs)
  local order = {1, 2, 3, 3, 4, 1}
  for i = 1, #order do
    local index = order[i]
    local p, uv = points[index], uvs[index]
    vertex(out, p[1], p[2], p[3], normal[1], normal[2], normal[3], uv[1], uv[2])
  end
end

-- Generated item models are one texel thick.  Build every opaque texel as its
-- own box so each exposed face carries a real normal, and so the transparent
-- part of the sheet never becomes a depth-writing surface.
local function spriteModel(definition)
  local out = {}
  local image = texture.loadPng(HeldItem.sourceTexture(definition))
  if not image then
    -- Without pixel data a flat double-sided card is still usable.
    quad(out, {{-0.5, -0.5, 0.5}, {0.5, -0.5, 0.5}, {0.5, 0.5, 0.5}, {-0.5, 0.5, 0.5}},
      {0, 0, 1}, {{0, 1}, {1, 1}, {1, 0}, {0, 0}})
    quad(out, {{0.5, -0.5, -0.5}, {-0.5, -0.5, -0.5}, {-0.5, 0.5, -0.5}, {0.5, 0.5, -0.5}},
      {0, 0, -1}, {{1, 1}, {0, 1}, {0, 0}, {1, 0}})
    return out
  end

  local function opaque(x, y)
    if x < 0 or y < 0 or x >= image.w or y >= image.h then return false end
    return image.data[(y * image.w + x) * 4 + 3] >= 128
  end
  local function mx(px) return px / image.w - 0.5 end
  local function my(py) return 0.5 - py / image.h end

  for py = 0, image.h - 1 do
    for px = 0, image.w - 1 do
      if opaque(px, py) then
        local x0, x1 = mx(px), mx(px + 1)
        local y0, y1 = my(py), my(py + 1)
        -- Side walls and faces alike sample the centre of their own texel, so
        -- nothing can bleed in from a neighbouring or transparent pixel.
        local u, v = (px + 0.5) / image.w, (py + 0.5) / image.h
        local uvs = {{u, v}, {u, v}, {u, v}, {u, v}}
        quad(out, {{x0, y0, 0.5}, {x1, y0, 0.5}, {x1, y1, 0.5}, {x0, y1, 0.5}}, {0, 0, 1}, uvs)
        quad(out, {{x1, y0, -0.5}, {x0, y0, -0.5}, {x0, y1, -0.5}, {x1, y1, -0.5}}, {0, 0, -1}, uvs)
        local function wall(ax, ay, bx, by, normal)
          quad(out, {{ax, ay, 0.5}, {bx, by, 0.5}, {bx, by, -0.5}, {ax, ay, -0.5}}, normal, uvs)
        end
        if not opaque(px - 1, py) then wall(x0, y1, x0, y0, {-1, 0, 0}) end
        if not opaque(px + 1, py) then wall(x1, y0, x1, y1, {1, 0, 0}) end
        if not opaque(px, py - 1) then wall(x0, y0, x1, y0, {0, 1, 0}) end
        if not opaque(px, py + 1) then wall(x1, y1, x0, y1, {0, -1, 0}) end
      end
    end
  end
  return out
end

-- Held blocks are cubes drawn straight from the terrain atlas, so a placed
-- block and the one in hand are lit and textured by the same pixels.
local function blockModel(definition)
  local out = {}
  local uvs = definition.uvs or {}
  local function face(uv)
    uv = uv or definition.uv or uvs.side or uvs.top
    if not uv then return nil end
    local du = math.min(ATLAS_HALF_TEXEL, (uv.u1 - uv.u0) * 0.25)
    local dv = math.min(ATLAS_HALF_TEXEL, (uv.v1 - uv.v0) * 0.25)
    local u0, v0, u1, v1 = uv.u0 + du, uv.v0 + dv, uv.u1 - du, uv.v1 - dv
    return {{u0, v0}, {u1, v0}, {u1, v1}, {u0, v1}}
  end

  local h = 0.5
  local sides = {
    -- points wound so the first UV corner is the face's top-left texel
    {{{-h, h, h}, {h, h, h}, {h, -h, h}, {-h, -h, h}}, {0, 0, 1}, uvs.front or uvs.side},
    {{{h, h, -h}, {-h, h, -h}, {-h, -h, -h}, {h, -h, -h}}, {0, 0, -1}, uvs.back or uvs.side},
    {{{h, h, h}, {h, h, -h}, {h, -h, -h}, {h, -h, h}}, {1, 0, 0}, uvs.side},
    {{{-h, h, -h}, {-h, h, h}, {-h, -h, h}, {-h, -h, -h}}, {-1, 0, 0}, uvs.side},
    {{{-h, h, -h}, {h, h, -h}, {h, h, h}, {-h, h, h}}, {0, 1, 0}, uvs.top},
    {{{-h, -h, h}, {h, -h, h}, {h, -h, -h}, {-h, -h, -h}}, {0, -1, 0}, uvs.bottom or uvs.top}
  }
  for _, entry in ipairs(sides) do
    local uv = face(entry[3])
    if uv then quad(out, entry[1], entry[2], uv) end
  end
  return out
end

-- Returns the model vertices plus how the pass should texture them: sprites
-- bind their own PNG so the huge first-person model never picks up atlas
-- neighbours, blocks bind the shared terrain atlas.
function HeldItem.model(definition)
  if not definition then return nil end
  if HeldItem.isSprite(definition) then
    return {vertices = spriteModel(definition), source = HeldItem.sourceTexture(definition), sprite = true}
  end
  if not definition.uvs then return nil end
  return {vertices = blockModel(definition), atlas = true, sprite = false}
end

local function rotationMatrix(rollDeg, yawDeg, pitchDeg)
  local roll, yaw, pitch = math.rad(rollDeg), math.rad(yawDeg), math.rad(pitchDeg)
  local cr, sr = math.cos(roll), math.sin(roll)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local function rotate(x, y, z)
    local x1, y1 = x * cr - y * sr, x * sr + y * cr
    local x2, z2 = x1 * cy + z * sy, -x1 * sy + z * cy
    return x2, y1 * cp - z2 * sp, y1 * sp + z2 * cp
  end
  -- Column major, which is what glUniformMatrix3fv wants untransposed.
  local ax, ay, az = rotate(1, 0, 0)
  local bx, by, bz = rotate(0, 1, 0)
  local cx, cyy, cz = rotate(0, 0, 1)
  return {ax, ay, az, bx, by, bz, cx, cyy, cz}
end

HeldItem.rotationMatrix = rotationMatrix

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local REST_POSE = {roll = 0, yaw = 0, pitch = 0, x = 0, y = 0, z = 0}

local function smoothstep(x)
  x = clamp(x, 0.0, 1.0)
  return x * x * (3.0 - 2.0 * x)
end

-- The quick tap. `progress` is one 0..1 cycle: the tool drops back and to the
-- right, then the wrist drives it down and across so the head traces an arc
-- through the middle of the frame instead of sliding sideways.
local function tapPose(t)
  local lead = math.sin(t ^ 0.75 * math.pi)          -- strikes early, recovers slowly
  local follow = math.sin(t * t * math.pi)           -- lags behind the lead
  local lift = math.sin(math.sqrt(t) * math.pi * 2.0) -- up out of frame, then through
  return {
    -- Roll carries most of the arc: with the pivot below and right of the
    -- model, rolling forwards sweeps the head down and across the crosshair
    -- instead of jabbing it straight ahead. Pitch tips the head away as it
    -- travels so the arc has depth, and the lift lets it rise before it falls.
    roll = 38.0 * lead,
    pitch = -32.0 * lead,
    yaw = -10.0 * lead,
    x = -0.06 * lead,
    y = 0.12 * lift,
    z = -0.15 * follow
  }
end

-- How far along the felling swing the axe is: +1 fully cocked back over the
-- right shoulder, 0 at rest, negative through the follow-through past the far
-- side. Wind up slowly, cross fast, coast back.
local CHOP_WINDUP = 0.36
local CHOP_STRIKE = 0.58
local CHOP_OVERSHOOT = 1.45

local function chopAmount(t)
  if t < CHOP_WINDUP then
    return smoothstep(t / CHOP_WINDUP)
  end
  if t < CHOP_STRIKE then
    local k = (t - CHOP_WINDUP) / (CHOP_STRIKE - CHOP_WINDUP)
    -- Ease out, so the blade is quickest as it passes the crosshair.
    return 1.0 - (1.0 + CHOP_OVERSHOOT) * (1.0 - (1.0 - k) * (1.0 - k))
  end
  local k = (t - CHOP_STRIKE) / (1.0 - CHOP_STRIKE)
  return -CHOP_OVERSHOOT * (1.0 - smoothstep(k))
end

-- The felling swing: a wide horizontal sweep from the right shoulder across the
-- view, the way a two-handed axe is actually used, rather than a tap on the
-- spot. Yaw carries the sweep and the translation carries the reach, so the
-- head crosses the crosshair edge-on instead of skimming past it flat.
local function chopPose(t)
  local a = chopAmount(t)
  -- The two halves are not mirror images: the wind-up only has to leave the
  -- frame's edge, while the strike has to carry the head all the way across it.
  local back = math.max(0.0, a)
  local through = math.max(0.0, -a)
  return {
    -- Yaw turns the blade face-on as the swing leaves rest, in both halves:
    -- the authored pose is oblique enough that adding to it edge-on would make
    -- the axe vanish to a line at exactly the moment you want to see it.
    roll = 46.0 * a,
    yaw = 20.0 * math.abs(a),
    pitch = -8.0 * a,
    x = 0.44 * back - 1.10 * through,
    y = 0.16 * back - 0.08 * through,
    z = 0.10 * back - 0.06 * through
  }
end

function HeldItem.swingPose(progress, style)
  local t = clamp(progress or 0.0, 0.0, 1.0)
  -- Both ends of the cycle are the rest pose exactly. Letting the curves land
  -- on their own leaves a residual tilt that never quite settles.
  if t <= 0.0 or t >= 1.0 then return REST_POSE end
  if style == "chop" then return chopPose(t) end
  return tapPose(t)
end

-- Raising a newly selected item.  `progress` runs 0..1 while it comes up.
function HeldItem.equipPose(progress)
  local t = clamp(progress or 1.0, 0.0, 1.0)
  local dip = (1.0 - t) * (1.0 - t)
  return {pitch = -34.0 * dip, roll = 0.0, yaw = 0.0, x = 0.0, y = -1.15 * dip, z = 0.0}
end

-- Camera-driven sway.  `lookX`/`lookY` are smoothed turn rates in degrees per
-- second and `walk` is a 0..1 walk cycle phase; both come back as pixel offsets
-- against the 720p reference placement.
function HeldItem.motionOffset(motion)
  motion = motion or {}
  local lookX = clamp(motion.lookX or 0.0, -220.0, 220.0)
  local lookY = clamp(motion.lookY or 0.0, -220.0, 220.0)
  local bob = motion.bob or 0.0
  local phase = (motion.walkPhase or 0.0) * math.pi * 2.0
  return {
    -- xInset counts from the right edge, so a rightward turn has to shrink it
    -- for the tool to trail behind the view.
    x = -lookX * 0.16 + math.sin(phase) * 5.0 * bob,
    y = lookY * 0.14 + math.abs(math.cos(phase)) * 4.0 * bob
  }
end

-- Advances the swing cycle and reports the frame the blow connects.
--
-- `state.handSwing` is the phase of the current swing, not mining progress: the
-- break bar has its own timer, and a swing stretched to match a stone block
-- would barely appear to move. The style and length are fixed when the swing
-- starts, so changing target mid-swing cannot stutter the animation.
function HeldItem.updateSwing(state, dt, attacking, heavy)
  local landed = false
  if attacking and not state.handSwinging then
    state.handSwinging = true
    state.handSwing = 0.0
    state.handSwingStyle = heavy and "chop" or "quick"
    state.handSwingSeconds = heavy and HeldItem.CHOP_SECONDS or HeldItem.SWING_SECONDS
  end
  if not state.handSwinging then
    state.handSwing = 0.0
    return false
  end

  local impact = state.handSwingStyle == "chop" and HeldItem.CHOP_IMPACT or HeldItem.SWING_IMPACT
  local before = state.handSwing or 0.0
  local after = before + math.max(0.0, dt or 0.0) /
    math.max(0.05, state.handSwingSeconds or HeldItem.SWING_SECONDS)
  if before < impact and after >= impact then landed = true end
  if after >= 1.0 then
    if attacking then
      after = after % 1.0
      -- A frame long enough to wrap the cycle still owes the next blow.
      if not landed and after >= impact then landed = true end
      state.handSwingStyle = heavy and "chop" or "quick"
      state.handSwingSeconds = heavy and HeldItem.CHOP_SECONDS or HeldItem.SWING_SECONDS
    else
      state.handSwinging = false
      after = 0.0
    end
  end
  state.handSwing = after
  return landed
end

-- Sway for the first-person model. The hand trails a fast turn and settles
-- again once the view stops, which is what sells the model as carried rather
-- than pinned to the screen.
function HeldItem.updateMotion(motion, camera, dt)
  if not motion or not camera then return end
  dt = math.max(1.0 / 240.0, math.min(0.1, dt or 0.0))
  local yaw, pitch = camera.yaw or 0.0, camera.pitch or 0.0
  if motion.yaw == nil then motion.yaw, motion.pitch = yaw, pitch end
  -- Yaw here is unbounded, so wrap the difference: a turn past 180 degrees is
  -- still a small movement, not a full spin.
  local yawDelta = (yaw - motion.yaw + 180.0) % 360.0 - 180.0
  local pitchDelta = pitch - motion.pitch
  motion.yaw, motion.pitch = yaw, pitch

  local blend = math.min(1.0, dt * 12.0)
  motion.lookX = (motion.lookX or 0.0) + (yawDelta / dt - (motion.lookX or 0.0)) * blend
  motion.lookY = (motion.lookY or 0.0) + (pitchDelta / dt - (motion.lookY or 0.0)) * blend

  local velocity = camera.velocity or {0, 0, 0}
  local speed = math.sqrt(velocity[1] * velocity[1] + velocity[3] * velocity[3])
  local walking = camera.grounded and speed > 0.6
  local target = walking and math.min(1.0, speed / (camera.walkSpeed or 5.1)) or 0.0
  motion.bob = (motion.bob or 0.0) + (target - (motion.bob or 0.0)) * math.min(1.0, dt * 8.0)
  if walking then
    motion.walkPhase = ((motion.walkPhase or 0.0) + dt * speed * 0.42) % 1.0
  end
end

return HeldItem
