shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/floor_common.gdshaderinc"

uniform vec2 area_center = vec2(0.0, 0.0);
uniform vec2 area_half_extents = vec2(48.0, 26.0);
uniform float plate_size = 4.0;
uniform vec3 plate_a : source_color = vec3(0.085, 0.075, 0.065);
uniform vec3 plate_b : source_color = vec3(0.1, 0.086, 0.072);
uniform vec3 seam_color : source_color = vec3(0.022, 0.027, 0.035);
uniform vec3 accent_color : source_color = vec3(1.0, 0.34, 0.065);
uniform vec3 accent_emission = vec3(0.45, 0.13, 0.02);
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.19);
uniform vec3 glow_emission = vec3(0.32, 0.19, 0.04);
uniform float guide_inset = 6.0;
uniform float gantry_spacing = 16.0;

void fragment() {
	vec2 p = world_position.xz;
	vec2 local = p - area_center;
	float half_plate = plate_size * 0.5;

	float plate = aa_checker(p + half_plate, plate_size);
	float seam = max(aa_grid_line(p.x, plate_size, half_plate, 0.035), aa_grid_line(p.y, plate_size, half_plate, 0.035));
	vec3 steel = mix(plate_a, plate_b, plate);
	steel = mix(steel, seam_color, seam * 0.85);

	float inset = rect_inset(p, area_center, area_half_extents);
	float guides = aa_line(abs(local.y) - (area_half_extents.y - guide_inset), 0.06, fwidth(abs(local.y)));
	guides *= 1.0 - smoothstep(area_half_extents.x - 2.2, area_half_extents.x - 2.0, abs(local.x));
	float dashes = aa_grid_line(p.y, 2.0, 0.5, 0.5);
	float gantry = aa_grid_line(local.x, gantry_spacing, gantry_spacing * 0.5, 0.05) * dashes;
	gantry *= step(guide_inset, area_half_extents.y - abs(local.y));
	float accent = max(guides, gantry * 0.55);

	float band_fw = max(fwidth(inset), 1e-4);
	float band = smoothstep(0.25 - band_fw, 0.25 + band_fw, inset) * (1.0 - smoothstep(1.4 - band_fw, 1.4 + band_fw, inset));
	float hazard = band * aa_stripes(p, 1.4);
	float edge = aa_rect_line(p, area_center, area_half_extents, 1.8, 0.05);
	float glow = max(hazard, edge * 0.6);

	ALBEDO = mix(mix(steel, accent_color, accent), glow_color, glow);
	EMISSION = accent_emission * accent + glow_emission * glow;
	ROUGHNESS = 0.55;
	METALLIC = 0.5;
}
