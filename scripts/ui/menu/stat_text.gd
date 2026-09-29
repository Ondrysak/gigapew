class_name StatText
extends RefCounted

## Human-readable lines for StatModifier fields, used by class and armory
## screens. Each entry is {"text": String, "good": bool}.

## `scale` multiplies every field (e.g. a meta upgrade's purchased level).
static func entries(modifier: StatModifier, scale := 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if modifier == null:
		return result
	_percent(result, modifier.damage_multiplier * scale, "damage")
	_percent(result, modifier.fire_rate_multiplier * scale, "fire rate")
	_percent(result, modifier.move_speed_multiplier * scale, "move speed")
	_percent(result, modifier.crit_chance * scale, "critical chance")
	_flat(result, modifier.crit_multiplier * scale, "× critical damage", "%+.2f")
	_flat(result, modifier.max_health_bonus * scale, "max health", "%+d")
	_flat(result, modifier.regen_per_second * scale, "HP/s regen", "%+.1f")
	_flat(result, modifier.armor * scale, "armor", "%+.1f")
	_flat(result, modifier.pickup_radius * scale, "m pickup radius", "%+.1f")
	_flat(result, modifier.pierce_bonus * scale, "pierce", "%+d")
	_flat(result, modifier.projectile_bonus * scale, "projectiles", "%+d")
	_percent(result, modifier.area_multiplier * scale, "weapon area")
	_percent(result, modifier.cooldown_multiplier * scale, "auto-weapon cooldown", true)
	_percent(result, modifier.ability_cooldown_multiplier * scale, "ability cooldown", true)
	_percent(result, modifier.xp_multiplier * scale, "XP gain")
	_percent(result, modifier.mining_multiplier * scale, "mining power")
	_percent(result, modifier.resource_multiplier * scale, "resource yield")
	return result

## Entries joined with ", " (plain text).
static func summary(modifier: StatModifier, scale := 1.0) -> String:
	var parts := PackedStringArray()
	for entry in entries(modifier, scale):
		parts.append(entry.text)
	return ", ".join(parts)

## BBCode lines colored green (buff) or red (drawback).
static func bbcode(modifier: StatModifier, good_color: Color, bad_color: Color, scale := 1.0) -> String:
	var lines := PackedStringArray()
	for entry in entries(modifier, scale):
		var color: Color = good_color if entry.good else bad_color
		lines.append("[color=#%s]%s[/color]" % [color.to_html(false), entry.text])
	return "\n".join(lines)

static func _percent(result: Array[Dictionary], value: float, label: String, lower_is_better := false) -> void:
	if is_zero_approx(value):
		return
	var percent := roundf(value * 1000.0) / 10.0
	var number := ("%+d" % int(percent)) if is_equal_approx(percent, roundf(percent)) else ("%+.1f" % percent)
	result.append({"text": "%s%% %s" % [number, label], "good": (value < 0.0) == lower_is_better})

static func _flat(result: Array[Dictionary], value: float, label: String, format: String) -> void:
	if is_zero_approx(value):
		return
	var number := ("%+d" % int(roundf(value))) if format == "%+d" else (format % value)
	result.append({"text": "%s %s" % [number, label], "good": value > 0.0})
