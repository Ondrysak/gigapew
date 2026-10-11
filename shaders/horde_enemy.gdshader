shader_type spatial;
render_mode diffuse_burley;

// Static (non-animated) horde enemy: one material per baked surface.
#include "res://shaders/horde_enemy_common.gdshaderinc"

void vertex() {
	v_flash = INSTANCE_CUSTOM.x * flash_strength;
	v_telegraph = INSTANCE_CUSTOM.y;
	v_frost = INSTANCE_CUSTOM.w;
	v_fusion = horde_fusion(INSTANCE_CUSTOM.z);
	v_local = VERTEX;
	float phase = horde_phase(INSTANCE_CUSTOM.z);
	float variation = sin(phase * 3.0 + 0.7);
	float wave = (v_fusion > 0.0 ? hallucination_time : TIME) * bob_speed * (v_fusion > 0.0 ? 0.38 : 1.0 + variation * 0.08) + phase;
	if (v_fusion > 0.0) {
		horde_fused_pose(VERTEX, NORMAL, TANGENT, BINORMAL, v_fusion, wave);
	} else {
		VERTEX.y += sin(wave) * bob_amplitude * (1.0 + variation * 0.12);
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	horde_anatomy_pose(VERTEX, NORMAL, TANGENT, BINORMAL, UV2.y, phase, vec3(0.0), vec3(0.0), origin, camera);
	if (length(origin.xz - camera.xz) < near_cull) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	horde_surface(UV, NORMAL, VIEW, TIME, v_local, v_fusion, v_flash, v_telegraph, v_frost, ALBEDO, ROUGHNESS, METALLIC, EMISSION);
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
