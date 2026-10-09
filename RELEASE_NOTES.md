# Unreleased source changes

- Removed `DOWN` from enemy finisher numbers; actual damage, critical labels and
  hit/kill feedback remain.
- Authored head/core weak volumes for all ten enemy types. Main-gun precision
  hits guarantee ×3 base damage; ordinary rolled crits now deal ×2. Crit-damage
  upgrades improve both, without multiplying the two critical bonuses together.
- Weak volumes follow yaw, scale and feet height, including exposed features
  above the old body bounds. World blockers limit precision hits. Pierced enemies
  resolve their own critical state; precision does not boost collateral splash.
- Spitter base health increased to 180, tank health to 420 and boss health to
  6000, retaining schedule scaling and unchanged grunt/runner health. Lucky
  Strike cards describe the new body and precision damage factors.
- `tools/check_combat.gd` passed real-shot regressions for body/head damage,
  random-crit non-stacking, piercing, splash, wall blocking, elevation, yaw and
  Lucky Strike, alongside nested-blast coverage.
- An isolated 1280×720 Mesa llvmpipe run rendered and hit the weak feature on all
  ten enemy types, inspected boss head/eye alignment, showed a noncritical
  finisher as its actual damage alone and rendered all three Lucky Strike cards.
  It exited with code 0.
- Historical **triple-volley** fresh-Scout checks measured stationary-boss
  body/weak-spot times of 9.62/3.22 s (Yard), 15.68/5.13 s (Foundry), and
  23.37/7.85 s (Reactor). They predate the focused-gun rotation below and are
  not current balance claims or full-campaign certification.
- Repeated combat regression runs reported 33–42 ObjectDB instances leaked at
  exit; rendered smoke runs reported up to 20, and the virtual display still
  warns about unsupported V-Sync. These changes are not claimed warning-free.
- Visual test lab (`make lab`, `make lab-shots`, `tools/lab.py`): 18 scenarios,
  including gun models, rotation, alternate fire, finite ammo, survival
  pickups, directional armor, mining defense and Yard boss patterns.
  Script/engine errors fail the runner. Lab content is excluded
  from the Linux export.
- Pixel-art icons (16 × 16) for every upgrade, gun, class, ability, Armory
  upgrade, mineral, workshop recipe, shop item and HUD glyph, generated from
  `tools/icons/art_*.py` (`make icons`).
- Gun feel: gentle, more strongly damped weapon and camera springs, no firing
  FOV punch, stable head-based ray aim, varied muzzle flashes, fading tracers,
  casings and a blooming crosshair. Point-blank impact flashes and enemy spit
  no longer fill the screen.
- Round shop rebuilt: hand loadout cards with stats and rank pips, 4 weapon-mod
  offers for the selected hand plus 2 suit-system offers, live effect previews
  and icon prices. Rerolls keep sold cards. Hand upgrades live in one catalog.
- HUD, boss and level-up pass: icon-based HUD, boss WARNING banner and
  segmented bar with damage trail and ENRAGED state, death stat panel, level-up
  cards with icons, rank pips and gold overclocks, and less overlap between
  damage numbers. Menus show class, ability, recipe, loadout and Armory icons.
- Focused firing replaces the triple volley. Finite magazines, automatic
  holstered reloads and a 0.2 s draw encourage rotation. In-hand reloads are
  1.6× slower; partial reload progress survives swaps and upgrades.
- Each class now starts with three different guns; crafted slot overrides remain.
  Hits charge the other two alternates; drilling charges the focused gun.
  HUD cards show magazine/reserve ammo, reload progress and alternate meters.
- Six RMB modes: Pulse Tag Burst (+35% exposure window), charged Rail Lance,
  Scatter Concussion (shorter boss stagger), Minigun Overspin, ballistic
  Autocannon Breach Grenade and persistent slowing Flamethrower Napalm.
  RMB near an aimed mineral section remains the drill, without an open-field
  drill shove. Rail Lance and Breach Grenade can fracture sections at range.
- Original Blender-built firearm assets replace runtime primitive gun geometry.
  Models have open bores, detailed receivers/rails/sights, magazines, pump,
  rotary barrels and gloved grips; static geometry is batched by material.
  Generation is reproducible with `tools/guns/build_guns.py`.
- Rendered recoil checks measured 0.16° for a Rail shot and approximately
  0.04–0.05° during sustained minigun fire, without aim drift. Controlled
  fresh-Scout primary-only rotation before the reserve/auto-swap pass killed
  a stationary Yard boss in 11.72 s body / 3.90 s weak-spot (zero random crits,
  60 Hz simulation, manual empty swaps). Historical baseline, not certification.
- Automatic empty-primary swapping picks the next loaded, non-reloading gun,
  preserving draw timing and manual selection. Idle, drilling and active
  alternates keep focus; an all-dry loadout never cycles or fires free rounds.
- Finite reserves: three spare magazines per gun at stage start, cap six.
  Holstered and in-hand reloads consume only rounds actually transferred.
  Ammo crates restore one magazine to each equipped gun's reserve; capped
  packs remain available. Regular kills drop ammo every 12 and magnets every 50;
  bosses drop both.
- XP magnets attract all currently loose gems without an instant XP grant or
  permanent global vacuum. Saturated gem pools merge value even while homing.
  Red-cross repair kits report actual healing and remain at full health.
- Timed ammo supply every 25 gameplay seconds, at most two separated waiting packs,
  independent of ordinary loot. Grounded route checks reject obstacles and
  cliffs; a nearer placement fallback serves small raised decks.
- Pickup radar glyphs, compact aggregated ammo/magnet/repair/supply notices,
  separate automatic-swap feedback and low/dry/reserve weapon readouts.
  New ammo and magnet pixel icons use the existing reproducible generator.
- Pickup-loop verification: all 15 rendered lab scenarios produced 93 captures with zero
  failures on the Radeon GPU; precision and nested-blast regressions passed.
  Checks cover actual ammo collection and recovered firing, finite/partial
  reloads, swap boundaries, full-cap pickup preservation, exact XP conservation,
  homing-pool overflow, later loose gems, boss loot, paused/inactive supply
  timers and real raised-deck supply fallback.
- Optional Yard defense vein: real, persistent mineral sections and conserved
  fragments; three escalating response packs; one upgrade choice after both
  mining and defense finish. E claims once; boss clear escrows earned choices
  before the shop without consuming or fabricating XP levels.
- Rare Bulwark role: batched amber front plate, teal rear precision core, slow
  capped turning and directional direct-hit reduction. Flanks, splash, burn
  ticks and area hazards remain counters. Auto guns, piercing beams and blades
  use their actual sources; mixed direct/splash remains one damage transaction.
- Yard Dreadnought alternates a locked ram lane and three staggered, cover-clipped
  mortar footprints. Both have harmless warnings and a teal +50% recovery
  window; stagger interrupts windups/rushes. Terrain, height and actual warned
  footprints constrain hits. Pausing, death, node removal and stage clear
  release controller state and prevent late attacks.
- Authored mining formations reserve placement space outside random respawn
  budgets; bounded response reservations and lifetime generations keep full
  crowds and recycled enemy slots from corrupting encounter completion.
- Game-root pause semantics are explicit even under the lab's always-processing
  shell. Encounter HUD, radar discovery and the earned-choice picker use the
  existing presentation conventions.
- Encounter verification: all 18 rendered lab scenarios produced 114 captures
  with zero failures and no script/engine errors on the Radeon GPU. Precision
  and nested-blast regressions passed (the existing ObjectDB exit warning remains).
  An accelerated live-director smoke from 90–122 Yard seconds observed 492
  hostiles including a scheduled Bulwark, with the defense vein still optional.
  This is encounter/integration evidence, not full-campaign balance certification.

The published 0.3.0 export and archive below have not been rebuilt for these
source changes.

# Kakaboomboom 0.3.0

Three-hand gunplay, a between-round mineral exchange and persistent base crafting;
Godot 4.7.2 Linux x86_64 release.

## Changes

- Three visible gloved weapon hands fire together, with independent cooldowns and
  minigun spin-up. Number keys and the wheel focus a hand without resetting fire.
- Original hard-surface firearm models add receivers, magazines, sights, barrels,
  grips and gloves. Geometry and materials are cached by weapon kind.
- Actual-damage numbers distinguish critical hits and finishers, merge nearby
  same-type damage briefly and use a fixed label pool.
- Small camera recoil recovers without aim drift; target flashes, impact sparks,
  hit sounds and weapon kick reinforce contact without global hit-stop.
- Kinetic, fire, frost and shock damage: burning damage over time, movement slows
  and bounded lightning chains. Critical overkill reports only health removed.
- Each hand upgrades its own projectiles, splash, damage type, damage, cadence
  and pierce without mutating authored definitions or sibling weapons.
- Boss kills bank Gold, Cinder Crystals and Void Shards, then pause in a randomized
  mineral shop. Purchases affect the selected hand or whole run; paid rerolls
  replace stock and increase in price. Selected hands carry into the next round.
- The final shop returns to the base. The Base Workshop crafts permanent armor,
  weapon blueprints, per-hand gadgets, perks and ranked talents. Its Armory tab
  retains the existing permanent stat upgrades.
- Crafting ranks and equipment survive restart. Existing profiles retain their
  currencies, unlocks, Armory ranks, records and settings. Multi-mineral payments
  validate the entire transaction before debiting; refused purchases charge nothing.
- Nested blasts preserve their original target sets, including synchronous Chain
  Reaction callbacks beyond the pooled nesting depth.

The procedural mining overhaul from 0.2.0 remains intact. Previous versioned
release artifacts are not overwritten.

## Linux installation

Extract `kakaboomboom-0.3.0-linux-x86_64.tar.gz`, open the extracted folder and run
`./kakaboomboom.x86_64`. Keep the included credits and engine license notices with
redistributed copies. Requires Linux x86_64 and an OpenGL 3.3-capable graphics
driver; the game uses Godot's GL Compatibility renderer. No Godot installation
is required to play.

The main menu displays the game version. `VERSION` and `build-info.json` identify
the package; `sha256sum -c SHA256SUMS` verifies its files. The adjacent
`.tar.gz.sha256` verifies the archive before extraction.

Profiles remain outside the installation, under Godot's `user://` directory
(usually `~/.local/share/godot/app_userdata/Kakaboomboom/`). Updating or removing
the game folder does not remove the profile. Controls and research references
are documented in `README.md`.

## Verification and limits

Source-project smoke scenarios passed for legacy-profile preservation, atomic
payments, all five crafting categories, equipment reload, independent hands,
real perk effects, seeded shop stock, sold-item protection, rerolls, Cinder
banking and stage continuation.

Combat smoke verified fire ticks, frost slowing, bounded shock chains, critical
overkill, dead-target guards, clean reused status slots, synchronous nested
blasts, real three-hand shots, multishot/splash upgrades and recoil recovery.
`tools/check_combat.gd` retains regression coverage for nested target corruption
and the deeper-than-pool fallback.

An isolated 1280×720 GL Compatibility run on Mesa llvmpipe exercised real base
craft/equip buttons in every category, held-LMB three-hand fire, visible critical
numbers/finishers, actual boss deaths opening the shop, purchase/reroll buttons,
selected-hand continuation and final return to the base. It exited with code 0.
These controlled scenarios do not constitute completion of the campaign.

All six firearm models were rendered and exercised against a real target;
the minigun reached full spin under held fire.

The Linux archive and every packaged file passed SHA-256 verification. The
extracted executable ran outside the source project: the 0.3.0 menu, persistent
base equipment, Scout deployment, held fire, pause, abandonment and Quit were
exercised; normal UI shutdown exited with code 0. Scripted assertions ran against
the source project, not the release template's unsupported `--script` mode.

Headless scenarios still report `ObjectDB instances were leaked at exit`
(20–31 instances across source checks, 26 in the packaged UI smoke). The virtual display reports
unsupported V-Sync mode. The game is not claimed warning-free; sustained 60 fps,
Radeon hardware performance, economic balance and other distributions have not
been certified.
