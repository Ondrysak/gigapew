# Kakaboomboom 0.6.0

- Every generated sector now has a roofed underground hall at −4.5 m, a
  connecting passage, a public WC and two usable stair entrances. Players and
  enemies descend the same continuous ramps; pitched ceilings no longer block
  the horde through an overly broad vertical obstacle bound.
- Prague station dressing follows Jiřího z Poděbrad (A), Palmovka (B) and
  Hlavní nádraží (C): coloured wall panels, terrazzo, station/exit signs,
  fluorescent tubes, ticket machines, validators and benches.
- Corrected rotated kit transforms: local dimensions now rotate with both
  visuals and colliders. Portal-cut metro/WC lining also has physical walls
  between adjoining underground floors, not only around the terrain perimeter.
- Public WCs now have hollow oval bowls, seats, cisterns with dual flush buttons,
  plumbing and paper holders, plus accessible stalls, urinals, twin basins,
  mirrors, soap/towels, drains and an attendant's coin table. Sector-specific
  partitions and seeded wear vary the interiors. Portable cabins remain outdoors.
- Station bays add notices, maps, bins and utility fittings. Seeded hospoda,
  herna, večerka and nonstop layouts add detailed bars, taps, goods, shelving,
  cashier desks and seating while preserving the circulation aisle.
- Kenney's CC0 Furniture Kit radio and potted-plant models dress pub/nonstop
  counters. Imported geometry and original materials are shared in mesh batches;
  selected files and their license are under `assets/third_party/kenney_furniture/`.
- Real furniture colliders preserve all carved doorway widths and machine
  standing approaches. Geometry and sign art use shared batches; kit lights
  and labels are bounded.
- Every sector has two herny, two hospody and two nonstops: separate 12×18 m
  interiors with signed 4 m entrances, connected porches and seeded furnishing.
  Palmovka retains its večerka and uses a 120×88 m footprint. Outdoor plazas,
  landings and combat halls stay separate from venue and stair approaches.
  Public WC remains accessible through the underground passages and stairs.
- Mineable automaty occupy supported, resource-specific venue bays: fruit
  banks in herna/hospoda, the rare bank in herna, cigarette machines in
  hospoda/večerka/nonstop. Initial stock covers the contract; procedural
  respawns stay in compatible venues, never on arbitrary terrain or islands.
  Furniture reserves access to every compartment, and fruit-bank plinths
  sit on the actual floor. Obsolete fake pub/herna facade doors are removed.
- Each indoor venue starts with a compatible machine before additional quest
  stock is filled; further placement favours less-populated compatible rooms.
- Hlášky boards draw complete random lines from `hlasky.txt`: hanging indoor
  notices, entrance signs, station/WC notices and park/construction boards.
  Source is cached, text wraps and fits, choices are seeded independently of
  furnishing/gameplay RNG, and exports explicitly include the text file.
- Negative floor heights propagate through enemy navigation, pickup grounding,
  radar and floor effects. Timed supplies, extraction and player/boss mortar
  targets reject covered floors. Mineable machines occupy street-level venues.
- This is not stacked playable terrain: each XZ cell has one traversable
  height, with the underground reserved beneath nonwalkable building mass.
- The `levels` visual lab captures indoor/outdoor fixtures, toilet and counter
  details, and verifies physical stair descent, enemy following, held-W wall
  blocking and entry into every repeated venue, real held-F herna prying,
  every initial compartment's clearance/reach, room population, sufficient
  contract stock, whole-source fitted quote text, seeded connectivity and
  fixture budgets across all three sectors.
- Release verification: the final `levels` run produced 202 captures with
  zero failures. Mining, venue, quest, gear and encounter scenarios also
  passed; the quest scenario exercised the full three-sector extraction path.

# Kakaboomboom 0.5.0

Realistic spinning fruit machines, recursive hallucinations with feedback-loop vision,
mega fusion, passive gear and required stash raids; Godot 4.7.2 Linux x86_64 release.
The 0.4.1 notes follow the 0.5.0 changes.

- Výherní automaty (Drobné) and JACKPOT 777 machines (Kešulky) are now banks
  of three upright Czech pub fruit machines modelled on a real cabinet.
  - **Cabinet:** backlit top glass ("SUPER DROBNÉ ★★★ 750" or "JACKPOT 777")
    with fruit paytables, a lit SUPER TURBO x1–x10 ladder and win-line lamps.
    Red 7-segment SÁZKA/MULTIWIN/BONUS displays. A slanted lower glass with
    an x2 RISK game and ladder. A chrome deck with eight lit buttons, and a
    lower cabinet with a KOVOHRA badge, cash-box door, lock and sticker.
  - **Reels:** curved drums with drawn fruit symbols on cream reel paper.
    Each cabinet runs its own 8–14 s game: reels jolt, spin up with motion
    blur and stop left to right with a damped mechanical bounce. 15–25% of
    spins win: lamps and the payline flash, the paytable row lights, the
    credit LED counts up, then the risk game plays.
  - **Prying:** top glass, lower glass and cash-box doors are the pryable
    compartments, with visible chrome locks. Prying any door stops that
    cabinet's game and flashes its red service candle. Emptied banks go out
    of order with dark glass and LEDs, exposing dead reel drums and empty
    cash boxes.
  - **Unchanged:** loot, RNG draws, colliders (exact per door; decoration
    has none), placement and the cigarette machine. Everything animates
    from the paused gameplay clock with no per-frame script work. Art is
    our own, generated by `tools/automat_art.py` (Fira Sans, OFL).
- Cigarette machines blink like real cabinets: chasing marquee bulbs, rail
  lights, a neon strip and door lamps. The first pry flashes the service
  candle red, pried doors go dark and emptied machines sputter out of order.
- Rendered `mining` covers a whole bank, a close cabinet settled and
  mid-spin, reel stops, a win, pause freeze, a tampered cabinet and out of
  order.

- Swarm megas now have self-repeating native anatomy: two auxiliary heads,
  extra arms/legs and paired smaller limb offshoots through three bounded
  generations. Nested smaller heads cycle inward for an endless-zoom illusion;
  this uses the actual textured model/VAT geometry, not a geometric overlay.
- World-only peripheral vision is a Fraksl-style feedback loop: six nested,
  mirror-tiled copies of the rendered world shrink endlessly toward the aim point, spiral,
  hue-drift, split chromatically and mirror-fold at depth, over soft blur and a
  drifting double image. It sits below the HUD and menus and never echoes them.
  The central aim region remains clear; controls, main precision targets,
  collisions, damage and credited lives are unchanged.
- Saved **INTENZITA HALUCINACÍ** control: 0–100%, default 65%, immediate even
  while paused. Zero removes recursive appendages and the whole screen-reading
  pass, preserving original mega bodies, brass bindings and six-segment crowns.
  New motion follows the paused gameplay clock; fine/distant anatomy fades.
- New rendered `hallucinations` scenario covers native human/mouse/insect
  anatomy, head-depth cycles, actual paused keyboard input, peripheral blur,
  crisp main head/HUD, off restoration and actual precision shots.
- Recursive-hallucination verification passed the full rendered lab: 29
  scenarios / 293 captures, zero failures or script/engine errors. Settings
  persistence, paused death/recycle and precision/nested-blast checks passed.
  Anatomy and blur were inspected visually; frame rate is not measured. The
  feedback-loop vision follow-up passed `hallucinations combat pressure boss menu
  levelup gear` (7 scenarios / 81 captures), zero failures or engine errors.

- Dense packs of 6–8 ordinary same-species enemies now fuse into a single mega
  after persistent local crowding, reducing overlapping models without deleting
  represented health or spawn pressure. No reward is paid during fusion;
  defeat credits the absorbed species kills, normal sparse loot and primary
  gear streaks.
- Megas have smooth 1.7× grow-in, broadened torsos, brass binding seams,
  segmented crowns, gathering sparks and slower asymmetric gait/stomp motion.
  Normal enemies also vary gait timing. Enlarged hit/precision bounds match
  the rendered bodies; combined mass and slower movement make megas distinct.
  Death effects emit once per body with scaled particles and grounded blood
  splats, rather than duplicating effects for every credited constituent.
- Bosses, plated/specialist roles, reserved loot/response enemies, active status
  targets, falling/knocked bodies and enemies already beside the player remain
  separate. Fusion respects cover, deck height and enlarged clearance, cannot
  recurse and is limited to four transitions per half-second.
- New rendered `fusion` scenario exercises real primary precision/defeat,
  conserved health, per-member quests/sparse XP/gear streaks, protected lives,
  statuses, pressure budgets, pause and before/after/motion captures.
- Fusion integration passed the full rendered lab: 28 scenarios / 274 captures,
  zero failures or script/engine errors. After the single-body death-FX adjustment,
  `fusion gear combat boss armor` passed five scenarios / 46 captures, also clean.
  Precision/nested-blast regressions and terrain/callback/death-effect smoke
  reported `failures=0`. Fusion transitions and heavy-gait views were inspected
  visually; frame rate is not certified.

- Six Czech-named passive items with pixel icons and matching source hlášky:
  Zrcadlo těžkýho dna (ricochet), Geoxy z Palmovky (dash trail),
  Kabel celoživotních blesků (chain shock), Podržtaškovy rukavice (salvage shield),
  Nebozízkový zapalovač (kill-streak explosion) and Nejsem sklenička
  (+50% damage / −35% maximum-health curse).
- Four run-only gear slots. Full inventories require explicit replacement;
  reward, replacement and G inspection cards show both mechanics and flavour.
  Discovery persists and unlocks future elite drops, but a new run starts unequipped.
- Each generated sector supplies one steal-or-fight stash, two exploration caches
  and an optional elite hunt. Hold E for 2 s to open stashes; press E for the elite drop.
  Guarded stashes offer up to three choices, caches and elites one item.
  **Looting two distinct stashes is required for level completion and extraction**,
  alongside salvage and kill objectives. Guarded stashes and exploration caches count;
  elite drops do not. Declining gear still counts, repeated claims do not, and progress
  resets per sector. The HUD shows the 0/2 objective and E instructions.
  Pause/retreat preserve pry progress, and declining cannot reroll a claimed reward.
- New rendered `gear` lab scenario covers real passive damage, shielding, curse
  removal, discovery, replacement and loot sources across all three sectors.
  These were source-only after 0.4.1 and ship in 0.5.0.
- Initial gear verification, before the required-stash change: the full rendered lab passed 27 scenarios / 263 captures with zero
  check failures or script/engine errors; the precision/nested-blast regression
  reported `failures=0`. Gear UI, stash/elite views and icons were inspected visually.
  Frame rate is not measured.
- Required-stash verification: `quests gear onboarding levels` passed four rendered
  scenarios / 52 captures with zero failures or script/engine errors. All three
  sectors extracted only after two distinct stashes plus salvage/kills; elite loot
  and duplicate claims were excluded, declined rewards counted, and counters reset
  per sector. Expanded HUD inspected; precision/nested-blast regression passed.

## 0.5.0 verification and limits

Released after the developer playtested a round. The final pre-release lab run of the
slot cabinets was skipped at the developer's request. The previous full rendered lab
(29 scenarios, 305 captures) had one open failure: the `quests` check presses F the
same frame it aims at a compartment and the crowbar never raises, so that scripted
prying deals no damage. Normal play was reported working. Frame rate is not measured.

# Kakaboomboom 0.4.1

Prague street arenas, fourteen shop venues, more invented faces and cleaner levels; Godot
4.7.2 Linux x86_64 release. The 0.4.0 notes follow.

- Removed the painted guide lines from generated levels: the corridor centre lines,
  room outlines, the landing-pad bars, and the glowing wall-top and wall-base neon
  strips in Palmovka and Hlavák. Layouts, colliders, mining sites and RNG order are
  unchanged. Ramp treads and deck edges stay. Hlavák is noticeably darker without them.
- Eight more invented homeless characters: a hood over a long beard, taped glasses, a
  bandana, a flat cap with a black eye, an eyepatch, heavy jowls, smeared eyeliner and
  a swollen face. The face atlas is now 5 × 5 (24 faces), with 20 homeless cells and 4
  harder ones, and is quantized to a small flat palette so it stays cartoonish. The
  generator reads no image file; characters are designed from broad categories, not
  from any photograph. `street` lab scenario updated.
- Fourteen shop venues as storefronts on the tenement walls (all in Žižkov, subsets in
  Palmovka and Hlavák) and as the named venue of the stage-clear shop, with their own
  awnings, signs, window goods and taglines: Večerka NONSTOP, Bazar Roháč, Potraviny
  pivo 18, Second hand Nositel, Hospoda točené 32, Železářství, Trafika losy,
  Absintherie, Výdejna PPL, Drogerie Savo, Řeznictví, Herna žetony, Pekárna 6:00 and
  Žižkovský tunel. Flavour only; stock, prices, layouts and RNG order are unchanged.
  A florist was deliberately omitted. New `venues` lab scenario.
- The lab's authored arenas are reskinned from cyan sci-fi to Žižkov courtyards,
  Palmovka and Hlavák (warm sodium light, plaster/tile, Czech signs). Colliders,
  node paths and gameplay hooks are unchanged. Hazard arcs stay blue-white so
  shocks read.

## 0.4.1 verification and limits

The full rendered lab (26 scenarios, 244 captures) and the precision/nested-blast
regression passed with zero failures before packaging; the packaged archive and its files
passed SHA-256 verification and the extracted executable booted outside the source project.
Frame rate is not measured. Storefront taglines are small: legible at about 3 m. Hlavák is
darker after the guide lines were removed. The package contains no reference photographs.

# Kakaboomboom 0.4.0

LUĎAS: LAST TIME KRATOS reskin: Prague humans and delirium creatures with invented
faces, junk guns, crowbar salvage and a street UI; Godot 4.7.2 Linux x86_64 release.

- Homeless enemies with invented faces: Bezdomovec, Feťák and Alkoholik, plus the
  harder Vekslák, Vyhazovač and Pan Herna, draw one of sixteen painted pixel
  faces per enemy (bruises, sores, beards, gaps, drool, a gold tooth, shades),
  generated by `tools/vat/faces/build_faces.py`. Shader grime muddies clothes and
  skin, and props (bedroll, backpack, second bottle) sharpen silhouettes. Hlavák now
  admits Bezdomovci, Feťáci and Alkoholici beside the delirium creatures. New
  `street` lab scenario.
- All six primary guns are now original improvised junk models with unchanged
  numbers: Excalibur, Vinyly, Holubí letka, Absintovej molotov and Rum + zapalovač.
  Each has its own pooled projectile and impact visuals; the Minigun wheel and
  Scatter pump, previously unlinked by a scene-path bug, now animate.
- Full street-UI reskin: Czech navigation, character profiles, workshop,
  settings/records, pause, HUD/tutorial, boss and extraction prompts,
  upgrade/shop cards and death/banked-loot screens. Dark paper/metal,
  worn ink, chipped borders and muted tobacco/rust/amber replace neon cyan
  and glossy framing. The logo uses fixed misregistered ink, not glitch flashes.
- Party names now follow the bible: Luďas, Vítek ultras, Mikoláš hajzldítě
  and Aleš legendary skillz. Remaining primary labels/descriptions also follow
  the bible; their five models are now improvised guns (below). Input, save IDs and combat effects
  are preserved. Character selection scrolls to keep full skill descriptions
  reachable, with taller cards for long names.
- The `menu` lab now also captures intro, full scrollable party/skill details,
  records/settings and pause/settings/abandon-confirmation surfaces.
- Shop purchase coverage uses actual mouse input against a visible stock card,
  so hidden/blank tab content cannot pass by emitting a button signal.

- Mining is now machine salvage: labelled gambling/cigarette/jackpot cabinets
  have independently breakable compartments and permanent empty housings.
  A hooked crowbar inserts/levers under real held-F input instead of spinning
  a drill. Locks, leverage, persistent damage, reach, occlusion, conserved loot
  and contract progress remain; drops are coins, cigarette packs and tokens.
  Removed obsolete crystal/fractal-history shaders and feedback buffers.
- All 41 XP upgrades, eight permanent talents, workshop recipes, shop stock,
  skill effect descriptions and mastery/purchase/status previews use Czech
  scene fiction. IDs, prices and effects are unchanged. Mastery text now
  distinguishes actual duration/protection/fire-rate scaling rather than
  claiming the same damage/duration bonuses for every skill.

- Playable Prague asset swap: all eleven enemy slots now use animated human
  hallucinations or original mouse, cockroach, rum-bottle and slot-machine models.
  Walk/attack/death VAT replaces the old robot and alien meshes; the bouncer
  carries a HERNA door with a rear money-pouch precision target. Removed obsolete
  monster textures and updated the CC0 source credits and bake instructions.
- The first primary is **Lahve od piva**: gloved-hand beer bottle, pooled
  tumbling bottle trails and glass/foam impacts instead of muzzle flash and
  shell casings. Its combat numbers are unchanged. The original Blender gun
  builder supports `-- --weapon pulse` for selective regeneration.
- The generated first sector is **Žižkov**, with plaster/brick tenements,
  pavlače, cobbles, warm sodium lighting, HERNA NONSTOP/PIVO signs and the TV
  tower. Layout, collisions, mining sites and RNG order are unchanged.
  Later sectors are labelled **Palmovka** and **Hlavák**; currencies are
  **Drobné / Cigára / Kešulky** with matching pixel icons.
- Skill names and combo callouts now follow Luďas's vocabulary without changing
  their effects. Four additional spoken phrases are cut from longer recordings
  and used as combo, extraction and clear variants. The bible records ending B:
  waking back in the Žižkov septik after the last set; no ending cutscene is
  implemented by this asset pass.

- Reskin started: *LUĎAS: LAST TIME KRATOS*. The design bible
  (`docs/ludas/BIBLE.md`) sets the 90s Prague story, the three circles of
  Tartarus (Žižkov, Palmovka, Hlavák), the hallucination bestiary, improvised
  weapons, renamed skills and currencies. First playable piece: Luďas's own
  recorded voice reacts to arrival, kill bursts, combos, new skills, low
  health, healing, extraction, clears and death, with priorities and
  cooldowns. New `voice` lab scenario.
- Guided start (Settings, on by default) introduces the game gradually. Runs
  begin with one skill; the others unlock at levels 2, 3, 5 and 7 with a NEW
  SKILL callout, a dim next-skill teaser on the HUD and locked shop cards.
  Perks join level-up cards at level 3, gun mods at level 5. One-time tips
  explain movement, the contract, each new skill, mining, low health,
  extraction and combos; *Show tips again* resets them. Turning it off
  restores the full kit from the start. Independently, the Yard contract asks
  for one mining and one kill objective (Foundry 2 + 1, Reactor 2 + 2), and the
  Yard opens with a 12 s calm before spawning. The controls footer lists only
  unlocked actions. New `onboarding` lab scenario.
- Extraction: completing the contract no longer opens the shop instantly. A
  drop pod lands in the farthest clear room, marked by a tall green beam and a
  radar diamond. Hold its ring for 10 s (progress kept while you step out) as
  the director spawns at double rate; lift-off banks minerals and opens the
  shop. Dying mid-extraction still ends the run; XP choices can be answered.
- Skill combos for every class: CRUSH (skill blasts into your Gravity Well
  deal +60%), COLLAPSE (Pulse Barrier near the well detonates it, scaling with
  held enemies) and SHIELD RAM (dash or leap while shielded slams a landing
  shockwave). Named callouts appear below the crosshair; ability text explains
  the combos. New `combos` lab scenario; `quests` now drives all three pod
  extractions through touchdown, beam progress, pause and stepping out.
- Level design: sectors are now carved from solid rock instead of open boxes.
  Irregular rooms (L, T, cross, chamfered, round, ring and colonnade) join
  through dog-legged corridors of 4/6/8 m with loops and dead-end alcoves.
  Yard is a mixed compound, Foundry three stacked furnace halls with transfer
  passages, Reactor a round hub around a glowing core with spokes and chords.
  Areas grew to 88², 120×72 and 104² m. Raised overlooks with ramps sit in arena
  rooms; ore outcrops and broad walls host contract ore. Floor lines trace
  corridors and flag chokepoints, and the radar draws nearby walls. A 120-seed
  sweep placed every set piece with clear ore standing room; rendered checks
  prove connectivity, ramp climbing by player and enemy, and contract ore.
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

## 0.4.0 verification and limits

The full rendered lab (25 scenarios, 199 captures) and the precision/nested-blast
regression passed with zero failures before packaging. The packaged archive and all
its files passed SHA-256 verification; the extracted executable booted through the
intro and main menu outside the source project for 600 frames and exited with code 0.
The package contains no reference photographs: the export excludes `homeless_pictures/`,
Godot ignores that folder, and a scan of the executable found none of its file names.
Faces in the game are painted from parameters only.

The packaged smoke reported 6 leaked ObjectDB instances at exit. Sustained 60 fps,
Radeon hardware performance, balance and other distributions are not certified.

Version 0.4.0 installs like 0.3.0: extract `kakaboomboom-0.4.0-linux-x86_64.tar.gz`,
verify with the adjacent `.sha256` and `SHA256SUMS`, run `./kakaboomboom.x86_64`.
Previous versioned release artifacts are not overwritten. The 0.3.0 notes follow.

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
