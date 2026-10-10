# Unreleased source changes

- Reworked the core loop around one unlimited-ammo primary firearm and five
  independently cooled-down hero abilities. Removed player melee weapons,
  magazines/reserves/reloads, ammunition drops, charged RMB secondaries and
  three-hand charge/rotation state. The six existing firearm models remain.
- Mouse wheel or the free shop selector swaps the primary. Purchased mod ranks
  follow the new gun and rebuild from an immutable authored snapshot without
  compounding damage, cadence, pellets or element conversions.
- Aiming at visible ore within 2.6 m automatically equips the drill; held F is
  the only extraction input. Look away to return to the gun. Firearms and
  abilities cannot mine at range or through cover. Persistent section health,
  conserved yield, weak seams, resonance and mining feedback remain.
- Ability keys are **1–5**, preserving WASD movement. Every unlocked operator
  includes its entire kit: Scout Blink/Recon/Grapple, Gunner Bulwark/Barrage/
  Battle Frenzy, Driller Seismic/Drill Dash/Magma Trail, Engineer Overdrive/
  Platform Turret/Repair Drone; all include Gravity Well and Pulse Barrier.
  Old single-ability purchase/equipment controls have been removed.
- Gravity Well visibly pulls, slows, interrupts and damages a crowd. Pulse
  Barrier provides a short source-owned protective shield and a damaging
  knockback pulse. Battle Frenzy strengthens fire rate and pierce, not ammo.
- Each ability supports three run-upgrade ranks through the shop and level-up
  cards: +25% damage, -12% base cooldown and +15% duration per rank where
  applicable. Combat and previews share the same scaling. Pause freezes
  cooldowns and persistent effects; inactive/dead players release their effects.
  Overlapping protection, exposure and temporary cooldown buffs do not erase
  another source when one ends.
- HUD now shows one primary, five numbered readiness/cooldown/rank tiles and
  an F mining prompt, with a raised drill pose clear of the expanded HUD.
  Numeric card selection is consumed before resuming so it cannot cast a skill.
  Mastery descriptions use compact body text instead of overflowing cards.
- Round exchange has a primary comparison/swap panel, five individually priced
  skill upgrade cards, and scrollable Primary Mods / Suit Systems tabs.
  Sold, capped, duplicate and unaffordable purchases never debit minerals.
  Rerolls retain sold stock; the primary build and five skill ranks carry forward.
- Workshop uses one saved starting primary and one gadget. Legacy saves migrate
  the first valid crafted firearm/gadget, skip removed melee blueprints and keep
  currency, class unlocks, crafting, Armory/talent ranks, records and settings.
  Saved single-ability selections no longer hide the complete hero kit.
- Survival loot retains XP on every third ordinary kill, magnets every 120,
  .4% repair drops and actual arrival-based XP collection with overflow
  conservation. Bosses award a magnet instead of ammunition. Timed supplies are
  grounded repair packs every 50 gameplay seconds, in a separate two-pack pool.
  Full-health packs remain; paused/inactive players cannot advance supply timers.
- Gun cadence remains Pulse .09 s, Rail .45 s, Scatter .38 s, Minigun .032 s
  after .2 s spin-up, Autocannon .19 s and Flamethrower .045 s. Fractional
  cooldown overshoot preserves boosted rates above 60 shots/s with bounded
  hitch catch-up. Stable head-based aim, gentle recoil, pooled contact feedback,
  casings, tracers and the six original Blender firearm models are preserved.
- Campaign sectors retain seeded industrial layouts, connected cross-lanes and
  a clear mining perimeter. No countdown: two conserved-resource mining
  objectives and two exact ordinary-species kill objectives gate extraction.
  Initial ore budgets and sustained required-species spawning avoid random
  respawn gates; completion is one-shot and preserves earned upgrade choices.
- Precision head/core hits retain guaranteed ×3 base damage versus ×2 ordinary
  rolled crits, without stacking the critical bonuses. World blockers, yaw,
  scale, feet height and individual pierced victims determine valid precision.
  Spitters have 180 base health, tanks 420 and bosses 6000 before schedule scaling.
  Damage numbers report actual health removed and do not show `DOWN`/`CRIT` text.
- Authored Lab fixtures retain defense-vein response packs, interaction hazards,
  directional Bulwark armor/rear cores, and warned ram/mortar boss patterns.
  These fixed placements are not inserted into procedural campaign worlds.
  Passive auto weapons, perks, overclocks and main-gun combo/mod mechanics remain.
- Reproducible 16 × 16 pixel icons cover equipment, upgrades, abilities and UI,
  including new Gravity Well, Pulse Barrier and Battle Frenzy artwork. Removed
  obsolete melee assets, ammunition art and old combat scenarios.
- Visual Lab now has 21 scenarios. The full Radeon GPU pass produced 153 captures
  with zero failures and no script/engine errors; precision and nested-blast
  regressions passed. Checks exercise all 20 operator/skill bindings and actual
  effects, protection overlap, rank scaling, F mining/occlusion, primary swaps,
  purchases, save-safe workshop gear, procedural contracts and scarce pickups.
  These are integration checks, not full-campaign balance or FPS certification.
- Normal generated-Yard GPU smoke exercised live movement, firing, wheel swaps,
  all five Scout skills and real F mining under spawning pressure: 101 kills,
  41 live threats, no script/engine errors. Legacy on-disk save migration and
  a second startup also passed without touching the real player profile.
- Mastery-layout/quest/encounter follow-up passed 21 captures and all checks.
  That subset still reported 20 ObjectDB instances leaked at exit; source
  verification is not claimed universally warning-free.

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
