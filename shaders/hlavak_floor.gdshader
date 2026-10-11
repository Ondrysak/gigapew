shader_type spatial;
render_mode diffuse_burley;

// Hlavní nádraží concourse floor: cream-and-brown terrazzo squares, brass
// inlay rings around the middle, cigarette-burnt stains, and a faint violet
// delirium that creeps through the cracks.

#include "res://shaders/floor_common.gdshaderinc"
#include "res://shaders/zizkov_common.gdshaderinc"

uniform vec2 center = vec2(0.0, 0.0);
uniform float tile_size = 1.6;
uniform vec3 tile_a : source_color = vec3(0.3, 0.26, 0.2);
uniform vec3 tile_b : source_color = vec3(0.19, 0.15, 0.11);
uniform vec3 grout_color : source_color = vec3(0.07, 0.06, 0.05);
uniform vec3 brass : source_color = vec3(0.5, 0.36, 0.14);
uniform vec3 stain_color : source_color = vec3(0.1, 0.075, 0.05);
uniform vec3 delirium : source_color = vec3(0.5, 0.18, 0.78);
uniform vec4 ring_radii = vec4(5.0, 10.0, 15.0, 27.0);

void fragment() {
	vec2 p = world_position.xz;
	float checker = aa_checker(p + tile_size * 0.5, tile_size);
	float grout = max(aa_grid_line(p.x, tile_size, tile_size * 0.5, 0.012), aa_grid_line(p.y, tile_size, tile_size * 0.5, 0.012));
	float speckle = zz_noise(p * 14.0) * 0.6 + zz_noise(p * 31.0) * 0.4;
	vec3 color = mix(tile_a, tile_b, checker) * (0.78 + 0.4 * speckle);
	color = mix(color, grout_color, grout * 0.85);

	// Brass inlay rings of the hall's mosaic.
	float radius = length(p - center);
	float ring = 0.0;
	for (int i = 0; i < 4; i++) {
		float r = ring_radii[i];
		ring = max(ring, aa_line(radius - r, i == 1 ? 0.07 : 0.045, fwidth(radius)) * (i == 3 ? 0.6 : 1.0));
	}
	color = mix(color, brass * (0.8 + 0.4 * speckle), ring);

	// Foot-traffic wear, stains and burns.
	float dirt = zz_fbm(p * 0.28 + vec2(13.0, 71.0));
	color = mix(color, stain_color, smoothstep(0.45, 0.75, dirt) * 0.6);
	float burn = smoothstep(0.86, 0.9, zz_noise(p * 3.1 + 40.0));
	color = mix(color, vec3(0.025, 0.02, 0.015), burn * 0.7);

	// Violet seeping up out of the cracks, slowly breathing.
	float crack = abs(zz_fbm(p * 0.45 + vec2(5.0, 1.0)) - 0.5);
	float vein = (1.0 - smoothstep(0.0, 0.025 + fwidth(crack), crack)) * smoothstep(0.35, 0.6, zz_fbm(p * 0.09 + 3.0));
	float pulse = 0.55 + 0.45 * sin(TIME * 0.8 + radius * 0.25);

	ALBEDO = color;
	EMISSION = delirium * vein * pulse * 0.55;
	ROUGHNESS = mix(0.62, 0.9, smoothstep(0.3, 0.7, dirt));
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
