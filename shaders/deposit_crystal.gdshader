shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 mineral_color : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec3 weak_position = vec3(0.0);
uniform float weak_radius = 0.25;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float formation_seed = 0.0;
varying vec3 crystal_position;

void vertex() {
	crystal_position = VERTEX;
}

void fragment() {
	// Bounded folds repeat at three scales: an independent mineral pattern.
	vec3 p = crystal_position * 3.2 + vec3(formation_seed, 0.17, 0.41);
	float seams = 0.0;
	float structure = 0.0;
	float weight = 0.6;
	for (int octave = 0; octave < 3; octave++) {
		vec3 fold = abs(fract(p) - 0.5);
		float edge = min(fold.x, min(fold.y, fold.z));
		float width = 0.018 + damage * 0.055;
		seams += (1.0 - smoothstep(width, width + 0.025, edge)) * weight;
		structure += dot(fold, vec3(0.45, 0.35, 0.2)) * weight;
		p = abs(p) * 2.07 + vec3(0.19, 0.37, 0.11);
		weight *= 0.48;
	}
	float distance_to_seam = length(crystal_position - weak_position) / max(weak_radius, 0.01);
	float weak_core = 1.0 - smoothstep(0.45, 1.0, distance_to_seam);
	float weak_ring = 1.0 - smoothstep(0.08, 0.23, abs(distance_to_seam - 0.8));
	float weak_light = max(weak_core * 0.55, weak_ring);
	vec3 pale = mix(mineral_color.rgb, vec3(1.0), 0.7);
	ALBEDO = mineral_color.rgb * (0.28 + structure * 0.65) * (1.0 - seams * damage * 0.45);
	ALBEDO = mix(ALBEDO, pale, weak_light * 0.7 + flash * 0.5);
	EMISSION = mineral_color.rgb * (0.055 + seams * (0.2 + damage * 0.85)) + pale * (weak_light * 0.95 + flash * 1.3);
	METALLIC = 0.35;
	ROUGHNESS = 0.34 + damage * 0.25;
}
