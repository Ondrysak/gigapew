# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Pick an operator, survive escalating robot and alien swarms, mine walls for loot, choose guns and perks, clear three stages and spend banked currency between runs. Built with Godot's GL Compatibility renderer and CC0 art credited in [CREDITS.md](CREDITS.md); the music is synthesized at runtime. Open `project.godot` and press **F5**, or run `godot --path .`. Verified with Godot 4.4.1 and 4.7.2.

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
- **Hold LMB** fires only the focused gun. **1 / 2 / 3** or the **mouse wheel** swaps guns with a 0.2 s draw; cooldowns, reload progress and secondary charge survive swapping.
- **RMB** uses the focused gun's charged alternate fire. When aiming at a mineral section within 3.2 m, it instead raises the drill: hold to cut, aim at the glowing **◇ weak seam** for faster cuts. Release and press again to change RMB's purpose.
- **Q** uses your class ability.
- **E** activates nearby consoles or flame vents while facing them; shoot barrels and vent valves to trigger them. Look for warning lights before crossing electrified floor panels.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Clear a boss:** choose a hand in the mineral shop (click it or press **1 / 2 / 3**), buy weapon mods and suit systems or reroll stock, then **Continue**. After death: **R** retries with the same class, **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Base Workshop**, **Records**, **Settings**) → class and ability select → run. The base crafts permanent gear, perks and talents; its Armory tab retains existing permanent stat upgrades. Each stage counts down while the horde escalates. Most enemies spawn behind you; the radar shows the crowd. Yard and Foundry field robots, Reactor fields aliens. Each faction has grunts, runners, spitters, charging tanks and a boss. When the timer ends, the boss arrives while the horde keeps coming. Killing it banks minerals and opens the randomized round shop. Continue carries all three hand upgrades, level-up upgrades, perks and auto weapons into the next stage and refills health. The final shop returns to the base.

| Stage | Length | Crowd cap | Boss health |
| --- | --- | --- | --- |
| Training Yard (64 × 64 m) | 3:00 | 700 | 6000 |
| The Foundry (96 × 52 m) | 4:00 | 1100 | 9600 |
| Reactor Core (76 × 76 m) | 5:00 | 1600 | 14400 |

Contact damage comes in capped ticks of at most 4 damage per 0.5 s, even when surrounded. Enemies path through 4 m or wider doorways and around interior walls; each stage also has shootable explosive barrels, proximity mines, cycling electric floors, crystal-powered turrets and activatable flame vents.

**High ground.** Every stage has raised decks reached by ramps, plus 0.8 m jump ledges that only the player can climb as shortcuts. The Yard has a two-tier corner overlook (2.2 m and 3 m) and a 1.8 m gantry with a single-ramp chokepoint. The Foundry has a west casting gallery (1.6 m, 2.4 m, 1.6 m) and a 2.4 m forge mezzanine; each forms a loop back to the floor. The Reactor has corner bastions and mezzanines at 1.6 m and 2.4 m, a 3.2 m terrace and a 4 m overlook facing the core. Enemies cannot climb deck edges; they climb the ramps, so a ramp becomes a chokepoint. If you are below them, they walk off ledges and drop down at you. Enemies below a ledge cannot hit you in melee, but spitters still can, and no deck is out of the horde's reach.

## Classes

| Class | Unlock | Guns | Default ability (Q) | Alternate abilities (Void Shards) | Profile |
| --- | --- | --- | --- | --- | --- |
| Scout | free | Pulse, Rail, Scatter | Blink Dash: invulnerable 9 m dash | Recon Flare (3), Grapple Vault (5) | +12% speed, +1 m pickup |
| Gunner | 6 shards | Minigun, Autocannon, Scatter | Bulwark: 4 s shield and knockback pulse | Suppression Barrage (4), Ammo Frenzy (6) | +30 health, +1 armor, −5% speed |
| Driller | 10 shards | Flamethrower, Scatter, Rail | Seismic Charge: thrown charge with a 7 m blast | Drill Dash (5), Magma Trail (7) | +150% mining, +5% damage |
| Engineer | 14 shards | Pulse, Autocannon, Flamethrower | Overdrive: auto weapons recharge ~2× faster for 6 s | Platform Turret (6), Repair Drone (8) | Starts with Sentry Turret, −10% auto cooldown |

Each class has three Q abilities: its default and two permanent unlocks. On the class-select screen, select an ability tile, buy it with Void Shards, then equip it. The equipped choice is saved per class in `user://profile.json`.

**Gun roles and alternate fire:**

| Gun | Main fire | Magazine | Holstered reload | RMB at full charge |
| --- | --- | --- | --- | --- |
| Pulse | Precise carbine, pierces 1 | 24 | 1.6 s | **Tag Burst:** three shots expose targets for +35% damage from every gun for 4 s |
| Rail | Heavy piercing rifle | 5 | 2.0 s | **Overcharge Lance:** hold 0.7 s, release a ×3-damage piercing shot that also fractures minerals; early release or swapping cancels for free |
| Scatter | Seven-pellet shotgun | 6 | 1.8 s | **Concussion Blast:** 8 m forward cone, strong shove and 1.2 s stagger; bosses stagger for 0.3 s |
| Minigun | Spin-up rotary gun | 90 | 2.2 s | **Overspin:** instant full spin, double cadence and tight spread for 3 s; LMB remains the trigger |
| Autocannon | Explosive shells | 10 | 2.0 s | **Breach Grenade:** ballistic 4 m blast, heavy knockback and a deep cut into a struck mineral section |
| Flamethrower | Short-range piercing flame cone | 60 | 1.8 s | **Napalm Glob:** ballistic shot leaves a 4 s fire patch that burns and slows enemies |

**Rotation, not a triple volley:** each class starts with three complementary guns; crafted equipment still replaces individual slots. Only the focused model is raised. Holstered guns automatically refill partially spent magazines; an empty gun reloads in hand at 1.6× the listed time. Reload progress survives swapping. The HUD shows rounds, reload progress, an EMPTY · SWAP hint and a separate alternate meter per gun.

Landed main-fire shots charge the **other two guns**, nominally in about 4.5 s of hits at base cadence; kills add a bonus. Successful drilling charges the **focused gun**, with a weak-seam bonus. Meters start at 35/100 and each alternate costs 100. This enables rhythms such as Pulse → tag → Rail lance → Scatter escape, or Napalm → drill to recharge → switch to a longer-range gun while the fire patch persists. Swapping cancels held/burst/overspin effects, but launched projectiles and napalm remain. Each hand retains its own damage, cadence, pellets, splash, element and pierce upgrades without mutating siblings or authored resources.

**Damage and feedback:** kinetic deals direct damage; fire ignites for four burn ticks over two seconds; frost slows movement to 55% for 1.8 seconds; shock chains 40% damage to up to three nearby enemies. Critical and kill numbers report actual health removed, not overkill. Same-type hits within 0.9 m and 0.2 s merge into one number (a crit or kill upgrades it), and new numbers stack above ones they would overlap; crits carry a crit icon.

**Gun feel:** stronger damping and shorter weapon travel keep recoil gentle. Camera pitch/yaw/roll recovers on a bounded spring, with no firing FOV punch; both main and alternate rays use the head's stable aim, not the visually recoiling camera. The rendered lab measured 0.16° for one Rail shot and about 0.04–0.05° during sustained minigun fire. Models slide into the raised pose on swaps; detachable magazines dip during in-hand reloads and Scatter cycles its pump after shots. Muzzle flashes vary, tracers fade and pooled casings eject from authored ports. The crosshair blooms without changing aim.

**Precision hits (source changes, not yet packaged):** main-gun rays through a visible head or exposed core earn a guaranteed ×3 critical hit, without needing Lucky Strike. Ordinary rolled body crits deal ×2. Precision uses the current crit-damage factor plus one base-damage unit; it never multiplies a random crit again. Lucky Strike therefore improves both rolled crits and aimed hits. Each pierced victim is judged separately; headshots do not amplify splash, burn ticks or chained damage. Weak volumes follow enemy yaw, scale and feet height, and cannot be hit through a world blocker. Kill numbers retain actual damage but no longer say `DOWN`; critical numbers show a crit icon instead of `CRIT`.

Spitters have 180 base health, tanks 420 and bosses 6000; schedule multipliers still apply. A controlled 60 Hz simulation through the rendered input path, with fresh Scout guns, no random crits, a stationary Yard boss and swaps on empty magazines, measured **11.72 s body / 3.90 s weak-spot** kill times using primary fire only. Earlier triple-volley measurements are historical and do not describe this rotation model. These checks are not full-campaign balance certification.

**Gunplay research:** Derek Mattson's [GDC 2024 *A Second Shot*](https://media.gdcvault.com/gdc2024/Slides/GDC+slide+presentations/Mattson_Derek_ASecondShot_Notes.pdf) emphasizes reliable target reactions and coherent presentation. Contact feedback precedes restrained camera effects; recoil never drifts aim, and the horde simulation has no global hit-stop. Six original Blender-authored models use metre-scale receivers, open barrel bores, rails, sights, magazines, metal/polymer/rubber materials and gloved grips. Static parts are batched by material; magazines, the shotgun pump and the rotary barrel assembly remain movable.

**Hit chains:** each main-gun shot that directly hits an enemy adds one beat, no matter how many pellets hit. After three consecutive hits, each further shot gains +8% damage per beat, capped at +40%. A miss, taking damage, or 2.5 seconds without another hit breaks the chain; explosions alone do not extend it. The crosshair shows the next shot's bonus and a countdown. Hit-confirmation sounds climb in pitch; hits and kills have brighter impact sparks and stronger recoil.

**Auto weapons** (level-up picks, up to four at a time, each to level 5): Sentry Drones, Nova Pulse, Auto Mortar, Arc Coil, Saw Orbit, Sentry Turret, Cryo Field (slows and frost-tints enemies) and Homing Rockets. A weapon at max level unlocks its **overclock** card, a one-time signature upgrade: piercing drone beams, double nova, cluster mortar, forking arcs, twin blade rings, exploding turrets, shattering frost and splitting rockets.

**Perks** (level-up picks, each to level 3; do not occupy an auto-weapon slot): Chain Reaction (exploding kills), Vampiric Rounds (heal on kills), Adrenaline (fire rate when hurt), Thorns (contact retaliation), Lucky Strike (main-gun critical hits), Momentum (moving damage), Scavenger (bonus crystals) and Last Stand (survive a lethal hit once per stage, more charges at level 3).

**Gun mods** (single-pick level-up cards; no auto-weapon slots): Quickdraw Capacitor gives the focused hand's first shot within 1.5 s of a focus change +75% damage (the charge is spent on a miss); Longshot Optics gives direct hits beyond 15 m +40% damage; Executioner Core gives direct hits on enemies already below 35% health +60% damage. They can be combined, and installed mods appear under the focused hand on the HUD.

**Stat upgrades:** damage, fire rate, pierce, speed, health, regeneration, armor, pickup radius, auto-weapon area and cooldown, XP, and Splitter Array (extra drones, blades, shells, turrets and rockets). Lucky Strike also adds critical chance and damage to the main gun.

## Mining and progression

Minerals grow as large procedural formations on broad walls and obstacles. Each
seed chooses a hollow geode crown, winding vein or forked cluster with **7–9
independent sections**, each made from recursively branching crystals. Placement
reserves a roughly 4.4 × 2.6 × 1.35 m envelope (with size variation), tests full
surface/floor clearance and keeps formations away from spawn points and narrow
passages. Deposits respawn over time.

**Cut, reveal, retarget.** Hold RMB or shoot a section. Damage stays on that
section when you stop to fight. Its seams brighten as it cracks; breaking it
removes its actual surface collider and spills part of the deposit's loot
immediately. There is no whole-deposit shrink animation or final duplicate payout.
The pre-rolled total is 24–36 Gold, 10–16 Cinder Crystals or 1–2 rare Void Shards.
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
- **Void Shard**: banked, rare; the boss drops 3; unlocks classes and alternate abilities and pays for advanced shop/base recipes.
- **Cinder Crystal**: now banked as well as filling the supply meter for free upgrade picks and powering turret consoles (10 run crystals each).

All three minerals move into your profile at 100% when you clear a stage (loot still on the floor is swept up), and at 50% if you die or abandon the run. Spending run crystals on consoles removes those crystals before banking.

**Round mineral shop:** boss kills pause gameplay and open the exchange. The three hand cards show each gun's icon, damage type, DMG / RATE / PELLETS / SPLASH / PIERCE and rank pips per upgrade track. Stock comes in two sections rolled separately: **Weapon mods** (4 offers for the selected hand) from the FIREPOWER (damage, cadence), PAYLOAD (projectiles, splash, pierce) and ELEMENT (fire / frost / shock; one element per hand, buying another swaps it) tracks, and **Suit systems** (2 run-wide offers: armor, health, power). Each card previews its effect on the selected hand or run (for example `DMG 25 → 30`, `KINETIC → FIRE`) and shows its price with mineral icons, red when unaffordable. Paid rerolls replace only unsold cards and cost 3 gold + 1 crystal more after each refresh. Sold, capped or unaffordable purchases do not debit minerals. Hand selection carries into the next round. These upgrades expire when the run ends. All per-hand upgrades (names, tracks, caps, prices) are defined once in `RoundShop.CATALOG`; `WeaponHand` applies them and previews a hand's next rank without changing it.

**Persistent base:** craft armor, weapon blueprints and per-hand gadgets, plus automatically applied perks and ranked talents. Equip one armor set and one crafted weapon/gadget per hand; reset a gun to restore that class's free default. Crafting and equipment persist across runs, including after restarting the game. The Armory tab sells the existing eight permanent upgrades (Vitality, Firepower, Agility, Magnetism, Prospector, Salvager, Scholar, Plating), five levels each. Records track best time, kills, level, runs, victories and deepest stage. Everything is saved to `user://profile.json`; older profiles keep their currencies, unlocks, upgrades, records and settings.

## Music

The adaptive soundtrack is rendered procedurally on background threads at startup into sample-synced loop stems (D minor, 126 BPM). Layers fade in with the crowd density around you (pad → drums → bass drive and arp → lead and tension); the boss swaps in a darker harmony layer. Stingers mark level-ups, stage clears, death and victory. Music, SFX and master volumes are adjustable in Settings.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, unlocks, Armory levels, crafting ranks, equipped armor/hand gear, records and settings. Multi-mineral payments validate the entire cost before debiting. `Music` (`scripts/audio/music_director.gd`, with `music_score.gd` for the arrangement and `music_synth.gd` for synthesis) plays tracks and stingers and follows intensity. Buses are defined in `default_bus_layout.tres`.
- **Stats and economy:** `StatModifier` (`scripts/data/stat_modifier.gd`) holds shared stat fields. `RunState` combines class stats, Armory levels, crafted modifiers and level-up stacks, and owns three `WeaponHand` resources. `RoundShop` generates and purchases run-only stock; `CraftingCatalog` supplies persistent `CraftRecipe` definitions.
- **Classes and abilities:** `data/classes/*.tres` plus `roster.tres` define the loadout, stats, unlock cost, default `ability_scene` and optional `alternate_abilities` with shard costs. `Profile` remembers each class's equipped ability; abilities extend `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`).
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage type, damage, cadence, pellets, spread, pierce, recoil, knockback, explosion, spin-up, magazine size, reload time, icon and `secondary_scene`) plus a `WeaponView` scene in `scenes/weapons/`. Views instance the original `assets/guns/*.glb` meshes. Rebuild with `blender -b --python tools/guns/build_guns.py`, then import with the project Godot executable. No external image-generation access is required. `ArenaPlayer` owns the focused trigger, magazines, reloads, cross-charge, combo, gun mods and camera spring. Alternate scenes in `scenes/weapons/secondary/` extend `SecondaryFire`; `gun_secondary.gd` owns reusable rays, projectiles and fire patches, with expose/stagger state in `Horde`. Impact, tracer, casing and secondary visuals are pooled, not allocated per shot.
- **Auto weapons, perks and gun mods:** `AutoWeapon` subclasses in `scripts/weapons/auto/` and `PerkEffect` subclasses in `scripts/perks/`, granted by `UpgradeDefinition`s (STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD) listed in `data/upgrades/pool.tres`. The `AutoWeaponRack` owns auto weapons and perks; neither perks nor gun mods use an auto-weapon slot.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented simulation with one MultiMesh per enemy type, a shared flow field, weapon queries, `slow()`, faction FX and contact tuning. The flow field avoids obstacles and treats cliffs as walls; it routes to the player's level over ramps. Each enemy has a feet height taken from the stage heightfield: it snaps up ramps, falls off ledges and never climbs a step over 0.3 m. Hit tests, blasts, projectiles and contact damage all use that height. Robot and alien stats/animations are in `data/enemies/*.tres`. Meshes are baked from the CC0 models in `assets/monsters/` into shared textured surfaces; `shaders/horde_enemy_vat.gdshader` animates the crowd from position/normal textures and per-instance clip state. `tools/vat/README.md` covers the reproducible Blender bake and source pack licenses. The static shader remains available for other models.

  Enemy `weak_spot_offset` and `weak_spot_radius` author a head/core sphere in model-space metres before `model_scale` and yaw; radius zero disables precision hits. Type-level offsets, squared radii and upper hit bounds are cached once, not allocated per shot.
- **Mining:** `ResourceDefinition` data lives in `data/resources/`; deposit types are in `data/resources/deposits/`. `DepositGeometry` builds seeded section meshes and matching triangle colliders; `MineralDeposit` owns persistent local health and a conserved integer loot budget. `DepositField` probes placement and spills section loot. `MiningTool` owns the drill and `MiningFeedback`'s ping-pong canvas history. Materials are in `shaders/deposit_crystal.gdshader` and `shaders/mining_history.gdshader`; there are no authored deposit model scenes.
- **Stages and hazards:** `data/stages/*.tres` select a world, play area and `SpawnSchedule`. A world scene has a `PlayerSpawn`, a floor at y = 0, an `Obstacles` node of box/cylinder colliders (used by horde navigation and deposit placement), an optional `Elevation` node, and a `Hazards` node. `Elevation` holds `StaticBody3D` decks and ramps. Each has exactly one `BoxShape3D`, yawed in multiples of 90°, with ramps also pitched. They are solid down to the floor. The horde rasterises their top faces into a 0.5 m heightfield. Keep ramps ≤ 18°, at least 6 m wide, and flush with the floor and the deck edge (a lip of even a few centimetres stops the player's capsule). Decks must be at least 1.6 m high so their edges read as cliffs, and every deck must be reachable by ramp. `scripts/game.gd` configures every hazard once per round via `setup(horde, player, run_state)`. The five hazard scene/scripts live in `scenes/hazards/` and `scripts/hazards/`; world decoration is composed from CC0 MegaKit modules in `assets/third_party/`.
- **UI:** the HUD is `scenes/ui/hud.tscn`: stage panel with mineral counters and supply, timer, hostiles/kills, vitals (level, XP, health with low-health pulse, armor), ability slot with cooldown sweep, and three hand slots with weapon, damage-type, pellet, shop-upgrade and gun-mod icons. Bosses get a WARNING banner on arrival and a segmented top bar with a damage trail that turns ENRAGED at 30% or less; the radar marks the boss with a skull. Death shows a stat panel with banked minerals. Level-up cards (`scenes/ui/level_up.tscn`) show the upgrade icon, a kind chip, rank pips with NEW / MAX / INSTANT chips, gold overclock cards and a staggered entrance. The pause menu is `scenes/ui/pause_menu.tscn`. The intro, main menu and its screens are in `scenes/ui/` and `scenes/ui/menu/`, styled by the shared `menu_theme.tres`; class cards, ability tiles, workshop recipes, the hand loadout and Armory cards show framed icons (`scripts/ui/menu/icon_badge.gd`).
- **Pixel-art icons:** every upgrade, gun, class, ability, Armory upgrade, mineral, workshop recipe, shop item and HUD glyph has a 16 × 16 icon in `assets/icons/<group>/<id>.png`. They are authored as text grids in `tools/icons/art_*.py` on the shared palette in `tools/icons/pixel.py` (automatic dark outline). Data resources reference their icon through `icon` exports; code-only concepts use `GameIcons.lookup(group, id)` (`scripts/ui/game_icons.gd`), and `CraftRecipe.display_icon()` resolves a recipe's payload icon. Show them nearest-filtered at 2×, 3× or 4× (`GameIcons.rect`). After editing art, run `make icons` (renders, then imports); `python3 tools/icons/build.py --group <g> --preview /tmp/icons` also writes a labelled 6× preview sheet.
- **Run flow:** `scripts/game.gd` (`ArenaGame`) builds each stage under a fresh `Round` node, carries effective three-hand resources between stages, and handles level-up, pause, the mineral shop and final return to base. It banks all three minerals into `Profile`, records runs and drives music intensity from crowd density.

Performance: the mixed-faction 1,600-enemy horde was measured in a Godot 4.4.1 headless CPU check (120 frames). On the elevated stages, simulation averaged 7.2 ms per frame on the Yard and 7.5 ms on the Reactor (about 20% of the horde on raised ground); draw preparation took about 2.6 ms. The same check before the heightfield measured 6.1–6.5 ms. GL Compatibility visuals were inspected in an isolated 1280×720 virtual display (Mesa llvmpipe); **60 fps has not been measured on the Radeon GPU**.

Run the precision-damage and nested-blast regressions with the editor executable:

```sh
~/.local/opt/godot/4.7.2/godot --headless --path . --script tools/check_combat.gd
```

## Visual test lab

`scenes/lab/lab.tscn` runs isolated scenarios through the real game scenes and captures screenshots, like visual unit tests. `Profile.enter_sandbox()` resets the loaded profile to defaults and disables save writes before scenarios start; lab purchases and runs never overwrite `user://profile.json`.

| Scenario | Shows | Checks |
| --- | --- | --- |
| `combat` | Scout hands firing into a mixed robot pack | damage dealt, kills |
| `weapons` | each main gun firing from the focused hand | visual review |
| `recoil` | 6-frame strips after one rail shot and during minigun fire | camera kicks and recovers, sustained kick stays capped, player aim unchanged |
| `guns` | side and three-quarter views of all six Blender models | visual review |
| `gunplay` | focused fire, empty magazines, swaps, reloads and contextual drilling | offhands do not fire, draw lock, reloads, cross-charge, upgrades preserve ammo/charge, drill precedence |
| `secondary` | all six alternate modes and mineral shots | real damage and charge cost, cancellation, exposure damage/expiry, pursuit stopped by stagger, shorter boss stagger, overspin cadence, napalm burn/slow, mineral fracture |
| `boss` | robot and alien bosses: arrival, fight, low health, kill | boss tracked, frame and WARNING banner up, kill opens the shop |
| `levelup` | new, mixed and ranked picks incl. an overclock, entrance animation | every card has an icon, picking levels the upgrade and resumes play |
| `shop` | open, hand 3 selected, bought, maxed, empty wallet | 4 + 2 stock, layout fits, debits, sold marking, reroll, refusals charge nothing, Esc cannot skip |
| `hud` | play, armor/mods/cooldown gear, low health, death panel | armor and mod readouts, lethal damage ends the run |
| `mining` | approaching and drilling a live mineral section | aimed collider reachable, section damaged, focused meter charged |
| `menu` | main menu, every operator, each workshop tab | icons present and crisp |
| `icons` | one gallery page per icon group | icon groups exist |

```sh
make lab-shots                         # all scenarios -> lab_shots/*.png + lab_report.txt
make lab-shots SCENARIOS="shop boss"   # a subset
python3 tools/lab.py --list            # scenario names; --window renders visibly, --clean hides the overlay
make lab                               # interactive: pick a scenario, play on; F1 list, F12 screenshot
```

`tools/lab.py` renders in an invisible 1280 × 720 `gamescope --backend headless` session on the real GPU when gamescope is installed (otherwise in a window), prints each `PASS`/`FAIL` and engine error, and exits non-zero on a failed check, engine error, failed process, 240 s timeout or missing report. A scenario is a `LabScenario` subclass in `scripts/lab/scenarios/`, registered in `Lab.SCENARIOS`. Helpers include `start_game(class, stage)`, `spawn_pack`, `ahead`, `aim_at`, `aim_deposit` (finds an actual live section rather than a geode's hollow centre), `fire`, `wait`, `capture`, `capture_strip` and `check`. The 13-scenario gun rework run produced 84 captures with zero failures on the Radeon GPU.
