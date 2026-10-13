shader_type spatial;
render_mode diffuse_burley;

// Žižkov yards and streets: granite setts with patched, cracked asphalt,
// grime and rain puddles that catch the sodium lamps.

#include "res://shaders/floor_common.gdshaderinc"
#include "res://shaders/zizkov_common.gdshaderinc"

uniform vec2 sett_size = vec2(0.34, 0.24);
uniform vec3 sett_dark : source_color = vec3(0.22, 0.215, 0.215);
uniform vec3 sett_light : source_color = vec3(0.36, 0.33, 0.3);
uniform vec3 joint_color : source_color = vec3(0.07, 0.062, 0.055);
uniform vec3 asphalt_color : source_color = vec3(0.115, 0.11, 0.11);
uniform vec3 grime_color : source_color = vec3(0.12, 0.095, 0.07);
uniform vec3 puddle_color : source_color = vec3(0.05, 0.05, 0.055);

void fragment() {
	vec2 p = floor_hallucinated_uv(world_position.xz);

	vec2 stone;
	float joint = zz_bond(p, sett_size, 0.018, stone);
	float tone = zz_hash(stone);
	vec3 setts = mix(sett_dark, sett_light, tone * tone) * (0.85 + 0.3 * zz_hash(stone + 7.0));
	setts = mix(setts, joint_color, joint);

	// Patched asphalt over the setts, with dark tar-filled cracks.
	float patch = zz_fbm(p * 0.075 + vec2(3.1, 9.7));
	float asphalt_mask = smoothstep(0.53, 0.545, patch);
	float grain = zz_noise(p * 9.0);
	vec3 asphalt = asphalt_color * (0.82 + 0.35 * grain);
	float crack_field = abs(zz_fbm(p * 0.6 + 40.0) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.018 + fwidth(crack_field), crack_field)) * asphalt_mask;
	asphalt = mix(asphalt, joint_color * 0.6, crack * 0.8);
	float patch_edge = (smoothstep(0.515, 0.53, patch) - asphalt_mask) * 0.6;
	vec3 color = mix(setts, asphalt, asphalt_mask);
	color = mix(color, joint_color, patch_edge);

	// Soot, beer and worse.
	float dirt = zz_fbm(p * 0.32 + vec2(71.0, 13.0));
	color = mix(color, grime_color, smoothstep(0.45, 0.8, dirt) * 0.55);

	float wet = zz_fbm(p * 0.11 + vec2(41.0, 23.0));
	float puddle = smoothstep(0.6, 0.63, wet);
	color = mix(color, puddle_color, puddle * 0.75);

	ALBEDO = color;
	ROUGHNESS = mix(mix(0.86, 0.72, asphalt_mask), 0.06, puddle);
	SPECULAR = mix(0.4, 0.75, puddle);
	METALLIC = 0.0;
}
