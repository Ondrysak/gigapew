class_name DamageType
extends RefCounted


enum Kind { KINETIC, FIRE, FROST, SHOCK }

static func label(kind: int) -> String:
	match kind:
		Kind.FIRE: return "Oheň"
		Kind.FROST: return "Mráz"
		Kind.SHOCK: return "Blesk"
	return "Náraz"

static func color(kind: int) -> Color:
	match kind:
		Kind.FIRE: return Color(1.0, 0.48, 0.18)
		Kind.FROST: return Color(0.4, 0.85, 1.0)
		Kind.SHOCK: return Color(0.86, 0.64, 1.0)
	return Color(0.96, 0.97, 1.0)
