// Anti-aliased, distance-filtered floor marking helpers (world-space metres).
// Periodic patterns fade to their average coverage once a pixel covers a
// large part of one period, so large arenas stay free of moire.

#include "res://shaders/floor_hallucination.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Coverage of a line of half width `half_width` at signed/unsigned distance `d`.
// `fw` is the screen-space derivative of the distance field. Sub-pixel lines
// are kept one pixel wide but dimmed so their energy stays constant.
float aa_line(float d, float half_width, float fw) {
	float aa = max(fw, 1e-5);
	float w = max(half_width, aa * 0.5);
	float line = 1.0 - smoothstep(w - aa * 0.5, w + aa * 0.5, abs(d));
	return line * (half_width / w);
}

// Repeating lines every `period` metres along `x`, first line at x = offset.
float aa_grid_line(float x, float period, float offset, float half_width) {
	float fw = fwidth(x);
	float u = (x - offset) / period;
	float d = abs(fract(u + 0.5) - 0.5) * period;
	float line = aa_line(d, half_width, fw);
	float average = clamp(2.0 * half_width / period, 0.0, 1.0);
	return mix(line, average, smoothstep(0.2, 0.5, fw / period));
}

// Box-filtered checkerboard, cell size `cell` metres. Returns 0..1.
float aa_checker(vec2 p, float cell) {
	vec2 q = p / cell;
	vec2 w = max(fwidth(q), vec2(1e-4));
	vec2 i = 2.0 * (abs(fract((q - 0.5 * w) * 0.5) - 0.5) - abs(fract((q + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

// Diagonal 50% duty hazard stripes with `period` metres.
float aa_stripes(vec2 p, float period) {
	float x = (p.x + p.y) * 0.70710678;
	return aa_grid_line(x, period, 0.0, period * 0.25);
}

// Distance inside an axis-aligned rectangle (positive inside, metres to the
// nearest edge).
float rect_inset(vec2 p, vec2 center, vec2 half_extents) {
	vec2 q = abs(p - center) - half_extents;
	return -max(q.x, q.y);
}

// Line at a fixed inset from the rectangle edges.
float aa_rect_line(vec2 p, vec2 center, vec2 half_extents, float inset, float half_width) {
	float d = rect_inset(p, center, half_extents) - inset;
	return aa_line(d, half_width, fwidth(d));
}

// Ring of radius `radius` around `center`.
float aa_ring(vec2 p, vec2 center, float radius, float half_width) {
	float d = length(p - center) - radius;
	return aa_line(d, half_width, fwidth(d));
}
