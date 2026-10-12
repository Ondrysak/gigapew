// Shared helpers of the Prague kit surface shaders (metro walls, terrazzo, WC tiles).

float kit_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float kit_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(kit_hash(i), kit_hash(i + vec2(1.0, 0.0)), u.x), mix(kit_hash(i + vec2(0.0, 1.0)), kit_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float kit_fbm(vec2 p) {
	return kit_noise(p) * 0.5 + kit_noise(p * 2.03 + 3.1) * 0.3 + kit_noise(p * 4.1 + 7.7) * 0.2;
}

// Wall-plane coordinates from a world position and world normal: x runs along
// the wall, y is height above `base_y`.
vec2 kit_wall_uv(vec3 world_pos, vec3 world_normal, float base_y) {
	float along = abs(world_normal.x) > abs(world_normal.z) ? world_pos.z : world_pos.x;
	return vec2(along, world_pos.y - base_y);
}

// 0 inside a tile, 1 on the grout line; `cell` tile size, `grout` line width (both metres).
float kit_grout(vec2 p, vec2 cell, float grout) {
	vec2 f = fract(p / cell) * cell;
	vec2 d = min(f, cell - f);
	return 1.0 - smoothstep(grout * 0.5, grout, min(d.x, d.y));
}
