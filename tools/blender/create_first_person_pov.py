"""Build MineLua's first-person held-item shot in Blender.

Run from Blender's Scripting workspace, or from a command line:

    blender --background --python tools/blender/create_first_person_pov.py -- \
        --item wood_axe --save

The camera and item transform mirror src/held_item.lua and src/hud.lua.  The
generated item is not a flat card: every opaque source texel becomes a one-
texel-thick box, exactly as it does in MineLua.  A UV-mapped Steve right arm is
added to the same wrist hierarchy so animation reference frames include a hand.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix


# Edit this one value when running from Blender's Scripting workspace. Command
# line arguments override it when the script is run headlessly.
DEFAULT_ITEM_KEY = "wood_axe"

# These values are the 720p authoring values in src/held_item.lua.  Keep them
# here instead of approximating the composition by eye.
DEFAULTS = {
    "x_inset": (1.0 - 0.56) * 1280.0 * 0.5,
    "y_inset": (1.0 - 0.52) * 720.0 * 0.5,
    "size": 720.0,
    "roll": 0.0,
    "yaw": -45.0,
    "pitch": 0.0,
    "depth": -0.72,
    "thickness": 1.0 / 16.0,
    "perspective": 3.2,
}

QUICK_PIVOT = (0.22, -0.36, 0.0)
CHOP_PIVOT = (0.0, 0.0, 0.0)
QUICK_SECONDS = 0.280
CHOP_SECONDS = 0.340

CHOP_FRAMES = (
    (0, 161.5, 254.7, 526.8, 35.8, -46.1, -2.0),
    (45, 105.0, 235.0, 535.0, 47.0, -52.0, -4.0),
    (85, 145.0, 270.0, 545.0, 30.0, -48.0, -7.0),
    (120, 310.0, 300.0, 560.0, 5.0, -40.0, -11.0),
    (150, 540.0, 290.0, 575.0, -28.0, -28.0, -14.0),
    (180, 720.0, 255.0, 555.0, -48.0, -20.0, -10.0),
    (230, 430.0, 230.0, 535.0, -10.0, -34.0, -5.0),
    (285, 230.0, 245.0, 528.0, 24.0, -43.0, -3.0),
    (340, 161.5, 254.7, 526.8, 35.8, -46.1, -2.0),
)
CHOP_REFERENCE = CHOP_FRAMES[0]


def project_root() -> Path:
    if "__file__" in globals():
        return Path(__file__).resolve().parents[2]
    if bpy.data.filepath:
        candidate = Path(bpy.data.filepath).resolve().parent
        for folder in (candidate, *candidate.parents):
            if (folder / "src" / "held_item.lua").is_file():
                return folder
    return Path.cwd()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item", default=DEFAULT_ITEM_KEY, help="assets/textures/items/<item>.png")
    parser.add_argument("--texture", type=Path, help="override the item PNG")
    parser.add_argument("--style", choices=("auto", "quick", "chop", "idle"), default="auto")
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--save", action="store_true", help="save a .blend beside this script")
    parser.add_argument("--render", action="store_true", help="render the generated animation")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def rotation_matrix(roll_deg: float, yaw_deg: float, pitch_deg: float) -> Matrix:
    """Return the same Rz-roll, Ry-yaw, Rx-pitch transform used by MineLua."""
    roll, yaw, pitch = map(math.radians, (roll_deg, yaw_deg, pitch_deg))
    cr, sr = math.cos(roll), math.sin(roll)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)

    def rotate(x: float, y: float, z: float) -> tuple[float, float, float]:
        x1, y1 = x * cr - y * sr, x * sr + y * cr
        x2, z2 = x1 * cy + z * sy, -x1 * sy + z * cy
        return x2, y1 * cp - z2 * sp, y1 * sp + z2 * cp

    a, b, c = rotate(1, 0, 0), rotate(0, 1, 0), rotate(0, 0, 1)
    return Matrix(((a[0], b[0], c[0]), (a[1], b[1], c[1]), (a[2], b[2], c[2])))


def set_rotation(obj: bpy.types.Object, roll: float, yaw: float, pitch: float) -> None:
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = rotation_matrix(roll, yaw, pitch).to_quaternion()


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in tuple(bpy.data.collections):
        bpy.data.collections.remove(collection)


def new_empty(name: str, parent: bpy.types.Object | None, collection: bpy.types.Collection,
              display: str = "PLAIN_AXES", size: float = 0.18) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display
    obj.empty_display_size = size
    collection.objects.link(obj)
    obj.parent = parent
    return obj


def load_image(path: Path) -> bpy.types.Image:
    if not path.is_file():
        raise FileNotFoundError(f"Texture not found: {path}")
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = "sRGB"
    try:
        image.alpha_mode = "STRAIGHT"
    except Exception:
        pass
    return image


def image_material(name: str, image: bpy.types.Image) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (1, 1, 1, 1)
    try:
        material.surface_render_method = "DITHERED"
    except Exception:
        try:
            material.blend_method = "CLIP"
            material.alpha_threshold = 0.5
        except Exception:
            pass

    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "CLIP"
    material.node_tree.links.new(texture.outputs["Color"], emission.inputs["Color"])
    material.node_tree.links.new(texture.outputs["Alpha"], mix.inputs[0])
    material.node_tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    material.node_tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    material.node_tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def mesh_from_faces(name: str, faces: list[tuple[list[tuple[float, float, float]],
                                                    list[tuple[float, float]]]],
                    material: bpy.types.Material, collection: bpy.types.Collection,
                    parent: bpy.types.Object) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    polygons: list[tuple[int, int, int, int]] = []
    uvs: list[tuple[float, float]] = []
    for points, face_uvs in faces:
        start = len(vertices)
        vertices.extend(points)
        polygons.append((start, start + 1, start + 2, start + 3))
        uvs.extend(face_uvs)

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], polygons)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            uv_layer.data[loop_index].uv = uvs[mesh.loops[loop_index].vertex_index]

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def pixel_item(name: str, image: bpy.types.Image, material: bpy.types.Material,
               collection: bpy.types.Collection, parent: bpy.types.Object) -> bpy.types.Object:
    width, height = map(int, image.size)
    pixels = list(image.pixels[:])

    def opaque(px: int, py: int) -> bool:
        if px < 0 or py < 0 or px >= width or py >= height:
            return False
        blender_y = height - 1 - py
        return pixels[(blender_y * width + px) * 4 + 3] >= 0.5

    faces = []
    z_front, z_back = 0.5, -0.5
    for py in range(height):
        for px in range(width):
            if not opaque(px, py):
                continue
            x0, x1 = px / width - 0.5, (px + 1) / width - 0.5
            y_top, y_bottom = 0.5 - py / height, 0.5 - (py + 1) / height
            u, v = (px + 0.5) / width, 1.0 - (py + 0.5) / height
            uv = [(u, v)] * 4
            faces.append(([(x0, y_bottom, z_front), (x1, y_bottom, z_front),
                           (x1, y_top, z_front), (x0, y_top, z_front)], uv))
            faces.append(([(x1, y_bottom, z_back), (x0, y_bottom, z_back),
                           (x0, y_top, z_back), (x1, y_top, z_back)], uv))
            if not opaque(px - 1, py):
                faces.append(([(x0, y_bottom, z_front), (x0, y_top, z_front),
                               (x0, y_top, z_back), (x0, y_bottom, z_back)], uv))
            if not opaque(px + 1, py):
                faces.append(([(x1, y_bottom, z_back), (x1, y_top, z_back),
                               (x1, y_top, z_front), (x1, y_bottom, z_front)], uv))
            if not opaque(px, py - 1):
                faces.append(([(x0, y_top, z_front), (x1, y_top, z_front),
                               (x1, y_top, z_back), (x0, y_top, z_back)], uv))
            if not opaque(px, py + 1):
                faces.append(([(x0, y_bottom, z_back), (x1, y_bottom, z_back),
                               (x1, y_bottom, z_front), (x0, y_bottom, z_front)], uv))

    obj = mesh_from_faces(name, faces, material, collection, parent)
    obj.scale = (1.0, 1.0, DEFAULTS["thickness"])
    obj["source_texture"] = image.filepath
    obj["pixel_extruded"] = True
    return obj


def rect_uv(rect: tuple[int, int, int, int], width: int, height: int) -> list[tuple[float, float]]:
    x0, y0, x1, y1 = rect
    u0, u1 = x0 / width, x1 / width
    v_top, v_bottom = 1.0 - y0 / height, 1.0 - y1 / height
    return [(u0, v_bottom), (u1, v_bottom), (u1, v_top), (u0, v_top)]


def arm_box(name: str, size: tuple[float, float, float], rects: dict[str, tuple[int, int, int, int]],
            image: bpy.types.Image, material: bpy.types.Material,
            collection: bpy.types.Collection, parent: bpy.types.Object) -> bpy.types.Object:
    sx, sy, sz = (component * 0.5 for component in size)
    # Each face starts at its lower-left geometric corner. rect_uv applies the
    # Minecraft skin sheet's top-left image coordinates.
    points = {
        "front": [(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)],
        "back": [(sx, -sy, -sz), (-sx, -sy, -sz), (-sx, sy, -sz), (sx, sy, -sz)],
        "left": [(-sx, -sy, sz), (-sx, sy, sz), (-sx, sy, -sz), (-sx, -sy, -sz)],
        "right": [(sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz), (sx, -sy, sz)],
        "top": [(-sx, sy, sz), (sx, sy, sz), (sx, sy, -sz), (-sx, sy, -sz)],
        "bottom": [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)],
    }
    width, height = map(int, image.size)
    faces = [(points[face], rect_uv(rects[face], width, height)) for face in points]
    return mesh_from_faces(name, faces, material, collection, parent)


def create_arm(image: bpy.types.Image, collection: bpy.types.Collection,
               pose_parent: bpy.types.Object) -> bpy.types.Object:
    base_rects = {
        "top": (44, 16, 48, 20), "bottom": (48, 16, 52, 20),
        "left": (48, 20, 52, 32), "front": (44, 20, 48, 32),
        "right": (40, 20, 44, 32), "back": (52, 20, 56, 32),
    }
    sleeve_rects = {
        "top": (44, 32, 48, 36), "bottom": (48, 32, 52, 36),
        "left": (48, 36, 52, 48), "front": (44, 36, 48, 48),
        "right": (40, 36, 44, 48), "back": (52, 36, 56, 48),
    }
    material = image_material("MAT_SteveArm", image)
    arm_ctrl = new_empty("FP_Arm_CTRL", pose_parent, collection, "CUBE", 0.13)
    # The top end is the hand/grip; the lower end exits at the bottom-right of
    # the frame. These are deliberately separate controls for user-authored
    # grip corrections without disturbing the exact item placement.
    arm_ctrl.location = (0.12, -0.55, 0.18)
    set_rotation(arm_ctrl, 50.0, -8.0, -5.0)
    arm_box("FP_RightArm", (0.25, 0.75, 0.25), base_rects, image, material, collection, arm_ctrl)
    sleeve = arm_box("FP_RightSleeve", (0.268, 0.768, 0.268), sleeve_rects,
                     image, material, collection, arm_ctrl)
    sleeve["skin_overlay"] = True
    return arm_ctrl


def frame_tangent(index: int, field: int) -> float:
    if index <= 0 or index >= len(CHOP_FRAMES) - 1:
        return 0.0
    previous, following = CHOP_FRAMES[index - 1], CHOP_FRAMES[index + 1]
    return (following[field] - previous[field]) / max(0.0001, following[0] - previous[0])


def smooth_chop_field(index: int, field: int, time_ms: float) -> float:
    a, b = CHOP_FRAMES[index], CHOP_FRAMES[index + 1]
    span = max(0.0001, b[0] - a[0])
    k = clamp((time_ms - a[0]) / span, 0.0, 1.0)
    k2, k3 = k * k, k * k * k
    h00, h10 = 2 * k3 - 3 * k2 + 1, k3 - 2 * k2 + k
    h01, h11 = -2 * k3 + 3 * k2, k3 - k2
    return (h00 * a[field] + h10 * span * frame_tangent(index, field) +
            h01 * b[field] + h11 * span * frame_tangent(index + 1, field))


def chop_pose(progress: float) -> dict[str, float]:
    time_ms = clamp(progress, 0.0, 1.0) * 340.0
    segment = len(CHOP_FRAMES) - 2
    for index in range(len(CHOP_FRAMES) - 1):
        if time_ms <= CHOP_FRAMES[index + 1][0]:
            segment = index
            break
    absolute = [smooth_chop_field(segment, field, time_ms) for field in range(1, 7)]
    return {
        "x_inset": DEFAULTS["x_inset"] + absolute[0] - CHOP_REFERENCE[1],
        "y_inset": DEFAULTS["y_inset"] + absolute[1] - CHOP_REFERENCE[2],
        "scale": absolute[2] / CHOP_REFERENCE[3],
        "roll": DEFAULTS["roll"] + absolute[3] - CHOP_REFERENCE[4],
        "yaw": DEFAULTS["yaw"] + absolute[4] - CHOP_REFERENCE[5],
        "pitch": DEFAULTS["pitch"] + absolute[5] - CHOP_REFERENCE[6],
        "x": 0.0, "y": 0.0, "z": 0.0,
    }


def quick_pose(progress: float) -> dict[str, float]:
    t = clamp(progress, 0.0, 1.0)
    if t <= 0.0 or t >= 1.0:
        return {"roll": 0, "yaw": 0, "pitch": 0, "x": 0, "y": 0, "z": 0}
    lead = math.sin(t ** 0.75 * math.pi)
    follow = math.sin(t * t * math.pi)
    lift = math.sin(math.sqrt(t) * math.pi * 2.0)
    return {
        "roll": 38.0 * lead, "pitch": -32.0 * lead, "yaw": -10.0 * lead,
        "x": -0.06 * lead, "y": 0.12 * lift, "z": -0.15 * follow,
    }


def set_camera_insets(camera: bpy.types.Camera, x_inset: float, y_inset: float,
                      width: int, height: int) -> None:
    center_x = width - x_inset
    center_y = height - y_inset
    ndc_x = center_x / width * 2.0 - 1.0
    ndc_y = center_y / height * 2.0 - 1.0
    # Blender moves the image opposite its lens shift. A half-frame lens shift
    # is one full NDC unit, hence the -0.5 factor.
    camera.shift_x = -0.5 * ndc_x
    camera.shift_y = -0.5 * ndc_y


def keyframe_transform(obj: bpy.types.Object, frame: int) -> None:
    obj.keyframe_insert("location", frame=frame)
    obj.keyframe_insert("rotation_quaternion", frame=frame)
    obj.keyframe_insert("scale", frame=frame)


def animate(scene: bpy.types.Scene, camera: bpy.types.Camera, projection_scale: bpy.types.Object,
            swing_ctrl: bpy.types.Object, pose_ctrl: bpy.types.Object,
            style: str, width: int, height: int, fps: int) -> None:
    duration = CHOP_SECONDS if style == "chop" else QUICK_SECONDS
    frame_count = max(1, round(duration * fps))
    scene.frame_start, scene.frame_end = 1, frame_count + 1
    pivot = CHOP_PIVOT if style == "chop" else QUICK_PIVOT

    for offset in range(frame_count + 1):
        frame = offset + 1
        progress = offset / frame_count
        if style == "chop":
            pose = chop_pose(progress)
            set_camera_insets(camera, pose["x_inset"], pose["y_inset"], width, height)
            camera.keyframe_insert("shift_x", frame=frame)
            camera.keyframe_insert("shift_y", frame=frame)
            projection_scale.scale = (pose["scale"], pose["scale"], 1.0)
            set_rotation(pose_ctrl, pose["roll"], pose["yaw"], pose["pitch"])
            set_rotation(swing_ctrl, 0.0, 0.0, 0.0)
            swing_ctrl.location = (pivot[0], pivot[1], DEFAULTS["depth"] + pivot[2])
        else:
            pose = quick_pose(progress)
            set_camera_insets(camera, DEFAULTS["x_inset"], DEFAULTS["y_inset"], width, height)
            projection_scale.scale = (1.0, 1.0, 1.0)
            set_rotation(pose_ctrl, DEFAULTS["roll"], DEFAULTS["yaw"], DEFAULTS["pitch"])
            set_rotation(swing_ctrl, pose["roll"], pose["yaw"], pose["pitch"])
            swing_ctrl.location = (pivot[0] + pose["x"], pivot[1] + pose["y"],
                                   DEFAULTS["depth"] + pivot[2] + pose["z"])
        projection_scale.keyframe_insert("scale", frame=frame)
        keyframe_transform(swing_ctrl, frame)
        keyframe_transform(pose_ctrl, frame)

    # The values are already exact samples of MineLua's curve. Linear F-curves
    # preserve those rendered frames and avoid Blender adding a second easing.
    for animated_id in (camera, projection_scale, swing_ctrl, pose_ctrl):
        animation_data = animated_id.animation_data
        action = animation_data and animation_data.action
        if not action:
            continue
        for fcurve in action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "LINEAR"

    if style == "chop":
        for milliseconds, *_ in CHOP_FRAMES:
            marker_frame = 1 + round(milliseconds / 1000.0 * fps)
            scene.timeline_markers.new(f"CHOP_{milliseconds:03d}ms", frame=marker_frame)
        scene.timeline_markers.new("IMPACT_A", frame=1 + round(0.150 * fps))
        scene.timeline_markers.new("IMPACT_B", frame=1 + round(0.230 * fps))
    else:
        scene.timeline_markers.new("IMPACT", frame=1 + round(QUICK_SECONDS * 0.42 * fps))


def scene_settings(scene: bpy.types.Scene, width: int, height: int, fps: int,
                   output_dir: Path) -> bpy.types.Camera:
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.fps = fps
    scene.render.filepath = str(output_dir / "frame_")
    scene.view_settings.view_transform = "Standard"
    try:
        scene.view_settings.look = "None"
    except Exception:
        pass
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    camera_data = bpy.data.cameras.new("FP_Camera")
    camera = bpy.data.objects.new("FP_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    distance = DEFAULTS["perspective"]
    camera.location = (0.0, 0.0, distance)
    camera.rotation_euler = (0.0, 0.0, 0.0)
    # A Blender camera looks down local -Z. The FOV below makes its projection
    # algebraically equal to hud.lua's `size * distance / cameraZ` expression.
    camera.data.type = "PERSP"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.lens_unit = "FOV"
    camera.data.angle = 2.0 * math.atan(height / (2.0 * DEFAULTS["size"] * distance))
    camera.data.clip_start = max(0.1, distance - 1.4)
    camera.data.clip_end = distance + 1.4
    set_camera_insets(camera.data, DEFAULTS["x_inset"], DEFAULTS["y_inset"], width, height)
    return camera


def add_readme_text(item: str, style: str) -> None:
    text = bpy.data.texts.get("MINE_LUA_README") or bpy.data.texts.new("MINE_LUA_README")
    text.clear()
    text.write(
        "MineLua first-person animation scene\n\n"
        f"Item: {item}\nAnimation: {style}\n\n"
        "FP_Pose_CTRL          authored item orientation\n"
        "FP_Swing_CTRL         wrist/shoulder swing and depth\n"
        "FP_ProjectionScale    exact screen-size animation\n"
        "FP_Arm_CTRL           hand-only grip correction\n"
        "FP_Camera             exact screen inset/projection\n\n"
        "Render output is RGBA PNG with a transparent world. Timeline markers "
        "show supplied chop poses and impact frames.\n"
    )


def main() -> None:
    args = parse_args()
    root = project_root()
    item_key = args.item.removeprefix("minecraft:")
    item_key = {"wooden_axe": "wood_axe", "wooden_pickaxe": "wood_pickaxe",
                "wooden_shovel": "wood_shovel"}.get(item_key, item_key)
    texture_path = args.texture.resolve() if args.texture else root / "assets" / "textures" / "items" / f"{item_key}.png"
    skin_path = root / "assets" / "textures" / "entity" / "steve.png"
    style = args.style
    if style == "auto":
        style = "chop" if (item_key.endswith("_axe") or "hatchet" in item_key) else "quick"

    clear_scene()
    scene = bpy.context.scene
    output_dir = root / "tools" / "blender" / "renders" / item_key
    output_dir.mkdir(parents=True, exist_ok=True)
    camera = scene_settings(scene, args.width, args.height, args.fps, output_dir)

    collection = bpy.data.collections.new("FIRST_PERSON_POV")
    scene.collection.children.link(collection)
    projection_scale = new_empty("FP_ProjectionScale", None, collection, "CIRCLE", 0.34)
    swing_ctrl = new_empty("FP_Swing_CTRL", projection_scale, collection, "SPHERE", 0.22)
    pose_ctrl = new_empty("FP_Pose_CTRL", swing_ctrl, collection, "ARROWS", 0.28)
    pivot = CHOP_PIVOT if style == "chop" else QUICK_PIVOT
    swing_ctrl.location = (pivot[0], pivot[1], DEFAULTS["depth"] + pivot[2])
    pose_ctrl.location = (-pivot[0], -pivot[1], -pivot[2])
    set_rotation(pose_ctrl, DEFAULTS["roll"], DEFAULTS["yaw"], DEFAULTS["pitch"])

    item_image = load_image(texture_path)
    item_material = image_material(f"MAT_{item_key}", item_image)
    item_obj = pixel_item(f"FP_Item_{item_key}", item_image, item_material, collection, pose_ctrl)
    item_obj["MineLua_item_key"] = item_key
    create_arm(load_image(skin_path), collection, pose_ctrl)

    if style in {"quick", "chop"}:
        animate(scene, camera.data, projection_scale, swing_ctrl, pose_ctrl,
                style, args.width, args.height, args.fps)
    else:
        scene.frame_start = scene.frame_end = 1
        set_camera_insets(camera.data, DEFAULTS["x_inset"], DEFAULTS["y_inset"], args.width, args.height)
    add_readme_text(item_key, style)
    scene.frame_set(1)

    # Make the main pose control the active object when the file opens.
    bpy.context.view_layer.objects.active = pose_ctrl
    pose_ctrl.select_set(True)

    if args.save:
        blend_path = root / "tools" / "blender" / f"minelua_first_person_{item_key}.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    if args.render:
        bpy.ops.render.render(animation=True)

    print(f"MineLua POV ready: {item_key} ({style}), {scene.frame_end} frames")


if __name__ == "__main__":
    main()
