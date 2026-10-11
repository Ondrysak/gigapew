shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/slot_lamp.gdshaderinc"

void vertex() {
	float level;
	vec3 color;
	if (!lamp_vertex(UV, COLOR.rgb, level, color)) {
		VERTEX = vec3(0.0);
	}
	v_lamp_level = level;
	v_lamp_color = color;
}

void fragment() {
	// Unlit bulbs stay visibly coloured glass rather than black holes.
	ALBEDO = v_lamp_color * (0.12 + 0.95 * v_lamp_level);
}
