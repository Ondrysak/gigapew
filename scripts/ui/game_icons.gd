class_name GameIcons
extends RefCounted

## Pixel-art icons rendered by tools/icons/build.py into
## res://assets/icons/<group>/<id>.png. Data resources reference their icon
## directly (`icon` exports); code-only concepts (HUD glyphs, shop stock,
## damage types) look theirs up here. Missing icons return null.

const ROOT := "res://assets/icons/%s/%s.png"
const DAMAGE_TYPE_IDS: Array[StringName] = [&"kinetic", &"fire", &"frost", &"shock"]

static var _cache: Dictionary = {}

static func lookup(group: StringName, id: StringName) -> Texture2D:
	var key := "%s/%s" % [group, id]
	if _cache.has(key):
		return _cache[key]
	var path := ROOT % [group, id]
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[key] = texture
	return texture

static func damage_type(kind: int) -> Texture2D:
	return lookup(&"hud", DAMAGE_TYPE_IDS[clampi(kind, 0, DAMAGE_TYPE_IDS.size() - 1)])

## A crisp (nearest-filtered) icon control of `pixels` square size.
static func rect(texture: Texture2D, pixels: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
