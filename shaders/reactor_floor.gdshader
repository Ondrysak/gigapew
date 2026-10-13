shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/floor_common.gdshaderinc"

uniform vec2 area_center = vec2(0.0, 0.0);
uniform vec2 area_half_extents = vec2(38.0, 38.0);
uniform float tile_size = 4.0;
uniform vec3 tile_a : source_color = vec3(0.06, 0.075, 0.105);
uniform vec3 tile_b : source_color = vec3(0.07, 0.086, 0.122);
uniform vec3 seam_color : source_color = vec3(0.022, 0.027, 0.045);
uniform vec3 steel_color : source_color = vec3(0.22, 0.25, 0.28);
uniform vec3 teal_color : source_color = vec3(0.19, 0.92, 0.86);
uniform vec3 teal_emission = vec3(0.05, 0.42, 0.38);
uniform vec3 violet_color : source_color = vec3(0.65, 0.33, 1.0);
uniform vec3 violet_emission = vec3(0.3, 0.12, 0.5);
uniform vec4 ring_radii = vec4(5.0, 10.0, 15.0, 27.0);
uniform float spoke_count = 12.0;

void fragment() {
	vec2 p = world_position.xz;
	vec2 pattern = floor_hallucinated_uv(p);
	vec2 local = p - area_center;
	float half_tile = tile_size * 0.5;

	float tile = aa_checker(pattern + half_tile, tile_size);
	float seam = max(aa_grid_line(pattern.x, tile_size, half_tile, 0.03), aa_grid_line(pattern.y, tile_size, half_tile, 0.03));
	vec3 base = mix(tile_a, tile_b, tile);
	base = mix(base, seam_color, seam * 0.8);

	float radius = length(local);
	float angle = atan(local.y, local.x) / TAU * spoke_count;
	float spoke_distance = abs(fract(angle + 0.5) - 0.5) / spoke_count * TAU * radius;
	float spoke_fw = fwidth(spoke_distance);
	float spokes = aa_line(spoke_distance, 0.06, spoke_fw);
	spokes *= smoothstep(ring_radii.y + 1.5, ring_radii.y + 2.0, radius) * (1.0 - smoothstep(ring_radii.z + 2.5, ring_radii.z + 3.0, radius));
	float index_band = aa_line(radius - (ring_radii.z + 4.5), 0.35, fwidth(radius));
	float index_marks = index_band * aa_line(spoke_distance, 0.3, spoke_fw);
	base = mix(base, steel_color, spokes * 0.8);

	float teal = max(aa_ring(p, area_center, ring_radii.x, 0.09), aa_ring(p, area_center, ring_radii.z, 0.09));
	teal = max(teal, aa_rect_line(p, area_center, area_half_extents, 1.5, 0.06) * 0.8);
	float violet = max(aa_ring(p, area_center, ring_radii.y, 0.09), aa_ring(p, area_center, ring_radii.w, 0.05) * 0.6);
	violet = max(violet, index_marks);

	float inset = rect_inset(p, area_center, area_half_extents);
	float band_fw = max(fwidth(inset), 1e-4);
	float band = smoothstep(0.2 - band_fw, 0.2 + band_fw, inset) * (1.0 - smoothstep(0.9 - band_fw, 0.9 + band_fw, inset));
	violet = max(violet, band * aa_stripes(p, 1.0) * 0.7);

	ALBEDO = mix(mix(base, teal_color, teal), violet_color, violet);
	EMISSION = teal_emission * teal + violet_emission * violet;
	ROUGHNESS = 0.55;
	METALLIC = 0.5;
}
