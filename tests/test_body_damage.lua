package.path = "src/?.lua;" .. package.path

local BodyDamage = require("body_damage")

local body = BodyDamage.new()
assert(#BodyDamage.REGIONS == 6, "six physical body regions should be tracked")
assert(math.abs(body:vitality() - 1) < 1e-9 and body:movementMultiplier() == 1 and
  math.abs(body:actionMultiplier() - 1) < 1e-9,
  "an uninjured body should have no penalties")

local applied = body:applyDamage("head", 50, {helmet = 0.5})
assert(applied == 25 and body:part("head").health == 75,
  "helmet protection should apply only to incoming head damage")
assert(body:headEffect().shake > 0 and body:headEffect().blur > 0,
  "head hits should trigger disorientation effects")

body:applyDamage("left_arm", 70)
assert(body:condition("right_arm") == 1,
  "left and right arm health must remain independent")
assert(body:actionMultiplier() < 1 and body:strengthMultiplier() < 1,
  "arm injuries should slow and weaken tool use")

body:applyDamage("left_leg", 65)
local oneLeg = body:movementMultiplier()
body:applyDamage("right_leg", 65)
assert(body:movementMultiplier() < oneLeg,
  "two injured legs should penalize movement more than one")

local fallBody = BodyDamage.new()
assert(fallBody:applyFall(7.9) == 0, "small landings should not cause damage")
assert(fallBody:applyFall(12) > 0 and fallBody:condition("left_leg") < 1 and
  fallBody:condition("right_leg") < 1 and fallBody:condition("head") == 1,
  "fall damage should route primarily and evenly to the legs")

assert(BodyDamage.regionForHit(0.9, "left") == "head")
assert(BodyDamage.regionForHit(0.6, "right") == "body")
assert(BodyDamage.regionForHit(0.4, "left") == "left_arm")
assert(BodyDamage.regionForHit(0.1, "right") == "right_leg")

local restored = BodyDamage.new(body:saveState())
assert(restored:part("head").health == body:part("head").health and
  restored:part("left_arm").health == body:part("left_arm").health,
  "regional injuries should survive a persistence round trip")

print("body damage tests passed")
