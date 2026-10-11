shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

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
	float r = length(UV2);
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = v_lamp_color;
	ALPHA = falloff * falloff * v_lamp_level * 0.55;
}
