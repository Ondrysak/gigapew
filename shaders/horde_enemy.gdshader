shader_type spatial;
render_mode diffuse_burley;

// One material per baked surface. Per-instance state arrives in INSTANCE_CUSTOM:
// x = hit flash 0..1, y = attack telegraph 0..1, z = animation phase,
// w = slow strength 0..1 (frost tint).
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float roughness = 0.6;
uniform float metallic = 0.0;
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

varying float v_flash;
varying float v_telegraph;
varying float v_frost;

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
	float warning = v_telegraph > 0.0 ? (0.35 + 0.65 * v_telegraph) * (0.75 + 0.25 * sin(TIME * 24.0)) : 0.0;
	vec3 base = mix(albedo.rgb, telegraph_color.rgb, warning);
	base = mix(base, frost_color.rgb, v_frost * 0.6);
	ALBEDO = mix(base, flash_color.rgb, v_flash);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb * emission_energy + telegraph_color.rgb * warning * 1.5 + flash_color.rgb * v_flash + frost_color.rgb * v_frost * 0.35;
}
