shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Additive glow around fruit-machine candle tiers and buttons; UV spans -1..1.
#include "res://shaders/slot_machine.gdshaderinc"

varying flat vec3 v_color;
varying flat float v_level;

void vertex() {
	int code = int(UV2.y + 0.5);
	vec3 color = COLOR.rgb;
	v_level = sm_light(int(UV2.x + 0.5), code % 4, code / 4, sm_time(), COLOR.rgb, color);
	v_color = color;
}

void fragment() {
	float r = length(UV);
	float falloff = max(1.0 - r * r, 0.0);
	ALBEDO = v_color;
	ALPHA = falloff * falloff * v_level * 0.5;
}
