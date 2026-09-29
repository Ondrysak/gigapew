shader_type spatial;
render_mode diffuse_burley;

// Static (non-animated) horde enemy: one material per baked surface.
#include "res://shaders/horde_enemy_common.gdshaderinc"

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	if (length(origin.xz - camera.xz) < near_cull) {
		VERTEX = vec3(0.0);
	}
	v_flash = INSTANCE_CUSTOM.x * flash_strength;
	v_telegraph = INSTANCE_CUSTOM.y;
	v_frost = INSTANCE_CUSTOM.w;
	VERTEX.y += sin(TIME * bob_speed + INSTANCE_CUSTOM.z) * bob_amplitude;
}

void fragment() {
	horde_surface(UV, NORMAL, VIEW, TIME, v_flash, v_telegraph, v_frost, ALBEDO, ROUGHNESS, METALLIC, EMISSION);
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
