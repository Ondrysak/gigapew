shader_type spatial;

// Electric floor plate on a unit PlaneMesh scaled to the plate footprint:
// dark grating with hazard-striped borders; the grid glows faintly while idle,
// pulses amber while `warning` rises and crackles white-blue while `live`.

uniform float warning : hint_range(0.0, 1.0) = 0.0;
uniform float live : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_color : source_color = vec4(0.09, 0.1, 0.12, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.95, 0.68, 0.08, 1.0);
uniform vec4 idle_glow : source_color = vec4(0.12, 0.45, 0.85, 1.0);
uniform vec4 warning_glow : source_color = vec4(1.0, 0.5, 0.08, 1.0);
uniform vec4 live_glow : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float idle_strength = 0.35;
uniform float cell = 0.5;
uniform float border = 0.24;
uniform float stripe_width = 0.3;

varying vec2 v_meters;
varying vec2 v_size;

void vertex() {
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	v_meters = (VERTEX.xz + 0.5) * v_size;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = v_meters;
	vec2 edge = min(p, v_size - p);
	float rim = min(edge.x, edge.y);
	float in_border = 1.0 - step(border, rim);
	float stripe = step(0.5, fract((p.x + p.y) / (stripe_width * 2.0)));
	vec2 grid = abs(fract(p / cell) - 0.5);
	float line = smoothstep(0.4, 0.48, max(grid.x, grid.y));
	vec2 tile = floor(p / cell);
	// Travelling crackle: bright bands sweep the grid and random tiles flare.
	float sweep = pow(max(0.0, sin(p.x * 3.1 + TIME * 23.0) * sin(p.y * 2.3 - TIME * 17.0)), 3.0);
	float flare = step(0.86, hash(tile + floor(TIME * 18.0)));
	float crackle = 0.55 + 1.6 * sweep + 1.2 * flare;
	vec3 plate = base_color.rgb * (1.0 - 0.45 * line);
	vec3 border_color = mix(vec3(0.04), stripe_color.rgb, stripe);
	ALBEDO = mix(plate, border_color, in_border);
	METALLIC = mix(0.75, 0.2, in_border);
	ROUGHNESS = mix(0.42, 0.65, in_border);
	vec3 glow = idle_glow.rgb * idle_strength * (1.0 - max(warning, live));
	glow += warning_glow.rgb * warning * 2.2;
	glow += live_glow.rgb * live * 2.6 * crackle;
	float cells = line + live * flare * 0.35 * (1.0 - line);
	// The border's dark stripes also light up amber in warning.
	float rim_glow = in_border * (1.0 - stripe) * warning * 0.6;
	EMISSION = glow * cells * (1.0 - in_border) + warning_glow.rgb * rim_glow;
}
