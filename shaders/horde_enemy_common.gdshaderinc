// Shared surface for batched horde enemies (static and vertex-animated).
// Per-instance state arrives in INSTANCE_CUSTOM:
// x = status bits as the integer part (1 burning, 2 charged, 4 hyped,
//     8 hype source, 16 dazed) + hit flash 0..0.99 as the fraction,
// y = attack telegraph 0..1 (-1 = stagger),
// z = phase [0, TAU) + TAU * (fusion members - 1); ordinary enemies have one member,
// w = slow strength 0..1 (frost tint), -1 = Tag Burst exposure.
global uniform float hallucination_intensity;
global uniform float hallucination_time;
global uniform float hallucination_escalation;
global uniform float hallucination_beat;
global uniform int hallucination_mode;
// Only the once-baked appendage subset enables this; the real body is unchanged.
uniform bool anatomy_enabled = false;
uniform vec3 anatomy_head_origin = vec3(0.0, 1.15, 0.0);
uniform vec3 anatomy_left_arm = vec3(-0.2, 0.9, 0.0);
uniform vec3 anatomy_right_arm = vec3(0.2, 0.9, 0.0);
uniform vec3 anatomy_left_leg = vec3(-0.1, 0.5, 0.0);
uniform vec3 anatomy_right_leg = vec3(0.1, 0.5, 0.0);
uniform vec3 anatomy_left_arm_tip = vec3(-0.3, 0.4, 0.0);
uniform vec3 anatomy_right_arm_tip = vec3(0.3, 0.4, 0.0);
uniform vec3 anatomy_left_leg_tip = vec3(-0.1, 0.0, 0.0);
uniform vec3 anatomy_right_leg_tip = vec3(0.1, 0.0, 0.0);
uniform float anatomy_head_width = 0.4;
uniform float anatomy_head_radius = 0.35;
uniform bool anatomy_upright = true;
// Rest vertex references used only by VAT appendages to carry the attachment
// joints with the same sampled clip/frame as the source limb.
uniform vec4 anatomy_pivot_refs[6];
uniform vec4 anatomy_tip_refs[6];
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
// ORM-style packed texture; each channel vector selects the texture channel
// (all zero = no texture, use the scalar alone).
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0);
uniform vec4 metallic_channel = vec4(0.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// Textured imports flagged unshaded use their albedo as a low-intensity glow,
// not a flat white emission that erases all painted detail.
uniform float unshaded_texture_energy = 0.0;
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
// Fresnel silhouette glow; alpha is strength.
uniform vec4 rim_color : source_color = vec4(0.0);
uniform vec4 flash_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float flash_strength = 0.65;
uniform vec4 telegraph_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform float bob_amplitude = 0.05;
uniform float bob_speed = 6.0;
uniform vec4 frost_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
// Enemies standing within this horizontal distance of the camera collapse to
// nothing, so bodies pressed against the player never hide the crowd beyond.
// Done per vertex (no fragment discard) to keep early depth rejection intact.
uniform float near_cull = 1.2;
// 0..1 dirt: mud up the legs, dark stains and damp patches, from model-space position.
uniform float grime : hint_range(0.0, 1.0) = 0.0;
// Model-space dimensions supplied for both static and VAT materials.
uniform float fusion_body_height = 1.4;
uniform vec4 fusion_weak_spot = vec4(0.0, 1.15, 0.0, 0.22);
const float HORDE_TAU = 6.28318530718;

varying float v_flash;
varying float v_telegraph;
varying float v_frost;
varying float v_fusion;
varying vec3 v_local;
varying float v_status;

float horde_status(float encoded) {
	return floor(max(encoded, 0.0));
}

float horde_flash(float encoded) {
	return max(encoded, 0.0) - horde_status(encoded);
}

// Combo statuses stay readable without per-enemy nodes: burning bodies glow
// orange, charged rims crackle violet, hyped allies carry a gold rim and the
// hype source itself pulses magenta. Daze pulses the entire body orange/gold,
// not just a rim, without changing its silhouette or shot precision geometry.
void horde_status_surface(float status, vec3 normal, vec3 view, float time, vec3 local_pos, inout vec3 out_albedo, inout vec3 out_emission) {
	if (status < 0.5) {
		return;
	}
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 2.0);
	float burning = mod(status, 2.0);
	float charged = mod(floor(status / 2.0), 2.0);
	float hyped = mod(floor(status / 4.0), 2.0);
	float source = mod(floor(status / 8.0), 2.0);
	float lick = 0.75 + 0.25 * sin(time * 17.0 + local_pos.y * 9.0);
	out_emission += vec3(1.0, 0.38, 0.06) * burning * (0.25 + rim * 1.6) * lick;
	float crackle = step(0.8, fract(time * 7.3 + local_pos.y * 2.3 + local_pos.x * 1.7));
	out_emission += vec3(0.62, 0.45, 1.0) * charged * rim * (1.0 + 2.0 * crackle);
	out_emission += vec3(1.0, 0.8, 0.12) * hyped * rim * 1.2;
	out_albedo = mix(out_albedo, vec3(1.0, 0.25, 0.75), source * 0.35);
	out_emission += vec3(1.0, 0.25, 0.75) * source * (0.35 + rim * 1.8) * (0.6 + 0.4 * sin(time * 9.0));
	float dazed = mod(floor(status / 16.0), 2.0);
	float daze_pulse = 0.5 + 0.5 * sin(hallucination_time * 10.0);
	vec3 daze_gold = mix(vec3(1.0, 0.31, 0.025), vec3(1.0, 0.78, 0.08), daze_pulse);
	out_albedo = mix(out_albedo, daze_gold, dazed * (0.55 + 0.25 * daze_pulse));
	out_emission = mix(out_emission, daze_gold * (0.85 + 1.5 * daze_pulse + rim * 0.6), dazed);
}

float horde_phase(float encoded) {
	return fract(encoded / HORDE_TAU) * HORDE_TAU;
}

float horde_fusion(float encoded) {
	return clamp(floor(encoded / HORDE_TAU), 0.0, 7.0) / 7.0;
}

// The gradient travels with the torso mask, so the Jacobian transforms normals
// and the tangent frame correctly even at the shoulders and protected core.
vec4 fusion_torso(vec3 p) {
	float height = max(fusion_body_height, 0.01);
	float rise = clamp((p.y / height - 0.12) / 0.20, 0.0, 1.0);
	float fall = clamp((0.76 - p.y / height) / 0.16, 0.0, 1.0);
	float a = rise * rise * (3.0 - 2.0 * rise);
	float b = fall * fall * (3.0 - 2.0 * fall);
	float dy = (6.0 * rise * (1.0 - rise) * b / 0.20 - 6.0 * fall * (1.0 - fall) * a / 0.16) / height;
	vec3 offset = p - fusion_weak_spot.xyz;
	float distance = length(offset);
	float padding = max(fusion_weak_spot.w, height * 0.06);
	float protect = clamp((distance - fusion_weak_spot.w) / padding, 0.0, 1.0);
	float core = protect * protect * (3.0 - 2.0 * protect);
	vec3 gradient = offset / max(distance, 0.001) * (6.0 * protect * (1.0 - protect) / padding);
	return vec4(a * b * gradient + vec3(0.0, dy * core, 0.0), a * b * core);
}

vec3 horde_fusion_push(vec3 posed, float strength, float wave) {
	float stomp = pow(max(sin(wave), 0.0), 4.0);
	vec3 motion = fusion_body_height * vec3(sin(wave) * 0.027 + sin(wave * 2.0 + 0.7) * 0.009, -stomp * 0.022, sin(wave + 0.8) * 0.013);
	return (posed * vec3(0.20, 0.0, 0.10) + motion) * strength;
}

void horde_fused_pose(inout vec3 posed, inout vec3 normal, inout vec3 tangent, inout vec3 binormal, float fusion, float wave) {
	if (fusion <= 0.0) {
		return;
	}
	vec4 torso = fusion_torso(posed);
	float strength = mix(0.85, 1.0, fusion);
	vec3 push = horde_fusion_push(posed, strength, wave);
	vec3 scale = vec3(1.0) + vec3(0.20, 0.0, 0.10) * torso.w * strength;
	mat3 jacobian = mat3(vec3(scale.x, 0.0, 0.0) + push * torso.x,
		vec3(0.0, 1.0, 0.0) + push * torso.y,
		vec3(0.0, 0.0, scale.z) + push * torso.z);
	float handedness = dot(cross(normal, tangent), binormal) < 0.0 ? -1.0 : 1.0;
	normal = normalize(mat3(cross(jacobian[1], jacobian[2]), cross(jacobian[2], jacobian[0]), cross(jacobian[0], jacobian[1])) * normal);
	tangent = jacobian * tangent;
	tangent = normalize(tangent - normal * dot(normal, tangent));
	binormal = normalize(cross(normal, tangent)) * handedness;
	posed += push * torso.w;
}

// UV2.y identifies a whole rest-selected triangle subset, never an animated
// clipping plane. VAT columns/UVs and the source tangent frame stay intact.
void horde_anatomy_pose(inout vec3 posed, inout vec3 normal, inout vec3 tangent, inout vec3 binormal, float encoded_piece, float phase, vec3 pivot_delta, vec3 tip_delta, vec3 origin, vec3 camera) {
	if (!anatomy_enabled) {
		return;
	}
	float piece = mod(encoded_piece, 8.0);
	float level = floor(mod(encoded_piece, 32.0) / 8.0);
	float branch = floor(encoded_piece / 32.0);
	float distance = length(origin - camera);
	float strength = clamp(hallucination_intensity, 0.0, 1.0)
		* smoothstep(near_cull + 0.25, near_cull + 1.5, distance)
		* (1.0 - smoothstep(20.0, 36.0, distance));
	float escalation = clamp(hallucination_escalation, 0.0, 1.0);
	float rank = clamp(escalation / max(hallucination_intensity, 0.0001), 0.0, 1.0);
	float crystal = smoothstep(0.35, 0.70, rank);
	float maximum = smoothstep(0.70, 1.0, rank);
	float side = mod(piece, 2.0) > 0.5 ? -1.0 : 1.0;
	float clock = hallucination_time * (0.55 + 0.12 * sin(phase + piece)) + phase + piece * 1.71;
	bool head = piece < 2.5;
	bool arm = piece < 4.5;
	vec3 pivot = head ? anatomy_head_origin : arm
		? (side < 0.0 ? anatomy_left_arm : anatomy_right_arm)
		: (side < 0.0 ? anatomy_left_leg : anatomy_right_leg);
	pivot += pivot_delta;
	float roll;
	float pitch;
	mat3 hinge;
	float root_strength = sqrt(strength);
	float size = root_strength * (head ? 0.73 : 0.93);
	if (head) {
		// Beat breathing only shrinks source-head copies: the pre-existing
		// swept-radius clearance remains an upper bound at every rank.
		size *= 1.0 - escalation * (0.22 * hallucination_beat + 0.10 * crystal + 0.08 * maximum);
	}
	// Spin only the baked source-head copies. The primary surface never enters
	// this path; its VAT pose and precision target remain untouched.
	if (head && (hallucination_mode == 4 || hallucination_mode == 5)) {
		float spin_phase = phase + level * 0.67 + piece * 1.71;
		float spin_rate = (hallucination_mode == 5 ? 0.36 : 0.46) + 0.06 * sin(phase);
		float yaw = side * (hallucination_time * spin_rate + spin_phase
			+ escalation * (1.40 * hallucination_beat
				+ crystal * sin(hallucination_time * 0.71 + spin_phase) * 0.90
				+ maximum * sin(hallucination_time * 1.13 - spin_phase) * 0.65));
		roll = side * 0.17 + sin(hallucination_time * 0.29 + spin_phase) * 0.28
			+ escalation * (0.60 * (hallucination_beat - 0.5)
				+ crystal * sin(hallucination_time * 0.53 + spin_phase) * 0.45);
		pitch = sin(hallucination_time * 0.43 + spin_phase) * 0.12
			+ escalation * (crystal * sin(hallucination_time * 0.67 - spin_phase) * 0.40
				+ maximum * sin(hallucination_time * 0.97 + spin_phase) * 0.30);
		hinge = mat3(vec3(cos(yaw), 0.0, -sin(yaw)), vec3(0.0, 1.0, 0.0), vec3(sin(yaw), 0.0, cos(yaw)))
			* mat3(vec3(cos(roll), sin(roll), 0.0), vec3(-sin(roll), cos(roll), 0.0), vec3(0.0, 0.0, 1.0))
			* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(pitch), sin(pitch)), vec3(0.0, -sin(pitch), cos(pitch)));
		size *= 1.0 + sin(hallucination_time * 0.37 + spin_phase) * 0.045;
	} else {
		roll = head ? side * 0.17 + sin(clock) * 0.12
			: side * (arm ? 0.52 : 0.23) + sin(clock) * (arm ? 0.27 : 0.20);
		pitch = sin(clock * 0.73 + piece) * (head ? 0.14 : 0.31);
		hinge = mat3(vec3(cos(roll), sin(roll), 0.0), vec3(-sin(roll), cos(roll), 0.0), vec3(0.0, 0.0, 1.0))
			* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(pitch), sin(pitch)), vec3(0.0, -sin(pitch), cos(pitch)));
	}
	vec3 offset;
	if (head) {
		offset = vec3(side * (anatomy_head_width * 0.64 + fusion_body_height * 0.06),
			-fusion_body_height * (anatomy_upright ? 0.14 : 0.035), fusion_body_height * 0.035);
	} else {
		// Additional shoulders/hips overlap the torso, while their hands/feet
		// fan outward. Quadrupeds split sideways and along their body axis.
		offset = anatomy_upright
			? vec3(side * fusion_body_height * 0.055, -fusion_body_height * (arm ? 0.11 : 0.055), fusion_body_height * 0.09)
			: vec3(side * fusion_body_height * 0.10, fusion_body_height * 0.05, fusion_body_height * (arm ? -0.14 : 0.14));
	}
	vec3 relative = posed - pivot;
	if (head && level > 0.0) {
		// Three native heads cycle through shrinking depths. The first/last
		// depths collapse smoothly before reassignment, suggesting unending
		// inward growth without ever moving the player's camera or real head.
		float depth = mod(level - 1.0 + hallucination_time * 0.10 + phase * 0.08
			+ escalation * (hallucination_beat * 0.16 + crystal * sin(clock * 0.41) * 0.28
				+ maximum * sin(clock * 0.73 + level) * 0.20), 3.0) + 1.0;
		float envelope = smoothstep(1.0, 1.28, depth) * (1.0 - smoothstep(3.55, 4.0, depth));
		float child_size = pow(0.53, depth);
		float detail = 1.0 - smoothstep(9.0, 21.0, distance + depth * 2.0);
		relative = relative * child_size * envelope * detail
			+ vec3(side * anatomy_head_width * 0.58, anatomy_head_width * 0.55, -anatomy_head_width * 0.28) * (1.0 - child_size);
	} else if (!head && level > 0.0) {
		vec3 tip = arm
			? (side < 0.0 ? anatomy_left_arm_tip : anatomy_right_arm_tip)
			: (side < 0.0 ? anatomy_left_leg_tip : anatomy_right_leg_tip);
		tip += tip_delta;
		// Two children sprout from elbow/wrist; each sprouts two smaller
		// children. Every piece is real source limb triangles, not an ornament.
		for (int d = 2; d >= 1; d--) {
			if (float(d) <= level) {
				float fork = mod(floor(branch / pow(2.0, float(d - 1))), 2.0) * 2.0 - 1.0;
				float angle = fork * 0.62 + sin(clock * 0.67 + float(d) + branch) * 0.16;
				mat3 split = mat3(vec3(cos(angle), sin(angle), 0.0), vec3(-sin(angle), cos(angle), 0.0), vec3(0.0, 0.0, 1.0));
				relative = split * relative * 0.52 + (tip - pivot) * (fork < 0.0 ? 0.52 : 0.76);
				normal = split * normal;
				tangent = split * tangent;
				binormal = split * binormal;
			}
		}
		float detail = 1.0 - smoothstep(12.0, 25.0, distance + level * 3.0);
		relative = mix((tip - pivot) * 0.6, relative, detail);
	}
	posed = pivot + hinge * relative * size + offset * root_strength;
	if (head && (hallucination_mode == 4 || hallucination_mode == 5)) {
		// A long snout can rotate through the real precision face. Extra rank
		// motion only rotates/shrinks, so this full swept sphere (plus VAT
		// padding) also bounds every new beat/crystal orientation.
		// Core clearance does not shrink into the target at low intensity.
		float clearance = anatomy_head_radius * size * 1.2 + fusion_weak_spot.w * 1.35
			+ abs(pivot.x - fusion_weak_spot.x);
		posed.x += side * max(clearance - abs(offset.x) * root_strength, 0.0);
	}
	normal = hinge * normal;
	tangent = hinge * tangent;
	binormal = hinge * binormal;
	if (strength <= 0.0001) {
		posed = vec3(0.0);
	}
}

float grime_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float grime_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(grime_hash(i), grime_hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(grime_hash(i + vec3(0.0, 1.0, 0.0)), grime_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(grime_hash(i + vec3(0.0, 0.0, 1.0)), grime_hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(grime_hash(i + vec3(0.0, 1.0, 1.0)), grime_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

vec3 apply_grime(vec3 color, vec3 p, float amount) {
	if (amount <= 0.0) {
		return color;
	}
	float n = grime_noise(p * 6.0) * 0.6 + grime_noise(p * 17.0 + 3.1) * 0.4;
	float mud = smoothstep(0.95, 0.05, p.y) * (0.55 + 0.45 * grime_noise(p * 11.0));
	float stain = smoothstep(0.52, 0.78, n);
	float damp = smoothstep(0.62, 0.8, grime_noise(p * 3.7 + 9.0)) * smoothstep(0.35, 0.9, p.y) * smoothstep(1.6, 1.0, p.y);
	vec3 dirty = color * mix(1.0, 0.68, amount);
	dirty = mix(dirty, vec3(0.07, 0.05, 0.035), clamp(mud * 0.8 * amount, 0.0, 0.85));
	dirty = mix(dirty, color * vec3(0.32, 0.27, 0.18), stain * 0.65 * amount);
	dirty = mix(dirty, vec3(0.30, 0.27, 0.07), damp * 0.5 * amount);
	return dirty;
}

void horde_surface(vec2 uv, vec3 normal, vec3 view, float time, vec3 local_pos, float fusion, float flash, float telegraph, float frost, out vec3 out_albedo, out float out_roughness, out float out_metallic, out vec3 out_emission) {
	float warning = telegraph > 0.0 ? (0.35 + 0.65 * telegraph) * (0.75 + 0.25 * sin(time * 24.0)) : 0.0;
	float tagged = max(-frost, 0.0);
	float staggered = max(-telegraph, 0.0);
	frost = max(frost, 0.0);
	float quiet = 1.0 - clamp(max(max(warning, flash), max(max(frost, tagged), staggered)), 0.0, 1.0);
	vec3 base = albedo.rgb * texture(albedo_texture, uv).rgb * tint.rgb;
	base = apply_grime(base, local_pos, grime);
	float seam = 0.0;
	float fusion_rim = 0.0;
	vec3 brass = vec3(0.64, 0.36, 0.105);
	if (fusion > 0.0) {
		float height = max(fusion_body_height, 0.01);
		float band = abs(sin((local_pos.y / height + local_pos.x / height * 0.28) * 26.0));
		seam = (1.0 - smoothstep(0.08, 0.20, band)) * fusion_torso(local_pos).w;
		base = mix(base, base * 0.70 + brass * 0.30, seam * 0.75);
		fusion_rim = 0.12;
	}
	base = mix(base, telegraph_color.rgb, warning);
	base = mix(base, frost_color.rgb, frost * 0.6);
	base = mix(base, vec3(0.1, 0.85, 0.7), tagged * 0.3);
	out_albedo = mix(base, flash_color.rgb, flash);
	vec4 orm = texture(orm_texture, uv);
	float has_roughness = dot(roughness_channel, vec4(1.0));
	float has_metallic = dot(metallic_channel, vec4(1.0));
	out_roughness = roughness * mix(1.0, dot(orm, roughness_channel), has_roughness);
	out_metallic = metallic * mix(1.0, dot(orm, metallic_channel), has_metallic);
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
	out_emission = emission.rgb * emission_energy + base * unshaded_texture_energy + telegraph_color.rgb * warning * 1.5 + flash_color.rgb * flash + frost_color.rgb * frost * 0.35 + rim_color.rgb * rim_color.a * rim;
	out_emission += vec3(0.08, 0.9, 0.72) * tagged * (0.18 + rim * 1.5);
	out_emission += vec3(0.6, 0.7, 1.0) * staggered * rim;
	// Binding is subordinate to all combat cues; it never washes out the head,
	// face texture, frost, stagger, tag exposure or the hit flash.
	out_emission += brass * (seam * 0.10 + rim * fusion_rim) * quiet;
}
