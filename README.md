# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Pick an operator, mine and fight through three procedurally generated sectors, complete their contracts and spend banked currency between levels and runs. Built with Godot's GL Compatibility renderer and CC0 art credited in [CREDITS.md](CREDITS.md); the music is synthesized at runtime. Open `project.godot` and press **F5**, or run `godot --path .`. Current source verified with Godot 4.7.2.

## Linux release

Current game version: **0.3.0**. Downloadable/local release notes are in
[RELEASE_NOTES.md](RELEASE_NOTES.md).

To play the packaged release:

```sh
cd export/linux
sha256sum -c kakaboomboom-0.3.0-linux-x86_64.tar.gz.sha256
tar -xzf kakaboomboom-0.3.0-linux-x86_64.tar.gz
cd kakaboomboom-0.3.0-linux-x86_64
sha256sum -c SHA256SUMS
./kakaboomboom.x86_64
```

The executable embeds the game data. Players do not need Godot or the source
project. Requires Linux x86_64 and an OpenGL 3.3-capable driver. Save data lives in
`~/.local/share/godot/app_userdata/Kakaboomboom/` by default, not in the game folder.

### Building a release

Use **Godot 4.7.2 stable**, its matching **Linux x86_64 export templates**, Python
3.11+ and Make. The default executable is
`~/.local/opt/godot/4.7.2/godot`, deliberately not the older `godot` on PATH.
Install matching templates through **Editor → Manage Export Templates**; the
Linux release template must be in
`${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable/`.

```sh
make release-linux
# Override only the executable location, not the engine version:
make release-linux GODOT=/path/to/godot-4.7.2
```

The rule exports the `linux/x86_64` preset, then writes a versioned `.tar.gz`,
its SHA-256 sidecar, and an unpacked release under `export/linux/`. Each package
contains the executable, controls/install documentation, release notes, credits,
Godot and dependency license notices, `VERSION`, `build-info.json` and
`SHA256SUMS`. `export/linux/kakaboomboom.x86_64` is also available for direct use.
Export failures stop packaging; generated builds are ignored by version control.

For future releases, update `application/config/version` in `project.godot` and
`RELEASE_NOTES.md` before running the rule. The package name, metadata and menu
version come from that project setting. The rule replaces the artifacts for the
same version; older versioned releases remain intact.


## Controls

- **WASD** moves; **mouse** aims; **Space** jumps.
- **Hold LMB** fires your single primary gun with unlimited ammunition. The **mouse wheel** swaps among the six firearms; purchased primary-mod ranks follow the new gun. Swaps retain the 0.2 s draw.
- **Aim at visible ore within 2.6 m** to automatically equip the drill, then **hold F** to mine. Aim at the glowing **◇ weak seam** for faster cuts. Look away to return to your gun. Guns and abilities cannot extract minerals.
- **1 / 2 / 3 / 4 / 5** activate your class abilities. WASD is unchanged; W remains movement, not an ability binding. With **Guided start** (default) only key 1 works at first; the rest unlock as you level (see below).
- **E** interacts with consoles, flame vents or a secured defense-vein beacon in the standalone authored lab arenas.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Finish every level objective:** a drop pod lands in the farthest room, with a green beam over the walls and a radar marker. Reach it and hold its ring for 10 s while the horde surges (progress is kept if you step out to fight). Lift-off banks minerals and opens the shop. Swap the primary freely, upgrade any of your five abilities, buy primary mods or suit systems, then **Continue**. After death: **R** retries with the same class and a new layout; **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Base Workshop**, **Records**, **Settings**) → class select with the full five-ability kit → run. Each level is carved from solid rock by a new seed: irregular rooms joined by winding corridors, never one open box. Rooms come as L, T, cross, chamfered, round, ring (a walk-around central pillar of rock) and pillared colonnade shapes. Corridors are dog-legged, 4 m chokepoints, 6 m passages or 8 m boulevards; extra loops mean every area has a second way out and the horde can flank. Short dead-end alcoves make defensive pockets, or traps. Painted floor lines trace every corridor: accent for normal passages, secondary colour for chokepoints. The radar draws the walls around you.

Each theme plans differently:

- **Training Yard:** a compound of mixed-shape rooms on a spanning tree plus loops.
- **Foundry:** three long stacked furnace halls, one a colonnade, joined by several short transfer passages, with side chambers at the ends.
- **Reactor:** a round hub around a 15 m glowing reactor core, narrow spokes into the hub, and diagonal chords linking the outer rooms in a ring.

**Overlooks** sit in large arena rooms: raised decks reached by one treaded ramp, giving firing height while the horde funnels up the ramp, a choke point for Gravity Well and Pulse Barrier. **Ore outcrops** are rock islands with glowing seams and a beacon in the open rooms. Yard has 1 overlook / 2 outcrops, Foundry and Reactor 2 / 3. Themes keep their floor shaders, palettes and enemy schedules. Most groups arrive behind you.

**No level countdown or deadline.** At arrival, the LEVEL CONTRACT board gives two mining objectives (Gold and Cinder Crystal) and two different non-boss enemy-species kill objectives. Counts and species vary with the seed and scale with the sector. Drill nearby ore sections with F and defeat the requested enemies; unrelated kills, carried currency, collected reward nuggets and resource bonuses do not advance mining. Progress remains earned when you stop to fight.

Every generated contract starts with enough physically supported, reachable ore, with spare yield where possible. Contract ore fills outcrop faces first (a fair share per resource), then broad room and corridor walls with standing room in front. Requested enemy species spawn from the outset and remain available indefinitely. Crowd pressure ramps to a capped final rate, not a timer-triggered boss.

**Extraction:** finishing **all** objectives calls a drop pod to the clear room spot farthest from you. It descends for 3 s, then hovers in a beam; standing inside its 4.5 m ring for 10 s lifts off, banks minerals and opens the round shop. Progress accrues only inside the ring and while unpaused, and is kept if you step out. The director spawns at double rate until lift-off, and dying during extraction still ends the run at 50% banking. Earned upgrade choices can be answered mid-extraction; killing a boss cannot bypass unfinished objectives.

| Stage | Crowd cap | Objective scale | Contract | Arrival calm |
| --- | --- | --- | --- | --- |
| Training Yard (88 × 88 m, ~43% walkable) | 1000 | 1.0× | 1 mine + 1 kill | 12 s |
| The Foundry (120 × 72 m, ~62% walkable) | 1500 | 1.35× | 2 mine + 1 kill | none |
| Reactor Core (104 × 104 m, ~43% walkable) | 2100 | 1.7× | 2 mine + 2 kill | none |

Continue carries the primary build, all five ability ranks, level-up upgrades, perks and auto weapons into a newly generated next sector, resets its quest counters and refills health. Finishing the Reactor records victory; its final shop returns to the base. Run duration remains a record statistic, not a progression gate. Contact damage remains capped at 4 damage per 0.5 s; ordinary wave density and individual enemy health are preserved.

**Standalone tactical fixtures:** the `encounter`, `boss` and `boss_patterns` lab scenarios retain the authored defense vein, interactive hazards, raised decks and ramp combat. These fixed placements are not inserted into generated campaign layouts. Bulwarks still use directional front armor/rear precision cores in campaign crowds; explicit boss fixtures retain Breach Ram, Mortar Salvo and staggerable recovery windows.

## Classes

| Class | Unlock | Starting primary | Abilities 1 / 2 / 3 | Profile |
| --- | --- | --- | --- | --- |
| Scout | free | Pulse | Blink Dash / Recon Flare / Grapple Vault | +12% speed, +1 m pickup |
| Gunner | 6 shards | Minigun | Bulwark / Suppression Barrage / Battle Frenzy | +30 health, +1 armor, −5% speed |
| Driller | 10 shards | Flamethrower | Seismic Charge / Drill Dash / Magma Trail | +150% mining, +5% damage |
| Engineer | 14 shards | Pulse | Overdrive / Platform Turret / Repair Drone | Starts with Sentry Turret, −10% auto cooldown |

Every class includes **4: Gravity Well** and **5: Pulse Barrier**. Gravity Well gathers, slows, interrupts and damages nearby enemies for five seconds. Pulse Barrier gives 1.6 seconds of protection and an immediate damaging knockback pulse: a brief window to drill, reposition or escape. Battle Frenzy boosts main-gun fire rate and pierce; it has no ammo interaction.

All five skills have separate cooldowns. Each supports three run-upgrade ranks through level-up cards and the shop: +25% damage, −12% base cooldown and +15% duration per rank where applicable. The HUD shows each key, readiness, remaining cooldown and rank. Pause freezes both cooldowns and persistent effects; inactive/dead players release their fields and buffs. Overlapping shields and cooldown/exposure effects retain independent ownership.

**Guided start** (Settings, on by default) introduces the game in steps instead of all at once:

- **Skills by level:** a run starts with skill 1 only. Skills 2, 3, 4 (Gravity Well) and 5 (Pulse Barrier) unlock at levels 2, 3, 5 and 7, each with a NEW SKILL callout and a tip. The HUD shows a dim teaser of the next skill with its unlock level; locked skills cannot be cast, and do not appear as level-up cards. Shop cards show them as LOCKED with the level.
- **Upgrade types by level:** early level-ups offer auto weapons, stats and unlocked skill masteries; perks join at level 3 and gun mods at level 5.
- **One-time tips:** short cards above the skill bar explain each system when it first matters: moving and shooting, the contract, the first skill and each new one, mining near ore, low health, extraction and combos. Each tip counts as seen after 2 s on screen (an interrupted tip comes back) and is remembered in the profile; Settings → *Show tips again* resets them.
- **Footer:** the controls line lists only what you have unlocked.

Turning Guided start off gives experienced players all five skills and every upgrade type from the first second, with no tips. The smaller early contracts and the Yard's 12 s arrival calm are stage design and apply either way.

**Skill combos** (every class, since all carry Gravity Well and Pulse Barrier). A named callout appears below the crosshair:

- **CRUSH:** any skill blast that reaches into your active Gravity Well deals +60%. This covers Seismic Charge, Suppression Barrage, Grapple and Drill Dash landings, Platform Turret drops, Bulwark, Recon Flare, Magma Trail patches and the Pulse Barrier pulse.
- **COLLAPSE:** casting Pulse Barrier within 6 m of your active well's edge detonates it. The burst deals 70 base damage, +10% per held enemy (up to +150%), and flings the pack outward.
- **SHIELD RAM:** Blink Dash, Drill Dash or Grapple Vault used while another skill's shield holds (Pulse Barrier, Bulwark, Repair Drone) slams a 5.5 m, 45-damage shockwave where you land, and it can CRUSH too.

**One primary, one trigger:** no player melee weapons, magazines, reserves, reloads, ammunition pickups, charged secondaries or cross-charge meters. The six existing firearm models remain unchanged. Choose a persistent starting blueprint in the Workshop, change guns with the wheel or free shop selector, and keep purchased primary-mod ranks without compounding them. Passive auto weapons remain separate level-up picks.

| Weapon | Main cadence | Role |
| --- | --- | --- |
| Pulse | 0.09 s | Precise rapid carbine, pierces 1 |
| Rail | 0.45 s | Heavy piercing rifle |
| Scatter | 0.38 s | Seven-pellet shotgun |
| Minigun | 0.032 s after 0.2 s spin-up | Sustained high-rate fire |
| Autocannon | 0.19 s | Explosive shells |
| Flamethrower | 0.045 s | Short-range piercing flame cone |

**Survival loot:** every third regular kill earns that victim's XP gem; skipped XP is not silently merged into a later gem. Magnets drop every 120 regular kills, and repair kits have a 0.4% chance. Bosses retain their authored XP and award a magnet; the stage-clear reward is one Void Shard. Magnets attract all currently loose XP, including moving gems, and award XP only on arrival. Later gems stay loose. Repair kits heal up to 15 HP and remain at full health. There are no ammunition drops.

**Timed repair supply:** a nearby repair pack lands every 50 gameplay seconds, with at most two separated waiting packs independent of enemy loot. Placement checks obstacles, ground and walkable routes; small raised decks use a nearer fallback rather than dropping beyond a cliff. Timers stop during pause and after the player becomes inactive. The radar marks magnets and both ordinary and timed repairs. Continue refills health.

**Damage and feedback:** kinetic deals direct damage; fire ignites for four burn ticks over two seconds; frost slows movement to 55% for 1.8 seconds; shock chains 40% damage to up to three nearby enemies. Critical and kill numbers report actual health removed, not overkill. Same-type hits within 0.9 m and 0.2 s merge into one number (a crit or kill upgrades it), and new numbers stack above ones they would overlap; crits carry a crit icon.

**Gun feel:** stronger damping and shorter weapon travel keep recoil gentle. Camera pitch/yaw/roll recovers on a bounded spring, with no firing FOV punch; main-gun rays use the head's stable aim, not the visually recoiling camera. Models slide into the raised pose on swaps, and Scatter cycles its pump after shots. Muzzle flashes vary, tracers fade and pooled casings eject from authored ports. The crosshair blooms without changing aim. Fractional cooldown overshoot preserves boosted cadence above 60 shots/s; idle time and long hitches cannot bank an unbounded burst.

**Precision hits (source changes, not yet packaged):** main-gun rays through a visible head or exposed core earn a guaranteed ×3 critical hit, without needing Lucky Strike. Ordinary rolled body crits deal ×2. Precision uses the current crit-damage factor plus one base-damage unit; it never multiplies a random crit again. Lucky Strike therefore improves both rolled crits and aimed hits. Each pierced victim is judged separately; headshots do not amplify splash, burn ticks or chained damage. Weak volumes follow enemy yaw, scale and feet height, and cannot be hit through a world blocker. Kill numbers retain actual damage but no longer say `DOWN`; critical numbers show a crit icon instead of `CRIT`.

Spitters have 180 base health, tanks 420 and bosses 6000; schedule multipliers still apply. These values are not a full-campaign balance certification.

**Gunplay research:** Derek Mattson's [GDC 2024 *A Second Shot*](https://media.gdcvault.com/gdc2024/Slides/GDC+slide+presentations/Mattson_Derek_ASecondShot_Notes.pdf) emphasizes reliable target reactions and coherent presentation. Contact feedback precedes restrained camera effects; recoil never drifts aim, and the horde simulation has no global hit-stop. Six original Blender-authored models use metre-scale receivers, open barrel bores, rails, sights, magazines, metal/polymer/rubber materials and gloved grips. Static parts are batched by material; magazines, the shotgun pump and the rotary barrel assembly remain movable.

**Hit chains:** each main-gun shot that directly hits an enemy adds one beat, no matter how many pellets hit. After three consecutive hits, each further shot gains +8% damage per beat, capped at +40%. A miss, taking damage, or 2.5 seconds without another hit breaks the chain; explosions alone do not extend it. The crosshair shows the next shot's bonus and a countdown. Hit-confirmation sounds climb in pitch; hits and kills have brighter impact sparks and stronger recoil.

**Auto weapons** (level-up picks, up to four at a time, each to level 5): Sentry Drones, Nova Pulse, Auto Mortar, Arc Coil, Saw Orbit, Sentry Turret, Cryo Field (slows and frost-tints enemies) and Homing Rockets. A weapon at max level unlocks its **overclock** card, a one-time signature upgrade: piercing drone beams, double nova, cluster mortar, forking arcs, twin blade rings, exploding turrets, shattering frost and splitting rockets.

**Perks** (level-up picks, each to level 3; do not occupy an auto-weapon slot): Chain Reaction (exploding kills), Vampiric Rounds (heal on kills), Adrenaline (fire rate when hurt), Thorns (contact retaliation), Lucky Strike (main-gun critical hits), Momentum (moving damage), Scavenger (bonus crystals) and Last Stand (survive a lethal hit once per stage, more charges at level 3).

**Gun mods** (single-pick level-up cards; no auto-weapon slots): Quickdraw Capacitor gives the primary's first shot within 1.5 s of a wheel swap +75% damage (the charge is spent on a miss); Longshot Optics gives direct hits beyond 15 m +40% damage; Executioner Core gives direct hits on enemies already below 35% health +60% damage. They can be combined.

**Stat upgrades:** damage, fire rate, pierce, speed, health, regeneration, armor, pickup radius, auto-weapon area and cooldown, XP, and Splitter Array (extra drones, blades, shells, turrets and rockets). Lucky Strike also adds critical chance and damage to the main gun.

## Mining and progression

Minerals grow as large procedural formations on broad walls and obstacles. Each
seed chooses a hollow geode crown, winding vein or forked cluster with **7–9
independent sections**, each made from recursively branching crystals. Placement
reserves a roughly 4.4 × 2.6 × 1.35 m envelope (with size variation), tests full
surface/floor clearance and keeps formations away from spawn points and narrow
passages. Deposits respawn over time.

**Cut, reveal, retarget.** Aim at a section within 2.6 m and hold F. Damage stays on that
section when you stop to fight. Its seams brighten as it cracks; breaking it
removes its actual surface collider and spills part of the deposit's loot
immediately. There is no whole-deposit shrink animation or final duplicate payout.
The pre-rolled total is 14–20 Gold, 5–8 Cinder Crystals or one rare Void Shard. Initial contract ore is guaranteed on clear collider faces; generic formations fill the remaining 11–18 deposit budget, with 35–50 s respawns. Generated objectives never require waiting for a random respawn. The authored lab defense vein remains separate.
Rare deposits can have zero-yield outer sections; the complete formation still
contains its fixed shard budget.

**Weak seams and resonance.** The glowing tip/◇ cue marks a real physical weak
seam for **×1.75 cutting damage**. Sustained drilling on the same section builds
up to **+35% cut rate over 0.65 s**. Releasing, losing contact, changing section or
pausing resets resonance, but never restores the section's health. The readout
shows mineral type, local fracture progress, sections remaining and the current
resonance bonus. Drill pitch, sparks and recoil follow those states.

**Fractal feedback.** Contact injects mineral-coloured branching contours into
two alternating 384 × 216 history textures. Previous frames rotate, expand and
fade into translucent echoes; section breaks add a ring pulse. The centre stays
clear, HUD text is drawn outside the effect, and the history stops after a short
tail. Pause, death and stage teardown clear it. `MiningTool.feedback_strength`
controls intensity; zero disables the history effect while retaining the readout.

### Mining design references

- [Deep Rock Galactic's pickaxe](https://deeprockgalactic.wiki.gg/wiki/Pickaxe):
  progressive extraction and combat-compatible RMB mining (community wiki).
- [Astroneer developer interview](https://www.gamedeveloper.com/design/what-i-astroneer-i-s-devs-learned-while-leaving-early-access):
  locally deforming beautiful procedural structures without rebuilding a world.
- [No Man's Sky: Beyond](https://www.nomanssky.com/beyond-update/):
  cutting effectiveness communicated through tool state and colour.
- [Minecraft geodes](https://www.minecraft.net/en-us/article/amethyst-geode):
  readable geological structures and progressively revealed crystal interiors.
- [Crystaldive renderer](https://github.com/Ondrysak/crystaldive/blob/main/src/renderer.rs):
  temporal history, UV warping, injection and decay. The repository has no
  declared license; this project's geometry and shaders are independently
  authored mathematical implementations, not copied source.

The weak-seam multiplier, resonance and bounded fractal overlay are this game's
adaptations, not claims that all the reference games use those exact mechanics.

- **Gold**: banked; buys round-shop stock, base crafting and permanent Armory upgrades.
- **Void Shard**: banked, rare; each completed level awards one; unlocks classes and pays for advanced shop/base recipes and ability upgrades.
- **Cinder Crystal**: now banked as well as filling the supply meter for free upgrade picks and powering turret consoles (10 run crystals each).

All three minerals move into your profile at 100% when you clear a stage (loot still on the floor is swept up), and at 50% if you die or abandon the run. Spending run crystals on consoles removes those crystals before banking.

**Round mineral shop:** completing the entire level contract pauses gameplay and opens the exchange. One primary panel shows current stats, a free weapon selector and a comparison with purchased mods reapplied. All five skill cards are always available with their own ranks, effect previews and mineral prices. Random stock is split into **Primary mods** (4 FIREPOWER, PAYLOAD or ELEMENT offers) and **Suit systems** (2 run-wide armor/health/power offers), in scrollable tabs. Paid rerolls replace only unsold stock and cost 3 gold + 1 crystal more after each refresh. Sold, capped or unaffordable purchases do not debit minerals. The primary build and all five skill ranks carry into the next level; run-only upgrades expire at run end. `RoundShop.CATALOG` defines primary/suit stock, `WeaponBuild` rebuilds effective guns from authored snapshots, and ability cards use the same rank scaling as combat.

**Persistent base:** craft armor, starting weapon blueprints and one primary gadget, plus automatically applied perks and ranked talents. Equip one armor set, one starting primary and one gadget; resetting the primary restores the class default. The Armory tab retains eight permanent upgrades (Vitality, Firepower, Agility, Magnetism, Prospector, Salvager, Scholar, Plating), five levels each. Records track best time, kills, level, runs, victories and deepest stage. Everything is saved to `user://profile.json`. Older saves migrate the first valid crafted firearm/gadget into scalar equipment, skip deleted melee blueprints and retain currencies, class unlocks, other crafting, upgrades, records and settings. Old single-ability selections no longer hide the complete kit.

## Music

The adaptive soundtrack is rendered procedurally on background threads at startup into sample-synced loop stems (D minor, 126 BPM). Layers fade in with the crowd density around you (pad → drums → bass drive and arp → lead and tension); the boss swaps in a darker harmony layer. Stingers mark level-ups, stage clears, death and victory. Music, SFX and master volumes are adjustable in Settings.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, class unlocks, Armory levels, crafting ranks, equipped armor/primary/gadget, records and settings. Multi-mineral payments validate the entire cost before debiting. `Music` (`scripts/audio/music_director.gd`, with `music_score.gd` and `music_synth.gd`) plays tracks and stingers and follows intensity. Buses are defined in `default_bus_layout.tres`.
- **Stats and economy:** `RunState` combines class/Armory/crafted modifiers and level-up stacks, owns one `WeaponBuild` (`scripts/progression/weapon_build.gd`), and stores five ability ranks. Swaps rebuild from an immutable authored snapshot, retaining purchased ranks and the latest element conversion without compounding. `RoundShop` purchases stock and individual skills; `CraftingCatalog` supplies persistent `CraftRecipe` definitions.
- **Classes and abilities:** `data/classes/*.tres` and `roster.tres` define stats, class unlock cost, `primary_weapon` and five `ability_scenes`. `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`) owns slot-specific cooldowns and shared rank scaling. Buffs, exposure zones and protection are source-owned, so one ending skill cannot remove another's effect.
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage type, damage, cadence, pellets, spread, pierce, recoil, knockback, explosion, spin-up and icon) reference `WeaponView` scenes in `scenes/weapons/`, instancing the original `assets/guns/*.glb` meshes. Rebuild with `blender -b --python tools/guns/build_guns.py`, then import with the project Godot executable. No image-generation access is required. `ArenaPlayer` owns one trigger, draw lock, combo, gun mods and camera spring; hit/tracer/casing visuals remain pooled.
- **Auto weapons, perks and gun mods:** `AutoWeapon` subclasses in `scripts/weapons/auto/` and `PerkEffect` subclasses in `scripts/perks/` use `UpgradeDefinition`s (STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD) in `data/upgrades/pool.tres`. ABILITY offers are generated for the actual five class slots. `AutoWeaponRack` owns passive auto weapons and perks; perks, primary mods and ability ranks do not consume its four slots.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented simulation with one MultiMesh per enemy type, a shared flow field, weapon queries, `slow()`, faction FX and contact tuning. The flow field avoids obstacles and treats cliffs as walls; it routes to the player's level over ramps. Each enemy has a feet height taken from the stage heightfield: it snaps up ramps, falls off ledges and never climbs a step over 0.3 m. Hit tests, blasts, projectiles and contact damage all use that height. Robot and alien stats/animations are in `data/enemies/*.tres`. Meshes are baked from the CC0 models in `assets/monsters/` into shared textured surfaces; `shaders/horde_enemy_vat.gdshader` animates the crowd from position/normal textures and per-instance clip state. `tools/vat/README.md` covers the reproducible Blender bake and source pack licenses. The static shader remains available for other models.

  Enemy `weak_spot_offset` and `weak_spot_radius` author a head/core sphere in model-space metres before `model_scale` and yaw; radius zero disables precision hits. Type-level offsets, squared radii and upper hit bounds are cached once, not allocated per shot.
- **Mining:** `ResourceDefinition` data lives in `data/resources/`; deposit types are in `data/resources/deposits/`. `DepositGeometry` builds seeded section meshes and matching triangle colliders; `MineralDeposit` owns persistent local health and a conserved integer loot budget. `DepositField` probes placement and spills section loot. `MiningTool` owns the drill and `MiningFeedback`'s ping-pong canvas history. Materials are in `shaders/deposit_crystal.gdshader` and `shaders/mining_history.gdshader`; there are no authored deposit model scenes.
- **Survival pickups:** `scripts/progression/pickup_field.gd` pools XP, magnets, repairs and a separate two-pack timed repair supply set. `PickupGeometry` builds their faceted silhouettes once at setup. Kill thresholds and supply interval are exports; grounded placement uses the horde heightfield, and supply routes reject obstacles and cliffs. Collection never overwrites the persistent profile. The radar reads the same live pickup pools.
- **Procedural levels:** `data/stages/*.tres` configure play area, `layout_theme`, `cover_count`, `overlook_count`, `outcrop_count`, `quest_scale` and `SpawnSchedule`. `ProceduralWorld` (`scripts/world/procedural_world.gd`, `scenes/levels/procedural.tscn`) is configured with the stage and seed before entering the tree. It carves a 2 m grid identical to the horde grid: the theme plan places rooms, corridors join them (spanning tree plus loops, or the Reactor's spokes and chords), and alcoves are added. Ring cores are refilled and cells unreachable from spawn are pruned. Remaining rock merges greedily into exact axis-aligned blocks under `Obstacles`; broad block faces with two open cells in front become contract `mining_sites`. Overlook decks and tilted ramp boxes live under `Elevation`, which the horde rasterises into its walkable heightfield. Set pieces, pillars and cover check carved floor plus margins, so passages and ore standing room stay open. `layout_open` is public for the radar. Original authored worlds remain explicit lab fixtures with their own play areas.
- **Level contracts:** `LevelQuests` (`scripts/level_quests.gd`) selects seeded resource/ordinary-species targets, clamps progress and emits completion once. `DepositField` records conserved raw section fractures; `ArenaGame` records exact horde victim definitions. Inventory/banking signals never count. `HordeDirector` sustains every ordinary wave; `SpawnSchedule.ramp_duration` bounds pressure ramping, not level length, and `surge` multiplies spawning during extraction. Boss release is explicit. Completion defers beyond the current impact, rejects stale source ids and respects death and earned upgrade choices, then spawns an `ExtractionPod` (`scripts/extraction_pod.gd`, collision-free) at `ProceduralWorld.extraction_point()`; only its stale-checked `departed` signal clears the stage.
- **Skill combos:** `ActiveAbility.blast()` wraps every skill's area damage and applies CRUSH against `ArenaPlayer.active_gravity_well()`; `arrive()` is called at movement-skill landings for SHIELD RAM via `is_shielded_by_other()`; Pulse Barrier calls `GravityWell.collapse()`. `ArenaPlayer.ability_combo` drives the HUD callout (rate-limited per combo), while `combo_counts` records every trigger.
- **Luďas's voice:** `LudasVoice` (`scripts/audio/ludas_voice.gd`, owned by `ArenaGame` so it survives stage loads) plays recorded reactions from `assets/voice/ludas/`: arrival, kill bursts (12 kills within 1.5 s), combos, a skill unlock (*Jaj… krajíc… chleba* in sequence), dropping below 40% health, healing, extraction, stage clear and death. One line plays at a time; a higher-priority reaction interrupts a lower one, and each reaction has its own cooldown. The reskin plan lives in `docs/ludas/BIBLE.md`.
- **UI:** `scenes/ui/hud.tscn` has mineral/supply counters, contract objectives, hostiles/kills, vitals, one primary readout, numbered skill tiles (locked ones hidden behind one teaser) and a close-range F mining prompt. There is no level timer or ammo readout. Explicit boss fixtures retain WARNING, health/recovery readouts and radar markers. Numeric level-up choices consume input before resuming, so choosing a card does not cast a combat ability.
- **Guided start:** `RunState.start_guided()` sets `unlocked_abilities` from `ABILITY_UNLOCK_LEVELS` and emits `ability_unlocked` as levels are gained; `can_upgrade_ability()` and `_is_eligible()` gate skills, perks and gun mods. `Tutor` (`scripts/ui/tutor.gd`) queues one-time tips stored in `Profile` (`seen_tips`, `guided_start` setting). `StageDefinition.mine_objectives`, `kill_objectives` and `spawn_grace` (`HordeDirector.grace`) size each sector's contract and arrival.
- **Pixel-art icons:** every upgrade, gun, class, ability, Armory upgrade, mineral, workshop recipe, shop item and HUD glyph has a 16 × 16 icon in `assets/icons/<group>/<id>.png`. They are authored as text grids in `tools/icons/art_*.py` on the shared palette in `tools/icons/pixel.py` (automatic dark outline). Data resources reference their icon through `icon` exports; code-only concepts use `GameIcons.lookup(group, id)` (`scripts/ui/game_icons.gd`), and `CraftRecipe.display_icon()` resolves a recipe's payload icon. Show them nearest-filtered at 2×, 3× or 4× (`GameIcons.rect`). After editing art, run `make icons` (renders, then imports); `python3 tools/icons/build.py --group <g> --preview /tmp/icons` also writes a labelled 6× preview sheet.
- **Run flow:** `scripts/game.gd` (`ArenaGame`) builds each stage under a fresh `Round` node, carries the effective primary build and five ability ranks between stages, and handles level-up, pause, the mineral shop and final return to base. It banks all three minerals into `Profile`, records runs and drives music intensity from crowd density.

Performance: the mixed-faction 1,600-enemy horde was measured in a Godot 4.4.1 headless CPU check (120 frames). On the elevated stages, simulation averaged 7.2 ms per frame on the Yard and 7.5 ms on the Reactor (about 20% of the horde on raised ground); draw preparation took about 2.6 ms. The same check before the heightfield measured 6.1–6.5 ms. GL Compatibility visuals were inspected in an isolated 1280×720 virtual display (Mesa llvmpipe); **60 fps has not been measured on the Radeon GPU**.

Run the precision-damage and nested-blast regressions with the editor executable:

```sh
~/.local/opt/godot/4.7.2/godot --headless --path . --script tools/check_combat.gd
```

## Visual test lab

`scenes/lab/lab.tscn` runs isolated scenarios through the real game scenes and captures screenshots, like visual unit tests. `Profile.enter_sandbox()` resets the loaded profile to defaults and disables save writes before scenarios start; lab purchases and runs never overwrite `user://profile.json`.

| Scenario | Shows | Checks |
| --- | --- | --- |
| `combat` | one primary firing into a mixed robot pack | actual damage and kills |
| `weapons` | each of the six main guns firing | visual review |
| `recoil` | 6-frame strips after one rail shot and during minigun fire | camera kicks and recovers, sustained kick stays capped, player aim unchanged |
| `guns` | side and three-quarter views of all six Blender models | visual review |
| `gunplay` | sustained unlimited fire, upgraded gun swaps and paused trigger | real damage beyond a burst, stable aim, mods preserved without compounding, release before resumed fire |
| `tempo` | real held-input firing for six guns and boosted Minigun | actual cadence above 60 shots/s, stable aim, gentle recoil and bounded hitch catch-up |
| `pressure` | real stage directors and accelerated crowds with scarce loot | arrival calm free of spawns, prompt groups after it, all-stage caps, ordinary/specialist admissions, sparse XP/magnet boundaries, repair RNG, overflow conservation and paused/inactive/freed-player supply timers |
| `levels` | first-person, overhead and deck views of all three carved themes | same-seed repeatability incl. elevation, different-seed variation, connected clearance grid, reachable ramp feet and ore standing spots, placed overlook/outcrop counts, continuous ramp heightfield, outcrop contract ore, real W input climbing a ramp and an enemy following onto the deck |
| `quests` | F drilling, enemy kills, earned choices and three pod extractions | exact species, stock/reward exclusion, indefinite safe spawning, pause, both completion orders, pod lands far away with surge, no progress before touchdown or while away, beam progress, pause freeze, kept progress after stepping out, shop only after lift-off, one-shot clear and stale-level rejection |
| `pickups` | repair kits, distant XP vacuum and timed repair supplies | actual healing, full-health preservation, exact XP/overflow conservation, later loose gems, supply cap, pause/inactive timers and raised-deck fallback |
| `abilities` | every class's five physical number keys and actual effects | damage, movement, healing, source-owned buffs, overlapping shields, pause/death cleanup, rank-scaled damage/cooldown/protection |
| `combos` | CRUSH, COLLAPSE and SHIELD RAM through physical keys | exact +60% crush versus a plain blast, real Seismic Charge into a well, named callout, out-of-reach control, collapse burst scaling with held enemies, dash-without-shield control and ram damage on arrival |
| `onboarding` | guided arrival, a skill unlock and locked shop cards | one skill plus teaser, footer, locked key, two-objective first contract, 12 s calm with a real director, no early perks/gun mods/locked skills, level-gated unlocks with callout/tip/working key, combo tip at level 7, tips seen once, Guided start off shows everything |
| `voice` | Luďas's recorded reactions | arrival, kill-burst trigger and cooldown, skill-unlock sequence order and interruption, hurt growl with cooldown, heal gulp, death outranking everything |
| `boss` | robot and alien bosses: arrival, fight, low health, kill | tracked boss, WARNING/health frame, death cannot bypass unfinished objectives |
| `boss_patterns` | ram lanes, mortar footprints/impacts and teal recovery | real damage and movement dodges, locked targets, cover/height/radius boundaries, +50% recovery, stagger interruption, pause and death/menu/node-removal cancellation |
| `armor` | front shield/rear core, rotated markers and independent auto guns | real armor/precision arc boundaries, actual source direction, tag ordering, mixed splash, burn potency, finite stun/turning, slot reuse and reserved admission |
| `encounter` | authored defense vein, mining under pressure and earned reward | real sections/response identities, both completion orders, conserved loot, pause, E once, earned upgrade and queued XP choice preservation |
| `levelup` | new, mixed, ranked and ability mastery cards | selection upgrades the run and resumes play; physical numeric selection cannot leak into a combat skill |
| `shop` | primary comparison/swap, five skill upgrades, sold/maxed/empty wallet | real UI purchases, preserved mod ranks, layout bounds, exact debits, rerolls, capped/unaffordable refusals and no Esc skip |
| `hud` | five skill cooldowns/ranks, primary mods, armor, low health and death | actual lethal damage ends the run |
| `mining` | automatic idle drill, F fractures, out-of-range ore and a solid blocker | no gun mining, melee-only reach, actual section damage/yield, occlusion, paused input and return to gun |
| `menu` | every operator and workshop tab with one primary/gadget | saved gear, free primary switching and gadgets reapplied exactly once |
| `icons` | one gallery page per icon group | visual review |

```sh
make lab-shots                         # all scenarios -> lab_shots/*.png + lab_report.txt
make lab-shots SCENARIOS="shop boss"   # a subset
python3 tools/lab.py gunplay mining abilities shop  # single primary, proximity drill and hero kit
python3 tools/lab.py encounter armor boss_patterns  # tactical Yard features
python3 tools/lab.py tempo pressure pickups  # faster fire, scarce loot and healing supplies
python3 tools/lab.py levels quests     # generated arenas and mining/kill progression
python3 tools/lab.py --list            # scenario names; --window renders visibly, --clean hides the overlay
make lab                               # interactive: pick a scenario, play on; F1 list, F12 screenshot
```

`tools/lab.py` renders in an invisible 1280 × 720 `gamescope --backend headless` session on the real GPU when available, prints each `PASS`/`FAIL` and engine error, and exits non-zero on a failed check, engine error, failed process, 480 s timeout or missing report. Register a `LabScenario` subclass in `Lab.SCENARIOS`. `start_game(class, stage)` uses explicit authored combat fixtures; `start_game(class, stage, true, seed)` exercises actual generated campaign worlds. Helpers include `equip_weapon`, `spawn_pack`, `ahead`, `aim_at`, `aim_deposit`, `fire`, `wait`, `capture`, `capture_strip` and `check`. The game root remains pausable under the lab's always-processing shell.

The primary/hero-kit cutover passed **21 rendered scenarios / 153 captures with zero failures or script/engine errors** on the Radeon GPU. Coverage includes physical 1–5 input for all four operators, actual damage/movement/healing, independent shields and buffs, rank scaling, proximity-only F extraction, solid occlusion, sustained unlimited fire, preserved primary upgrades, skill/shop purchases, procedural contracts and scarce pickups. Precision and nested-blast regressions also passed.

A separate normal-scene GPU smoke retained live director/physics, capsule movement, primary firing, real wheel swaps and earned XP choices in a generated Yard (sandbox profile, invulnerable player). All five Scout skills activated; real F extraction fractured quest ore while hostiles kept spawning. It finished with 101 actual kills and 41 living threats, without script/engine errors. This is a functional smoke, not campaign-balance or FPS certification.

An isolated on-disk legacy save migrated and then restarted successfully: currencies, class unlocks, crafting/talents, records and settings survived; the first valid firearm/gadget became scalar gear, and the gadget applied exactly once. The probe used an isolated user-data directory, never the player's real save.

The final mastery-layout/quest/encounter follow-up passed 21 captures with zero failures, including full card-text containment and numeric-input isolation. That subset still reported a 20-instance ObjectDB exit warning; this work is not claimed universally warning-free.

The published 0.3.0 package has not been rebuilt for these source changes.
