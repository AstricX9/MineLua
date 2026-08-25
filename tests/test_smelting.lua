package.path = "src/?.lua;" .. package.path

local Inventory=require("inventory")
local hud=require("hud")

local inventory=Inventory.new("survival")
inventory.furnace.input={item="iron_ore",count=2}
inventory.furnace.fuel={item="coal",count=1}

assert(inventory:updateSmelting(9.9),"igniting should consume one fuel item")
assert(inventory.furnace.burnTime>0 and inventory.furnace.cookTime>9,
  "valid fuel should ignite and advance cooking")
assert(inventory:updateSmelting(0.2),"finishing a recipe should change stacks")
assert(inventory.furnace.input.count==1,"smelting should consume one input")
assert(inventory.furnace.output.item=="iron_ingot" and inventory.furnace.output.count==1,
  "iron ore should smelt into an iron ingot")

inventory.cursor={item="sand",count=3}
assert(inventory:swapFurnace("furnace_input"),"valid smelting input should enter its slot")
assert(inventory.cursor and inventory.cursor.item=="iron_ore",
  "placing a different input should swap with the existing stack")
inventory.cursor={item="flint",count=1}
assert(not inventory:swapFurnace("furnace_fuel"),"non-fuel items should be rejected from the fuel slot")

local width,height=800,600
local input=hud.inventorySlotAt("furnace",width,height,350,180,{inventory=inventory})
local fuel=hud.inventorySlotAt("furnace",width,height,350,250,{inventory=inventory})
local output=hud.inventorySlotAt("furnace",width,height,470,220,{inventory=inventory})
assert(input and input.kind=="furnace_input","furnace input slot should be interactive")
assert(fuel and fuel.kind=="furnace_fuel","furnace fuel slot should be interactive")
assert(output and output.kind=="furnace_output","furnace output slot should be interactive")

local saved=inventory:saveState()
local restored=Inventory.new("survival"):restoreState(saved)
assert(restored.furnace.output and restored.furnace.output.item=="iron_ingot",
  "furnace contents should persist with inventory state")

print("smelting tests passed")
