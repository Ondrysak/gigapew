shader_type spatial;
render_mode diffuse_burley;

// Polished terrazzo / stone floor of the metro vestibules: a cement base with
// dense stone chips, 1.2 m slab joints and worn walking paths (lower gloss).

#include "res://shaders/kits/kit_common.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.55, 0.52, 0.47, 1.0);
uniform vec4 chip_a : source_color = vec4(0.82, 0.8, 0.74, 1.0);
uniform vec4 chip_b : source_color = vec4(0.25, 0.24, 0.23, 1.0);
uniform vec4 chip_c : source_color = vec4(0.62, 0.35, 0.25, 1.0);
uniform float slab = 1.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 cell = floor(p * 28.0);
	vec2 f = fract(p * 28.0) - 0.5;
	float h = kit_hash(cell);
	float size = 0.25 + kit_hash(cell + 5.3) * 0.25;
	float chip = step(length(f + (vec2(kit_hash(cell + 1.7), kit_hash(cell + 2.9)) - 0.5) * 0.4), size);
	vec3 albedo = base_color.rgb * (0.92 + kit_noise(p * 3.0) * 0.12);
	vec3 chip_col = h < 0.45 ? chip_a.rgb : (h < 0.8 ? chip_b.rgb : chip_c.rgb);
	albedo = mix(albedo, chip_col, chip * step(0.35, kit_hash(cell + 9.1)));
	float joint = kit_grout(p, vec2(slab), 0.012);
	albedo = mix(albedo, albedo * 0.45, joint);
	float worn = kit_fbm(p * 0.35);
	albedo *= 0.85 + worn * 0.2;
	ALBEDO = albedo;
	ROUGHNESS = mix(0.18, 0.5, smoothstep(0.4, 0.75, worn)) + joint * 0.3;
}
