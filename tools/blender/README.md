# MineLua first-person Blender scene

`create_first_person_pov.py` builds an animation-ready, transparent first-person
shot from the real MineLua item and skin textures. Its camera, screen placement,
item thickness, wrist pivot, quick swing, and nine-pose axe chop come from
`src/held_item.lua` and `src/hud.lua`.

## Use it in Blender

1. Open Blender and switch to **Scripting**.
2. Open `tools/blender/create_first_person_pov.py` in the Text Editor.
3. Press **Run Script**.
4. Use the timeline and render RGBA PNG frames. The default scene is the wooden
   axe with the chop animation at 60 fps and 1280x720.

To choose another item in the Scripting workspace, change `DEFAULT_ITEM_KEY`
near the top of the script before running it.

The useful controls are named `FP_Pose_CTRL`, `FP_Swing_CTRL`,
`FP_ProjectionScale`, and `FP_Arm_CTRL`. The item placement is exact to the game;
`FP_Arm_CTRL` is intentionally independent so the new hand's grip can be tuned
without changing the item reference pose.

## Command line

```powershell
blender --background --python tools/blender/create_first_person_pov.py -- --item stone_pickaxe --save
```

Options:

- `--item wood_axe` selects `assets/textures/items/wood_axe.png`.
- `--texture C:\path\custom.png` uses a custom item texture.
- `--style auto|quick|chop|idle` chooses the animation.
- `--fps 60 --width 1280 --height 720` controls output timing and resolution.
- `--save` writes a `.blend` into `tools/blender/`.
- `--render` renders the complete RGBA PNG sequence into
  `tools/blender/renders/<item>/`.

The script clears objects in the current Blender scene before rebuilding it, so
run it in a new file or save unrelated work first.
