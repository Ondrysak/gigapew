# Animated horde monsters (Blender → Godot)

Ten CC0 source characters are baked into GL Compatibility vertex animation textures (VAT). Source archives are **not** redistributed; licenses and original authors/URLs are preserved in `assets/monsters/LICENSES.txt`. Download/extract the five source packs listed there under a common downloads directory, retaining the `essentials/`, `mech/`, `alien/`, `megakit/`, and `bug/` names shown in `monsters.json`. Blender 5.2 and Godot 4.4+ are used; no addon is required.

From the project root:

```sh
KAKABOOMBOOM_DOWNLOADS=/absolute/path/to/kakaboomboom-downloads ./tools/vat/bake_all.sh
# Optional: rebuild one or more members, e.g. ./tools/vat/bake_all.sh robot_grunt alien_runner
# Optional: BLENDER=/absolute/path/to/blender ./tools/vat/bake_all.sh
```

`monsters.json` lists source path, decimation, facing yaw, fitted height/footprint, and source action → logical clip mapping. The Blender baker runs decimation **before** armature deformation; mesh joining retains materials and skin weights. The `smooth` override removes FBX's face-sharp flags on the alien runner, avoiding unnecessary split normals. Texture images are downscaled to at most 1024 px before the rest `.glb` exports. It writes `assets/monsters/<id>/<id>.glb`, `<id>_positions.exr`, `<id>_normals.exr`, `<id>_vat.tres`, import settings and `tools/vat/reports/<id>.json`. The `.glb` holds a deformed pose, embedded materials/maps and a UV2 lookup; the armature is removed. Baking does not need a running Godot editor. On a fresh checkout, **import** resources once in Godot so `.glb` and float textures are available to the stage scenes.

Each EXR contains 32-bit linear float RGBA texels: X = lookup column, Y = frame (clips concatenated), RGB = Godot-local position or normal. At most 4096 columns fit per row; wider meshes wrap over `ceil(columns / texture_width)` rows per frame. **Every polygon loop gets its own UV2.x = (column + 0.5) / column_count**; split normals reuse a lookup column only if they share the same original vertex and rest normal. glTF/Godot vertex reordering, seam splits and indices therefore cannot invalidate animation. The vertex shader reads UV2, never `VERTEX_ID`, and fetches exact pixels using `texelFetch(..., ..., 0)`. Both EXRs use lossless, non-sRGB, no-mipmap, uncompressed HDR imports (`.exr.import`), including under GL Compatibility. No binary normalization/UNORM compression is allowed: it would lose signed world positions and fine movement. The baker's report includes emitted clip frame offsets/counts and texture dimensions.

The scene's `HordeEnemyDefinition.vertex_animation` enables the VAT shader. `move_clip` is required, `idle_clip`, `attack_clip`, `death_clip` are optional, and `move_clip_speed` controls gait playback relative to travel speed. The old static mesh path remains supported for definitions without VAT. MultiMesh per-instance `COLOR` stores local fractional frame, first frame, clip length, and loop flag; `INSTANCE_CUSTOM` stores flash, attack warning, random phase and frost. The menu uses the same mesh/shader but sets instance preview frame/clip uniforms on a few independent `MeshInstance3D`s. With no death clip, the renderer uses the existing short collapse. The ten `.tres` definitions use the same combat role numbers as their replaced primitive versions; yard/foundry spawn robots, reactor spawns aliens. Robot bursts use sparks/debris; alien bursts use goo/splats.

The budget below counts actual glTF POSITION accessor vertices (after material/UV splits), not Blender's often-unreferenced mesh vertices. All embedded color textures are ≤1024×1024. Numbers are from the checked-in `reports/*.json` and glTF accessors; rebaking may change counts slightly across Blender releases.

| Monster | GPU vertices | VAT columns | EXR WxH | Frames (move / idle / attack / death) |
| --- | ---: | ---: | ---: | --- |
| robot_grunt | 724 | 708 | 708×80 | 67 / – / 13 / – |
| robot_runner | 808 | 794 | 794×31 | 13 / – / 8 / 10 |
| robot_spitter | 1725 | 1671 | 1671×154 | 21 / 83 / 13 / 37 |
| robot_tank | 1391 | 1350 | 1350×60 | 33 / – / 6 / 21 |
| robot_boss | 5320 | 5116 | 4096×252 | 17 / 67 / 12 / 30 |
| alien_grunt | 700 | 700 | 700×49 | 8 / 32 / 9 / – |
| alien_runner | 1097 | 869 | 869×167 | 18 / 83 / 19 / 47 |
| alien_spitter | 1297 | 1297 | 1297×67 | 67 / – / – / – |
| alien_tank | 1844 | 1844 | 1844×67 | 67 / – / – / – |
| alien_boss | 1046 | 1046 | 1046×67 | 67 / – / – / – |

The latter three source aliens supply only `Alien_Idle`; they have a true skeletal loop plus procedural sway/bob in their definition instead of fake attack/death clips. Verify any fresh rebake in a rendered GL Compatibility session: a headless import checks resources/scripts but **cannot prove visual fidelity**, texture orientation or GPU shader output.
