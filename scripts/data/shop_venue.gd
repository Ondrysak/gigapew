class_name ShopVenue
extends Resource

## One street venue: a storefront on the generated tenement faces and the named
## venue of the stage-clear shop. Pure flavour; no gameplay number lives here.

@export var id: StringName
## Full name as the shop header shows it ("Potraviny s Vietnamcem").
@export var display_name: String
## Short lit-sign form ("VEČERKA NONSTOP").
@export var sign_text: String
## The hand-lettered line: the shop subtitle and the paper taped in the window.
@export_multiline var tagline: String
## Window display, for the shop copy and for choosing what the window shows.
@export var goods: Array[String] = []
## Sector themes (`StageDefinition.layout_theme`) whose streets carry this venue.
@export var sectors: Array[StringName] = []
## Facade kit: `awning` (window, door, striped awning), `tiled` (butcher's wall
## tiles), `neon` (dark window in a lit frame) or `arch` (the tunnel mouth).
@export var facade_style: StringName = &"awning"
## What fills the window: bottles, boxes, parcels, coats, tools, sausages,
## loaves, machines, jars, glasses, shoes.
@export var goods_shape: StringName = &"boxes"
@export var awning_color := Color(0.6, 0.16, 0.1)
@export var awning_alt := Color(0.82, 0.8, 0.72)
## Lit sign board face and its lettering.
@export var sign_color := Color(0.06, 0.05, 0.045)
@export var text_color := Color(0.95, 0.85, 0.6)
## Window light, neon trim and the street fill light.
@export var glow_color := Color(1.0, 0.6, 0.24)
## Window goods cycle through these (kept to the shared street palette).
@export var goods_colors: Array[Color] = []
## Chaser bulbs around the sign: reads as a flashing sign in a still frame.
@export var bulbs := false
## The street fill light of this venue, 0 for none (kept to a few per level).
@export_range(0.0, 3.0, 0.1) var fill_energy := 0.0
## Brightness of the shop window (a pub is dim, a večerka is a fluorescent box).
@export_range(0.2, 1.3, 0.05) var window_glow := 1.0
