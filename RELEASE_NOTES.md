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
