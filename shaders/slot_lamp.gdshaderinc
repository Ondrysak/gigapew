// Blinking cigarette-machine lamps (see DepositGeometry.lamps; fruit machines use
// slot_machine.gdshaderinc). Patterns are
// evaluated once per vertex: every vertex of a lamp shares its code.
// UV.x = chase ordinal or phase, UV.y = pattern + 8 * (door + 1).

// The paused gameplay clock: lamps freeze under menus with the rest of the world.
global uniform float hallucination_time;
// Per-machine offset, so a row of cabinets never blinks in lockstep.
instance uniform float lamp_seed = 0.0;
// Set on the first pry: the service candle turns red and blinks.
instance uniform float tilt = 0.0;
// Set once emptied: lamps die, with the odd sputter.
instance uniform float out_of_order = 0.0;
// Bitmask of tampered doors; their lamps go dark.
instance uniform float dark_doors = 0.0;

varying vec3 v_lamp_color;
varying float v_lamp_level;

const int LAMP_MARQUEE = 0;
const int LAMP_RAIL = 1;
const int LAMP_CANDLE = 2;
const int LAMP_STRIP = 3;
const int LAMP_PAYLINE = 4;
const int LAMP_WIN = 5;

float lamp_hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

float lamp_level(int pattern, float phase, float t) {
	if (out_of_order > 0.5) {
		bool sputters = pattern == LAMP_STRIP || (pattern == LAMP_CANDLE && phase < 0.5);
		return sputters && lamp_hash(floor(t * 9.0) + phase * 7.0 + lamp_seed * 13.0) > 0.88 ? 0.6 : 0.03;
	}
	float lit = 1.0;
	if (pattern == LAMP_MARQUEE) {
		// Every third bulb lit, stepping around the sign.
		lit = mod(phase - floor(t * 5.0), 3.0) < 0.5 ? 1.0 : 0.14;
	} else if (pattern == LAMP_RAIL) {
		// Pairs of bulbs climbing both rails.
		lit = mod(phase - floor(t * 7.0), 4.0) < 1.5 ? 1.0 : 0.12;
	} else if (pattern == LAMP_CANDLE) {
		if (tilt > 0.5) {
			lit = fract(t * 2.5 + phase * 0.5) < 0.5 ? 1.0 : 0.1;
		} else {
			lit = phase < 0.5 ? (fract(t * 0.9) < 0.6 ? 1.0 : 0.3) : 1.0;
		}
	} else if (pattern == LAMP_STRIP) {
		// Neon hum with an occasional weak-tube drop.
		lit = 0.88 + 0.12 * sin(t * 9.0);
		lit *= lamp_hash(floor(t * 14.0) + lamp_seed * 31.0) > 0.96 ? 0.35 : 1.0;
	} else if (pattern == LAMP_PAYLINE) {
		lit = 0.25 + 0.5 * (0.5 + 0.5 * sin(t * 2.6 + phase * 6.28318530718));
	} else if (pattern == LAMP_WIN) {
		lit = fract(t * 1.4 + phase) < 0.5 ? 1.0 : 0.1;
	}
	// Attract mode: every 11 s the whole cabinet flashes together, below 3 Hz.
	bool attract_lamp = pattern != LAMP_CANDLE && pattern != LAMP_STRIP;
	if (attract_lamp && fract(t / 11.0) < 0.12) {
		lit = fract(t * 2.5) < 0.5 ? 1.0 : 0.08;
	}
	return lit;
}

// Returns false when the lamp belongs to a tampered door and must vanish.
bool lamp_vertex(vec2 code, vec3 color, out float level, out vec3 lamp_color) {
	float encoded = code.y + 0.5;
	int pattern = int(mod(encoded, 8.0));
	float door = floor(encoded / 8.0) - 1.0;
	level = 0.0;
	lamp_color = color;
	if (door >= 0.0 && mod(floor(dark_doors / exp2(door)), 2.0) > 0.5) {
		return false;
	}
	float t = hallucination_time + lamp_seed * 11.0;
	level = lamp_level(pattern, code.x, t);
	if (pattern == LAMP_CANDLE) {
		lamp_color = mix(color, vec3(1.0, 0.08, 0.05), tilt * step(out_of_order, 0.5));
	}
	return true;
}
