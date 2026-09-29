# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Pick an operator, survive escalating robot and alien swarms, mine walls for loot, choose guns and perks, clear three stages and spend banked currency between runs. Built with Godot's GL Compatibility renderer and CC0 art credited in [CREDITS.md](CREDITS.md); the music is synthesized at runtime. Open `project.godot` and press **F5**, or run `godot --path .`. Verified with Godot 4.4.1 and 4.7.2.

## Controls

- **WASD** moves; **mouse** aims; **Space** jumps.
- **Hold LMB** fires your main gun. **1 / 2 / 3** or the **mouse wheel** switches guns. Switching keeps the current shot cooldown.
- **Hold RMB** drills: it mines mineral deposits and shoves nearby enemies.
- **Q** uses your class ability.
- **E** activates nearby consoles or flame vents while facing them; shoot barrels and vent valves to trigger them. Look for warning lights before crossing electrified floor panels.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Enter** advances after a boss dies. After death: **R** retries with the same class, **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Armory**, **Records**, **Settings**) → class and ability select → run. Each stage counts down while the horde escalates. Most enemies spawn behind you; the radar shows the crowd. Yard and Foundry field robots, Reactor fields aliens. Each faction has grunts, runners, spitters, charging tanks and a boss. When the timer ends, the boss arrives while the horde keeps coming. Kill it to clear the stage. Level, upgrades, perks and auto weapons carry into the next stage; health refills.

| Stage | Length | Crowd cap | Boss health |
| --- | --- | --- | --- |
| Training Yard (64 × 64 m) | 3:00 | 700 | 2500 |
| The Foundry (96 × 52 m) | 4:00 | 1100 | 4000 |
| Reactor Core (76 × 76 m) | 5:00 | 1600 | 6000 |

Contact damage comes in capped ticks of at most 4 damage per 0.5 s, even when surrounded. Enemies path through 4 m or wider doorways and around interior walls; each stage also has shootable explosive barrels, proximity mines, cycling electric floors, crystal-powered turrets and activatable flame vents.

**High ground.** Every stage has raised decks reached by ramps, plus 0.8 m jump ledges that only the player can climb as shortcuts. The Yard has a two-tier corner overlook (2.2 m and 3 m) and a 1.8 m gantry with a single-ramp chokepoint. The Foundry has a west casting gallery (1.6 m, 2.4 m, 1.6 m) and a 2.4 m forge mezzanine; each forms a loop back to the floor. The Reactor has corner bastions and mezzanines at 1.6 m and 2.4 m, a 3.2 m terrace and a 4 m overlook facing the core. Enemies cannot climb deck edges; they climb the ramps, so a ramp becomes a chokepoint. If you are below them, they walk off ledges and drop down at you. Enemies below a ledge cannot hit you in melee, but spitters still can, and no deck is out of the horde's reach.

## Classes

| Class | Unlock | Guns | Default ability (Q) | Alternate abilities (Void Shards) | Profile |
| --- | --- | --- | --- | --- | --- |
| Scout | free | Pulse, Rail | Blink Dash: invulnerable 9 m dash | Recon Flare (3), Grapple Vault (5) | +12% speed, +1 m pickup |
| Gunner | 6 shards | Minigun, Autocannon | Bulwark: 4 s shield and knockback pulse | Suppression Barrage (4), Ammo Frenzy (6) | +30 health, +1 armor, −5% speed |
| Driller | 10 shards | Flamethrower, Scatter | Seismic Charge: thrown charge with a 7 m blast | Drill Dash (5), Magma Trail (7) | +150% mining, +5% damage |
| Engineer | 14 shards | Pulse, Autocannon | Overdrive: auto weapons recharge ~2× faster for 6 s | Platform Turret (6), Repair Drone (8) | Starts with Sentry Turret, −10% auto cooldown |

Each class has three Q abilities: its default and two permanent unlocks. On the class-select screen, select an ability tile, buy it with Void Shards, then equip it. The equipped choice is saved per class in `user://profile.json`.

**Main guns:** Pulse (fast, pierces 1), Rail (heavy, pierces the whole line), Scatter (7-pellet cone), Minigun (spins up to a shredding rate), Autocannon (explosive rounds), Flamethrower (short-range piercing cone).

**Hit chains:** each main-gun shot that directly hits an enemy adds one beat, no matter how many pellets hit. After three consecutive hits, each further shot gains +8% damage per beat, capped at +40%. A miss, taking damage, or 2.5 seconds without another hit breaks the chain; explosions alone do not extend it. The crosshair shows the next shot's bonus and a countdown. Hit-confirmation sounds climb in pitch; hits and kills have brighter impact sparks and stronger recoil.

**Auto weapons** (level-up picks, up to four at a time, each to level 5): Sentry Drones, Nova Pulse, Auto Mortar, Arc Coil, Saw Orbit, Sentry Turret, Cryo Field (slows and frost-tints enemies) and Homing Rockets. A weapon at max level unlocks its **overclock** card, a one-time signature upgrade: piercing drone beams, double nova, cluster mortar, forking arcs, twin blade rings, exploding turrets, shattering frost and splitting rockets.

**Perks** (level-up picks, each to level 3; do not occupy an auto-weapon slot): Chain Reaction (exploding kills), Vampiric Rounds (heal on kills), Adrenaline (fire rate when hurt), Thorns (contact retaliation), Lucky Strike (main-gun critical hits), Momentum (moving damage), Scavenger (bonus crystals) and Last Stand (survive a lethal hit once per stage, more charges at level 3).

**Gun mods** (single-pick level-up cards; no auto-weapon slots): Quickdraw Capacitor gives the first shot within 1.5 s of a weapon swap +75% damage (the charge is spent on a miss); Longshot Optics gives direct hits beyond 15 m +40% damage; Executioner Core gives direct hits on enemies already below 35% health +60% damage. They can be combined, and installed mods appear under the selected gun on the HUD.

**Stat upgrades:** damage, fire rate, pierce, speed, health, regeneration, armor, pickup radius, auto-weapon area and cooldown, XP, and Splitter Array (extra drones, blades, shells, turrets and rockets). Lucky Strike also adds critical chance and damage to the main gun.

## Mining and progression

Mineral deposits are embedded in walls and obstacles and respawn over time. Drill them (RMB) or shoot them. Loot pops out and flies to you.

- **Gold**: banked; buys permanent Armory upgrades.
- **Void Shard**: banked, rare; the boss drops 3; unlocks classes and alternate abilities.
- **Cinder Crystal**: in-run only; fills the supply meter for free upgrade picks, or powers turret consoles (10 crystals each).

Banked resources move into your profile at 100% when you clear a stage (loot still on the floor is swept up), and at 50% if you die or abandon the run. The Armory sells eight permanent upgrades (Vitality, Firepower, Agility, Magnetism, Prospector, Salvager, Scholar, Plating), five levels each. Records track best time, kills, level, runs, victories and deepest stage. Everything is saved to `user://profile.json`.

## Music

The adaptive soundtrack is rendered procedurally on background threads at startup into sample-synced loop stems (D minor, 126 BPM). Layers fade in with the crowd density around you (pad → drums → bass drive and arp → lead and tension); the boss swaps in a darker harmony layer. Stingers mark level-ups, stage clears, death and victory. Music, SFX and master volumes are adjustable in Settings.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, unlocks, Armory levels, records and settings. `Music` (`scripts/audio/music_director.gd`, with `music_score.gd` for the arrangement and `music_synth.gd` for synthesis) plays tracks and stingers and follows intensity. Buses are defined in `default_bus_layout.tres`.
- **Stats:** `StatModifier` (`scripts/data/stat_modifier.gd`) holds the shared additive stat fields. `ClassDefinition`, `MetaUpgradeDefinition` and level-up `UpgradeDefinition` extend it. `RunState` sums the class (×1), Armory upgrades (× purchased level) and level-up upgrades (× stacks).
- **Classes and abilities:** `data/classes/*.tres` plus `roster.tres` define the loadout, stats, unlock cost, default `ability_scene` and optional `alternate_abilities` with shard costs. `Profile` remembers each class's equipped ability; abilities extend `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`).
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage, cadence, pellets, spread, pierce, knockback, explosion, spin-up) plus a `WeaponView` scene in `scenes/weapons/`. Each first-person model uses reusable primitive parts; the view reuses impact and tracer meshes per ray. `ArenaPlayer` tracks direct-hit chains and resolves the three main-gun mods at shot time.
- **Auto weapons, perks and gun mods:** `AutoWeapon` subclasses in `scripts/weapons/auto/` and `PerkEffect` subclasses in `scripts/perks/`, granted by `UpgradeDefinition`s (STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD) listed in `data/upgrades/pool.tres`. The `AutoWeaponRack` owns auto weapons and perks; neither perks nor gun mods use an auto-weapon slot.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented simulation with one MultiMesh per enemy type, a shared flow field, weapon queries, `slow()`, faction FX and contact tuning. The flow field avoids obstacles and treats cliffs as walls; it routes to the player's level over ramps. Each enemy has a feet height taken from the stage heightfield: it snaps up ramps, falls off ledges and never climbs a step over 0.3 m. Hit tests, blasts, projectiles and contact damage all use that height. Robot and alien stats/animations are in `data/enemies/*.tres`. Meshes are baked from the CC0 models in `assets/monsters/` into shared textured surfaces; `shaders/horde_enemy_vat.gdshader` animates the crowd from position/normal textures and per-instance clip state. `tools/vat/README.md` covers the reproducible Blender bake and source pack licenses. The static shader remains available for other models.
- **Mining:** `ResourceDefinition` data lives in `data/resources/`; deposit types are in `data/resources/deposits/`. `DepositField` and `MiningTool` live in `scenes/mining/`; deposit models are in `scenes/mining/models/`.
- **Stages and hazards:** `data/stages/*.tres` select a world, play area and `SpawnSchedule`. A world scene has a `PlayerSpawn`, a floor at y = 0, an `Obstacles` node of box/cylinder colliders (used by horde navigation and deposit placement), an optional `Elevation` node, and a `Hazards` node. `Elevation` holds `StaticBody3D` decks and ramps. Each has exactly one `BoxShape3D`, yawed in multiples of 90°, with ramps also pitched. They are solid down to the floor. The horde rasterises their top faces into a 0.5 m heightfield. Keep ramps ≤ 18°, at least 6 m wide, and flush with the floor and the deck edge (a lip of even a few centimetres stops the player's capsule). Decks must be at least 1.6 m high so their edges read as cliffs, and every deck must be reachable by ramp. `scripts/game.gd` configures every hazard once per round via `setup(horde, player, run_state)`. The five hazard scene/scripts live in `scenes/hazards/` and `scripts/hazards/`; world decoration is composed from CC0 MegaKit modules in `assets/third_party/`.
- **UI:** the HUD is `scenes/ui/hud.tscn`, level-up cards are `scenes/ui/level_up.tscn`, and the pause menu is `scenes/ui/pause_menu.tscn`. The intro, main menu and its screens are in `scenes/ui/` and `scenes/ui/menu/`, styled by the shared `menu_theme.tres`.
- **Run flow:** `scripts/game.gd` (`ArenaGame`) builds each stage from data under a fresh `Round` node. It handles level-up and pause states, banks currency into `Profile`, records runs and drives music intensity from crowd density.

Performance: the mixed-faction 1,600-enemy horde was measured in a Godot 4.4.1 headless CPU check (120 frames). On the elevated stages, simulation averaged 7.2 ms per frame on the Yard and 7.5 ms on the Reactor (about 20% of the horde on raised ground); draw preparation took about 2.6 ms. The same check before the heightfield measured 6.1–6.5 ms. GL Compatibility visuals were inspected in an isolated 1280×720 virtual display (Mesa llvmpipe); **60 fps has not been measured on the Radeon GPU**.
