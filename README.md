# Kakaboomboom

A small desktop arena FPS using Godot's GL Compatibility renderer. Open `project.godot` and press **F5**, or run `godot --path .`. Verified with Godot 4.4.1 and 4.7.2. No external assets or downloads are required.

## Controls

- **WASD** moves; **mouse** aims; **Space** jumps.
- **Hold left mouse button** to fire the pulse weapon. Two hits destroy a robot.
- **Esc** releases the cursor. The first click recaptures aim without shooting; release and click again to fire. Releasing the cursor does not pause enemies.
- **R** restarts after victory or death.

Destroy all three robots to clear the arena. Robots deal 10 damage on contact, with a 0.75-second cooldown. Perimeter walls block movement and shots.

## Visual and combat upgrade

- Neon-industrial arena, anti-aliased panel markings, cyan/amber lighting, perimeter machinery, and industrial skyline.
- Armored hover robots with facing, hover animation, isolated hit flashes, knockback, and short destruction animations.
- Fast acceleration and braking, limited air control, and 120 ms jump buffering / ledge grace. Movement speed is 9.5 m/s; weapon cadence is one shot per 0.16 seconds.
- Layered pulse-weapon model with recoil, mouse sway, restrained movement bob and landing dip. These weapon animations do not move the hitscan aim; there is no camera shake.
- Reusable shot traces and impact flashes, reactive crosshair, hit markers, kill confirmation, damage-edge feedback, low-health color, and readable terminal overlays.
- Original synthesized shot, hit, kill, damage, jump, landing, victory, and death cues. Audio buffers are built once per player instance and reused.

## Editing

`scenes/arena.tscn` contains editable world geometry and HUD layout; `shaders/arena_floor.gdshader` draws the floor markings. Character scenes contain their primitive meshes. The player and enemy controllers own gameplay; `scripts/arena.gd` owns round state. `scripts/combat_feedback.gd` draws transient HUD feedback and `scripts/combat_audio.gd` synthesizes and plays sounds.
