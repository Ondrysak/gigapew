shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Flame vent lane marking on a unit PlaneMesh (center_offset z = -0.5) scaled
// to the lane: dashed amber edge chevrons that brighten while `primed`, and a
// flickering heat glow that follows the flame front (`reach`, 0..1 of the
// lane) while `heat` is up.

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float reach : hint_range(0.0, 1.0) = 1.0;
uniform float primed : hint_range(0.0, 1.0) = 0.0;
uniform vec4 mark_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 heat_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 scorch_color : source_color = vec4(0.05, 0.03, 0.02, 1.0);
uniform float edge_width = 0.14;
uniform float dash = 0.9;

varying vec2 v_meters;
varying vec2 v_size;

void vertex() {
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	// x across the lane from its centre, y metres out from the vent.
	v_meters = vec2(VERTEX.x * v_size.x, -VERTEX.z * v_size.y);
}

void fragment() {
	float across = abs(v_meters.x);
	float along = v_meters.y;
	float to_edge = v_size.x * 0.5 - across;
	float edge = 1.0 - smoothstep(edge_width * 0.6, edge_width, to_edge);
	// Chevrons: dashes slanted toward the far end of the lane.
	float chevron = step(0.45, fract((along - across * 0.6) / dash));
	float fade_out = 1.0 - smoothstep(v_size.y - 1.5, v_size.y, along);
	float marks = edge * chevron * fade_out * (0.35 + 0.45 * primed);
	float front = reach * v_size.y;
	float lit = (1.0 - smoothstep(front - 1.2, front, along)) * fade_out;
	float flicker = 0.75 + 0.25 * sin(along * 2.7 - TIME * 19.0) * sin(across * 5.0 + TIME * 11.0);
	float glow = heat * lit * flicker * (1.0 - smoothstep(0.2, v_size.x * 0.5, across) * 0.6);
	vec3 color = mix(scorch_color.rgb, heat_color.rgb * 1.6, clamp(glow * 1.5, 0.0, 1.0));
	color = mix(color, mark_color.rgb, marks / max(marks + glow, 0.001) * step(0.001, marks));
	ALBEDO = color;
	ALPHA = clamp(max(marks, glow * 0.55 + heat * lit * 0.12), 0.0, 1.0);
}
