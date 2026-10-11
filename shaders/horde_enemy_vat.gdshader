shader_type spatial;
render_mode diffuse_burley;

// Vertex-animated horde enemy (see HordeVertexAnimation). The mesh's UV2.x picks
// the VAT column; per-instance COLOR carries the animation state:
// r = frame within the clip (fractional; interpolated), g = clip start frame,
// b = clip frame count, a = 1 for looping clips (wrap) else 0 (hold last frame).
#include "res://shaders/horde_enemy_common.gdshaderinc"

uniform sampler2D vat_positions : filter_nearest, repeat_disable;
uniform sampler2D vat_normals : filter_nearest, repeat_disable;
uniform int vat_vertex_count = 1;
// Procedural lean (radians) at bob_speed, pivoting at the feet.
uniform float sway_amplitude = 0.0;
// Menu previews use one MeshInstance per monster rather than a MultiMesh.
// Per-instance uniforms preserve shared materials for all copies of a species.
instance uniform float preview_frame = -1.0;
instance uniform float preview_start = 0.0;
instance uniform float preview_count = 1.0;
// Face atlas: columns, rows, first cell, cell count. The surface whose UV spans cell
// 0 shows one of `count` cells per instance, picked from the random animation phase.
uniform vec4 face_atlas = vec4(1.0, 1.0, 0.0, 1.0);

ivec2 vat_texel(int column, int frame, int width, int rows) {
	return ivec2(column % width, frame * rows + column / width);
}

vec3 anatomy_joint_delta(vec4 reference, int start, int f0, int f1, float blend, int width, int rows) {
	int column = clamp(int(reference.w * float(vat_vertex_count)), 0, vat_vertex_count - 1);
	vec3 a = texelFetch(vat_positions, vat_texel(column, start + f0, width, rows), 0).xyz;
	vec3 b = texelFetch(vat_positions, vat_texel(column, start + f1, width, rows), 0).xyz;
	return mix(a, b, blend) - reference.xyz;
}

void vertex() {
	int width = max(textureSize(vat_positions, 0).x, 1);
	int rows = (vat_vertex_count + width - 1) / width;
	int column = clamp(int(UV2.x * float(vat_vertex_count)), 0, vat_vertex_count - 1);
	float local = max(preview_frame >= 0.0 ? preview_frame : COLOR.r, 0.0);
	int start = int((preview_frame >= 0.0 ? preview_start : COLOR.g) + 0.5);
	int count = max(int((preview_frame >= 0.0 ? preview_count : COLOR.b) + 0.5), 1);
	int f0 = int(floor(local));
	float blend = local - float(f0);
	int f1 = f0 + 1;
	if (preview_frame >= 0.0 || COLOR.a > 0.5) {
		f0 = f0 % count;
		f1 = f1 % count;
	} else {
		f0 = min(f0, count - 1);
		f1 = min(f1, count - 1);
	}
	vec3 p0 = texelFetch(vat_positions, vat_texel(column, start + f0, width, rows), 0).xyz;
	vec3 p1 = texelFetch(vat_positions, vat_texel(column, start + f1, width, rows), 0).xyz;
	vec3 n0 = texelFetch(vat_normals, vat_texel(column, start + f0, width, rows), 0).xyz;
	vec3 n1 = texelFetch(vat_normals, vat_texel(column, start + f1, width, rows), 0).xyz;
	vec3 posed = mix(p0, p1, blend);
	v_local = posed;
	// Previews carry no crowd custom data and must never look fused.
	v_fusion = preview_frame >= 0.0 ? 0.0 : horde_fusion(INSTANCE_CUSTOM.z);
	float phase = horde_phase(INSTANCE_CUSTOM.z);
	if (face_atlas.x * face_atlas.y > 1.0) {
		float pick = min(floor((phase / HORDE_TAU) * face_atlas.w), face_atlas.w - 1.0);
		float cell = face_atlas.z + pick;
		UV += vec2(mod(cell, face_atlas.x) / face_atlas.x, floor(cell / face_atlas.x) / face_atlas.y);
	}
	vec3 normal = normalize(mix(n0, n1, blend));
	// Rotate the rest tangent frame onto the animated normal (normal maps).
	vec3 axis = cross(NORMAL, normal);
	float s = length(axis);
	float c = dot(NORMAL, normal);
	if (s > 0.0001) {
		vec3 k = axis / s;
		TANGENT = TANGENT * c + cross(k, TANGENT) * s + k * dot(k, TANGENT) * (1.0 - c);
		BINORMAL = BINORMAL * c + cross(k, BINORMAL) * s + k * dot(k, BINORMAL) * (1.0 - c);
	}
	float variation = sin(phase * 3.0 + 0.7);
	// Fused stomps follow the sampled gait and freeze with it while paused.
	float wave = v_fusion > 0.0 ? local / float(count) * HORDE_TAU + phase
		: TIME * bob_speed * (1.0 + variation * 0.08) + phase;
	if (sway_amplitude != 0.0 && v_fusion <= 0.0) {
		float roll = sin(wave) * sway_amplitude * (1.0 + variation * 0.12);
		float pitch = sin(wave * 0.5 + phase * 0.3 + 1.3) * sway_amplitude * 0.6;
		mat3 lean = mat3(vec3(cos(roll), sin(roll), 0.0), vec3(-sin(roll), cos(roll), 0.0), vec3(0.0, 0.0, 1.0))
			* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(pitch), sin(pitch)), vec3(0.0, -sin(pitch), cos(pitch)));
		posed = lean * posed;
		normal = lean * normal;
		TANGENT = lean * TANGENT;
		BINORMAL = lean * BINORMAL;
	}
	if (v_fusion > 0.0) {
		horde_fused_pose(posed, normal, TANGENT, BINORMAL, v_fusion, wave);
	} else {
		posed.y += sin(wave) * bob_amplitude * (1.0 + variation * 0.12);
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	if (anatomy_enabled) {
		int piece = clamp(int(mod(UV2.y, 8.0)) - 1, 0, 5);
		vec3 pivot_delta = anatomy_joint_delta(anatomy_pivot_refs[piece], start, f0, f1, blend, width, rows);
		vec3 tip_delta = anatomy_joint_delta(anatomy_tip_refs[piece], start, f0, f1, blend, width, rows);
		horde_anatomy_pose(posed, normal, TANGENT, BINORMAL, UV2.y, phase, pivot_delta, tip_delta, origin, camera);
	}
	VERTEX = posed;
	NORMAL = normal;
	if (length(origin.xz - camera.xz) < near_cull) {
		VERTEX = vec3(0.0);
	}
	v_flash = preview_frame >= 0.0 ? 0.0 : INSTANCE_CUSTOM.x * flash_strength;
	v_telegraph = preview_frame >= 0.0 ? 0.0 : INSTANCE_CUSTOM.y;
	v_frost = preview_frame >= 0.0 ? 0.0 : INSTANCE_CUSTOM.w;
}

void fragment() {
	horde_surface(UV, NORMAL, VIEW, TIME, v_local, v_fusion, v_flash, v_telegraph, v_frost, ALBEDO, ROUGHNESS, METALLIC, EMISSION);
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
