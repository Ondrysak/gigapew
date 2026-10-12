shader_type spatial;
render_mode diffuse_burley;

// Run-down Prague public toilet tiling.
//   is_floor = false: 15 cm white wall tiles up to `tile_top` with a two-row blue
//                  band, dirty cream paint above, cracked/missing tiles, rust
//                  streaks and grimy grout near the floor;
//   is_floor = true: 10 cm grey anti-slip floor tiles with dark grout and wet,
//                  glossy puddles.

#include "res://shaders/kits/kit_common.gdshaderinc"

uniform bool is_floor = false;
uniform float base_y = 0.0;
uniform float tile_top = 1.8;
uniform vec4 band_color : source_color = vec4(0.12, 0.3, 0.62, 1.0);
uniform float wear : hint_range(0.0, 1.0) = 0.65;
uniform float wear_seed = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo;
	float rough;
	if (is_floor) {
		vec2 p = world_pos.xz;
		vec2 id = floor(p / 0.1);
		albedo = vec3(0.42, 0.42, 0.4) * (0.88 + kit_hash(id) * 0.16);
		float grout = kit_grout(p, vec2(0.1), 0.006);
		albedo = mix(albedo, vec3(0.12, 0.11, 0.09), grout);
		vec2 dirt_uv = p + vec2(wear_seed * 0.17, wear_seed * 0.11);
		float wet = smoothstep(0.72 - wear * 0.14, 0.82 - wear * 0.14, kit_fbm(dirt_uv * 0.8));
		albedo *= 0.92 - wear * 0.12 + kit_fbm(dirt_uv * 2.0) * 0.16 - wet * 0.10;
		rough = mix(0.78, 0.18, wet * wear);
	} else {
		vec2 uv = kit_wall_uv(world_pos, world_normal, base_y);
		vec2 cell = vec2(0.15);
		vec2 id = floor(uv / cell);
		float grout = kit_grout(uv, cell, 0.005);
		float row = id.y;
		bool band = row == 10.0 || row == 11.0;
		albedo = band ? band_color.rgb : vec3(0.86, 0.87, 0.85);
		albedo *= 0.94 + kit_hash(id) * 0.06;
		vec2 wear_id = id + vec2(wear_seed, wear_seed * 0.73);
		float missing = step(0.997 - wear * 0.023, kit_hash(wear_id + 31.0));
		albedo = mix(albedo, vec3(0.32, 0.3, 0.27), missing);
		float crack = step(0.994 - wear * 0.040, kit_hash(wear_id + 17.0)) * (1.0 - smoothstep(0.0, 0.01, abs(fract(uv.x / cell.x + uv.y / cell.y) - 0.5) * cell.x));
		float low = 1.0 - smoothstep(0.0, 0.6, uv.y);
		albedo = mix(albedo, mix(vec3(0.3, 0.28, 0.22), vec3(0.12, 0.1, 0.07), low), grout);
		albedo = mix(albedo, vec3(0.2), crack * 0.8);
		float streak = smoothstep(0.7, 0.95, kit_noise(vec2(uv.x * 7.0 + wear_seed, uv.y * 0.6))) * low;
		albedo = mix(albedo, vec3(0.45, 0.3, 0.15), streak * wear * 0.65);
		rough = mix(0.15, 0.9, max(grout, missing));
		if (uv.y > tile_top) {
			albedo = vec3(0.72, 0.68, 0.56) * (0.75 + kit_fbm(uv * 1.5) * 0.3);
			rough = 0.95;
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
}
