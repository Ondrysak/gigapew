shader_type spatial;
render_mode diffuse_burley;

// Palmovka tram junction: patched asphalt and granite setts around double
// tram rails, worn road paint, oil and rain puddles that hold the lamp light.

#include "res://shaders/floor_common.gdshaderinc"
#include "res://shaders/zizkov_common.gdshaderinc"

uniform float track_period = 13.0;
uniform float gauge = 1.435;
uniform vec3 asphalt_color : source_color = vec3(0.115, 0.105, 0.098);
uniform vec3 sett_dark : source_color = vec3(0.2, 0.185, 0.17);
uniform vec3 sett_light : source_color = vec3(0.34, 0.3, 0.26);
uniform vec3 joint_color : source_color = vec3(0.06, 0.052, 0.045);
uniform vec3 rail_color : source_color = vec3(0.34, 0.2, 0.12);
uniform vec3 paint_color : source_color = vec3(0.62, 0.55, 0.36);
uniform vec3 oil_color : source_color = vec3(0.035, 0.032, 0.036);

void fragment() {
	vec2 p = world_position.xz;
	float track_z = floor(p.y / track_period + 0.5) * track_period;
	float across = p.y - track_z;

	// Asphalt with tar cracks.
	float grain = zz_noise(p * 9.0);
	vec3 color = asphalt_color * (0.8 + 0.4 * grain);
	float crack_field = abs(zz_fbm(p * 0.55 + 20.0) - 0.5);
	float crack = 1.0 - smoothstep(0.0, 0.016 + fwidth(crack_field), crack_field);
	color = mix(color, joint_color, crack * 0.8);

	// Granite setts where the road was opened for the rails.
	vec2 stone;
	float joint = zz_bond(p, vec2(0.3, 0.2), 0.016, stone);
	vec3 setts = mix(sett_dark, sett_light, zz_hash(stone) * zz_hash(stone + 3.0)) * (0.85 + 0.3 * zz_hash(stone + 7.0));
	setts = mix(setts, joint_color, joint);
	float bed = 1.0 - smoothstep(gauge * 0.5 + 0.9, gauge * 0.5 + 1.0, abs(across));
	float patch_mask = smoothstep(0.52, 0.55, zz_fbm(p * 0.08 + vec2(3.0, 8.0)));
	color = mix(color, setts, max(bed, patch_mask));

	// Rails: rusty heads with a lighter worn running edge.
	float rail_d = abs(abs(across) - gauge * 0.5);
	float rail = 1.0 - smoothstep(0.03, 0.03 + fwidth(rail_d) + 0.006, rail_d);
	float shine = 1.0 - smoothstep(0.0, 0.012 + fwidth(rail_d), abs(rail_d - 0.012));
	color = mix(color, rail_color * (0.8 + 0.5 * grain), rail);
	color = mix(color, vec3(0.5, 0.42, 0.34), shine * rail * 0.5);

	// Faded paint: a dashed centre line between the tracks, kerb-side stripe.
	float lane = abs(abs(across) - track_period * 0.5);
	float dash = step(0.5, fract(p.x / 4.0));
	float line = (1.0 - smoothstep(0.07, 0.07 + fwidth(lane), lane)) * dash;
	float wear = smoothstep(0.35, 0.65, zz_fbm(p * 0.7 + 11.0));
	color = mix(color, paint_color, line * wear * 0.85);

	// Oil and puddles.
	float oil = smoothstep(0.62, 0.65, zz_fbm(p * 0.13 + vec2(41.0, 23.0)));
	color = mix(color, oil_color, oil * 0.8);
	float dirt = zz_fbm(p * 0.3 + vec2(71.0, 13.0));
	color = mix(color, vec3(0.1, 0.075, 0.05), smoothstep(0.45, 0.8, dirt) * 0.45);

	ALBEDO = color;
	ROUGHNESS = mix(mix(0.86, 0.6, rail), 0.05, oil);
	SPECULAR = mix(0.4, 0.8, oil);
	METALLIC = rail * 0.2;
}
