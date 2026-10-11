shader_type spatial;
render_mode unshaded;

// Plain paper pack, red tax band and two printed lines; original procedural art.
void fragment() {
	float band = step(0.68, UV.y) * step(UV.y, 0.86);
	float print_line = step(0.2, UV.x) * step(UV.x, 0.8) * (step(0.3, UV.y) * step(UV.y, 0.34) + step(0.41, UV.y) * step(UV.y, 0.45));
	ALBEDO = mix(vec3(0.88, 0.83, 0.65), vec3(0.53, 0.08, 0.035), band);
	ALBEDO = mix(ALBEDO, vec3(0.11, 0.1, 0.065), clamp(print_line, 0.0, 1.0));
	ROUGHNESS = 0.94;
}
