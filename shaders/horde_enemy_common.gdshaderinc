// Shared surface for batched horde enemies (static and vertex-animated).
// Per-instance state arrives in INSTANCE_CUSTOM:
// x = hit flash 0..1, y = attack telegraph 0..1 (-1 = stagger), z = animation phase,
// w = slow strength 0..1 (frost tint), -1 = Tag Burst exposure.
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

varying float v_flash;
varying float v_telegraph;
varying float v_frost;

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

void horde_surface(vec2 uv, vec3 normal, vec3 view, float time, vec3 local_pos, float flash, float telegraph, float frost, out vec3 out_albedo, out float out_roughness, out float out_metallic, out vec3 out_emission) {
	float warning = telegraph > 0.0 ? (0.35 + 0.65 * telegraph) * (0.75 + 0.25 * sin(time * 24.0)) : 0.0;
	float tagged = max(-frost, 0.0);
	float staggered = max(-telegraph, 0.0);
	frost = max(frost, 0.0);
	vec3 base = albedo.rgb * texture(albedo_texture, uv).rgb * tint.rgb;
	base = apply_grime(base, local_pos, grime);
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
}
