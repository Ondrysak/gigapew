shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/floor_common.gdshaderinc"

uniform vec2 area_center = vec2(0.0, 0.0);
uniform vec2 area_half_extents = vec2(32.0, 32.0);
uniform float panel_size = 4.0;
uniform vec3 steel_a = vec3(0.105, 0.145, 0.175);
uniform vec3 steel_b = vec3(0.125, 0.17, 0.2);
uniform vec3 seam_color = vec3(0.027, 0.047, 0.063);
uniform vec3 cyan_color = vec3(0.1, 0.58, 0.63);
uniform vec3 cyan_emission = vec3(0.035, 0.33, 0.38);
uniform vec3 amber_color = vec3(0.78, 0.46, 0.12);
uniform vec3 amber_emission = vec3(0.22, 0.09, 0.015);
uniform float ring_radius = 7.2;
uniform float lane_offset = 14.0;

void fragment() {
	vec2 p = world_position.xz;
	vec2 local = p - area_center;
	float half_panel = panel_size * 0.5;

	float panel = aa_checker(p + half_panel, panel_size);
	float seam = max(aa_grid_line(p.x, panel_size, half_panel, 0.04), aa_grid_line(p.y, panel_size, half_panel, 0.04));
	vec3 steel = mix(steel_a, steel_b, panel);
	steel = mix(steel, seam_color, seam * 0.85);

	float angle_mask = abs(sin(atan(local.y, local.x) * 4.0));
	float broken = smoothstep(0.2, 0.28, angle_mask);
	float ring = aa_ring(p, area_center, ring_radius, 0.07) * broken;
	float inner_ring = aa_ring(p, area_center, ring_radius - 0.7, 0.025);
	float lane_x = aa_line(abs(local.x) - lane_offset, 0.07, fwidth(abs(local.x))) * smoothstep(9.0, 9.5, abs(local.y));
	float lane_z = aa_line(abs(local.y) - lane_offset, 0.07, fwidth(abs(local.y))) * smoothstep(9.0, 9.5, abs(local.x));
	float cyan = max(max(ring, inner_ring * 0.38), max(lane_x, lane_z) * 0.7);

	float inset = rect_inset(p, area_center, area_half_extents);
	float perimeter = aa_rect_line(p, area_center, area_half_extents, 1.7, 0.09);
	float band_fw = max(fwidth(inset), 1e-4);
	float band = smoothstep(0.25 - band_fw, 0.25 + band_fw, inset) * (1.0 - smoothstep(1.2 - band_fw, 1.2 + band_fw, inset));
	float hazard = band * aa_stripes(p, 1.2);
	float amber = max(perimeter * 0.65, hazard);

	ALBEDO = mix(mix(steel, cyan_color, cyan), amber_color, amber);
	EMISSION = cyan_emission * cyan + amber_emission * amber;
	ROUGHNESS = 0.78;
	METALLIC = 0.3;
}
