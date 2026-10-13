# Credits and third-party assets

The third-party **art listed below** is released under **CC0 1.0 (public domain)**: free for personal and commercial use, no attribution required. Code, synthesized instruments, primitive models and shaders are original to this project. Sampled audio has separate terms below.

| Asset | Author | Source | License | Used as |
| --- | --- | --- | --- | --- |
| Modular Sci-Fi MegaKit (Standard) | Quaternius | https://quaternius.com/packs/modularscifimegakit.html | CC0 | Level modules and props (`assets/third_party/quaternius_megakit/`), retained in the later-sector and authored lab environments |
| Sci-Fi Essentials Kit (Standard) | Quaternius | https://quaternius.com/packs/scifiessentialskit.html | CC0 | Hazard and dressing props (`assets/third_party/quaternius_scifi_essentials/`) |
| Ultimate Animated Character Pack | Quaternius | https://quaternius.com/packs/ultimatedanimatedcharacter.html | CC0 | The six Žižkov/Palmovka hallucinations (Bezdomovec, Feťák, Alkoholik, Vekslák, Vyhazovač, Pan Herna), recoloured and baked into `assets/monsters/robot_*` |
| Furniture Kit (2.0), `radio.glb` and `plantSmall3.glb` | Kenney | https://kenney.nl/assets/furniture-kit | CC0 | Retained source models from the 0.6.0 counter-prop pass; current venue fixtures use project primitives (`assets/third_party/kenney_furniture/License.txt`) |

The environment packs include their original `LICENSE.txt` in `assets/third_party/`. `assets/monsters/LICENSES.txt` records the CC0 people pack and the project's original procedural delirium creatures. All five `alien_*` slots now use original mouse, cockroach, rum-bottle and slot-machine meshes, rigs and actions from `tools/vat/build_delirium.py`; no old alien or mech monster textures remain. Raw source downloads are not stored in the repository. `tools/vat/README.md` documents generation and baking.

**Voice:** `assets/voice/ludas/*.wav` are short clips from the project owner's private recordings (archive `#ludas_vox`), mono 22 kHz and loudness-normalised (EBU R128, −16 LUFS). They are not CC0 and are included with the owner's permission for this project only.

**Soundtrack samples:** `assets/audio/protokseed/*.wav` contains complete conversions of all **87 WAVs** in the locally supplied **PROTOKSEED SAMPLE PACK**: 52 labelled tuned kicks, four drum loops, two 303 recordings, 17 ambience recordings, ten synth FX plus one kick FX, and one lead. `tools/music_samples.py` retains whole recordings, antialiases/downsamples stereo PCM16/44100 to mono PCM16/22050 and generates `catalog.gd` with explicit exported dependencies, original source paths, SHA256 checksums, roles, labelled kick pitch classes and exact measured loop grids. The complete converted bank holds 18,287,572 PCM bytes; the five old selected/trimmed conversions have been removed. Original Luďas recording bytes are unchanged; six voice imports retain uncompressed PCM for shared sample-bank access.

**Finisher samples:** `assets/audio/finishers/*.wav` contains eight new short
launch/contact derivatives cut directly from the same supplied pack.
`tools/finisher_samples.py` uses KICK F 05, G# 03, D 01 and F 22, 303 01,
FX 03 and 05, DRUM LOOP 04 and LEAD 01. Mono PCM16/22050 edits combine
reversals, stutters, pitch traversal, saturation and faded layering; a 6 kHz
source lowpass precedes traversal. `assets/audio/finishers/catalog.json`
records original SHA256 hashes, exact source intervals and processing,
derived WAV hashes and PCM measurements. Originals and Luďas recordings are
unchanged. These derivatives inherit the pack's unverified terms below.

The supplied PROTOKSEED folder contained no licence/readme. **Redistribution permission is unverified; these samples are not CC0 or claimed royalty-free.** Confirm the pack's terms before publishing the new sample-backed source/assets or release binaries. The pushed `v0.6.0` precedes this soundtrack integration.

**Techno samples:** `assets/audio/techno/*.wav` contains 56 complete conversions
from the user's locally purchased **TECHNO_ESS** folder: seven bass loops, five
synth loops, five arp loops, three atmosphere loops, twelve no-kick drum grooves,
and eight each of kick, clap and hat hits. The pitched loops form matched C minor,
Eb minor and Gb minor pools at 125 BPM. `tools/techno_samples.py` converts whole
stereo PCM24/44100 recordings to antialiased mono PCM16/22050, with DC removal,
peak ceilings and 1 ms edges. The generated `catalog.gd` preserves source paths,
SHA256 hashes, roles, labelled roots, exact loop grids and explicit export
dependencies. The converted bank holds 9,544,656 PCM bytes; originals are
unchanged. No licence/readme was found in this folder. **Purchase was reported
by the user, but redistribution permission is unverified; these samples are
not CC0 or claimed royalty-free.** Confirm the pack's terms before publishing
source/assets or release binaries containing them.

**Kára callouts:** `assets/audio/kara/*.mp3` are the 33 MP3s indexed on
https://www.jirikara.cz/ that downloaded successfully, stored as the original HTTP
response bytes with no trimming, normalisation or transcoding. `tools/kara_samples.py`
fetched them; `assets/audio/kara/catalog.json` records source URLs, retrieval times,
SHA256 hashes and the three indexed slugs that returned HTTP 404 (`vychodni_tazeni`,
`posledni_varovani`, `grc`). The user authorised their reuse, but no
redistribution licence was found on the inspected pages. **These clips are not
CC0; confirm rights before publishing.**

## Engine and bundled libraries

Kakaboomboom runs on **Godot Engine 4.7.2**, distributed under the MIT license.
See https://godotengine.org/license/ for the engine's license terms. Release
packages include the full Godot license and dependency copyright/license notices
in `licenses/GODOT-LICENSE.txt` and `licenses/GODOT-COPYRIGHT.txt`; source copies
are under `tools/release/licenses/`. These notices cover the engine and its
bundled libraries, not the original game code.

## Visual and design inspiration

CrystalDive's `src/modes/core_modes.wgsl`, `mode_moire.wgsl` and
`mode_bragg_kaleido.wgsl` informed the hallucination presets: analytic-gradient
lensing, twisted surface lattices and radius-preserving polar folds.
The Godot floor fields, screen presets and rotating source-head copies are
original adaptations; no CrystalDive assets or rendering pipeline are shipped.


Derek Mattson's [GDC 2024 *A Second Shot*](https://media.gdcvault.com/gdc2024/Slides/GDC+slide+presentations/Mattson_Derek_ASecondShot_Notes.pdf)
informed the emphasis on reliable target feedback before camera effects. The
nine firearm models and gloved grips in `assets/guns/`, generated by
`tools/guns/build_guns.py`, are original to this project.
No third-party weapon meshes or slide content are redistributed.
The quote-expansion ability scenes and eleven pixel icons
(`tools/icons/art_quotes.py`) are original project art. Their selected source
lines and adaptations are recorded in README's ten-round provenance table.
The street-face atlas (`tools/vat/faces/atlas.png`) is painted from parameters by
`tools/vat/faces/build_faces.py`. Its faces are invented; none is traced from,
sampled from or modelled on a photograph or a real person.
The six passive-gear pixel icons in `assets/icons/gear/` are original to this
project, authored in `tools/icons/art_passive.py` and rendered by the existing
`tools/icons/build.py` pipeline. Item flavour quotes come from the supplied
`hlasky.txt`; the item names are adaptations, not verbatim quotations.
The fruit-machine glass, reel strip, button caps, badge and stickers in
`assets/automat/` are drawn from parameters by `tools/automat_art.py`. The
cabinets follow the general layout of Czech pub fruit machines, but the logos
("SUPER DROBNÉ", "JACKPOT 777", the KOVOHRA badge), symbols and artwork are
invented; no manufacturer's brand, artwork or photograph is reproduced.
Their lettering is rasterised from **Fira Sans** (Heavy, Heavy Italic, Bold and
Condensed ExtraBold) by Carrois Apostrophe / Mozilla, under the
[SIL Open Font License 1.1](https://openfontlicense.org); only rendered pixels
are shipped, not the font files.

**UI fonts:** `assets/fonts/RubikGlitch-Regular.ttf` (Rubik Glitch, Rubik Filtered
Project Authors, NaN and Luke Prowse, https://github.com/NaN-xyz/Rubik-Filtered)
and `assets/fonts/BarlowSemiCondensed-Medium.ttf` (Barlow Semi Condensed, Barlow
Project Authors, Jeremy Tribby, https://github.com/jpt/barlow) are bundled under
the SIL Open Font License 1.1. Their licences are
`assets/fonts/RubikGlitch-OFL.txt` and `assets/fonts/BarlowSemiCondensed-OFL.txt`.

The Prague room fixtures, wall/floor shaders and sign atlas in `assets/kits/`
are original procedural artwork, generated by `tools/kits_art.py`. Lettering
uses rendered Fira Sans Bold pixels under the SIL Open Font License 1.1 above;
no font file is shipped. Station names and public-wayfinding terms refer to
Prague; Žižkovská 12°, TOJ TOJ, Šťastná čísla and the developer banner are
invented identities, not reproductions of commercial logos. Metro cladding
evokes line A's pressed aluminium cups, line B's glass panels and line C's
ceramic tiles. Current toilet fixtures and other kit furniture are built from
the project's own primitives; the retained Kenney source models are not instanced
in the current venue design.
