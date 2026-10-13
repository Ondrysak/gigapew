# Kakaboomboom

A first-person techno arena shooter with hardtek final bosses. Pick an operator, choose a procedurally generated Prague arena, combine two complementary guns, double jumps and slides, defeat its final boss, then spend banked currency between rounds and runs. Built with Godot's GL Compatibility renderer and CC0 art credited in [CREDITS.md](CREDITS.md); sampled audio has separate terms. Open `project.godot` and press **F5**, or run `godot --path .`. Current source verified with Godot 4.7.2.

## Current Prague reskin

The source game is being reskinned as **LUĎAS: LAST TIME KRATOS**, with the
story and selected septik-loop ending B recorded in [the design bible](docs/ludas/BIBLE.md).
The implemented asset changes are:

- All eleven enemy slots use the new hallucination models: Bezdomovec, Feťák,
  Alkoholik, Vekslák, Vyhazovač and Pan Herna in the first two sectors; Bílá myška,
  Šváb z herny, Lahev rumu, Jednoruký bandita and Pan Jackpot in the third.
  `robot_*` and `alien_*` are retained internal slot IDs, not the visible creatures.
- The six human enemies wear original invented faces. `tools/vat/faces/build_faces.py`
  paints 24 pixel faces (twenty homeless/drunk/junkie characters, four harder men) and
  `tools/vat/bake_vat.py` maps them onto the front of each head; the horde shader
  picks one per enemy, so a crowd of Bezdomovci shows most of the twenty. No photograph
  or real person is used. Mud, stains and damp patches come from the shader
  (`grime`); a bedroll, ragged backpack and second bottle add silhouette.
  Bezdomovec, Feťák and Alkoholik also spawn in Hlavák, so every sector has
  homeless in its crowd.
- Fourteen shop venues stand as storefronts on tenement walls: Večerka NONSTOP, Bazar
  Roháč, Potraviny pivo 18, Second hand Nositel, Hospoda točené 32, Železářství,
  Trafika losy, Absintherie, Výdejna PPL, Drogerie Savo, Řeznictví, Herna žetony,
  Pekárna 6:00 and Žižkovský tunel. Each has its own awning, sign, window goods and
  hand-lettered tagline; Žižkov may show all of them, Palmovka and Hlavák their own
  subsets, and the stage-clear shop is named after one of the sector's venues. They are
  flavour only: stock, prices, layouts, mining sites and RNG order are unchanged. A
  florist was deliberately left out.
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
  DROP and clear reactions alongside the existing barks.
- Optional close-range crowbar salvage opens gambling/cigarette/jackpot
  machines with physical breakable compartments and currency-shaped loot.
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

The later-sector environments retain their visual designs. The nine improvised
junk guns have distinct combat jobs (see below).
The narrative ending is specified in the bible, not a newly implemented cutscene.
The authored lab arenas (Yard, Foundry, Reactor) are now dressed as Žižkov courtyards,
Palmovka and Hlavák through `scenes/levels/arena_skin.gd`; collisions and gameplay nodes
are unchanged. The `levels`, `arena`, `onboarding` and `venues` scenarios exercise generated campaign worlds.


## Linux release

Current source version: **0.7.0**. Version notes are in
[RELEASE_NOTES.md](RELEASE_NOTES.md).

To play a package built using the release recipe below:

```sh
cd export/linux
sha256sum -c kakaboomboom-0.7.0-linux-x86_64.tar.gz.sha256
tar -xzf kakaboomboom-0.7.0-linux-x86_64.tar.gz
cd kakaboomboom-0.7.0-linux-x86_64
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

- **WASD** moves; **mouse** aims. **Space** jumps; a fresh second press in the air double-jumps once.
- **Ctrl** starts a momentum slide when you are already moving. The gun tucks/cants and a forward leg appears with a short visual bank/FOV rush. Aim and shooting remain available; the lowered capsule waits for headroom before standing.
- **Hold LMB** fires the active gun with unlimited ammunition. A fresh LMB press on the audible beat is required to spend a charged **DROP**.
- **Q** or the **mouse wheel** toggles the two guns drafted at the start. Catalogue replacement is available only during empty breaks (**Tab** or the route screen's pair button) and in the sector shop; either slot can be replaced for free. Shared primary/gadget ranks apply once to both guns.
- **RMB** kicks on a fresh press. An incoming projectile is parried first; otherwise the kick launches light bodies, staggers heavies, or kicks a keg. A slide kick carries the launch; an airborne kick stomps downward and bounces on contact, but commits to a dive on a miss.
- **F** leaps toward an aimed, dazed non-boss enemy within 8 m and finishes with one of four acrobatic kicks, or otherwise smashes one aimed machine compartment within 2.6 m. Release and press again for another action. Machine loot is optional; the raised crowbar replaces the gun, including impact recovery.
- **1 / 2 / 3 / 4 / 5** activate your class abilities. With **Guided start** (default) only key 1 works at first; the rest unlock as you level (see below).
- **E** collects optional gear: hold it for 2 s at a stash, or press it at an elite's drop. Authored lab arenas also use E for consoles, vents and the guarded-machine beacon.
- **G** pauses to inspect all four equipped gear slots, with their effects and source hlášky; **Esc** closes the inspection.
- **Level up / full supply meter:** the game pauses; press **1 / 2 / 3** or click a card.
- **Esc** pauses (Resume, Settings, Abandon Run).
- **Clear the final set:** defeating the last real survivor opens the shop. Swap guns freely, upgrade abilities, buy primary mods or protection, then continue. After death: **R** retries with the same class and a new layout; **Enter** returns to the menu.

## Flow

Intro → main menu (**Deploy**, **Base Workshop**, **Records**, **Settings**) → class select → **run setup** (level, preset, tuning) → **draft two distinct guns** → choose a venue → physically travel there → fight → breather → next route. Each level is generated from a new seed as connected combat spaces rather than one open box. Rooms come as L, T, cross, chamfered, round, ring and pillared colonnade shapes. Corridors are 6 m passages or 8 m boulevards; every room gets an extra loop where possible, removing dead-end alcoves and narrow chokepoints. Painted floor lines trace routes; a cyan radar marker and distance readout guide you to the chosen venue.

Each theme plans differently:

- **Žižkov** (`yard`): a tenement compound of mixed-shape rooms on a spanning tree plus loops.
- **Palmovka** (`foundry`): two long furnace halls joined by transfer passages and indoor streets. Its 120×88 m footprint accommodates repeated venues, the retained večerka and outdoor fixtures without overlapping their approaches.
- **Hlavák** (`reactor`): a round hub, narrow spokes and diagonal chords linking the outer rooms. The underlying environment remains the existing Reactor.

**Traverse routes:** large rooms contain raised decks with ordinary ramps for the horde. Decks stand 1.5–1.8 m high, so a double jump can take a shortcut from their non-ramp side. Small cover and traverse blocks are 1.1–1.5 m high; taller landmark islands still break long sightlines. Žižkov has 1 overlook / 2 traverse covers, Palmovka and Hlavák 2 / 3. Most groups arrive away from your view.

Every generated sector includes a **roofed underground station hall at −4.5 m**, a connecting passage, a tiled public WC and two street stair entrances. Station dressing uses Jiřího z Poděbrad / green line A, Palmovka / yellow line B and Hlavní nádraží / red line C panels, signs, maps, validators, ticket machines, benches and utility fittings. Every sector has **two herny, two hospody and two nonstops**; Palmovka also retains its **večerka**. Combat venues are 12×16 m interiors with a 6 m front door, a separate 6 m side escape and a carved outdoor lane between them. Their 4.4 m ceilings and 3.2 m central aisles leave room for jumps and slides. Seeded assignment, bars, taps, shelving, goods and seating vary the rooms; outdoor sites add portable WC cabins, construction equipment and a small park. Public toilets have actual hollow bowls, seats, cisterns, flush buttons and paper holders, alongside stalls, urinals, basins, mirrors, soap/towels and the attendant's coin table.

**Interior finishes and service areas:** hospody use worn plank floors, timber seating and a backbar separated from the counter by a real staff passage. Nonstops use checker vinyl, cold-drinks cabinets, food displays, espresso/till equipment and wipe-clean cafe seating. Herny have patterned carpet and a front cashier area with transparent security panes, a cash-transfer slot, register, security monitor and CCTV; the front bay beside it stays free of machines. The večerka uses commercial tile and places its checkout before shelving. Ceiling finishes, fitted lights, menus, clocks and electrical/safety details vary the rooms. Floor finish/palette choices remain room-seeded but share one instanced material across every venue; furnishing and quotes keep their independent seeds. Up to ten unshadowed kit lights cover the station, WC and venues; kit labels remain capped at 64.

**Hlášky signs:** hanging indoor notices, entrance boards, station/toilet notices and park/construction signs draw random complete lines from [`hlasky.txt`](hlasky.txt). Text wraps and fits its board; choices repeat for the same run seed and vary between runs. A separate quote RNG leaves furnishing, layout and encounter randomness untouched. The text file is explicitly included in exports.

The navigation model still has **one walkable height per XZ cell**: underground halls sit beneath reserved, nonwalkable building footprints, not beneath a second playable street. Both stair ramps link the street to the hall for players and enemies. Rotated kit visuals and colliders share local dimensions; portal-cut linings have physical walls even between adjoining rooms. Furniture preserves both venue doors, the central aisle and machine approaches. Sky-dropped supplies remain outside; loose loot and floor effects use the actual floor, including negative heights.

**Linked venue score attack:** each level has seven physical fight locations: two hospodas, two hernas, two nonstops and the metro. Choose a deterministic, unvisited route between fights; choosing resumes travel, not remote spawning. Physical arrival starts finite BUILD/PEAK admissions through that location's authored entry/approach lanes. Blocked placement retains its real budget rather than spilling enemies across the district. Each fight ends only after all actual represented survivors are defeated; elapsed time never wins. The empty five-second breather, route choice and travel freeze STYLE decay. After the configured number of distinct venue crowds (3 / 4 / 5 by default), clear delayed damaging effects and face the level's final boss in that same last venue. Defeat it and any remaining enemies/projectiles/fire before the shop opens. Unsafe boss placement retries without awarding a clear or closing the venue. There is no level countdown, mining quota, required stash or extraction.

Optional automaty stay in supported, reachable venue bays. Fruit-machine banks belong in the herna and hospoda, the rare bank in the herna, and cigarette machines in the hospoda, večerka or nonstop. Respawns use the same bays; no random cabinets appear in the street.

### Optional gear raids

Each generated sector has one guarded stash, two exploration caches and one elite hunt.
These rewards are optional detours; none is needed to clear the arena.
Repeated claims never count twice. Approaching within
6 m activates the stash's finite defenders or the elite and its escort. Fight first, or
hold E to steal the stash while its guards remain alive. Partial opening survives
retreat and pause; rewards can be claimed only once.

- **Guarded stash:** choose one of up to three different items.
- **Exploration cache:** reveals one random item.
- **Elite hunt:** the Podržtaškův výběrčí has three times its base species' health.
  Killing it leaves an E pickup on reachable floor; it never auto-equips gear.

Four passive slots, no duplicates. With a full inventory, choose exactly which item
to discard or leave the reward behind. Equipment survives sector changes but not a
new run. Revealing gear records its discovery even if you decline it: mirror,
trainers and gloves are available in elite drops initially; wire, lighter and glass
join that pool after discovery in a stash/cache. Discoveries persist in the profile,
not the equipped build. Loot placement and reward rolls use their own seeded RNG.

| Item | Effect |
| --- | --- |
| Zrcadlo těžkýho dna | One ricochet per primary shot: 40% of direct-hit damage to another visible enemy within 6 m. |
| Geoxy z Palmovky | Dashes leave a 2 s trail: 10 damage every 0.25 s within 1.1 m. |
| Kabel celoživotních blesků | Four direct-hit shots on the same enemy lifetime discharge 25 damage to up to three nearby enemies within 5 m. |
| Podržtaškovy rukavice | Opening a machine compartment grants a 20-point shield for 5 s; another opening refreshes it, never stacks it. |
| Nebozízkový zapalovač | Eight primary kills with gaps of at most 2.5 s prime the next killing primary hit for a 50-damage explosion within 3 m. |
| Nejsem sklenička | Clearly marked curse: +50% damage and −35% maximum health. Replacing it removes both effects without compounding modifiers. |

Each item has a pixel icon, Czech effect description and a matching quote from
`hlasky.txt`, shown in reward cards, explicit replacement and G inspection. The HUD
shows four compact slots, shield/lighter status, loot-source distances and the
aimed stash's E prompt.

| Level | Default fights | Arrival calm | Live represented-life cap |
| --- | ---: | ---: | ---: |
| Žižkov (88 × 88 m) | 3 | 6 s | 40 |
| Palmovka (120 × 72 m) | 4 | 4 s | 48 |
| Hlavák (104 × 104 m) | 5 | 4 s | 56 |

### Run setup, presets and rounds

There is no fixed level order. After class select, **run setup** picks the level and tunes the run; every change is saved for next time.

| Control | Range | Effect |
| --- | --- | --- |
| Level | Žižkov / Palmovka / Hlavák | Which generated level the run starts on |
| Bitky | 1–8 | Fights to clear; presets that keep the level's own count follow the chosen level |
| Hustota | ×0.25–3 | Bodies in every wave |
| Strop davu | ×0.5–2 | Represented lives alive at once (8–200) |
| Zdraví nepřátel | ×0.5–3 | Enemy and boss health |
| Příchozí poškození | ×0.25–3 | Every hit you take, before armor |
| Tempo nástupu | ×0.5–2 | How quickly the next group is admitted |
| Specialisté | on / off | Off removes bombers, Tarzans, sprayers, throwers, bouncers and hype men; core crowd roles stay |
| Obtížnost | 0–10 | Each tier: +15% enemy health, +10% incoming damage, +8% density, +25% clear rewards |

| Preset | Fights | Density | Cap | Health | Damage | Pace | Specialists |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Pohodička | 2 | ×0.6 | ×0.75 | ×0.7 | ×0.5 | ×0.8 | off |
| Klasika | level | ×1 | ×1 | ×1 | ×1 | ×1 | on |
| Rychlovka | 1 | ×1 | ×1 | ×1 | ×1 | ×1.4 | on |
| Horda | level | ×2.5 | ×1.8 | ×0.6 | ×0.8 | ×1.5 | on |
| Hardtek peklo | level | ×1.6 | ×1.4 | ×1.6 | ×1.6 | ×1.3 | on |

Moving any slider turns the setup into *Vlastní*. The summary line shows the actual body estimate across all fights, the crowd cap, the reward multiplier and your permanent shop ranks. Tuning works on copies, so the authored levels never change.

Clearing a level opens the shop. Its footer starts **another round** on any level, either at the same difficulty or **one tier harder**. A new round carries score, both guns, primary and skill ranks, level-up upgrades, perks and auto weapons into a freshly generated level, then refills health. **Domů do bazaru** ends the run and records it as a victory with its rounds, last level and tier. Contact damage remains capped at 4 per 0.5 s before tuning; fusion preserves represented lives and aggregate remaining enemy health.

**Tactical fixtures and final bosses:** `encounter` and `boss_patterns` retain an authored guarded machine, interactive hazards, raised decks and ramp combat; these fixed placements are not inserted into generated layouts. The `boss` scenario covers final bosses in all three generated levels as well as explicit fixture release. Vyhazovač still uses directional front armor and a rear precision target; the Yard boss retains its ram/mortar attacks and staggerable recovery windows.

### Combat roles and weapons

Enemy types now pose different tactical problems:

| Role | Base HP | Behavior |
| --- | ---: | --- |
| Grunt | 90 | Commits to a left or right flanking lane before closing. |
| Runner | 65 | Visibly winds up, commits to a fast dash only with line of sight, then recovers in place. |
| Ranged specialist | 150 | Holds a firing lane, repositions for sight, then fires a locked three-lane fan. |
| Charger | 420 | Commits to a charge and leaves a 1.2 s recovery. |
| Plated Vyhazovač | 480 | Rams only along its armored facing; circling exposes its rear core and recovery. |
| Boss | 2600 | Authored attacks and recovery windows. |
| Flaškař | 110 | Lobs a bottle at a committed landing spot; dodge the splash or return the bottle. |
| Bouncer | 600 | Physically blocks your movement, winds up a locked shove; sidestep or interrupt with a kick. |
| Hecíř | 70 | Visibly buffs nearby allies' speed, attack cadence and damage without adding health; kill or stun the source. |
| Masta Blasta | 200 | Stands still for a 1.2 s arming warning, then rushes a locked lane at 16 m/s and self-detonates. A gun ray through the visible backpack, an RMB kick or an F execution turns the blast against the crowd. |
| Tarzan ze stropu | 125 | Hangs only from real roofs (hospoda, metro), marks a fixed landing ring, then drops. Shooting knocks him loose early; a midair kick launches him for AIR MAIL. |
| Absintovej Polejvač | 220 | Warns for 0.9 s, then lobs finite green absinthe that is harmless until lit. FIRE rays or any fire hit ignite it into a crowd-burning patch. |

Stun interrupts any non-boss windup. Stage health scaling remains 1.0× / 1.25× / 1.6×; boss scaling remains 1.0× / 1.6× / 2.4×.

**Specialist counterplay:** a Masta Blasta blast deals 150 damage within 4.2 m and stops at walls. A hostile detonation deals 12 damage to the player. Explosions you set off with a backpack shot, kick or execution never hurt you. Each of their kills counts once toward score, STYLE and DROP. An executed bomber's corpse flies forward and explodes on impact or after 0.85 s. Absinthe puddles last 8 s. Ignition deals 80 damage, then the fire burns for 5 s at 6 damage per 0.4 s. Only a deliberate primary FIRE shot earns ignition credit; automatic and ambient fire still damage enemies but award nothing. If a hostile bomber's blast lights a puddle, the fire damages the player for 4 per tick instead of burning enemies. Clearing a stage removes all fuel, fire and pending blasts.

**Kára callouts:** enemy warnings play short positional lines from jirikara.cz on the SFX bus. They need line of sight and are audible up to 18 m, with per-event cooldowns and a 2.5 s global gap. Soundtrack playback is never ducked. The arming warning and rush play *Děléj!*, absinthe plays *Nemáte voheň…*, a reversed bomber plays *Do prdele co se děje?!* and a cleared encounter plays *Je čas klidu.* The first sighting of each specialist opens its tutor tip.

| Gun | Job |
| --- | --- |
| Pulse | Reliable precision; pierces one target. |
| Scatter | Close-range crowd displacement. |
| Rail | Long lines and exposed rear cores. |
| Autocannon | Clustered packs and plate-ignoring blasts. |
| Tvarohomet | Slowing splash. |
| Maschine | Shock chains. |
| Cihlomet | Mid-range lanes; pierces one target. |
| Flamethrower | Burns through armor. |
| Minigun | Sustained single-target fire. |

Explosions damage first, then apply a separate line-of-sight blast reaction: enemies are pushed outward, attacks are interrupted and lighter bodies are launched. The reaction deals no hidden damage or extra rewards. Wall- and ceiling-constrained motion keeps the visual, physical and precision body together. Deaths throw larger directional debris, and each blast has an expanding ground ring and a rate-limited boom. Soundtrack playback is never ducked or paused by these effects.

**Gun flourishes:** each gun belongs to a flourish family with a draw, idle inspect and DROP showpiece.

| Family | Guns | Draw | Inspect | DROP shot |
| --- | --- | --- | --- | --- |
| Shake | Pulse | Cocked back, swung up, quick fizz | Turned over, then shaken hard | Tipped back and shaken wild |
| Twirl | Maschine | Spun once above the rising hand | Flipped end over end and caught | Barrel roll tossed clear of the hand |
| Rack | Scatter, Cihlomet, Tvarohomet | Comes up canted, hard rack levels it | Turned over with a rack | Barrel roll tossed clear of the hand |
| Heave | Minigun, Autocannon, Flamethrower | Hauled up nose-first, settling bounce | Weighed in the hand | Muzzle hoisted skyward, slammed down |
| Snap | Rail | Swings in from the right and locks with a hum | Sighted down the barrel | Barrel roll tossed clear of the hand |

- **Draw:** plays whenever the gun appears: round start, Q swap, after an F finisher or salvage.
- **Inspect:** starts after 6 s standing still on the ground. Firing, kicking, sliding, jumping or hiding the gun cancels it.
- **Tosses:** the gun spins about its middle while the gloved hand stays in place to catch it.
- **Extras:** minigun barrels whirl and pilot flames flare during flourish accents.
- **Airborne:** the gun dips while rising and floats up while falling.

All of it is presentation only. Shots still fire instantly, and aim is never moved. Pause freezes the pose.

### Combat pinball

Light enemies fly from a kick and damage themselves/other bodies on real wall or body impacts. Heavy enemies, bosses and megas stagger without becoming airborne. All kicks and manual bursts check wall lanes; launched bodies keep their collision, floor and ceiling constraints. A missed kick has longer recovery, held input never repeats it, and a press carried through a menu requires release.

Kick animation has a fast extension, contact hold and weighted return, with distinct standing, horizontal slide and downward stomp poses. Misses overextend without the contact glow. Gun motion, boot geometry and impact shake are visual only; they never steer the player's aim. Pausing cancels committed melee actions and freezes the remaining presentation.

**Daze and finishing moves:** surviving damage at or below 20% of a non-boss lifetime's starting HP opens one 2.8-second window. The original body pulses orange/gold and stops pursuit/attacks, but remains damageable; lethal hits are never clamped into a forced finisher. Dazed lives cannot fuse away. If the window expires, pursuit resumes and that lifetime cannot daze again.

Aim at a dazed body within **8 m** for **F · DORAZIT**. F commits to a real capsule-colliding leap and a **0.80-second** execution, with actual contact at **0.46 seconds** and a planted recovery. A cached shuffled bag presents all four moves before reshuffling and never repeats the preceding move, even across bag boundaries. The original launch direction and travel budget are fixed; there is no homing, correction warp or aim snap. Each move has bounded camera bank/pitch and a FOV rush without spinning the entire view. The gun and crowbar stay hidden until recovery ends.

Lethal contact still requires the recorded dazed body within **2.3 m**, with a clear lane on the same floor. Successful contact adds a directional gold/magenta crown, penetration sparks, tumbling debris and a hollow terrain-aligned floor stamp alongside the victim's ordinary species death effects. Score/STYLE/DROP credit and up to 12 HP draw from the shared close-healing budget. Walls or ceilings interrupt the leap; intervening bodies, different floors, expired daze, death and recycled target identities invalidate contact. There is no immunity or soundtrack pause. Held F cannot repeat or also claim nearby salvage; a fresh F takes priority over simultaneous gunfire.

| Finisher | Animation | Fresh launch / impact cuts |
| --- | --- | --- |
| Front flip | Bracing hands, knee tuck, full forward boot rotation and sole snap | Reversed rising lead with kick snap / tuned kick with FX transient |
| Corkscrew heel | Depth-changing horizontal orbit, yaw revolution and lateral heel sweep | Forward/reverse 303 stutters and scrape / metallic tuned kick and scrape |
| Flying dropkick | Both knees tuck, then both boots extend together | Reversed drum/lead rise / staggered double-kick crunch |
| Overhead axe kick | Raised heel above the reticle, then a vertical downward chop | Descending abrasive lead/FX sweep / descending kick slam and saturated tail |

`assets/audio/finishers/` holds eight short mono PCM16/22050 edits, not full
loops. Launch clips end before contact; the impact clip plays only after a
successful execution. Interrupts cancel pending finisher sound. Cached voices
use SFX routing without changing soundtrack gain. `tools/finisher_samples.py`
rebuilds the cuts from the original supplied pack; `catalog.json` records
source hashes, cut ranges, reversals, pitch traversals, layering and WAV hashes.
The sample pack's redistribution terms remain unverified (see CREDITS).

| Setup → finish | Payoff |
| --- | --- |
| Tvarohomet → kick → impact | Frozen bodies shatter on death or first launch impact. |
| Flamethrower → scatter / Cihlomet | Consumes burning state for a short, bounded flame burst. |
| Kick → rail | **AIR MAIL** doubles direct rail damage to a launched body in the same shot. |
| Maschine → autocannon / Tvarohomet | Consumes electric charge for at most five local conduction targets; no onward recursion. |

AIR MAIL requires actual ascent or airborne motion; standing on a raised floor never doubles damage.

Successful projectile parries heal 6 HP once, but award no STYLE/charge until a returned shot actually kills. Rank-zero returns fly straight; the return build adds homing. Ordinary close kills within 3.5 m heal one 6 HP step per transaction, including multi-kills; deliberate F executions can heal 12 HP. Both draw from an 18 HP budget refilling at 4 HP/s. Distant kills, corpse/prop hits and missed parries do not heal. Death and maximum health take precedence.

Finite steel kegs can be kicked into enemies/walls or shot in place. An armed keg detonates on impact or after its fuse; each keg explodes once, with real wall-clipped damage. Keg chains remain finite and synchronous.

Three two-rank perks change the tools: **Mokrá podlaha** adds slide speed and refunds landed slide-kick recovery; **Rozbitej led** widens/strengthens shatter and freezes survivors without recursion; **Zpátky k odesílateli** extends parry reach, strengthens/homes returned shots and refunds parry recovery.

### STYLE, score and DROP

Actual primary-gun kills and explicitly credited player kicks, F executions, launch impacts, reflected shots, manual weapon combinations and keg explosions earn score and STYLE once per defeated represented life. Nonlethal hits, random critical rolls, ambient burn/shock deaths, abilities, auto weapons and external deaths do not. Precision, perfect beat, air, slide, multi-kill and gun variety add primary bonuses. STYLE feeds the capped +40% damage bonus, hallucinations and soundtrack intensity. A spent DROP's own synchronous chain windfall cannot recharge that DROP; independent later actions can.

STYLE also charges one **DROP**. Each kill transaction adds at most 32% charge; a full charge cannot bank a second one. Fire a fresh manual shot on the audible beat (±10% of a quarter note) with a heavy gun whose upgraded interval is at least half a beat. That shot deals **×10 damage** and adds its gun's signature payoff:

- Scatter or Cihlomet: stronger push and stun.
- Rail: pierces the whole line.
- Explosive guns: 1.8× radius and stronger knockback.
- Frost and shock: stronger slow or stun.

Off-beat, held/automatic, fast-gun, muted-music and unavailable-clock shots retain normal damage and keep the charge. Inputs are never delayed or fired automatically. Timing follows the playing stage mix's rounded PCM grid, playback pitch and audio-output latency. Overkill reports only the enemy's actual remaining health.

### Mega hallucinations

Persistent overcrowding turns **6–8 ordinary grunts of the same species into
one mega**: constituents must stay within 2.4 m of the seed for 0.75 s. Sparse
packs remain ordinary. Fusion gathers small amber sparks, grows the body to
1.7× scale over 0.55 s, broadens its torso and adds brass binding seams and a
segmented crown. Megas use slower, heavier, asymmetric gait/stomp motion;
ordinary enemies also vary gait timing per instance.

Fusion preserves the sum of current and maximum health, without healing or
awarding kills, loot or score. Defeating the mega credits each
absorbed life to its original species, normal sparse XP/utility-drop rules and
primary-kill gear streaks. The enlarged main head/core remains a precision
target. Megas move at 68% of ordinary speed, resist knockback with combined
mass and contribute at most twice their species' normal contact damage, still
under the shared contact cap.
Visual death bursts are emitted once per body, not per credited life; blood
splats stay grounded instead of stacking in the enlarged body's center.

Bosses, plated enemies, ranged/charger specialists and reserved stash/elite/
guarded-machine responses never fuse. Active burns, frost, stun, exposure,
knockback and falling also prevent fusion. Groups cannot merge through cover,
between decks, into insufficient clearance or within 4 m of the player.
Megas cannot fuse again; transitions are capped at four per half-second.

**HALUCINACE counts visible living bodies**, while spawn caps and music pressure
count all represented lives. Fewer models therefore do not refill the director's
budget or silently reduce credited kills. Fusion ships in 0.5.0.

### Recursive hallucinations

Megas repeat their **anatomy**, not geometric wallpaper: two auxiliary heads,
extra arms/legs, and smaller limb offshoots branching through three bounded
generations. Smaller native heads cycle through nested scales on the auxiliary
heads, creating an endless inward-zoom illusion without infinite geometry.
The original model triangles, textures, face selection and VAT animation are
reused.

The crowned main head/core remains the real precision target. Phantom
appendages add no enemy lives, health, collision, damage or rewards.
**Settings → REŽIM HALUCINACÍ** saves one of six presets. **Delirium mix**
is the default; the original feedback effect remains selectable.

| Preset | Effect |
| --- | --- |
| Zpětná vazba | Original recursive spiral echoes, chromatic separation and mirror folding |
| Vířivá podlaha | Authored floor patterns twist into bounded vortices; peripheral vision curls radially |
| Tekuté vidění | Travelling floor waves and slow, gradient-driven peripheral lensing |
| Krystalové zrcadlo | Eight-way polar world reflections with gently breathing rings |
| Kolotoč hlav | Source-textured phantom heads counter-rotate, nod and breathe, without a screen-reading pass |
| Delirium mix | Smoothly blended feedback/lensing, both floor fields and rotating phantom heads |

Screen effects sample only the rendered world, leaving the central aim region,
HUD and menus clear. Floor effects warp procedural pattern coordinates, never
vertices or collision: outdoor surfaces, metro terrazzo, WC tiles and wood,
carpet, vinyl and ceramic venue floors keep their real geometry. Wall tiles and
industrial warning/navigation markings remain anchored. Rotating head copies
use baked head-radius clearance, including long quadruped snouts, around the real
precision face; the main head and hitbox are unchanged. New motion freezes in
pause/reward screens, without camera steering or strobing.

**Settings → STROP HALUCINACÍ** saves an intensity ceiling from 0–100% (default 65%).
Actual STYLE drives anatomy, floor fields and world vision from
28% of that ceiling with no STYLE to 100% at 100 STYLE; the drive changes
over about half a second and falls with decay or a wipe. Zero immediately
removes the new anatomy, floor warps, screen-reading pass and beat-driven combo
dance, while retaining the original mega body, brass binding and six-segment
crown. Pause freezes the drive and counter motion.

The intensity ceiling remains intact beyond 100 STYLE; higher STYLE escalates
the selected preset's **motifs**, not the saved scalar limit. Delirium mix adds:

| STYLE | Escalation |
| --- | --- |
| 100 | Beat-kicked combo lettering, orbiting print shards and peripheral breathing rings |
| 200 | Stronger counter rotation/shake, crystalline harmonics and wilder phantom-head motion |
| 300+ | Layered print orbits, a bounded wild counter dance and deeper tunnel/floor ripples |

Milestone styles blend between tiers and retreat with the real chain. Counter
movement stays in a bounded lower-centre lane: the reticle, damage bonus, decay
bar and rhythm cue do not dance. Beat accents use the audible music clock; no
camera roll or strobing is added. The saved hallucination ceiling also scales
the new counter decoration.

Feedback and Mixed retain a six-level, mirror-tiled tunnel in one unrolled pass,
without a history buffer. The presets adapt CrystalDive's polar folding,
analytic-gradient lensing and twisted-lattice ideas into the existing Godot
shaders; no CrystalDive assets or rendering pipeline are bundled.



## Classes

| Class | Unlock | Starting primary | Abilities 1 / 2 / 3 | Profile |
| --- | --- | --- | --- | --- |
| Luďas (`scout`) | free | Lahve od piva | Kolobežka Duplex / Šlehat blesky / Vytrhnu hajzl z podlahy | +12% speed, +1 m pickup |
| Vítek ultras (`gunner`) | 6 Kešulky | Holubí letka | Jsem god / Blesky ze stropu / Heroic Ragnarok | +30 health, +1 armor, −5% speed |
| Mikoláš hajzldítě (`driller`) | 10 Kešulky | Rum + zapalovač | Odpočet do autodestrukce / Ilegal street racer / Brikulóza | +150% prying, +5% damage |
| Aleš legendary skillz (`engineer`) | 14 Kešulky | Lahve od piva | Unlimited god mode on / 4 setupy / Sony s rejzí | Starts with Vyhazovač na baterky, −10% auto cooldown |
| Real producer (`producer`) | free | Maschine | Brucelee / Crossfader / Party without me | Guarded directional flurry, alternating crowd impulses and a remote frost speaker |

Every class includes **4: Ban zóna** and **5: Valhalla**. Ban zóna gathers, slows, interrupts and damages nearby enemies for five seconds. Valhalla gives 1.6 seconds of protection and an immediate damaging knockback pulse: a brief window to pry, reposition or escape. Heroic Ragnarok boosts main-gun fire rate and pierce; it has no ammo interaction.

All five skills have separate cooldowns and three run-upgrade ranks through level-up cards and the shop. Rank previews now describe the actual skill-specific effects: damage or fire-rate bonus, −12% base cooldown and +15% duration/protection where applicable. Movement skills do not claim longer travel, and instantaneous blasts do not claim longer duration. The HUD shows each key, readiness, remaining cooldown and rank. Pause freezes cooldowns and persistent effects; inactive/dead players release fields and buffs. Overlapping shields and cooldown/exposure effects retain independent ownership.

**Guided start** (Settings, on by default) introduces the game in steps instead of all at once:

- **Skills by level:** a run starts with skill 1 only. Skills 2, 3, 4 (Ban zóna) and 5 (Valhalla) unlock at levels 2, 3, 5 and 7, with an unlocked-skill callout and a tip. The HUD shows a dim teaser of the next skill with its unlock level; locked skills cannot be cast and do not appear as level-up cards. Shop cards show their unlock level.
- **Upgrade types by level:** early level-ups offer auto weapons, stats and unlocked skill masteries; perks join at level 3 and gun mods at level 5.
- **First fight:** the calm arrival ends at route choice. Enemies wait until you physically reach your selected venue.
- **One-time tips:** cards above the skill bar explain movement, arena sets, DROP, skills, optional machine smashing, low health and combos. A tip counts as seen after 2 s on screen (an interrupted tip comes back) and is remembered in the profile; Settings → *Show tips again* resets them.
- **Footer:** the controls line lists only what you have unlocked.

Turning Guided start off gives experienced players all five skills and every upgrade type from the first second, with no tips. Arena set counts and arrival calms are stage design and apply either way.

**Skill combos** (every class carries Ban zóna and Valhalla). A named callout appears below the crosshair:

- **POWNED** (`crush`): any skill blast reaching your active Ban zóna deals +60%, including thrown charges, barrages, movement landings, turret drops and defensive pulses.
- **PERMABAN** (`collapse`): casting Valhalla within 6 m of the zone's edge detonates it for 70 base damage, +10% per held enemy (up to +150%), and flings the pack outward.
- **LAST TIME KRATOS** (`ram`): dash or grapple while another skill protects you to slam a 5.5 m, 45-damage shockwave at landing. It can POWNED too.

**One primary, one trigger:** no main-weapon melee, magazines, reserves, reloads, ammunition pickups, charged secondaries or cross-charge meters. Every primary is an original improvised model held by a fingerless glove: bottles, rebar, vinyl, pigeons, molotovs, hairspray flame, speaker beats, hollow bricks or curd. Choose a starting blueprint in the Workshop, change weapons with the wheel or free shop selector, and keep purchased primary-mod ranks without compounding them. The crowbar is a close-range salvage tool, not a combat weapon. Passive auto weapons remain separate level-up picks.

| Weapon | Main cadence | Role |
| --- | --- | --- |
| Lahve od piva (`pulse`) | 0.09 s | Rapid thrown bottles, pierces 1 |
| Rail | 0.45 s | Heavy piercing rifle |
| Scatter | 0.38 s | Seven-pellet shotgun |
| Minigun | 0.032 s after 0.2 s spin-up | Sustained high-rate fire |
| Autocannon | 0.19 s | Explosive shells |
| Flamethrower | 0.045 s | Short-range piercing flame cone |
| Maschine | 0.42 s | Six close-range shock pellets, chains into nearby victims |
| Cihlomet | 0.46 s | Three narrow brick projectiles, pierces 1, heavy knockback |
| Tvarohomet | 0.34 s | Pressurized curd, 2.8 m frost splash with real slowdown |

**Survival loot:** every third regular kill earns that victim's XP gem; skipped XP is not silently merged into a later gem. Magnets drop every 120 regular kills, and repair kits have a 0.4% chance. Bosses retain their authored XP and award a magnet; the stage-clear reward is one Void Shard. Magnets attract all currently loose XP, including moving gems, and award XP only on arrival. Later gems stay loose. Repair kits heal up to 15 HP and remain at full health. There are no ammunition drops.

**Timed repair supply:** a nearby repair pack lands every 50 gameplay seconds, with at most two separated waiting packs independent of enemy loot. Placement checks obstacles, ground and walkable routes; small raised decks use a nearer fallback rather than dropping beyond a cliff. Timers stop during pause and after the player becomes inactive. The radar marks magnets and both ordinary and timed repairs. Continue refills health.

**Damage and feedback:** kinetic deals direct damage; fire ignites for four burn ticks over two seconds; frost slows movement to 55% for 1.8 seconds; shock chains 40% damage to up to three nearby enemies. Critical and kill numbers report actual health removed, not overkill. Same-type hits within 0.9 m and 0.2 s merge into one number (a crit or kill upgrades it), and new numbers stack above ones they would overlap; crits carry a crit icon.

**Gun feel:** stronger damping and shorter weapon travel keep recoil gentle. Camera pitch/yaw/roll recovers on a bounded spring, with no firing FOV punch; main-gun rays use the head's stable aim, not the visually recoiling camera. Models slide into the raised pose on swaps, and Scatter cycles its pump after shots. Muzzle flashes vary, tracers fade and pooled casings eject from authored ports. The crosshair blooms without changing aim. Fractional cooldown overshoot preserves boosted cadence above 60 shots/s; idle time and long hitches cannot bank an unbounded burst.

**Precision hits (source changes, not yet packaged):** main-gun rays through a visible head or exposed weak point earn a guaranteed ×3 critical hit without a luck perk. Ordinary rolled body crits deal ×2. Precision uses the current crit-damage factor plus one base-damage unit; it never multiplies a random crit again. **Štěstí z automatu** improves both rolled crits and aimed hits. Each pierced victim is judged separately; headshots do not amplify splash, burns or chained damage. Weak volumes follow enemy yaw, scale and feet height and cannot be hit through a world blocker. Kill numbers retain actual damage; critical numbers show an icon.

Base health and combat roles are listed above; schedule multipliers still apply. These values are not a long-session balance certification.

**Gunplay research:** Derek Mattson's [GDC 2024 *A Second Shot*](https://media.gdcvault.com/gdc2024/Slides/GDC+slide+presentations/Mattson_Derek_ASecondShot_Notes.pdf) emphasizes reliable target reactions and coherent presentation. Contact feedback precedes restrained camera effects; recoil never drifts aim, and the horde simulation has no global hit-stop. Nine original Blender-authored junk guns share one gloved grip rig. Static parts are batched by material; pumps, rotary parts and pooled thrown projectiles stay movable. The quote additions include drum pads and a speaker cabinet, a hollow-brick feeder and a dairy tub with a pressure pump.

**STYLE timing:** each credited kill transaction refreshes STYLE. Up to 10 STYLE, a **six-second grace period** applies and idle decay removes **10% (rounded up, at least one point) every 1.5 seconds**. From 10 to 100 STYLE both timers tighten linearly: at 100+, grace is **3 seconds** and each 10% decay step arrives after **0.45 seconds**. The damage bonus scales linearly to its +40% cap at 100 STYLE. Misses and nonlethal hits neither extend nor erase it; actual nonlethal player damage costs two points, blocked damage costs none, and death clears it. Pause, arrival, empty breathers, route choice and travel freeze decay. The crosshair shows readable action labels, fractured STYLE, DROP charge and the beat cue. The compact HUD separates vitals, all five skills and both gun names.

**Typography:** Rubik Glitch gives titles, actions, card names, kills, criticals and the combo a torn rave-flyer look. Barlow Semi Condensed keeps descriptions, settings, small HUD labels and music readouts compact and readable. Both bundled fonts cover Czech diacritics.

**Auto weapons** (up to four, each to level 5): Lítající pager, Zvukovka na doraz, Ohňostroj z pavlače, Zkrat v mixáku, Cirkulárka z bazaru, Vyhazovač na baterky, Ledovej Fernet and Rachejtle z tržnice. Their existing weapon geometry and behavior remain; all names, rank descriptions and one-time max-level upgrades use Czech scene fiction.

**Perks** (each to level 3, no auto-weapon slot): Domino v herně (exploding kills), Panák za účet (heal on kills), Panika před zavíračkou (fire rate when hurt), Lokty na baru (retaliation), Štěstí z automatu (critical hits), Plná rychlost (moving damage), Šacování kapes (bonus Cigára), Ještě jedno kolo (survive lethal damage).

**Primary mods:** Rychlej crossfader gives the first shot within 1.5 s of a wheel swap +75% damage, spent even on a miss; Přes celou pavlač gives direct hits beyond 15 m +40%; Poslední účet gives direct hits on enemies already below 35% health +60%. They can be combined and use no auto-weapon slots.

**Stat and permanent upgrades:** all 45 XP upgrade resources and eight permanent talents have Czech names and accurate effect/rank text. Shop/workshop categories, previews, prices, locked/sold/capped states and mastery cards use the same fiction. Modifiers improve damage, cadence, pierce, speed, health, regeneration, protection, pickup radius, area, cooldown, XP, extra auto-projectiles, prying and loot; internal IDs remain stable for saves.

### Ten quote-selection rounds

Ten independent rounds sampled ten random non-empty lines from `hlasky.txt`.
Up to five draws were allowed per round; every first draw supplied a usable
concept, so the completed selection sampled 100 lines with no retries.
Three guns, three active skills and four ranked upgrades are actual playable
content, not a future-content list. The free **Real producer** class carries the
three new skills on physical keys **1–3**, plus the existing Ban zóna/Valhalla
on **4–5**. Guided start still reveals slots by level.

| Round | Source line | Selected quote | Playable result |
| --- | --- | --- | --- |
| 1 | 10 | Brucelee imuni vuci vsemu | Brucelee: 1.1 s source-owned guard and four aimed cone strikes; mastery adds strikes, damage and guard time |
| 2 | 349 | Ja pres maschine jsem real producer to je vis hard to na kompu to je izi delat | Maschine shock gun; the new class starts with it |
| 3 | 407 | Nemakacenko | Nemakačenko: per rank +1.5 m XP pickup, −10% base auto cooldown |
| 4 | 32 | Cihlomet | Piercing three-brick volley with visible hollow bricks |
| 5 | 98 | Delaj mam vytazeny gramce uplne bych vam ukazal co je crossfader | Crossfader: six alternating pull/push pulses over 3 s, real damage and turntables; mastery adds pulses and duration |
| 6 | 207 | Zase krasne party without me | One remotely placed speaker pulses frost for 8 s; it remains when you walk away |
| 7 | 260 | Tartarus se uzavira musis rychle minuta no mercy pak uz za rok gl | Tartarus: per rank +8% damage, +1 pierce, −8 maximum HP |
| 8 | 68 | Tvaroh | Tvarohomet: visible white curd projectiles and slowing splash |
| 9 | 54 | Jaj krajic chleba | Krajíc chleba: per rank +15 maximum HP, +0.4 HP/s regeneration, −3% movement |
| 10 | 25 | Rave | Rave: per rank +12% primary fire rate and +8% effect area |

All four passive additions cap at three ranks and enter the normal level-up
pool. New guns have Workshop recipes and join wheel/shop selection; primary
mod ranks survive swaps. New skill hits exclude solid walls and other floors.
Speaker placement validates floor, range, footprint and sight; a rejected
placement spends no cooldown. Pause freezes effects and recharge. Cancellation
ends future pulses and hides the pooled speaker; already applied native frost
expires normally without erasing another source's slow.


## Machine salvage and progression

Wall-mounted banks of worn gambling, cigarette and jackpot machines replace
crystal formations. Each seeded bank has **7–9 independently breakable front
compartments**, real matching triangle colliders, permanent trays/backing and a
labelled frame. Reels and coin slots identify gambling machines; rows of packs
identify cigarette machines; jackpot panels show **777**.

**Smash and grab.** Aim close at a live compartment and press F. The
fingerless-gloved hand swings an original hooked steel crowbar and opens that
compartment immediately. Holding F cannot repeat payouts; release and press again for another door. Doors pull
outward with their colliders before breaking, then release their allocated loot
and lose their harvestable collider. Empty housing remains visible and cannot
yield again. Guns and abilities do not salvage; a wall or out-of-range aim
prevents tool contact.

The conserved pre-rolled bank budget remains **14–20 Drobné**, **5–8 Cigára**
or **one rare Kešulky**. Rare banks may have zero-yield outer compartments.
Optional stock uses clear supported venue faces with the 11–18 live-bank cap and 35–50 s respawn intervals. Empty housings reserve
their footprints for the remainder of the level. Payouts are the actual emitted
compartment units; opening machines is never required to finish an arena.
The authored guarded-machine encounter remains a separate optional event.

Czech feedback shows currency type and compartments remaining. Metal chips,
sparks, clanks and crowbar motion replace drill hum and crystal effects.

Coin, paper cigarette-pack and token pickups use the existing pooled collection
and banking path. The fractal crystal shader, rotating history-texture halo,
spinning-drill exports and their obsolete assets are removed, not retained as
an alternative mining mode.


- **Drobné** (`gold`): banked; buys round-shop stock, base crafting and permanent Armory upgrades.
- **Kešulky** (`shard`): banked, rare; each completed level awards one; unlocks classes and pays for advanced shop/base recipes and ability upgrades.
- **Cigára** (`crystal`): banked, fills the supply meter for free upgrade picks and powers turret consoles (10 run Cigára each).

All three currencies move into your profile at 100% on stage clear (loose loot is swept up), and at 50% on death or abandonment. Cigára spent on consoles is removed before banking.

**Round shop:** clearing a level pauses gameplay and opens the exchange. **Every purchase is permanent**: weapon mods, suit ranks and per-class skill ranks are saved in the profile and re-applied at the start of every later run, within the same caps. The primary panel shows both upgraded equipped guns and a free selector with separate replace-A/replace-B buttons. Invalid replacements never lose the partner or compound shared mods. Five skill cards show ranks, effects and prices; guided progression locks unavailable skills. Random stock has four primary mods and two protection/health/power offers in scrollable tabs. Rerolls replace only unsold stock and cost 3 Drobné + 1 Cigára more after each refresh. Sold, capped or unaffordable purchases do not debit currency. The footer picks the next round's level and difficulty, or goes home. `RoundShop.CATALOG` owns prices, caps and previews.

**Persistent base:** craft protection, starting-primary blueprints and one gadget, plus automatically applied perks and ranked talents. Equip one protection set, one starting primary and one gadget; resetting the primary restores the class default. Eight five-level permanent talents are Trénink u výčepu, Škola disrespectu, Útěk před účtem, Velká igelitka, Páka z bazaru, Veksláckej čuch, DJ legenda and Kožená bunda. Records track best score, time, kills, level, runs, victories and the most rounds cleared in one run; the last run also names its final level and difficulty. `user://profile.json` stores them with the run setup and the permanent shop build. Stable IDs preserve currencies, unlocks, crafting, upgrades, records and settings; older gear migrates to a single primary/gadget without restoring deleted melee blueprints.

## Music

Every **new game or run restart** generates two fresh 32-bar scores on background threads: **125 BPM techno** for ordinary gameplay and **180, 186, 192 or 198 BPM hardtek** for the final boss. Techno uses the purchased `TECHNO_ESS` selection: one matched C minor, Eb minor or Gb minor bass/synth/arp/atmosphere set, plus kick, clap, hats and a no-kick drum groove. Phrases retain their source key and tempo; seeded sections add musical rests and variation without changing samples every bar. Hardtek uses the existing PROTOKSEED kick/drum/303/ambience/FX pool with synthesized acid/harmony/percussion and original Luďas vocal chops. Both banks are selection pools between runs, not playlists within a run. Private composition RNG never consumes gameplay RNG. All eight stems of each score share its exact rounded PCM grid. Level changes retain both scores; a new run cancels both old compositions and rejects stale worker results.

The techno kick stays present during exploration. Nearby/total horde pressure, actual kill STYLE, momentum, health loss and low-health danger bring in stronger layers; the stronger of crowd pressure and STYLE drive wins. A fresh crowbar swing adds brief salvage drive. A real boss arrival crossfades the whole score to hardtek on the active track's next bar; boss death crossfades back to the same techno score. DROP timing follows the active playback grid, including the tempo change. Kill bursts, DROP shots, salvage openings and danger queue priority/cooldown-bounded vocal accents on beats. Backing gain stays steady through weapon effects, spoken reactions, accents, milestone stingers and pause; spoken Luďas reactions silence only hardtek's remix vocal layer. Pause cancels queued gameplay accents and disables gameplay beat timing, while music keeps playing. Reactive layer changes and track crossfades remain. The 90 BPM menu motif and milestone stingers remain. Music, SFX and master volumes are adjustable in Settings; master clipping protection is unchanged.

The panel below the radar switches between **TECHNO** and **HARDTEK**, naming the active score's eight stems plus the live gameplay accent. Its header identifies the current mix. A lit dot means that part is routed into the mix; its bar follows the player's actual mono PCM16 audio, so phrase/vocal rests stay silent rather than becoming a fake equalizer. Meters use a 46 ms source window at 20 Hz, adjusted for playback pitch/output latency, track fades, vocal gating and Music/Master attenuation or mute. They are **pre-FX**: reverb tails and the master limiter are not attributed to individual stems.

The panel shows the mix ID, key, BPM, beat pulses, current bar out of 32, active accents/stingers, spoken-vocal priority, full-volume pause playback, mute and score-generation progress. It continues updating during pause and uses a shorter layout below 660 px viewport height. A fresh crowbar swing feeds salvage drive every gameplay frame, so the brief smash cannot disappear between crowd-intensity checks.

To rebuild the sample banks, run `python3 tools/techno_samples.py "/path/to/TECHNO_ESS"` and `python3 tools/music_samples.py "/path/to/PROTOKSEED SAMPLE PACK"` (requires NumPy), then import with Godot. The generated catalogs under `assets/audio/techno/` and `assets/audio/protokseed/` explicitly preload every selected recording for exported builds and record source paths, SHA256, roles, labelled roots and exact loop grids. Conversion keeps whole recordings as antialiased mono PCM16/22050. The techno bank contains 56 WAVs and 9,544,656 PCM bytes. Purchase does not establish redistribution permission; sampled-audio terms remain unverified in `CREDITS.md`.

## Architecture and reskinning

Gameplay code reads data resources and draws through replaceable scenes and materials. It never refers to mesh names, so a reskin replaces art without touching controllers.

- **Autoloads:** `Profile` (`scripts/meta/profile.gd`) holds persistent currency, class unlocks, Armory levels, crafting ranks, equipped armor/primary/gadget, records and settings. Multi-mineral payments validate the entire cost before debiting. `Music` (`scripts/audio/music_director.gd`) uses persistent render workers, separate techno/hardtek `MusicComposition`s per run and a once-decoded, shared immutable sample bank (`music_samples.gd`). New-run generations cancel obsolete work and reject stale callbacks; main-thread gameplay changes gains, schedules recorded accents and switches tracks on bar boundaries without rendering audio samples. Beat timing and `MusicLayers` (`scripts/ui/music_layers.gd`) follow the active score; a caller-owned `Music.MixMeter` snapshot supplies bounded, read-only PCM metering. Buses are defined in `default_bus_layout.tres`. Sample preparation/provenance is in `tools/music_samples.py` and `tools/techno_samples.py`; sampled-audio terms are separate from CC0 art in `CREDITS.md`.
- **Stats and economy:** `RunState` combines class/Armory/crafted modifiers and level-up stacks, owns one shared `WeaponBuild` plus `secondary_primary_source`, and stores five ability ranks. `equip_pair` validates and commits a distinct available pair atomically; `swap_equipped` only toggles those sources. Immutable authored snapshots and shared gadget/ranks prevent compounding. `WeaponDraftScreen` presents both effective previews without mutating the equipped pair before confirmation. `RoundShop` purchases stock and individual skills; `CraftingCatalog` supplies persistent recipes.
- **Classes and abilities:** `data/classes/*.tres` and `roster.tres` define stats, class unlock cost, `primary_weapon` and five `ability_scenes`. `ActiveAbility` (`scripts/abilities/`, scenes in `scenes/abilities/`) owns slot-specific cooldowns and shared rank scaling. Buffs, exposure zones and protection are source-owned, so one ending skill cannot remove another's effect.
- **Main guns:** `data/weapons/*.tres` (`WeaponDefinition`: damage type, damage, cadence, pellets, spread, pierce, recoil, knockback, explosion, spin-up and icon) reference `WeaponView` scenes in `scenes/weapons/`, instancing the original `assets/guns/*.glb` meshes. Rebuild with `blender -b --python tools/guns/build_guns.py`, then import with the project Godot executable. No image-generation access is required. `ArenaPlayer` owns one trigger, draw lock, combo, gun mods and camera spring; hit/tracer/casing visuals remain pooled.
- **Auto weapons, perks and gun mods:** `AutoWeapon` subclasses in `scripts/weapons/auto/` and `PerkEffect` subclasses in `scripts/perks/` use `UpgradeDefinition`s (STAT, WEAPON, OVERCLOCK, PERK, GUN_MOD) in `data/upgrades/pool.tres`. ABILITY offers are generated for the actual five class slots. `AutoWeaponRack` owns passive auto weapons and perks; perks, primary mods and ability ranks do not consume its four slots.
- **Horde:** `scripts/horde/horde.gd` runs a data-oriented simulation with one MultiMesh per enemy type, a shared flow field, weapon queries, `slow()`, material FX and contact tuning. The flow field avoids obstacles and treats cliffs as walls; it routes to the player's level over ramps. Each enemy has a feet height taken from the stage heightfield: it snaps up ramps, falls off ledges and never climbs a step over 0.3 m. Hit tests, blasts, projectiles and contact damage all use that height. Hallucination stats/animations are in `data/enemies/*.tres`, retaining `robot_*`/`alien_*` as internal slot IDs. Six CC0 humans and five original delirium rigs bake into `assets/monsters/`; `shaders/horde_enemy_vat.gdshader` animates the crowd from position/normal textures and per-instance clip state. `tools/vat/README.md` covers source generation, baking and licenses. `Faction.MACHINE`/`FLESH` select sparks or splatter independently of slot IDs.

  Enemy `weak_spot_offset` and `weak_spot_radius` author a head/core sphere in model-space metres before `model_scale` and yaw; radius zero disables precision hits. Type-level offsets, squared radii and upper hit bounds are cached once, not allocated per shot.

  Human enemies share a 5 × 5 face atlas (`tools/vat/faces/atlas.png`). `HordeEnemyDefinition.face_atlas`, `face_first` and `face_count` choose which cells an enemy draws from; `horde_enemy_vat.gdshader` offsets the Face surface's UV by the per-instance phase, so one mesh and one draw call serve every face. `grime` (0–1) darkens and stains flat surfaces from model-space position in `horde_enemy_common.gdshaderinc`. Homeless enemies draw cells 0–19 (twelve original characters plus eight invented archetypes: hood, taped glasses, bandana, flat cap, eyepatch, jowls, smeared eyeliner, swollen face), Vekslák 20–21, Vyhazovač 21–22 and Pan Herna 23. The generator reads no image file; the archetypes are hand-designed from broad street-look categories, recombined so none mirrors any reference, exaggerated, and the whole atlas is quantized to 72 flat colours so nothing reads as photographic.

  Fusion uses fixed per-slot constituent/identity storage and bounded grid scans,
  not per-enemy nodes or all-pairs checks. `alive_count` counts bodies;
  `population_count` counts represented lives. Cached body dimensions drive
  rendering, movement, hit cylinders, weak spots, splash and contact together.
  `HordeFx` batches mega crowns and pools gathering sparks. Slot generations are
  opaque life IDs: absorption/recycling invalidates them immediately.
- **Salvage:** `ResourceDefinition` data lives in `data/resources/`; internal deposit types remain in `data/resources/deposits/`. `SlotBankGeometry` builds the gold/shard banks of three fruit machines (backlit glass, reel drums, button deck, cash-box doors) and `DepositGeometry` the cigarette machine; both give every door its exact triangle collider. Reels, LEDs and lamps are shader functions of the paused gameplay clock (`shaders/slot_machine.gdshaderinc`); their art is generated by `tools/automat_art.py` into `assets/automat/`. `MineralDeposit` owns health, hinged opening transforms, permanent housing and conserved integer loot. `DepositField` retains seeded site/stock placement. `MiningTool` owns crowbar contact/leverage; `MiningFeedback` draws mechanical latch markers and Czech telemetry. `ResourcePickupSet` pools coin/token meshes and paper packs using `shaders/cigarette_pack.gdshader`. Mining-named APIs/input IDs remain intentional internals; the obsolete crystal/history shaders are removed.
- **Survival pickups:** `scripts/progression/pickup_field.gd` pools XP, magnets, repairs and a separate two-pack timed repair supply set. `PickupGeometry` builds their faceted silhouettes once at setup. Kill thresholds and supply interval are exports; grounded placement uses the horde heightfield, and supply routes reject obstacles and cliffs. Collection never overwrites the persistent profile. The radar reads the same live pickup pools.
- **Procedural levels:** `data/stages/*.tres` configure play area, `layout_theme`, `cover_count`, `overlook_count`, `outcrop_count`, `quest_scale` and `SpawnSchedule`. `ProceduralWorld` (`scripts/world/procedural_world.gd`, `scenes/levels/procedural.tscn`) is configured with the stage and seed before entering the tree. It carves a 2 m grid identical to the horde grid: the theme plan places rooms, corridors join them (spanning tree plus loops, or the Reactor's spokes and chords), and alcoves are added. Venue wall rings are reserved before carving; connectors aim at explicit street porches and entrances. Ring cores are refilled and cells unreachable from spawn are pruned. Remaining rock merges greedily into exact axis-aligned blocks under `Obstacles`; `mining_sites` instead come from supported, resource-compatible wall bays inside playable venues. Overlook decks and tilted ramp boxes live under `Elevation`, which the horde rasterises into its walkable heightfield. Set pieces, pillars and cover check carved floor plus margins, so passages and machine standing room stay open. `layout_open` is public for the radar. Original authored worlds remain explicit lab fixtures with their own play areas.
- **Prague rooms and underground:** `scripts/world/prague_layout.gd` reserves the station, passage, WC and stair footprints before street carving. `ProceduralWorld` publishes `layout_level`, `layout_roofed`, `layout_walkable`, `stairs` and `kit_sites`; venue sites carry stable ownership IDs, reserved machine zones and deterministic `quote_signs` records. `Ground` contains exact street/passage floor rectangles. `PragueKits` and `KitTarget` (`scripts/world/kits/`) batch palette furniture, printed signs and venue floors, with bounded local lights and real colliders. `venue_floor.gdshader` reads each floor's finish and palette from normalized instance channels, so all four finish types and three variants use one shared MultiMesh batch. Hlášky boards reuse the palette and fixed text labels, capped at 64 kit labels per world; their private RNG and cached source do not change gameplay RNG order. Horde obstacle intervals follow pitched box planes at the queried position, so stair roofs do not close the upper ramp. Spawning, radar, supplies, stashes, salvage pickups and auto-weapon floor effects consume floor/roof metadata. The heightfield remains single-layer per XZ.
- **Shop venues:** `ShopVenue` resources (`scripts/data/shop_venue.gd`, `data/venues/*.tres`, listed in `data/venues/catalog.tres`) carry the shop name, sign text, tagline, window goods and colours. `ProceduralWorld` builds storefronts ~4 physics frames after the world, on wall stretches a physics query finds clear, through the batched visual path (`shaders/venue_front.gdshader`) with a private RNG seeded from the stage seed, so layouts and the global RNG are untouched. The round shop header reads the sector's first seeded venue.
- **Arena flow:** routed `HordeDirector` runs ARRIVAL/ROUTE/TRAVEL/BUILD/PEAK/CLEANUP/RECOVERY, then final BOSS_PENDING/BOSS/CLEANUP/CLEAR, from physical `ProceduralWorld.combat_venues` and finite authored wave budgets. `choose_route` accepts a paused modal commit but waits for physical arrival before admitting safely placed bodies through local role lanes; no whole-district fallback. The last venue stays open through bounded safe boss-admission retries and combat. Completion is once-only and requires the scheduled boss's actual death, zero live bodies/represented lives and resolved damaging projectiles/specialist effects. `ArenaGame` defers it, rejects stale directors/hordes and duplicate signals, preserves earned choices and death precedence, then opens the shop. Primary captures and explicit `Horde.action_killed` scopes feed `ArenaPlayer.arena_scored`; callback/ambient deaths cannot steal action credit. Authored fixtures retain automatic finite sets and explicit boss release; an early boss death never bypasses their remaining crowds.
- **Skill combos:** `ActiveAbility.combo_blast_damage()` applies POWNED (`crush`) against `ArenaPlayer.active_gravity_well()`. Existing radial attacks use it through `blast()`; the three producer attacks share it before their wall/floor-filtered native hits. `arrive()` is called at movement-skill landings for LAST TIME KRATOS (`ram`) via `is_shielded_by_other()`; Valhalla calls `GravityWell.collapse()` for PERMABAN (`collapse`). `ArenaPlayer.ability_combo` drives the HUD callout (rate-limited per combo), while `combo_counts` records every trigger.
- **Luďas's voice:** `LudasVoice` (`scripts/audio/ludas_voice.gd`, owned by `ArenaGame` so it survives stage loads) plays recorded reactions from `assets/voice/ludas/`: arrival, kill bursts (12 kills within 1.5 s), combos and DROP shots, a skill unlock (*Jaj… krajíc… chleba* in sequence), dropping below 40% health, healing, stage clear and death. One line plays at a time; a higher-priority reaction interrupts a lower one, and each reaction has its own cooldown. The reskin plan lives in `docs/ludas/BIBLE.md`.
- **UI:** `scenes/ui/hud.tscn` has currencies/supply, score/record/fight/venue, hostiles/kills, vitals, both gun names, five numbered skills and a close-range F smash prompt. `CombatFeedback` draws action labels, STYLE, DROP and the beat cue. Responsive compact bounds prevent the bottom-row overlap. `WeaponDraftScreen` and `RouteChoiceScreen` own choice input; Game owns pause, validation and resume. Numeric choice inputs are consumed before combat resumes. There is no ammo/level timer.
- **Guided start:** `RunState.start_guided()` sets `unlocked_abilities` from `ABILITY_UNLOCK_LEVELS` and emits `ability_unlocked` as levels are gained; `can_upgrade_ability()` and `_is_eligible()` gate skills, perks and gun mods. `Tutor` (`scripts/ui/tutor.gd`) queues one-time tips stored in `Profile` (`seen_tips`, `guided_start` setting). `StageDefinition.arena_encounters` and `spawn_grace` (`HordeDirector.grace`) size each arena and its arrival.
- **Pixel-art icons:** every upgrade, gun, class, ability, Armory upgrade, mineral, workshop recipe, shop item and HUD glyph has a 16 × 16 icon in `assets/icons/<group>/<id>.png`. They are authored as text grids in `tools/icons/art_*.py` on the shared palette in `tools/icons/pixel.py` (automatic dark outline). Data resources reference their icon through `icon` exports; code-only concepts use `GameIcons.lookup(group, id)` (`scripts/ui/game_icons.gd`), and `CraftRecipe.display_icon()` resolves a recipe's payload icon. Show them nearest-filtered at 2×, 3× or 4× (`GameIcons.rect`). After editing art, run `make icons` (renders, then imports); `python3 tools/icons/build.py --group <g> --preview /tmp/icons` also writes a labelled 6× preview sheet.
- **Run flow:** `RunConfig` (`scripts/meta/run_config.gd`) is the level catalogue plus presets, tuning ranges and the difficulty tier; `build_stage()` returns a tuned copy of a `StageDefinition` and its `SpawnSchedule`. `RunSetupScreen` edits it and `Profile.run_config` persists it. `ArenaGame` builds each round under a fresh `Round` from `active_stage`, applies `ArenaPlayer.incoming_damage_scale`, re-applies `Profile.apply_shop_build()` at run start, carries score, both equipped guns, the primary build and five skill ranks between rounds, and handles level-up, pause, shop, next round and return to base. It banks all three currencies into `Profile`, records runs and drives music from crowd density and STYLE.

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
| `weapons` | each of the nine main guns firing | visual review |
| `recoil` | 6-frame strips after one rail shot and during minigun fire | camera kicks and recovers, sustained kick stays capped, player aim unchanged |
| `guns` | side/three-quarter views of all nine Blender models and their flying projectile templates | visual review |
| `gunplay` | sustained fire, kill STYLE, two-gun swaps, double jump, slide and paused input | real damage beyond a burst, stable aim, hit-spam exclusion, miss/decay/recovery timing, drafted partner swaps without compounding ranks, one air jump, collider shrink/headroom, sliding fire, ceiling/wall bounds and fresh resumed actions |
| `combo_pressure` | kill-earned hot STYLE, sensory drive and cooldown | actual primary kills only, finite grace and gradual decay, recovery freeze, nonlethal-hit exclusion, hallucination ceiling, soundtrack drive and banked score/DROP retention |
| `rhythm_combo` | earned DROP, compact HUD and real beat-timed heavy shots | primary-kill charge, single bank, offbeat/held/fast/muted/stopped retention, early-wrap ×10 spend, return to baseline, precision, actual overkill, pause and DROP-chain self-charge exclusion |
| `quotes` | new gun impacts and ranked passive builds | shock chaining, brick penetration/knockback, frost splash, Workshop crafting/equipping, retained primary ranks, passive caps, actual health cost/clamping and regeneration |
| `producer` | guarded cone strikes, inward/outward turntable waves and a remote speaker | physical 1–3, directional/wall/deck exclusions, guard expiry, ranked strikes, opposite native impulses, pause, remote persistence, rejected placement and cancellation |
| `tempo` | real held-input firing for nine guns and boosted Minigun | actual cadence above 60 shots/s, stable aim, gentle recoil and bounded hitch catch-up |
| `pressure` | finite stage directors, live sets and scarce loot | arrival calm, small admissions, pause/inactive freezes, caps, survivor cleanup, empty recovery, exact finite budgets, blocked placement retention, sparse XP/magnet boundaries, repair RNG and supply timers |
| `fusion` | dense-pack grow-in, mega/ordinary motion strips and actual primary shots | no healing or early rewards, bounded same-species membership, director cap preservation, enlarged precision hits, per-member kills/XP/gear streaks, protected identities, statuses, player proximity and pause |
| `arena` | linked venue choices, primary scoring, a level shop and a harder chosen next round | real distinct local fights, actual survivor cleanup, unopened optional cabinets, earned-choice input, duplicate/stale clear rejection, tier-scaled next level, carried score and the recorded level/tier |
| `routes` | initial draft, route choice and actual doorway traversal at 960×600 | duplicate refusal, pending/cancel atomicity, real keyboard confirmation, break replacement, physical arrival starts the selected fight, combat cannot reopen draft and HUD regions do not overlap |
| `pinball` | actual RMB boot, returns, slide/stomp, four weapon combos and keg | kill-only action credit, bounded recovery, parry/no-farm, heavy/ceiling constraints, AIR MAIL, exact-once bursts, ambient exclusions and pause/death release gates |
| `horde_pinball` | native launch/shatter/return/keg/hype and enemy counters | wall/body collision, precise ledger, perk reach/homing/refreeze, one-shot kegs, aura health conservation, blocking/locked shove and committed bottle splash |
| `finishers` | original-body gold daze, aimed F prompt, four leaping execution/death strips and captured SFX WAVs | threshold/HP conservation, expiry/resumption, once-per-life, boss/overkill/ambient exclusions, real forward/airborne travel, long-range limit, wall/ceiling interruption, no correction warp or aim steering, floor/body/generation constraints, exact-once credit, shared recovery budget, simultaneous-fire priority, pause pixels, stale/dead cancellation, no double salvage, all four moves per bag, no consecutive repeats and routed launch PCM before contact |
| `hallucinations` | native recursive heads/limbs on human and mouse megas, inward head-cycle strips, STYLE-driven peripheral feedback-loop vision and paused settings | actual primary kills reaching the 65% ceiling, actual keyboard ceiling changes, 65%/100% world-only feedback, clear main precision head/center/HUD, frozen drive/anatomy/feedback motion, exact off restoration and real precision damage with STYLE bonus |
| `hallucination_modes` | actual keyboard preset selection, six world/anatomy views, four-phase head strips and spatial floors in all three stages and six indoor types | compact settings reachability, clear centre/HUD, STYLE-driven ceiling, pause and exact off restoration, real precision-shot damage, independently moving floor patterns with unchanged physical floor |
| `levels` | first-person, overhead and deck views of all three themes, repeated furnished venues, station halls, public/portable WCs and hlášky boards | seeded repeatability/variation, two-door combat venues with indoor/outdoor routes and headroom, actual held-W entry, slide escape and double-jump deck shortcut, one-press F bank opening, compatible reachable optional loot, fitted whole-source quote text, connected routes/stairs and actual descent/enemy following |
| `pickups` | repair kits, distant XP vacuum and timed repair supplies | actual healing, full-health preservation, exact XP/overflow conservation, later loose gems, supply cap, pause/inactive timers and raised-deck fallback |
| `abilities` | every class's five physical number keys and actual effects | damage, movement, healing, source-owned buffs, overlapping shields, pause/death cleanup, rank-scaled damage/cooldown/protection |
| `combos` | POWNED, PERMABAN and LAST TIME KRATOS through physical keys | exact +60% crush versus a plain blast, real thrown charge into a well, out-of-reach control, collapse burst scaling with held enemies, dash-without-shield control and ram damage on arrival |
| `onboarding` | guided arrival, an unlocked-skill callout/tip and locked shop cards | one skill plus teaser, footer, locked key, enemy-free arena calm with a real director, no early perks/gun mods/locked skills, level-gated unlocks and working key, combo tip at level 7, tips seen once, Guided start off shows everything |
| `voice` | Luďas's recorded reactions | arrival, kill-burst trigger and cooldown, skill-unlock sequence order and interruption, hurt growl with cooldown, heal gulp, death outranking everything |
| `music` | real techno PCM/HUD, boss hardtek and return, speech, weapon FX, cues, pause, mute and rapid restarts | purchased waveform correlation, real phrase notes/rests, active 125/faster BPM and DROP clocks, no backing duck, vocal gating, live paused HUD/audio, Music/Master mute, fresh playable scores with stale-render rejection and both-score persistence across levels |
| `boss` | final crowd, same-venue boss, real rail hits, health/phase and earned shop in all three levels | no clear before actual boss death, survivors and damaging hazards block clear, safe blocked-admission retries, pause/inactive freezes, duplicate/stale refusal, explicit fixture release and simultaneous-death precedence |
| `boss_patterns` | ram lanes, mortar footprints/impacts and teal recovery | real damage and movement dodges, locked targets, cover/height/radius boundaries, +50% recovery, stagger interruption, pause and death/menu/node-removal cancellation |
| `armor` | front shield/rear core, rotated markers and independent auto guns | real armor/precision arc boundaries, actual source direction, tag ordering, mixed splash, burn potency, finite stun/turning, slot reuse and reserved admission |
| `encounter` | authored guarded machine, prying under pressure and earned reward | real compartments/response identities, completion orders, conserved loot, pause, E once and queued XP choice preservation |
| `levelup` | new, mixed, ranked and ability mastery cards | selection upgrades the run and resumes play; physical numeric selection cannot leak into a combat skill |
| `shop` | primary comparison/swap, five skill upgrades, sold/maxed/empty wallet | real UI purchases, preserved mod ranks, layout bounds, exact debits, rerolls, capped/unaffordable refusals, no Esc skip, a harder next round on a chosen level, and the bought rank re-applied in a brand-new run |
| `hud` | five skill cooldowns/ranks, primary mods, armor, low health and death | actual lethal damage ends the run |
| `mining` | whole fruit-machine bank, blinking lamps, a reel-stop strip, a win, paused spin, a tampered cabinet, automatic crowbar, one-press opened compartments, empty housing and out of order | lamps and reels freeze in pause, wins count up, tampered/out-of-order states read clearly, held/duplicate/paused presses cannot repeat payouts, firearm/reach/wall rejection, conserved loot and return to gun |
| `street` | all twenty homeless faces on the Bezdomovec, the eight archetypes on the other two bodies, close faces, the harder men, the boss and a crowd per sector | atlas ranges and grime on every human, 18+ of 20 faces appear in a crowd, homeless admitted by the real director in all three sectors |
| `menu` | intro, every party member and scrollable skill details, run setup (level, Horda preset, custom tuning), workshop tabs, records, settings and pause/abandon screens | saved gear, free primary switching and gadgets reapplied exactly once; class select continues to setup, presets/sliders/specialists save and turn custom, the summary states the real body estimate, records name level and tier |
| `run_config` | the tuned in-run HUD | saved level choice starts the run, specialist filter, density/health/cap stacked with the tier in the live director, authored levels untouched, scaled real incoming damage, preset ordering and corrupt-save clamping |
| `venues` | all fourteen storefronts in a generated Žižkov, natural views of all three sectors and the stage-clear shop for several venues | unique ids and text, no florist, identical carve/mining sites/RNG end state with and without storefronts, venue named in the shop header, Label3D/instance/batch/light bounds |
| `gear` | Czech gear cards, replacement/inspection, all six effects, stashes and elite hunts in every generated sector | real ricochet/shock/explosion/dash/shield damage, curse removal, slot-generation safety, discovery persistence, actual card/E/G input, pause/retreat, one-shot claims and sector carry-over |
| `icons` | one gallery page per icon group | visual review |

```sh
make lab-shots                         # all scenarios -> lab_shots/*.png + lab_report.txt
make lab-shots SCENARIOS="shop boss"   # a subset
python3 tools/lab.py gunplay mining abilities shop  # single primary, close-range salvage and hero kit
python3 tools/lab.py encounter armor boss_patterns  # tactical Yard features
python3 tools/lab.py tempo pressure pickups  # faster fire, scarce loot and healing supplies
python3 tools/lab.py fusion pressure armor  # crowd fusion, heavy gait and conserved combat
python3 tools/lab.py levels arena     # generated combat spaces and complete arena progression
python3 tools/lab.py gear arena       # optional gear raids and stage rewards
python3 tools/lab.py --list            # scenario names; --window renders visibly, --clean hides the overlay
make lab                               # interactive: pick a scenario, play on; F1 list, F12 screenshot
```

`tools/lab.py` renders in an invisible 1280 × 720 `gamescope --backend headless` session on the real GPU when available, prints each `PASS`/`FAIL` and engine error, and exits non-zero on a failed check, engine error, failed process, 480 s timeout or missing report. Register a `LabScenario` subclass in `Lab.SCENARIOS`. `start_game(class, stage)` uses explicit authored combat fixtures; `start_game(class, stage, true, seed)` exercises actual generated campaign worlds. Helpers include `equip_weapon`, `spawn_pack`, `ahead`, `aim_at`, `aim_deposit`, `fire`, `wait`, `capture`, `capture_strip` and `check`. The game root remains pausable under the lab's always-processing shell.

Lab runs are silent by default: `tools/lab.py` starts Godot with `--audio-driver Dummy`, which still mixes buses (SFX-bus PCM captures keep working) but sends nothing to the speakers. Pass `--sound` to hear a run.

The techno/final-boss integration passed **13 rendered scenarios / 132 captures,
zero check failures or script/engine errors**, using the silent Dummy driver.
Coverage includes actual final-boss combat and earned shops in all three levels,
blocked admission, survivor/hazard cleanup, death precedence, PCM-backed
techno → hardtek → techno transitions, DROP timing, pause/mute, speech gating
and rapid-run stale-render rejection. The batch still reported a 22-instance
ObjectDB exit warning; a verbose music-only run identified retained
`AudioStreamWAV`/`AudioStreamPlaybackWAV` objects at shutdown. This is not a
warning-free, listening-quality or long-session balance certification.

The primary/hero-kit cutover passed **21 rendered scenarios / 153 captures with zero failures or script/engine errors** on the Radeon GPU. Coverage includes physical 1–5 input for all four operators, actual damage/movement/healing, independent shields and buffs, rank scaling, proximity-only F extraction, solid occlusion, sustained unlimited fire, preserved primary upgrades, skill/shop purchases, procedural contracts and scarce pickups. Precision and nested-blast regressions also passed.

A separate normal-scene GPU smoke retained live director/physics, capsule movement, primary firing, real wheel swaps and earned XP choices in a generated Yard (sandbox profile, invulnerable player). All five Scout skills activated; real F extraction fractured quest ore while hostiles kept spawning. It finished with 101 actual kills and 41 living threats, without script/engine errors. This is a functional smoke, not campaign-balance or FPS certification.

An isolated on-disk legacy save migrated and then restarted successfully: currencies, class unlocks, crafting/talents, records and settings survived; the first valid firearm/gadget became scalar gear, and the gadget applied exactly once. The probe used an isolated user-data directory, never the player's real save.

The final mastery-layout/quest/encounter follow-up passed 21 captures with zero failures, including full card-text containment and numeric-input isolation. That subset still reported a 20-instance ObjectDB exit warning; this work is not claimed universally warning-free.

The Prague asset/salvage/street-UI pass ran the full rendered lab:
**176 captures, zero check failures or script/engine errors**. Final tab-bar and
scroll-layout follow-ups cover real mouse purchases and complete party/skill
descriptions. Screenshots were visually reviewed for menu, HUD/death, shop,
mastery, tutorial, boss and extraction surfaces; this is not FPS certification.

The street-faces and junk-guns pass, shipped as 0.4.0, ran the full rendered lab
across 25 scenarios: **199 captures, zero check failures or script/engine errors**,
plus the precision/nested-blast regression (`failures=0`).

After the lab arenas were reskinned and the shop venues added, the full lab ran again
across all 26 scenarios: **244 captures, zero check failures or script/engine
errors**, and the precision regression passed (`failures=0`). Arena, storefront and
stage-clear shop captures were inspected as screenshots, as were the eight invented
archetypes on the runner and spitter bodies. Frame rate is not measured, and the
storefront taglines are small: legible at about 3 m, marginal across a street.

Version 0.4.1 packages the faces, guns, arenas, archetypes, venues and the guide-line removal. Version 0.5.0 adds gear, required stashes, fusion, recursive hallucinations and the fruit machines.

The initial passive-gear expansion, before the required-stash change, passed the full rendered lab across **27 scenarios /
263 captures with zero check failures or script/engine errors**, plus
`tools/check_combat.gd` (`failures=0`). Reward, replacement, inspection, stash,
elite and pixel-icon captures were visually inspected. The `gear` scenario alone
produced 18 captures and checks all six real effects and loot sources in all three
sectors. Frame rate is not measured. Gear ships in 0.5.0.

The required-stash follow-up passed `quests gear onboarding levels`: **4 rendered
scenarios / 52 captures, zero failures or script/engine errors**. Checks exercise
all three sector extractions, two distinct stash claims, elite/duplicate exclusion,
declined rewards, stash-first and stash-last completion, pending choices and
per-sector reset. The expanded HUD was visually inspected; precision/nested-blast
regressions also passed (`failures=0`).

The fusion integration passed the full rendered lab: **28 scenarios / 274
captures, zero failures or script/engine errors**. After the final single-body
death-effect adjustment, `fusion gear combat boss armor` passed **5 scenarios /
46 captures**, again with zero failures or script/engine errors. Precision and
nested-blast regressions reported `failures=0`; a throwaway terrain/callback
smoke also passed wall, narrow-corridor, deck, static-mesh, synchronous
clear/recycle and grounded single-burst death cases.

Before/after, smooth fusion-transition and heavy-gait captures were inspected
visually. One normal live-pressure smoke retained this conserved population:

| Represented lives | Visible living bodies | Megas |
| --- | --- | --- |
| 1000 | 363 | 123 |

These are functional crowd-reduction observations, not FPS certification.

The recursive-hallucination replacement passed the full rendered lab: **29
scenarios / 293 captures, zero failures or script/engine errors**. Native
human, mouse and insect anatomy, nested-head cycle strips, peripheral blur
and crowded play were inspected visually. Isolated settings persistence and a
paused death/recycle smoke reported `failures=0`; precision/nested-blast
regressions also passed. Frame rate is not measured.

The feedback-loop vision follow-up passed `hallucinations combat pressure boss
menu levelup gear`: **7 rendered scenarios / 81 captures, zero failures or
script/engine errors**, including strong peripheral echoes, an unchanged health
bar, frozen feedback motion in pause and complete off restoration. Default,
full-intensity, crowded-play and reward-menu captures were inspected visually.

The ten-round quote expansion passed `quotes abilities combos guns weapons
tempo menu`: **seven rendered scenarios / 106 captures, zero failures or
script/engine errors**. Final `producer shop levelup` adds **three scenarios /
17 captures**, again with zero failures or script/engine errors. Native checks
cover all three new gun effects, crafting/equipping, rank-preserving swaps,
four capped passive stacks, actual health cost/clamping and regeneration,
directional/wall/deck skill boundaries, overlapping and removed-node guards,
real crossfader movement, remote frost, pause and placement/cancellation.
Menu, held/model/projectile, guard and field screenshots were inspected.
Precision/nested-blast regressions also passed (`failures=0`).

The cracked typography, high-chain decay and combo-driven sensory pass ran
`combo_pressure gunplay hallucinations music hud menu levelup shop`: **eight
scenarios / 81 captures**. Four first-run failures were fixed; the corrected
`combo_pressure hallucinations` rerun then passed **24 captures** with zero
failures or script/engine errors. Combat precision/nested-blast regressions
reported `failures=0`. Hot combo, menu detail and level-up card captures were
inspected visually. Frame rate is not measured.

The CrystalDive-inspired presets passed native
`hallucination_modes hallucinations combo_pressure menu`: **four scenarios /
98 captures, zero failures**. This covers actual preset/ceiling input, all
three stages, six indoor types, frozen/off restoration, unchanged physical
floors and real precision-shot damage for human, mouse and
insect megas. Combat regressions also reported `failures=0`. Settings,
crystal mirrors, rotating-head strips and warped indoor floors were inspected.
Frame rate is not measured.

The sustained-gunplay balance passed native
`gunplay pressure armor fusion boss quests`: **six scenarios / 51 captures,
zero failures**, including all three contract-driven extractions and recorded
campaign victory. A throwaway real-shot trace checked body/precision kills
against actual wave health in all three stages; `failures=0`. Combat precision,
piercing and nested-blast regressions also reported `failures=0`. Sustained
fire and live crowd/loot captures were inspected visually. The throwaway
driver was removed; frame rate is not measured.

The beat-shot and milestone escalation pass ran native
`rhythm_combo combo_pressure gunplay hallucination_modes hallucinations armor music`:
**seven scenarios / 104 captures, zero failures**. This includes actual
early/late beat shots, graded/off-beat damage, direct-plus-splash scaling,
fast-gun exclusions, real 100/200/300-hit chains, unchanged physical floors,
paused counter pixels, zero-intensity restoration and existing armor/music
boundaries. Combat regressions reported `failures=0`. Maximum-shot confirmation,
milestone effects, the 960×600 counter and off restoration were inspected
visually; frame rate is not measured.

The combat-pinball and venue-route overhaul passed the complete native lab:
**38 scenarios / 607 captures, zero failures or script/engine errors**.
It covers all three sectors' 3/4/5 distinct venue clears, local admission
budgets, initial/break/shop drafts, physical doorway arrival, kick/slide/stomp,
wall/ceiling constraints, returned shots, four weapon interactions, recovery
limits, exact-once manual credit, counter enemies and one-shot kegs. Existing
music, hallucination, armor, optional loot and progression paths also passed.
Combat regressions reported `failures=0` with clean teardown. Draft, routes,
live indoor combat and HUD at 960×600, launch/shatter/keg effects and hype aura
captures were inspected visually. Evidence: `/tmp/kbb_pinball_final`.
Frame rate and long-session balance are not measured.

The salvage presentation, movement animation and daze/finisher pass ran the
complete native lab: **39 scenarios / 616 captures, zero failures or
script/engine errors**, under `/tmp/kbb_finishers_final`. The final contact,
simultaneous-fire and paused-highlight changes also passed native `finishers
mining gunplay recoil music onboarding`: **40 captures, zero failures or
script/engine errors**, under `/tmp/kbb_finishers_boundaries`. A separate
native mining run covered automatic and cigarette cabinets: **19 captures,
zero failures**, under `/tmp/kbb_cigarette_switch`.
Crowbar-only salvage, standing/slide kicks, sustained slide, stomp and the
live F execution sequence were inspected visually. The finisher checks cover
daze expiry, bosses, walls, intervening bodies, floors, recycled lives,
held/released F, simultaneous fire/F, bounded healing, pause and death.
Frame rate and long-session balance are not measured.

The leaping front-flip upgrade passed native `finishers mining pinball
horde_pinball gunplay recoil music onboarding`: **8 scenarios / 57 captures,
zero failures**, under `/tmp/kbb_flip_finishers`. Final native `finishers`
playback also passed: **9 captures, zero failures**, under
`/tmp/kbb_flip_live_contact`, including live enemy death physics, out-of-range
F, real long-leap travel and wall/ceiling interruption. Combat regressions
reported `failures=0`. The brace/tuck/boot orbit, contact, directional burst,
live death and recovery sequence were inspected visually. Frame rate and
long-session balance are not measured.

The four-move/sample-cut pass ran native `finishers mining pinball gunplay
recoil music onboarding`: **7 scenarios / 58 captures, zero failures or
script/engine errors**, under `/tmp/kbb_finisher_variants_verified`. Two actual F-driven
bags each exercised every move without adjacent repeats. All four launches
produced measured SFX-bus PCM before contact; launch/contact recordings are
saved there as `finishers_{flip,corkscrew,drop_kick,axe_kick}_sfx.wav`. All four
brace/flight/contact/death/recovery strips and the updated tutorial were
inspected visually. A delayed contextual-input regression proves pending fresh
F suppresses LMB until its owner consumes it; budget checks count actual physics
refill rather than assuming screenshot timing. Existing salvage switching,
movement, gunplay, paused input and steady backing checks also passed.
Regenerating the eight WAVs and provenance catalog produced identical payloads;
Godot adds resource UIDs to the import sidecars on first import.
Combat regressions reported `failures=0`. Subjective listening, frame rate and
long-session balance are not measured.
