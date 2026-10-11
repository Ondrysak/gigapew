# Animated horde monsters (Blender → Godot)

Six Prague human enemies from Quaternius' CC0 Ultimate Animated Character Pack and five original procedural delirium creatures are baked into GL Compatibility vertex animation textures (VAT). Source archives are **not** redistributed; licenses and original authors/URLs are preserved in `assets/monsters/LICENSES.txt`. Extract the human character pack under `people/` in the downloads directory, preserving the paths in `monsters.json`, and generate the delirium sources as described below. No Blender addon is required.

From the project root:

```sh
KAKABOOMBOOM_DOWNLOADS=/absolute/path/to/kakaboomboom-downloads ./tools/vat/bake_all.sh
# Optional: rebuild one or more members, e.g. ./tools/vat/bake_all.sh robot_grunt alien_runner
# Optional: BLENDER=/absolute/path/to/blender ./tools/vat/bake_all.sh
```

## Street faces, grime and props

The six human enemies share a 5 × 5 atlas of invented faces (24 painted cells, quantized to a flat palette):

```sh
python3 tools/vat/faces/build_faces.py --preview /tmp/faces.png   # writes tools/vat/faces/atlas.png
./tools/vat/bake_all.sh robot_grunt robot_runner robot_spitter robot_tank robot_bulwark robot_boss
```

The atlas is painted from parameters only; no photograph or real person is used.
In `monsters.json`, `"face": {"atlas": ..., "cells": [5, 5]}` makes `bake_vat.py`
move the front-facing head skin polygons into the Face material and project them
planarly onto cell 0. `HordeEnemyDefinition.face_atlas/face_first/face_count`
select the runtime cells. `"cut": [{"material", "below_z", "above_z", "max_abs_x",
"max_normal_y"}]` deletes polygons, e.g. the Bezdomovec's moustache hair, so the
painted mouth shows. `props` may add rigid shapes to any bone (a bedroll on the
Torso, a bottle in each fist). Dirt is not baked: `HordeEnemyDefinition.grime`
drives the shader.

## Original Hlavák delirium sources

The five Hlavák replacements are generated locally, with no external model or
texture downloads: `mys` (white mouse), `svab` (six-legged cockroach), `lahev`
(walking rum bottle), `automat` (slot machine), and `jackpot` (golden boss).
From the project root:

```sh
# Default output: ../kakaboomboom-downloads/delirium
blender -b --python tools/vat/build_delirium.py
# Custom downloads location; trailing creature names optionally select a subset.
blender -b --python tools/vat/build_delirium.py -- /absolute/path/to/kakaboomboom-downloads/delirium
blender -b --python tools/vat/preview_delirium.py -- ../kakaboomboom-downloads/delirium /tmp/delirium_preview
KAKABOOMBOOM_DOWNLOADS=/absolute/path/to/kakaboomboom-downloads ./tools/vat/bake_all.sh alien_grunt alien_runner alien_spitter alien_tank alien_boss
```

Each `.blend` has one armature and one weighted mesh, faces -Y, uses metre-scale
coordinates with its resting feet at z=0, and contains bone-only `Walk`, `Idle`,
`Attack`, and `Death` actions at 24 fps. Walk/Idle loop; Attack/Death are one-shot.
Ground contact is sampled from the deformed mesh and baked into the root bone;
there are no runtime constraints or animated object transforms. The cork and
boss crown remain attached. Materials connect solid-colour Principled BSDFs
directly to Material Output; glowing parts use emission, not image textures.
The builder writes vertex counts and action ranges to `delirium_report.json`.

Previews contain four frames per row: Walk front, Walk side, Attack side, Death
front, and Idle front. Attack includes windup and impact, and Death includes its
final pose. Each camera fits the full action. Alongside `<name>.png`,
`<name>.json` records the row frame numbers and the lowest vertex height over
every frame of each action. Inspect both the sheets and these floor diagnostics
before baking; then inspect the baked enemies in a rendered Godot session.

## VAT pipeline

`monsters.json` lists source path, decimation, facing yaw, fitted height/footprint, and source action → logical clip mapping. The Blender baker runs decimation **before** armature deformation; mesh joining retains materials and skin weights. The `smooth` override removes face-sharp flags, avoiding unnecessary split normals. Texture images are downscaled to at most 1024 px before the rest `.glb` exports. It writes `assets/monsters/<id>/<id>.glb`, `<id>_positions.exr`, `<id>_normals.exr`, `<id>_vat.tres`, import settings and `tools/vat/reports/<id>.json`. The `.glb` holds a deformed pose, embedded materials/maps and a UV2 lookup; the armature is removed. Baking does not need a running Godot editor. On a fresh checkout, **import** resources once in Godot so `.glb` and float textures are available to the stage scenes.

Each EXR contains 32-bit linear float RGBA texels: X = lookup column, Y = frame (clips concatenated), RGB = Godot-local position or normal. At most 4096 columns fit per row; wider meshes wrap over `ceil(columns / texture_width)` rows per frame. **Every polygon loop gets its own UV2.x = (column + 0.5) / column_count**; split normals reuse a lookup column only if they share the same original vertex and rest normal. glTF/Godot vertex reordering, seam splits and indices therefore cannot invalidate animation. The vertex shader reads UV2, never `VERTEX_ID`, and fetches exact pixels using `texelFetch(..., ..., 0)`. Both EXRs use lossless, non-sRGB, no-mipmap, uncompressed HDR imports (`.exr.import`), including under GL Compatibility. No binary normalization/UNORM compression is allowed: it would lose signed world positions and fine movement. The baker's report includes emitted clip frame offsets/counts and texture dimensions.

The scene's `HordeEnemyDefinition.vertex_animation` enables the VAT shader. `move_clip` is required, `idle_clip`, `attack_clip`, `death_clip` are optional, and `move_clip_speed` controls gait playback relative to travel speed. The old static mesh path remains supported for definitions without VAT. MultiMesh per-instance `COLOR` stores local fractional frame, first frame, clip length, and loop flag; `INSTANCE_CUSTOM` stores flash, attack warning, random phase and frost. The menu uses the same mesh/shader but sets instance preview frame/clip uniforms on a few independent `MeshInstance3D`s. With no death clip, the renderer uses the existing short collapse. Internal `robot_*` IDs now refer to Prague humans and `alien_*` IDs to the five delirium creatures; the IDs are retained for resource stability, not their former appearances.

Use the current `reports/*.json` for baked VAT column counts, EXR dimensions,
clip frame counts, and bounds. GPU vertices are glTF POSITION accessor vertices
(after material/UV splits), not the Blender source vertex count; rebaking may
change counts slightly across Blender releases. The generator's
`delirium_report.json` reports source mesh counts and action ranges separately.

Verify any fresh rebake in a rendered GL Compatibility session: a headless
import checks resources/scripts but **cannot prove visual fidelity**, texture
orientation or GPU shader output.
