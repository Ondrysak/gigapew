shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/floor_common.gdshaderinc"

uniform vec2 area_center = vec2(0.0, 0.0);
uniform vec2 area_half_extents = vec2(48.0, 26.0);
uniform float plate_size = 4.0;
// World position of one plate corner, so plate seams line up with the 4 m module grid.
uniform vec2 plate_origin = vec2(-48.0, -26.0);
uniform vec3 plate_a : source_color = vec3(0.085, 0.075, 0.065);
uniform vec3 plate_b : source_color = vec3(0.1, 0.086, 0.072);
uniform vec3 seam_color : source_color = vec3(0.022, 0.027, 0.035);
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.19);
uniform vec3 glow_emission = vec3(0.32, 0.19, 0.04);
// Furnace heat soaking into the plates along the north wall.
uniform vec3 heat_color : source_color = vec3(0.55, 0.16, 0.03);
uniform float heat_edge_z = -26.0;
uniform float heat_depth = 16.0;
uniform float heat_half_width = 20.0;

void fragment() {
	vec2 p = world_position.xz;
	vec2 q = p - plate_origin;

	float plate = aa_checker(q, plate_size);
	float seam = max(aa_grid_line(q.x, plate_size, 0.0, 0.035), aa_grid_line(q.y, plate_size, 0.0, 0.035));
	float bolts = aa_grid_line(q.x, plate_size * 0.5, plate_size * 0.25, 0.05) * aa_grid_line(q.y, plate_size * 0.5, plate_size * 0.25, 0.05);
	vec3 steel = mix(plate_a, plate_b, plate);
	steel = mix(steel, seam_color, max(seam * 0.85, bolts * 0.6));

	float inset = rect_inset(p, area_center, area_half_extents);
	float band_fw = max(fwidth(inset), 1e-4);
	float band = smoothstep(0.25 - band_fw, 0.25 + band_fw, inset) * (1.0 - smoothstep(1.4 - band_fw, 1.4 + band_fw, inset));
	float hazard = band * aa_stripes(p, 1.4);
	float edge = aa_rect_line(p, area_center, area_half_extents, 1.8, 0.05);
	float heat = (1.0 - smoothstep(0.0, heat_depth, p.y - heat_edge_z)) * (1.0 - smoothstep(heat_half_width - 4.0, heat_half_width, abs(p.x - area_center.x)));
	heat *= heat * (1.0 - seam * 0.5);
	float glow = max(hazard, edge * 0.6);

	ALBEDO = mix(steel + heat_color * heat * 0.25, glow_color, glow);
	EMISSION = glow_emission * glow + heat_color * heat * 0.35;
	ROUGHNESS = 0.55;
	METALLIC = 0.5;
}
