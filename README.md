# Kakaboomboom

A first-person horde shooter in the style of Deep Rock Galactic: Survivor. Pick an operator, mine and fight through three procedurally generated sectors, complete their contracts and spend banked currency between levels and runs. Built with Godot's GL Compatibility renderer and CC0 art credited in [CREDITS.md](CREDITS.md); the music is synthesized at runtime. Open `project.godot` and press **F5**, or run `godot --path .`. Current source verified with Godot 4.7.2.

## Current Prague reskin

The source game is being reskinned as **LUĎAS: LAST TIME KRATOS**, with the
story and selected septik-loop ending B recorded in [the design bible](docs/ludas/BIBLE.md).
The implemented asset changes are:

- All eleven enemy slots use the new hallucination models: Bezdomovec, Feťák,
  Alkoholik, Vekslák, Vyhazovač and Pan Herna in the first two sectors; Bílá myška,
  Šváb z herny, Lahev rumu, Jednoruký bandita and Pan Jackpot in the third.
  `robot_*` and `alien_*` are retained internal slot IDs, not the visible creatures.
- The first weapon, **Lahve od piva** (`pulse`), is a dirty fingerless-gloved hand
  holding a brown beer bottle, with pooled tumbling flying bottles and glass/foam
  impacts. It has no muzzle flash or brass casings; damage and cadence are unchanged.
  Rebuild only this mesh with
  `blender -b --python tools/guns/build_guns.py -- --weapon pulse`.
- The generated **Žižkov** sector has weathered plaster/brick tenements,
  pavlače, cobbled/asphalt ground, HERNA NONSTOP and PIVO signs, sodium lamps,
  overflowing bins and a distant three-column TV tower. This is visual dressing:
  carving, collisions, mining sites and gameplay RNG order are unchanged.
- Stage labels are **Žižkov → Palmovka → Hlavák**. Currency labels are
  **Drobné / Cigára / Kešulky**, with matching coin, cigarette-pack and token icons.
  Skills use the bible's names; combo callouts are **POWNED / PERMABAN /
  LAST TIME KRATOS**. Their mechanics and internal identifiers are unchanged.
- Four more recorded phrases, cut from longer voice messages, vary combo,
  extraction and clear reactions alongside the existing barks.
- Mining is now close-range crowbar salvage from gambling/cigarette/jackpot
  machines, with physical breakable compartments and currency-shaped loot.
- All XP/permanent/workshop/shop upgrade names, descriptions, mastery previews
  and purchase/status labels use Czech scene fiction with unchanged effects.
- Intro, main menu, character selection, workshop, records/settings, pause,
  upgrades, shop, HUD, tutorial, world prompts and death/banked-loot screens now
  share Czech copy and a dark street-poster palette: worn ink, chipped frames,
  dirty amber, tobacco and rust rather than cyan neon. Wear is cached on resize,
  drawn behind content, and excluded from input and container layout.
- The party is **Luďas / Vítek ultras / Mikoláš hajzldítě / Aleš legendary skillz**.
  The remaining primary labels follow the bible: **Excalibur / Vinyly /
  Holubí letka / Absintové molotov / Rum + zapalovač**.

The other five primary weapon models and later-sector environments retain their
existing designs. Renamed labels do not imply those meshes have been replaced.
The narrative ending is specified in the bible, not a newly implemented cutscene.
Authored combat lab arenas deliberately retain their original sci-fi dressing;
the `levels`, `quests` and `onboarding` scenarios exercise generated campaign worlds.


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
- **Aim at a visible machine compartment within 2.6 m** to automatically raise the crowbar, then **hold F** to pry. Target the brass **+ lock** for faster progress. Look away to return to your gun. Guns and abilities cannot extract machine loot.
- **1 / 2 / 3 / 4 / 5** activate your class abilities. WASD is unchanged; W remains movement, not an ability binding. With **Guided start** (default) only key 1 works at first; the rest unlock as you level (see below).
- **E** interacts with consoles, flame vents or a secured guarded-machine beacon in the standalone authored lab arenas.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Finish every level objective:** a drop pod lands in the farthest room, with a green beam over the walls and a radar marker. Reach it and hold its ring for 10 s while the horde surges (progress is kept if you step out to fight). Lift-off banks currency and opens the shop. Swap the primary freely, upgrade any of your five abilities, buy primary mods or protection, then continue. After death: **R** retries with the same class and a new layout; **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Base Workshop**, **Records**, **Settings**) → class select with the full five-ability kit → run. Each level is carved from solid rock by a new seed: irregular rooms joined by winding corridors, never one open box. Rooms come as L, T, cross, chamfered, round, ring (a walk-around central pillar of rock) and pillared colonnade shapes. Corridors are dog-legged, 4 m chokepoints, 6 m passages or 8 m boulevards; extra loops mean every area has a second way out and the horde can flank. Short dead-end alcoves make defensive pockets, or traps. Painted floor lines trace every corridor: accent for normal passages, secondary colour for chokepoints. The radar draws the walls around you.

Each theme plans differently:

- **Žižkov** (`yard`): a tenement compound of mixed-shape rooms on a spanning tree plus loops.
- **Palmovka** (`foundry`): three long stacked halls, one a colonnade, joined by short transfer passages and side chambers. The underlying later-sector environment remains the existing Foundry.
- **Hlavák** (`reactor`): a round hub, narrow spokes and diagonal chords linking the outer rooms. The underlying environment remains the existing Reactor.

**Overlooks** sit in large rooms: raised decks reached by a treaded ramp, giving firing height while the horde funnels up a choke point for Ban zóna and Valhalla. **Salvage islands** supply extra solid faces for machine banks in open rooms. Žižkov has 1 overlook / 2 islands, Palmovka and Hlavák 2 / 3. Collision layouts, floor themes and enemy schedules remain unchanged. Most groups arrive behind you.

**No level countdown or deadline.** The contract requests machine salvage and non-boss hallucination kills. Objective counts and species vary with the seed and sector; early guided contracts are smaller (see below). Pry close machine compartments with F and defeat the listed enemies. Unrelated kills, carried/banked currency, collected loose loot and resource bonuses do not advance salvage objectives. Progress remains earned when you stop to fight.

Every generated contract starts with enough supported, reachable machine stock, with spare yield where possible. Contract machines fill salvage-island faces first, then broad room and corridor walls with standing room in front. Requested enemy species spawn after the arrival calm and remain available indefinitely. Crowd pressure ramps to a capped final rate, not a timer-triggered boss.

**Extraction:** finishing **all** objectives calls a drop pod to the clear room spot farthest from you. It descends for 3 s, then hovers in a beam; standing inside its 4.5 m ring for 10 s lifts off, banks minerals and opens the round shop. Progress accrues only inside the ring and while unpaused, and is kept if you step out. The director spawns at double rate until lift-off, and dying during extraction still ends the run at 50% banking. Earned upgrade choices can be answered mid-extraction; killing a boss cannot bypass unfinished objectives.

| Stage | Crowd cap | Objective scale | Contract | Arrival calm |
| --- | --- | --- | --- | --- |
| Žižkov (88 × 88 m, ~43% walkable) | 1000 | 1.0× | 1 salvage + 1 kill | 12 s |
| Palmovka (120 × 72 m, ~62% walkable) | 1500 | 1.35× | 2 salvage + 1 kill | none |
| Hlavák (104 × 104 m, ~43% walkable) | 2100 | 1.7× | 2 salvage + 2 kill | none |

Continue carries the primary build, all five ability ranks, level-up upgrades, perks and auto weapons into a newly generated next sector, resets its quest counters and refills health. Finishing Hlavák records victory; its final shop returns to the base. Run duration remains a record statistic, not a progression gate. Contact damage remains capped at 4 damage per 0.5 s; ordinary wave density and individual enemy health are preserved.

**Standalone tactical fixtures:** `encounter`, `boss` and `boss_patterns` retain an authored guarded machine, interactive hazards, raised decks and ramp combat. These fixed placements are not inserted into generated campaign layouts. Vyhazovač still uses directional front armor and a rear precision target; explicit boss fixtures retain ram/mortar attacks and staggerable recovery windows.

## Classes

| Class | Unlock | Starting primary | Abilities 1 / 2 / 3 | Profile |
| --- | --- | --- | --- | --- |
| Luďas (`scout`) | free | Lahve od piva | Kolobežka Duplex / Šlehat blesky / Vytrhnu hajzl z podlahy | +12% speed, +1 m pickup |
| Vítek ultras (`gunner`) | 6 Kešulky | Holubí letka | Jsem god / Blesky ze stropu / Heroic Ragnarok | +30 health, +1 armor, −5% speed |
| Mikoláš hajzldítě (`driller`) | 10 Kešulky | Rum + zapalovač | Odpočet do autodestrukce / Ilegal street racer / Brikulóza | +150% prying, +5% damage |
| Aleš legendary skillz (`engineer`) | 14 Kešulky | Lahve od piva | Unlimited god mode on / 4 setupy / Sony s rejzí | Starts with Vyhazovač na baterky, −10% auto cooldown |

Every class includes **4: Ban zóna** and **5: Valhalla**. Ban zóna gathers, slows, interrupts and damages nearby enemies for five seconds. Valhalla gives 1.6 seconds of protection and an immediate damaging knockback pulse: a brief window to pry, reposition or escape. Heroic Ragnarok boosts main-gun fire rate and pierce; it has no ammo interaction.

All five skills have separate cooldowns and three run-upgrade ranks through level-up cards and the shop. Rank previews now describe the actual skill-specific effects: damage or fire-rate bonus, −12% base cooldown and +15% duration/protection where applicable. Movement skills do not claim longer travel, and instantaneous blasts do not claim longer duration. The HUD shows each key, readiness, remaining cooldown and rank. Pause freezes cooldowns and persistent effects; inactive/dead players release fields and buffs. Overlapping shields and cooldown/exposure effects retain independent ownership.

**Guided start** (Settings, on by default) introduces the game in steps instead of all at once:

- **Skills by level:** a run starts with skill 1 only. Skills 2, 3, 4 (Ban zóna) and 5 (Valhalla) unlock at levels 2, 3, 5 and 7, with an unlocked-skill callout and a tip. The HUD shows a dim teaser of the next skill with its unlock level; locked skills cannot be cast and do not appear as level-up cards. Shop cards show their unlock level.
- **Upgrade types by level:** early level-ups offer auto weapons, stats and unlocked skill masteries; perks join at level 3 and gun mods at level 5.
- **One-time tips:** cards above the skill bar explain moving/shooting, contracts, skills, prying machines, low health, extraction and combos. A tip counts as seen after 2 s on screen (an interrupted tip comes back) and is remembered in the profile; Settings → *Show tips again* resets them.
- **Footer:** the controls line lists only what you have unlocked.

Turning Guided start off gives experienced players all five skills and every upgrade type from the first second, with no tips. The smaller early contracts and the Yard's 12 s arrival calm are stage design and apply either way.

**Skill combos** (every class carries Ban zóna and Valhalla). A named callout appears below the crosshair:

- **POWNED** (`crush`): any skill blast reaching your active Ban zóna deals +60%, including thrown charges, barrages, movement landings, turret drops and defensive pulses.
- **PERMABAN** (`collapse`): casting Valhalla within 6 m of the zone's edge detonates it for 70 base damage, +10% per held enemy (up to +150%), and flings the pack outward.
- **LAST TIME KRATOS** (`ram`): dash or grapple while another skill protects you to slam a 5.5 m, 45-damage shockwave at landing. It can POWNED too.

**One primary, one trigger:** no main-weapon melee, magazines, reserves, reloads, ammunition pickups, charged secondaries or cross-charge meters. The first model is a thrown-beer-bottle weapon; the other five primary models remain unchanged. Choose a starting blueprint in the Workshop, change weapons with the wheel or free shop selector, and keep purchased primary-mod ranks without compounding them. The crowbar is a close-range salvage tool, not a combat weapon. Passive auto weapons remain separate level-up picks.

| Weapon | Main cadence | Role |
| --- | --- | --- |
| Lahve od piva (`pulse`) | 0.09 s | Rapid thrown bottles, pierces 1 |
| Rail | 0.45 s | Heavy piercing rifle |
| Scatter | 0.38 s | Seven-pellet shotgun |
| Minigun | 0.032 s after 0.2 s spin-up | Sustained high-rate fire |
| Autocannon | 0.19 s | Explosive shells |
| Flamethrower | 0.045 s | Short-range piercing flame cone |

**Survival loot:** every third regular kill earns that victim's XP gem; skipped XP is not silently merged into a later gem. Magnets drop every 120 regular kills, and repair kits have a 0.4% chance. Bosses retain their authored XP and award a magnet; the stage-clear reward is one Void Shard. Magnets attract all currently loose XP, including moving gems, and award XP only on arrival. Later gems stay loose. Repair kits heal up to 15 HP and remain at full health. There are no ammunition drops.

**Timed repair supply:** a nearby repair pack lands every 50 gameplay seconds, with at most two separated waiting packs independent of enemy loot. Placement checks obstacles, ground and walkable routes; small raised decks use a nearer fallback rather than dropping beyond a cliff. Timers stop during pause and after the player becomes inactive. The radar marks magnets and both ordinary and timed repairs. Continue refills health.

**Damage and feedback:** kinetic deals direct damage; fire ignites for four burn ticks over two seconds; frost slows movement to 55% for 1.8 seconds; shock chains 40% damage to up to three nearby enemies. Critical and kill numbers report actual health removed, not overkill. Same-type hits within 0.9 m and 0.2 s merge into one number (a crit or kill upgrades it), and new numbers stack above ones they would overlap; crits carry a crit icon.

**Gun feel:** stronger damping and shorter weapon travel keep recoil gentle. Camera pitch/yaw/roll recovers on a bounded spring, with no firing FOV punch; main-gun rays use the head's stable aim, not the visually recoiling camera. Models slide into the raised pose on swaps, and Scatter cycles its pump after shots. Muzzle flashes vary, tracers fade and pooled casings eject from authored ports. The crosshair blooms without changing aim. Fractional cooldown overshoot preserves boosted cadence above 60 shots/s; idle time and long hitches cannot bank an unbounded burst.

**Precision hits (source changes, not yet packaged):** main-gun rays through a visible head or exposed weak point earn a guaranteed ×3 critical hit without a luck perk. Ordinary rolled body crits deal ×2. Precision uses the current crit-damage factor plus one base-damage unit; it never multiplies a random crit again. **Štěstí z automatu** improves both rolled crits and aimed hits. Each pierced victim is judged separately; headshots do not amplify splash, burns or chained damage. Weak volumes follow enemy yaw, scale and feet height and cannot be hit through a world blocker. Kill numbers retain actual damage; critical numbers show an icon.

Spitters have 180 base health, tanks 420 and bosses 6000; schedule multipliers still apply. These values are not a full-campaign balance certification.

**Gunplay research:** Derek Mattson's [GDC 2024 *A Second Shot*](https://media.gdcvault.com/gdc2024/Slides/GDC+slide+presentations/Mattson_Derek_ASecondShot_Notes.pdf) emphasizes reliable target reactions and coherent presentation. Contact feedback precedes restrained camera effects; recoil never drifts aim, and the horde simulation has no global hit-stop. Six original Blender-authored models use metre-scale receivers, open barrel bores, rails, sights, magazines, metal/polymer/rubber materials and gloved grips. Static parts are batched by material; magazines, the shotgun pump and the rotary barrel assembly remain movable.

**Hit chains:** each main-gun shot that directly hits an enemy adds one beat, no matter how many pellets hit. After three consecutive hits, each further shot gains +8% damage per beat, capped at +40%. A miss, taking damage, or 2.5 seconds without another hit breaks the chain; explosions alone do not extend it. The crosshair shows the next shot's bonus and a countdown. Hit-confirmation sounds climb in pitch; hits and kills have brighter impact sparks and stronger recoil.

**Auto weapons** (up to four, each to level 5): Lítající pager, Zvukovka na doraz, Ohňostroj z pavlače, Zkrat v mixáku, Cirkulárka z bazaru, Vyhazovač na baterky, Ledovej Fernet and Rachejtle z tržnice. Their existing weapon geometry and behavior remain; all names, rank descriptions and one-time max-level upgrades use Czech scene fiction.

**Perks** (each to level 3, no auto-weapon slot): Domino v herně (exploding kills), Panák za účet (heal on kills), Panika před zavíračkou (fire rate when hurt), Lokty na baru (retaliation), Štěstí z automatu (critical hits), Plná rychlost (moving damage), Šacování kapes (bonus Cigára), Ještě jedno kolo (survive lethal damage).

**Primary mods:** Rychlej crossfader gives the first shot within 1.5 s of a wheel swap +75% damage, spent even on a miss; Přes celou pavlač gives direct hits beyond 15 m +40%; Poslední účet gives direct hits on enemies already below 35% health +60%. They can be combined and use no auto-weapon slots.

**Stat and permanent upgrades:** all 41 XP upgrade resources and eight permanent talents have Czech names, accurate effect/rank text and unchanged values. Shop/workshop categories, previews, prices, locked/sold/capped states and mastery cards use the same fiction. Modifiers improve damage, cadence, pierce, speed, health, regeneration, protection, pickup radius, area, cooldown, XP, extra auto-projectiles, prying and loot; internal IDs remain stable for saves.

## Machine salvage and progression

Wall-mounted banks of worn gambling, cigarette and jackpot machines replace
crystal formations. Each seeded bank has **7–9 independently breakable front
compartments**, real matching triangle colliders, permanent trays/backing and a
labelled frame. Reels and coin slots identify gambling machines; rows of packs
identify cigarette machines; jackpot panels show **777**.

**Pry, open, retarget.** Aim close at a live compartment and hold F. The
fingerless-gloved hand raises an original hooked steel crowbar, inserts it and
levers backward repeatedly. Damage persists when you stop to fight. Doors pull
outward with their colliders before breaking, then release their allocated loot
and lose their harvestable collider. Empty housing remains visible and cannot
yield again. Guns and abilities do not salvage; a wall or out-of-range aim
prevents tool contact.

The conserved pre-rolled bank budget remains **14–20 Drobné**, **5–8 Cigára**
or **one rare Kešulky**. Rare banks may have zero-yield outer compartments.
Contract stock is guaranteed on clear supported faces; ordinary stock retains
the 11–18 live-bank cap and 35–50 s respawn intervals. Empty housings reserve
their footprints for the remainder of the level. Contract progress counts
actual emitted compartment units, never collection, carried currency or banking.
The authored guarded-machine encounter remains separate from campaign contracts.

**Locks and leverage.** The brass **+** cue marks a real lock for **×1.75**
prying damage. Working the same latch builds up to **+35% rate over 0.65 s**.
Releasing, losing contact, changing compartment or pausing resets leverage,
not the door's health. Czech feedback shows currency type, local opening
progress, compartments remaining and current bonus. Metal chips, sparks,
clanks and crowbar motion replace drill hum and crystal effects.

Coin, paper cigarette-pack and token pickups use the existing pooled collection
and banking path. The fractal crystal shader, rotating history-texture halo,
spinning-drill exports and their obsolete assets are removed, not retained as
an alternative mining mode.


- **Drobné** (`gold`): banked; buys round-shop stock, base crafting and permanent Armory upgrades.
- **Kešulky** (`shard`): banked, rare; each completed level awards one; unlocks classes and pays for advanced shop/base recipes and ability upgrades.
- **Cigára** (`crystal`): banked, fills the supply meter for free upgrade picks and powers turret consoles (10 run Cigára each).

All three currencies move into your profile at 100% on stage clear (loose loot is swept up), and at 50% on death or abandonment. Cigára spent on consoles is removed before banking.

**Round shop:** extraction pauses gameplay and opens the exchange. The primary panel shows current stats, a free weapon selector and a comparison with purchased mods reapplied. Five skill cards show their ranks, accurate effect previews and currency prices; guided progression locks unavailable skills. Random stock has four primary mods and two protection/health/power offers in scrollable tabs. Rerolls replace only unsold stock and cost 3 Drobné + 1 Cigára more after each refresh. Sold, capped or unaffordable purchases do not debit currency. Primary and skill ranks carry into the next sector; run-only upgrades expire at run end. `RoundShop.CATALOG` owns prices, caps and previews.

**Persistent base:** craft protection, starting-primary blueprints and one gadget, plus automatically applied perks and ranked talents. Equip one protection set, one starting primary and one gadget; resetting the primary restores the class default. Eight five-level permanent talents are Trénink u výčepu, Škola disrespectu, Útěk před účtem, Velká igelitka, Páka z bazaru, Veksláckej čuch, DJ legenda and Kožená bunda. Records track time, kills, level, runs, victories and deepest sector in `user://profile.json`. Stable IDs preserve currencies, unlocks, crafting, upgrades, records and settings; older gear migrates to a single primary/gadget without restoring deleted melee blueprints.

## Music

The adaptive soundtrack is rendered procedurally on background threads at startup into sample-synced loop stems (D minor, 126 BPM). Layers fade in with the crowd density around you (pad → drums → bass drive and arp → lead and tension); the boss swaps in a darker harmony layer. Stingers mark level-ups, stage clears, death and victory. Music, SFX and master volumes are adjustable in Settings.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, class unlocks, Armory levels, crafting ranks, equipped armor/primary/gadget, records and settings. Multi-mineral payments validate the entire cost before debiting. `Music` (`scripts/audio/music_director.gd`, with `music_score.gd` and `music_synth.gd`) plays tracks and stingers and follows intensity. Buses are defined in `default_bus_layout.tres`.
- **Stats and economy:** `RunState` combines class/Armory/crafted modifiers and level-up stacks, owns one `WeaponBuild` (`scripts/progression/weapon_build.gd`), and stores five ability ranks. Swaps rebuild from an immutable authored snapshot, retaining purchased ranks and the latest element conversion without compounding. `RoundShop` purchases stock and individual skills; `CraftingCatalog` supplies persistent `CraftRecipe` definitions.
- **Classes and abilities:** `data/classes/*.tres` and `roster.tres` define stats, class unlock cost, `primary_weapon` and five `ability_scenes`. `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`) owns slot-specific cooldowns and shared rank scaling. Buffs, exposure zones and protection are source-owned, so one ending skill cannot remove another's effect.
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage type, damage, cadence, pellets, spread, pierce, recoil, knockback, explosion, spin-up and icon) reference `WeaponView` scenes in `scenes/weapons/`, instancing the original `assets/guns/*.glb` meshes. Rebuild with `blender -b --python tools/guns/build_guns.py`, then import with the project Godot executable. No image-generation access is required. `ArenaPlayer` owns one trigger, draw lock, combo, gun mods and camera spring; hit/tracer/casing visuals remain pooled.
- **Auto weapons, perks and gun mods:** `AutoWeapon` subclasses in `scripts/weapons/auto/` and `PerkEffect` subclasses in `scripts/perks/` use `UpgradeDefinition`s (STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD) in `data/upgrades/pool.tres`. ABILITY offers are generated for the actual five class slots. `AutoWeaponRack` owns passive auto weapons and perks; perks, primary mods and ability ranks do not consume its four slots.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented simulation with one MultiMesh per enemy type, a shared flow field, weapon queries, `slow()`, material FX and contact tuning. The flow field avoids obstacles and treats cliffs as walls; it routes to the player's level over ramps. Each enemy has a feet height taken from the stage heightfield: it snaps up ramps, falls off ledges and never climbs a step over 0.3 m. Hit tests, blasts, projectiles and contact damage all use that height. Hallucination stats/animations are in `data/enemies/*.tres`, retaining `robot_*`/`alien_*` as internal slot IDs. Six CC0 humans and five original delirium rigs bake into `assets/monsters/`; `shaders/horde_enemy_vat.gdshader` animates the crowd from position/normal textures and per-instance clip state. `tools/vat/README.md` covers source generation, baking and licenses. `Faction.MACHINE`/`FLESH` select sparks or splatter independently of slot IDs.

  Enemy `weak_spot_offset` and `weak_spot_radius` author a head/core sphere in model-space metres before `model_scale` and yaw; radius zero disables precision hits. Type-level offsets, squared radii and upper hit bounds are cached once, not allocated per shot.
- **Salvage:** `ResourceDefinition` data lives in `data/resources/`; internal deposit types remain in `data/resources/deposits/`. `DepositGeometry` builds machine doors and exact triangle colliders; `MineralDeposit` owns health, opening transforms, permanent housing and conserved integer loot. `DepositField` retains seeded site/stock placement. `MiningTool` owns crowbar contact/leverage; `MiningFeedback` draws mechanical latch markers and Czech telemetry. `ResourcePickupSet` pools coin/token meshes and paper packs using `shaders/cigarette_pack.gdshader`. Mining-named APIs/input IDs remain intentional internals; the obsolete crystal/history shaders are removed.
- **Survival pickups:** `scripts/progression/pickup_field.gd` pools XP, magnets, repairs and a separate two-pack timed repair supply set. `PickupGeometry` builds their faceted silhouettes once at setup. Kill thresholds and supply interval are exports; grounded placement uses the horde heightfield, and supply routes reject obstacles and cliffs. Collection never overwrites the persistent profile. The radar reads the same live pickup pools.
- **Procedural levels:** `data/stages/*.tres` configure play area, `layout_theme`, `cover_count`, `overlook_count`, `outcrop_count`, `quest_scale` and `SpawnSchedule`. `ProceduralWorld` (`scripts/world/procedural_world.gd`, `scenes/levels/procedural.tscn`) is configured with the stage and seed before entering the tree. It carves a 2 m grid identical to the horde grid: the theme plan places rooms, corridors join them (spanning tree plus loops, or the Reactor's spokes and chords), and alcoves are added. Ring cores are refilled and cells unreachable from spawn are pruned. Remaining rock merges greedily into exact axis-aligned blocks under `Obstacles`; broad block faces with two open cells in front become contract `mining_sites`. Overlook decks and tilted ramp boxes live under `Elevation`, which the horde rasterises into its walkable heightfield. Set pieces, pillars and cover check carved floor plus margins, so passages and ore standing room stay open. `layout_open` is public for the radar. Original authored worlds remain explicit lab fixtures with their own play areas.
- **Level contracts:** `LevelQuests` (`scripts/level_quests.gd`) selects seeded resource/ordinary-species targets, clamps progress and emits completion once. `DepositField` records conserved raw section fractures; `ArenaGame` records exact horde victim definitions. Inventory/banking signals never count. `HordeDirector` sustains every ordinary wave; `SpawnSchedule.ramp_duration` bounds pressure ramping, not level length, and `surge` multiplies spawning during extraction. Boss release is explicit. Completion defers beyond the current impact, rejects stale source ids and respects death and earned upgrade choices, then spawns an `ExtractionPod` (`scripts/extraction_pod.gd`, collision-free) at `ProceduralWorld.extraction_point()`; only its stale-checked `departed` signal clears the stage.
- **Skill combos:** `ActiveAbility.blast()` wraps every skill's area damage and applies POWNED (`crush`) against `ArenaPlayer.active_gravity_well()`; `arrive()` is called at movement-skill landings for LAST TIME KRATOS (`ram`) via `is_shielded_by_other()`; Valhalla calls `GravityWell.collapse()` for PERMABAN (`collapse`). `ArenaPlayer.ability_combo` drives the HUD callout (rate-limited per combo), while `combo_counts` records every trigger.
- **Luďas's voice:** `LudasVoice` (`scripts/audio/ludas_voice.gd`, owned by `ArenaGame` so it survives stage loads) plays recorded reactions from `assets/voice/ludas/`: arrival, kill bursts (12 kills within 1.5 s), combos, a skill unlock (*Jaj… krajíc… chleba* in sequence), dropping below 40% health, healing, extraction, stage clear and death. One line plays at a time; a higher-priority reaction interrupts a lower one, and each reaction has its own cooldown. The reskin plan lives in `docs/ludas/BIBLE.md`.
- **UI:** `scenes/ui/hud.tscn` has currency/supply counters, salvage/kill contracts, hostiles/kills, vitals, a primary readout, numbered skill tiles and a close-range F prying prompt. There is no level timer or ammo readout. Boss fixtures retain health/recovery readouts and radar markers. Numeric level-up choices consume input before resuming, so choosing a card cannot cast a combat ability.
- **Guided start:** `RunState.start_guided()` sets `unlocked_abilities` from `ABILITY_UNLOCK_LEVELS` and emits `ability_unlocked` as levels are gained; `can_upgrade_ability()` and `_is_eligible()` gate skills, perks and gun mods. `Tutor` (`scripts/ui/tutor.gd`) queues one-time tips stored in `Profile` (`seen_tips`, `guided_start` setting). `StageDefinition.mine_objectives`, `kill_objectives` and `spawn_grace` (`HordeDirector.grace`) size each sector's contract and arrival.
- **Pixel-art icons:** every upgrade, gun, class, ability, Armory upgrade, mineral, workshop recipe, shop item and HUD glyph has a 16 × 16 icon in `assets/icons/<group>/<id>.png`. They are authored as text grids in `tools/icons/art_*.py` on the shared palette in `tools/icons/pixel.py` (automatic dark outline). Data resources reference their icon through `icon` exports; code-only concepts use `GameIcons.lookup(group, id)` (`scripts/ui/game_icons.gd`), and `CraftRecipe.display_icon()` resolves a recipe's payload icon. Show them nearest-filtered at 2×, 3× or 4× (`GameIcons.rect`). After editing art, run `make icons` (renders, then imports); `python3 tools/icons/build.py --group <g> --preview /tmp/icons` also writes a labelled 6× preview sheet.
- **Run flow:** `ArenaGame` builds each stage under a fresh `Round`, carries the primary build and five skill ranks, and handles level-up, pause, shop and return to base. It banks all three currencies into `Profile`, records runs and drives music from crowd density.

Legacy performance evidence, **before the Prague model/environment swap**: the mixed-faction 1,600-enemy horde was measured in a Godot 4.4.1 headless CPU check (120 frames). On the elevated stages, simulation averaged 7.2 ms per frame on the Yard and 7.5 ms on the Reactor (about 20% of the horde on raised ground); draw preparation took about 2.6 ms. The same check before the heightfield measured 6.1–6.5 ms. These are not measurements of the new assets; **60 fps has not been certified on the Radeon GPU**.

Run the precision-damage and nested-blast regressions with the editor executable:

```sh
~/.local/opt/godot/4.7.2/godot --headless --path . --script tools/check_combat.gd
```

## Visual test lab

`scenes/lab/lab.tscn` runs isolated scenarios through the real game scenes and captures screenshots, like visual unit tests. `Profile.enter_sandbox()` resets the loaded profile to defaults and disables save writes before scenarios start; lab purchases and runs never overwrite `user://profile.json`.

| Scenario | Shows | Checks |
| --- | --- | --- |
| `combat` | thrown bottles into a mixed human hallucination pack | actual damage and kills |
| `weapons` | each of the six main guns firing | visual review |
| `recoil` | 6-frame strips after one rail shot and during minigun fire | camera kicks and recovers, sustained kick stays capped, player aim unchanged |
| `guns` | side/three-quarter views of all six Blender models and the flying beer bottle | visual review |
| `gunplay` | sustained unlimited fire, upgraded gun swaps and paused trigger | real damage beyond a burst, stable aim, mods preserved without compounding, release before resumed fire |
| `tempo` | real held-input firing for six guns and boosted Minigun | actual cadence above 60 shots/s, stable aim, gentle recoil and bounded hitch catch-up |
| `pressure` | real stage directors and accelerated crowds with scarce loot | arrival calm free of spawns, prompt groups after it, all-stage caps, ordinary/specialist admissions, sparse XP/magnet boundaries, repair RNG, overflow conservation and paused/inactive/freed-player supply timers |
| `levels` | first-person, overhead and deck views of all three carved themes | same-seed repeatability, different-seed variation, connected grid, reachable ramps and machine standing spots, overlook/island counts, supported contract stock and actual player/enemy ramp movement |
| `quests` | F prying, hallucination kills, earned choices and three extractions | exact emitted-unit/species progress, stock/reward exclusion, safe indefinite spawning, pause, completion orders, touchdown/ring progress, surge, shop only after lift-off and stale-level rejection |
| `pickups` | repair kits, distant XP vacuum and timed repair supplies | actual healing, full-health preservation, exact XP/overflow conservation, later loose gems, supply cap, pause/inactive timers and raised-deck fallback |
| `abilities` | every class's five physical number keys and actual effects | damage, movement, healing, source-owned buffs, overlapping shields, pause/death cleanup, rank-scaled damage/cooldown/protection |
| `combos` | POWNED, PERMABAN and LAST TIME KRATOS through physical keys | exact +60% crush versus a plain blast, real thrown charge into a well, out-of-reach control, collapse burst scaling with held enemies, dash-without-shield control and ram damage on arrival |
| `onboarding` | guided arrival, an unlocked-skill callout/tip and locked shop cards | one skill plus teaser, footer, locked key, two-objective first contract, 12 s calm with a real director, no early perks/gun mods/locked skills, level-gated unlocks and working key, combo tip at level 7, tips seen once, Guided start off shows everything |
| `voice` | Luďas's recorded reactions | arrival, kill-burst trigger and cooldown, skill-unlock sequence order and interruption, hurt growl with cooldown, heal gulp, death outranking everything |
| `boss` | Pan Herna and Pan Jackpot: arrival, fight, low health, kill | tracked boss, WARNING/health frame, death cannot bypass unfinished objectives |
| `boss_patterns` | ram lanes, mortar footprints/impacts and teal recovery | real damage and movement dodges, locked targets, cover/height/radius boundaries, +50% recovery, stagger interruption, pause and death/menu/node-removal cancellation |
| `armor` | front shield/rear core, rotated markers and independent auto guns | real armor/precision arc boundaries, actual source direction, tag ordering, mixed splash, burn potency, finite stun/turning, slot reuse and reserved admission |
| `encounter` | authored guarded machine, prying under pressure and earned reward | real compartments/response identities, completion orders, conserved loot, pause, E once and queued XP choice preservation |
| `levelup` | new, mixed, ranked and ability mastery cards | selection upgrades the run and resumes play; physical numeric selection cannot leak into a combat skill |
| `shop` | primary comparison/swap, five skill upgrades, sold/maxed/empty wallet | real UI purchases, preserved mod ranks, layout bounds, exact debits, rerolls, capped/unaffordable refusals and no Esc skip |
| `hud` | five skill cooldowns/ranks, primary mods, armor, low health and death | actual lethal damage ends the run |
| `mining` | automatic crowbar, held-F leverage strip, opened compartments and empty housing | firearm/reach rejection, conserved loot, wall occlusion, pause and return to gun |
| `menu` | intro, every party member and scrollable skill details, workshop tabs, records, settings and pause/abandon screens | saved gear, free primary switching and gadgets reapplied exactly once |
| `icons` | one gallery page per icon group | visual review |

```sh
make lab-shots                         # all scenarios -> lab_shots/*.png + lab_report.txt
make lab-shots SCENARIOS="shop boss"   # a subset
python3 tools/lab.py gunplay mining abilities shop  # single primary, close-range salvage and hero kit
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

The Prague asset/salvage/street-UI pass ran the full rendered lab:
**176 captures, zero check failures or script/engine errors**. Final tab-bar and
scroll-layout follow-ups cover real mouse purchases and complete party/skill
descriptions. Screenshots were visually reviewed for menu, HUD/death, shop,
mastery, tutorial, boss and extraction surfaces; this is not FPS certification.

The published 0.3.0 package has not been rebuilt for these source changes.
