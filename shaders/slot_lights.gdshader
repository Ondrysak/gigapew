shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Candle tiers, button caps, 7-segment LEDs and the coin window of the fruit
// machines (SlotBankGeometry._lights). Levels come from slot_machine.gdshaderinc.
#include "res://shaders/slot_machine.gdshaderinc"

// Theme atlas: button caps live in its misc row.
uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;

// UV2.x: SlotBankGeometry.Light. UV2.y: cabinet + 4 * sub.
const int LIGHT_BULB = 0;
const int LIGHT_BUTTON = 1;
const int LIGHT_LED = 2;
const int LIGHT_COIN = 3;
// Segment bits (a=1 top, b, c, d, e, f, g=64 middle) for 0-9, blank, '-', E, r, o, d.
const int SEGMENTS[16] = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111, 0, 64, 121, 80, 92, 94};
// Segment end points (x0, y0, x1, y1) in a digit cell, y up.
const vec4 SEGMENT_ENDS[7] = {
	vec4(0.3, 0.9, 0.7, 0.9), vec4(0.78, 0.84, 0.78, 0.56), vec4(0.78, 0.44, 0.78, 0.16),
	vec4(0.3, 0.1, 0.7, 0.1), vec4(0.22, 0.44, 0.22, 0.16), vec4(0.22, 0.84, 0.22, 0.56),
	vec4(0.3, 0.5, 0.7, 0.5)
};

varying flat int v_kind;
varying flat vec3 v_color;
varying flat float v_level;
// LED: value, mode (0 number, 1 dashes, 2 "door", 3 off), digits.
varying flat vec3 v_led;

void vertex() {
	v_kind = int(UV2.x + 0.5);
	int code = int(UV2.y + 0.5);
	int cabinet = code % 4;
	int sub = code / 4;
	float t = sm_time();
	vec3 color = COLOR.rgb;
	v_led = vec3(0.0, 3.0, 4.0);
	if (v_kind == LIGHT_LED) {
		vec3 display = sm_led(cabinet, sub, t);
		v_led = vec3(display.x, display.y, sub == 0 ? 4.0 : 3.0);
		v_level = display.z;
	} else {
		v_level = sm_light(v_kind, cabinet, sub, t, COLOR.rgb, color);
	}
	v_color = color;
}

float bar(vec2 p, vec4 ends) {
	vec2 pa = p - ends.xy;
	vec2 ba = ends.zw - ends.xy;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// x: lit segment light (core + glow), y: unlit segment ghost.
vec2 seven(vec2 cell, int bits) {
	vec2 p = vec2(cell.x - (cell.y - 0.5) * 0.12, cell.y);
	float lit = 0.0;
	float ghost = 0.0;
	for (int s = 0; s < 7; s++) {
		float d = bar(p, SEGMENT_ENDS[s]);
		float core = 1.0 - smoothstep(0.045, 0.075, d);
		if (((bits >> s) & 1) == 1) {
			lit = max(lit, core) + exp(-d * 24.0) * 0.12;
		} else {
			ghost = max(ghost, core);
		}
	}
	return vec2(lit, ghost);
}

vec3 led(vec2 uv, vec3 content, float level) {
	float digits = content.z;
	float cell = floor(uv.x * digits);
	vec2 p = (vec2(fract(uv.x * digits), 1.0 - uv.y) - 0.5) * vec2(1.2, 1.12) + 0.5;
	int mode = int(content.y + 0.5);
	int code = 10;
	if (mode == 0) {
		int place = int(digits - 1.0 - cell);
		float scale = 1.0;
		for (int i = 0; i < place; i++) {
			scale *= 10.0;
		}
		if (place == 0 || content.x >= scale) {
			code = int(mod(floor(content.x / scale + 0.0001), 10.0));
		}
	} else if (mode == 1) {
		code = 11;
	} else if (mode == 2) {
		code = cell < 0.5 ? 15 : (cell > digits - 1.5 ? 13 : 14);
	}
	int bits = mode == 3 ? 0 : SEGMENTS[code];
	vec2 seg = seven(p, bits);
	vec3 red = vec3(1.0, 0.07, 0.02);
	return vec3(0.025, 0.0, 0.0) + vec3(0.09, 0.01, 0.004) * seg.y + red * seg.x * level * 1.3 + vec3(0.7, 0.35, 0.15) * pow(min(seg.x, 1.0), 3.0) * level;
}

vec3 coin(vec2 uv, float level) {
	vec3 c = vec3(0.07, 0.07, 0.075);
	float left = step(abs(uv.x - 0.2), 0.12) * step(abs(uv.y - 0.5), 0.3);
	float right = step(abs(uv.x - 0.8), 0.12) * step(abs(uv.y - 0.5), 0.3);
	float slot = step(abs(uv.x - 0.5), 0.025) * step(abs(uv.y - 0.5), 0.36);
	c = mix(c, vec3(1.0, 0.1, 0.05) * (0.15 + level), left);
	c = mix(c, vec3(0.2, 0.4, 1.0) * (0.15 + 0.8 * level), right);
	return mix(c, vec3(0.0), slot);
}

void fragment() {
	vec3 c = v_color * (0.1 + v_level);
	if (v_kind == LIGHT_BUTTON) {
		vec3 cap = texture(art, UV).rgb;
		c = cap * v_color * (0.18 + 1.2 * v_level) + cap * 0.25 * v_level;
	} else if (v_kind == LIGHT_LED) {
		c = led(UV, v_led, v_level);
	} else if (v_kind == LIGHT_COIN) {
		c = coin(UV, v_level);
	}
	ALBEDO = c;
}
