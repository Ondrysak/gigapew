# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Pick an operator, survive escalating swarms of hundreds to thousands of weak enemies, mine the walls for loot, level up into a build of main-gun upgrades and auto-firing weapons, kill each stage's boss, and spend banked currency on permanent upgrades and new classes between runs. Built with Godot's GL Compatibility renderer; no external assets. The music is synthesized at runtime. Open `project.godot` and press **F5**, or run `godot --path .`. Verified with Godot 4.4.1 and 4.7.2.

## Controls

- **WASD** moves; **mouse** aims; **Space** jumps.
- **Hold LMB** fires your main gun. **1 / 2 / 3** or the **mouse wheel** switches guns. Switching keeps the current shot cooldown.
- **Hold RMB** drills: it mines mineral deposits and shoves nearby enemies.
- **Q** uses your class ability.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Enter** advances after a boss dies. After death: **R** retries with the same class, **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Armory**, **Records**, **Settings**) → class select → run. Each stage counts down while the horde escalates. Most enemies spawn behind you; the radar shows the crowd. When the timer ends, the Dreadnought arrives while the horde keeps coming. Kill it to clear the stage. Level, upgrades and auto weapons carry into the next stage, and your health refills.

| Stage | Length | Crowd cap | Boss health |
| --- | --- | --- | --- |
| Training Yard (64 × 64 m) | 3:00 | 700 | 2500 |
| The Foundry (96 × 52 m) | 4:00 | 1100 | 4000 |
| Reactor Core (76 × 76 m) | 5:00 | 1600 | 6000 |

Enemies are individually weak. Contact damage comes in capped ticks of at most 4 damage per 0.5 s, even when surrounded. Enemies: Grunt (swarm), Runner (fast), Spitter (telegraphed slow bolts), Tank (telegraphed charge), Dreadnought (boss).

## Classes

| Class | Unlock | Guns | Ability (Q) | Profile |
| --- | --- | --- | --- | --- |
| Scout | free | Pulse, Rail | Blink Dash: 9 m invulnerable dash that bowls enemies aside | +12% speed, +1 m pickup |
| Gunner | 6 shards | Minigun, Autocannon | Bulwark: 4 s shield plus knockback pulse | +30 health, +1 armor, −5% speed |
| Driller | 10 shards | Flamethrower, Scatter | Seismic Charge: thrown charge with a 7 m blast | +150% mining, +5% damage |
| Engineer | 14 shards | Pulse, Autocannon | Overdrive: auto weapons recharge ~2× faster for 6 s | Starts with Sentry Turret, −10% auto cooldown |

**Main guns:** Pulse (fast, pierces 1), Rail (heavy, pierces the whole line), Scatter (7-pellet cone), Minigun (spins up to a shredding rate), Autocannon (explosive rounds), Flamethrower (short-range piercing cone).

**Auto weapons** (level-up picks, up to four at a time, each to level 5): Sentry Drones, Nova Pulse, Auto Mortar, Arc Coil, Saw Orbit, Sentry Turret, Cryo Field (slows and frost-tints enemies) and Homing Rockets. A weapon at max level unlocks its **overclock** card, a one-time signature upgrade: piercing drone beams, double nova, cluster mortar, forking arcs, twin blade rings, exploding turrets, shattering frost and splitting rockets.

**Stat upgrades:** damage, fire rate, pierce, speed, health, regeneration, armor, pickup radius, auto-weapon area and cooldown, XP, and Splitter Array (extra drones, blades, shells, turrets and rockets).

## Mining and progression

Mineral deposits are embedded in walls and obstacles and respawn over time. Drill them (RMB) or shoot them. Loot pops out and flies to you.

- **Gold**: banked; buys permanent Armory upgrades.
- **Void Shard**: banked, rare; the boss drops 3; unlocks classes.
- **Cinder Crystal**: in-run only; fills the supply meter, and each full meter grants a free upgrade pick.

Banked resources move into your profile at 100% when you clear a stage (loot still on the floor is swept up), and at 50% if you die or abandon the run. The Armory sells eight permanent upgrades (Vitality, Firepower, Agility, Magnetism, Prospector, Salvager, Scholar, Plating), five levels each. Records track best time, kills, level, runs, victories and deepest stage. Everything is saved to `user://profile.json`.

## Music

The adaptive soundtrack is rendered procedurally on background threads at startup into sample-synced loop stems (D minor, 126 BPM). Layers fade in with the crowd density around you (pad → drums → bass drive and arp → lead and tension); the boss swaps in a darker harmony layer. Stingers mark level-ups, stage clears, death and victory. Music, SFX and master volumes are adjustable in Settings.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, unlocks, Armory levels, records and settings. `Music` (`scripts/audio/music_director.gd`, with `music_score.gd` for the arrangement and `music_synth.gd` for synthesis) plays tracks and stingers and follows intensity. Buses are defined in `default_bus_layout.tres`.
- **Stats:** `StatModifier` (`scripts/data/stat_modifier.gd`) holds the shared additive stat fields. `ClassDefinition`, `MetaUpgradeDefinition` and level-up `UpgradeDefinition` extend it. `RunState` sums the class (×1), Armory upgrades (× purchased level) and level-up upgrades (× stacks).
- **Classes:** `data/classes/*.tres` plus `roster.tres` define the loadout, starting upgrades, stat profile, unlock cost and `ability_scene`. Abilities extend `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`).
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage, cadence, pellets, spread, pierce, knockback, explosion, spin-up) plus a `WeaponView` scene in `scenes/weapons/`.
- **Auto weapons:** `AutoWeapon` subclasses in `scripts/weapons/auto/` with scenes in `scenes/weapons/auto/`, granted by `UpgradeDefinition`s (kinds STAT, WEAPON and OVERCLOCK) listed in `data/upgrades/pool.tres`.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented crowd simulation with one MultiMesh per enemy type, weapon queries, `slow()`, and exported contact tuning. Enemy stats are in `data/enemies/*.tres`. Model scenes in `scenes/enemies/models/` are baked into shared meshes that use `shaders/horde_enemy.gdshader` (hit flash, telegraph, frost, bob, near-camera cull).
- **Mining:** `ResourceDefinition` data lives in `data/resources/`; deposit types are in `data/resources/deposits/`. `DepositField` and `MiningTool` live in `scenes/mining/`; deposit models are in `scenes/mining/models/`.
- **Stages:** `data/stages/*.tres` (world scene, play area, `SpawnSchedule` of timed waves plus boss). A world scene holds static art, a `PlayerSpawn` marker, and an `Obstacles` node of cylinder/box colliders shared by the horde and deposit placement.
- **UI:** the HUD is `scenes/ui/hud.tscn`, level-up cards are `scenes/ui/level_up.tscn`, and the pause menu is `scenes/ui/pause_menu.tscn`. The intro, main menu and its screens are in `scenes/ui/` and `scenes/ui/menu/`, styled by the shared `menu_theme.tres`.
- **Run flow:** `scripts/game.gd` (`ArenaGame`) builds each stage from data under a fresh `Round` node. It handles level-up and pause states, banks currency into `Profile`, records runs and drives music intensity from crowd density.

Performance: ~60 fps with 1600 live enemies, a maxed auto-weapon build and the music running (measured on a Radeon RX 7900 XTX).
