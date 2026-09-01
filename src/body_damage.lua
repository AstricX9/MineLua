local persistence = require("state_persistence")

local BodyDamage = {}
BodyDamage.__index = BodyDamage

BodyDamage.MAX_HEALTH = 100
BodyDamage.REGIONS = {
  "head", "body", "left_arm", "right_arm", "left_leg", "right_leg"
}

local REGION_SET = {}
for _, name in ipairs(BodyDamage.REGIONS) do REGION_SET[name] = true end

-- Head and torso contribute more to survival than a limb. The resulting
-- vitality is the seventh, overall condition shown by the regular heart row;
-- it is derived from the six physical regions and cannot be damaged directly.
local VITALITY_WEIGHTS = {
  head = 0.28,
  body = 0.32,
  left_arm = 0.10,
  right_arm = 0.10,
  left_leg = 0.10,
  right_leg = 0.10
}

local REGION_HEIGHTS = {
  {name = "head", minimum = 0.82},
  {name = "body", minimum = 0.48},
  {name = "left_arm", minimum = 0.30}
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function freshPart()
  return {health = BodyDamage.MAX_HEALTH, flash = 0.0, flashKind = nil}
end

local function normalizedPart(part)
  part = type(part) == "table" and part or freshPart()
  part.health = clamp(part.health, 0, BodyDamage.MAX_HEALTH)
  part.flash = math.max(0, tonumber(part.flash) or 0)
  if part.flashKind ~= "damage" and part.flashKind ~= "healing" then
    part.flashKind = nil
  end
  return part
end

function BodyDamage.new(saved)
  local self = setmetatable({parts = {}, headTrauma = 0.0}, BodyDamage)
  for _, name in ipairs(BodyDamage.REGIONS) do self.parts[name] = freshPart() end
  if type(saved) == "table" then self:restoreState(saved) end
  return self
end

function BodyDamage:part(name)
  return self.parts[REGION_SET[name] and name or "body"]
end

function BodyDamage:condition(name)
  return self:part(name).health / BodyDamage.MAX_HEALTH
end

function BodyDamage:injuryState(name)
  local condition = self:condition(name)
  if condition <= 0.25 then return "critical" end
  if condition <= 0.50 then return "badly_damaged" end
  if condition <= 0.75 then return "damaged" end
  return "normal"
end

function BodyDamage:vitality()
  local total = 0.0
  for name, weight in pairs(VITALITY_WEIGHTS) do
    total = total + self:condition(name) * weight
  end
  return clamp(total, 0.0, 1.0)
end

function BodyDamage:isIncapacitated()
  return self:part("head").health <= 0 or self:part("body").health <= 0
end

-- Protection is a fraction in [0, 0.8]. Passing {helmet=...} or {armor=...}
-- keeps head and torso equipment independent; callers may also supply a
-- region-named value for limb-specific equipment later.
function BodyDamage:applyDamage(name, amount, protection)
  name = REGION_SET[name] and name or "body"
  amount = math.max(0, tonumber(amount) or 0)
  protection = protection or {}
  local reduction = protection[name]
  if reduction == nil and name == "head" then reduction = protection.helmet end
  if reduction == nil and name == "body" then reduction = protection.armor end
  reduction = clamp(reduction or 0, 0, 0.8)

  local part = self.parts[name]
  local applied = math.min(part.health, amount * (1.0 - reduction))
  part.health = part.health - applied
  if applied > 0 then
    part.flash = 0.32
    part.flashKind = "damage"
    if name == "head" then
      self.headTrauma = math.max(self.headTrauma,
        0.45 + applied / BodyDamage.MAX_HEALTH * 2.8)
    end
  end
  return applied, self:injuryState(name)
end

function BodyDamage:heal(name, amount)
  name = REGION_SET[name] and name or "body"
  amount = math.max(0, tonumber(amount) or 0)
  local part = self.parts[name]
  local restored = math.min(BodyDamage.MAX_HEALTH - part.health, amount)
  part.health = part.health + restored
  if restored > 0 then
    part.flash = 0.38
    part.flashKind = "healing"
  end
  return restored
end

-- Falls land through the feet: both legs take the bulk of the impact and a
-- small torso jolt appears only on especially hard landings.
function BodyDamage:applyFall(impactSpeed, protection)
  impactSpeed = math.max(0, tonumber(impactSpeed) or 0)
  if impactSpeed <= 8.0 then return 0 end
  local damage = (impactSpeed - 8.0) * 4.0
  local left = self:applyDamage("left_leg", damage * 0.5, protection)
  local right = self:applyDamage("right_leg", damage * 0.5, protection)
  local torso = 0
  if impactSpeed > 15.0 then
    torso = self:applyDamage("body", (impactSpeed - 15.0) * 1.25, protection)
  end
  return left + right + torso
end

-- Hit height is normalized from feet (0) to crown (1). Side chooses an arm or
-- leg when known; otherwise alternating/random callers can pass either side.
function BodyDamage.regionForHit(height, side)
  height = clamp(height, 0, 1)
  side = side == "left" and "left" or "right"
  if height >= REGION_HEIGHTS[1].minimum then return "head" end
  if height >= REGION_HEIGHTS[2].minimum then return "body" end
  if height >= REGION_HEIGHTS[3].minimum then return side .. "_arm" end
  return side .. "_leg"
end

function BodyDamage:applyHit(height, side, amount, protection)
  local region = BodyDamage.regionForHit(height, side)
  local applied, state = self:applyDamage(region, amount, protection)
  return region, applied, state
end

function BodyDamage:movementMultiplier()
  local left, right = self:condition("left_leg"), self:condition("right_leg")
  local average, worst = (left + right) * 0.5, math.min(left, right)
  local multiplier = 0.42 + average * 0.58
  if worst <= 0.25 then multiplier = multiplier - 0.12 end
  if left <= 0.50 and right <= 0.50 then multiplier = multiplier - 0.16 end
  return clamp(multiplier, 0.20, 1.0)
end

function BodyDamage:actionMultiplier()
  local left, right = self:condition("left_arm"), self:condition("right_arm")
  local average, worst = (left + right) * 0.5, math.min(left, right)
  return clamp(0.38 + average * 0.47 + worst * 0.15, 0.32, 1.0)
end

function BodyDamage:strengthMultiplier()
  local left, right = self:condition("left_arm"), self:condition("right_arm")
  return clamp(0.45 + (left + right) * 0.275, 0.45, 1.0)
end

function BodyDamage:recoveryMultiplier()
  return clamp(0.35 + self:condition("body") * 0.65, 0.35, 1.0)
end

function BodyDamage:sprintMultiplier()
  return clamp(0.55 + self:condition("body") * 0.45, 0.55, 1.0)
end

function BodyDamage:update(dt)
  dt = math.max(0, tonumber(dt) or 0)
  self.headTrauma = math.max(0, (self.headTrauma or 0) - dt)
  for _, name in ipairs(BodyDamage.REGIONS) do
    local part = self.parts[name]
    part.flash = math.max(0, (part.flash or 0) - dt)
    if part.flash == 0 then part.flashKind = nil end
  end
end

function BodyDamage:headEffect()
  local trauma = math.max(0, self.headTrauma or 0)
  local severity = 1.0 - self:condition("head")
  local active = trauma > 0 and math.min(1.0, trauma / 0.9) or 0.0
  return {
    shake = active * (0.35 + severity * 1.65),
    blur = active * (0.45 + severity * 2.25)
  }
end

function BodyDamage:color(name)
  local part = self:part(name)
  if (part.flash or 0) > 0 then
    if part.flashKind == "healing" then return {0.30, 0.90, 0.38, 1.0} end
    return {1.0, 0.08, 0.06, 1.0}
  end
  local health = part.health
  if health <= 25 then return {0.86, 0.10, 0.08, 1.0} end
  if health <= 50 then return {0.95, 0.38, 0.08, 1.0} end
  if health <= 75 then return {0.96, 0.78, 0.10, 1.0} end
  if health < BodyDamage.MAX_HEALTH then return {0.38, 0.78, 0.30, 1.0} end
  return {0.47, 0.49, 0.52, 1.0}
end

function BodyDamage:saveState()
  return persistence.snapshot(self)
end

function BodyDamage:restoreState(saved)
  if type(saved) == "table" then persistence.restore(self, saved) end
  self.parts = type(self.parts) == "table" and self.parts or {}
  for _, name in ipairs(BodyDamage.REGIONS) do
    self.parts[name] = normalizedPart(self.parts[name])
  end
  self.headTrauma = math.max(0, tonumber(self.headTrauma) or 0)
  return self
end

return BodyDamage
