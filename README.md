# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Survive escalating swarms of hundreds to thousands of weak enemies, level up from XP, stack upgrades and auto-firing weapons, then destroy each stage's boss. Built with Godot's GL Compatibility renderer and no external assets. Open `project.godot` and press **F5**, or run `godot --path .`. Verified with Godot 4.4.1 and 4.7.2.

## Controls

- **WASD** moves; **mouse** aims; **Space** jumps.
- **Hold left mouse button** to fire your main gun. **1 / 2 / 3** or the **mouse wheel** switches between Pulse, Scatter and Rail. Switching keeps the current shot cooldown.
- **Level up:** the game pauses; press **1 / 2 / 3** or click a card to choose an upgrade.
- **Esc** releases the cursor. The first click recaptures aim without shooting.
- **Enter** advances after a stage's boss dies. **R** starts a new run after death.

## A run

Each stage is a countdown. Enemies arrive from all sides and spawn mostly behind you; the radar (top right) shows the crowd around you. When the timer ends, the Dreadnought boss arrives while the horde keeps coming. Destroy it to clear the stage. Your level, upgrades and auto weapons carry into the next stage, and your health refills.

| Stage | Length | Crowd cap | Boss health |
| --- | --- | --- | --- |
| Training Yard (64 × 64 m) | 3:00 | 700 | 2500 |
| The Foundry (96 × 52 m) | 4:00 | 1100 | 4000 |
| Reactor Core (76 × 76 m) | 5:00 | 1600 | 6000 |

Enemies are individually weak; touching them hurts in capped ticks of at most 4 damage per 0.5 s, even when surrounded.

| Enemy | HP | Behavior |
| --- | --- | --- |
| Grunt | 12 | Swarming bulk of every wave |
| Runner | 7 | Very fast, fragile |
| Spitter | 30 | Keeps its distance, flashes orange, then fires a slow, dodgeable bolt |
| Tank | 140 | Slow and heavy; flashes red, then charges |
| Dreadnought | 2500+ | Stage boss; charging titan with its own health bar |

| Main gun | Damage | Cadence | Pierce |
| --- | --- | --- | --- |
| Pulse | 25 | 0.16 s | 1 extra enemy |
| Scatter | 7 × 14 | 0.65 s | — (close-range cone, big shove) |
| Rail | 100 | 0.8 s | 30 (the whole line) |

**Auto weapons** (unlocked by upgrades, up to four; each goes to level 5): Sentry Drones, Nova Pulse, Auto Mortar and Arc Coil.
**Stat upgrades:** damage, main-gun fire rate, pierce, move speed, max health, regeneration, armor, pickup radius, auto-weapon area and cooldown, XP gain, and Splitter Array (extra drones, shells, arc jumps and nova echoes). Field Repair (heal 30) fills the choices once most upgrades are maxed.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without editing controllers.

- **Horde** (`scripts/horde/horde.gd`, scene `scenes/horde/horde.tscn`): all enemies live in one data-oriented simulation with packed arrays, a uniform crowding grid and one MultiMesh draw per enemy type. There are no per-enemy nodes or physics bodies. Weapons use `raycast`, `query_radius`, `nearest`, `damage` and `damage_radius`. Crowd tuning is exported: `contact_tick`, `contact_cap` and `hit_headroom` (hitscan forgiveness above short enemies). Measured at ~60 fps with 1600 live enemies and a maxed build.
- **Enemies:** `data/enemies/*.tres` (`HordeEnemyDefinition`) holds stats, behavior (`SWARM` / `RANGED` / `CHARGER`), attack timings and a `model_scene`. A model is any Node3D of MeshInstance3Ds with StandardMaterial3D overrides, facing −Z with its feet at y = 0. It is baked at stage start into one mesh that uses `shaders/horde_enemy.gdshader` (hit flash, telegraph glow, bob, near-camera cull). Swap models in `scenes/enemies/models/` to reskin.
- **Stages:** `data/stages/*.tres` (`StageDefinition`) holds the name, world scene, `play_area` rectangle and a `SpawnSchedule` (`data/schedules/*.tres`) of timed `SpawnWave` ramps plus the boss. A world scene (`scenes/levels/*.tscn`) contains static art, a `PlayerSpawn` marker, and an `Obstacles` node of StaticBody3Ds with cylinder or box colliders; the horde reads those shapes for crowd avoidance. Stage order is `Game.campaign` in `scenes/game.tscn`.
- **Progression:** `RunState` (`scripts/progression/run_state.gd`) tracks XP, level and derived stats. Upgrades are `UpgradeDefinition` resources in `data/upgrades/`, collected in `data/upgrades/pool.tres`. Auto weapons extend `AutoWeapon` (`scripts/weapons/auto/`); their visuals are template nodes in `scenes/weapons/auto/*.tscn`. XP gems live in `scenes/pickups/pickup_field.tscn`; the level-up UI is `scenes/ui/level_up.tscn`.
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage, cadence, pellets, spread, pierce, knockback) plus a `WeaponView` scene in `scenes/weapons/`. List them in `Player.weapons` (`scenes/player.tscn`).
- **HUD:** `scenes/ui/hud.tscn` (`ArenaHUD`) holds health, XP bar, level, stage timer, hostiles/kills, boss bar and the `HordeRadar`. Restyle it freely as long as the named nodes remain.
- **Audio:** `CombatAudio` synthesizes default cues. Its `sound_overrides` Inspector map swaps any cue for an `AudioStream`.
- **Run flow:** `scripts/game.gd` (`ArenaGame`) builds each stage from data under a fresh `Round` node, pauses for level-ups and frees the whole round between stages.
