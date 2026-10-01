shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D history : filter_linear, repeat_disable;
uniform bool history_valid = false;
uniform float step_seconds = 0.0167;
uniform float aspect = 1.77778;
uniform float phase = 0.0;
uniform float contact = 0.0;
uniform float fracture = 0.0;
uniform float resonance = 0.0;
uniform float progress = 0.0;
uniform vec4 mineral_color : source_color = vec4(1.0, 0.7, 0.3, 1.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float radius = length(p);
	// The central opening never receives either history or new motifs.
	float opening = smoothstep(0.085, 0.13, radius);
	float envelope = opening * (1.0 - smoothstep(0.3, 0.49, radius));
	float angle = step_seconds * (0.12 + resonance * 0.14);
	mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 previous_p = turn * p / (1.0 + step_seconds * 0.18);
	// A small mirrored displacement folds echoes without warping the game image.
	previous_p += vec2(abs(p.y), abs(p.x)) * step_seconds * 0.012;
	vec2 previous_uv = previous_p / vec2(aspect, 1.0) + vec2(0.5);
	vec4 previous = vec4(0.0);
	if (history_valid) {
		previous = texture(history, clamp(previous_uv, vec2(0.0), vec2(1.0)));
	}
	float retained = previous.a * exp(-step_seconds * 6.0) * opening;
	// Four bounded triangular folds produce branching crystal contours.
	vec2 crystal = p * (4.6 + progress * 1.4);
	float contour = 1.0;
	for (int level = 0; level < 4; level++) {
		crystal = abs(crystal);
		crystal = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * crystal;
		crystal = crystal * 1.53 - vec2(0.43, 0.28);
		contour = min(contour, abs(crystal.x + crystal.y * 0.45) / (1.0 + float(level)));
	}
	float filaments = 1.0 - smoothstep(0.009, 0.028, contour);
	float ring = exp(-abs(radius - (0.18 + 0.035 * sin(phase * 1.3))) * 65.0);
	float beat = 0.75 + 0.25 * sin(phase * 9.0 + radius * 30.0);
	float injected = envelope * (filaments * contact * beat * (0.055 + resonance * 0.05) + ring * fracture * 0.30);
	float alpha = clamp(retained + injected * min(step_seconds * 60.0, 2.0), 0.0, 0.42) * envelope;
	vec3 tint = mix(mineral_color.rgb, vec3(0.9, 0.98, 1.0), fracture * 0.35);
	vec3 rgb = (previous.rgb * retained + tint * injected) / max(retained + injected, 0.00001);
	COLOR = vec4(clamp(rgb, vec3(0.0), vec3(1.0)), alpha);
}
