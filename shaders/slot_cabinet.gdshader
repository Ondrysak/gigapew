shader_type spatial;
render_mode cull_back;

// Fruit-machine housing and pryable doors (SlotBankGeometry). Backlit glass is
// lit per lamp segment from the mask; chrome and lacquer fake a pub's reflections.
#include "res://shaders/slot_machine.gdshaderinc"

// Theme atlas (tools/automat_art.py): top glass v 0-0.5, lower glass 0.5-0.75,
// button caps / badge / sticker / cash plate 0.75-1. Alpha 0 = window.
uniform sampler2D art : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Lamp segments: R = group * 16 + 8, G = ordinal * 16 + 8, B = coverage.
uniform sampler2D lamp_mask : filter_linear_mipmap, repeat_disable;
// Struck-door highlight 0..1 (MineralDeposit._flash); doors only.
instance uniform float hit_flash = 0.0;

// UV2.x: SlotBankGeometry.Surface. UV2.y: cabinet + 4 * (door + 1), door -1 = housing.
const int SURFACE_PAINT = 0;
const int SURFACE_CHROME = 1;
const int SURFACE_TOP_GLASS = 2;
const int SURFACE_LOW_GLASS = 3;
const int SURFACE_DECAL = 4;
const int SURFACE_MATTE = 5;
const int SURFACE_TUBE = 6;

varying flat int v_surface;
varying flat vec4 v_game;
varying flat vec3 v_stops;
// x: attract flash, y: cabinet halted, z: backlight power, w: per-cabinet salt.
varying flat vec4 v_glass;
varying flat float v_flash;

void vertex() {
	v_surface = int(UV2.x + 0.5);
	int code = int(UV2.y + 0.5);
	int cabinet = code % 4;
	int door = code / 4 - 1;
	v_flash = hit_flash;
	v_game = vec4(0.0, 1.0, -1.0, 1.0);
	v_stops = vec3(-1.0);
	v_glass = vec4(0.0);
	if (v_surface == SURFACE_TOP_GLASS || v_surface == SURFACE_LOW_GLASS) {
		float t = sm_time();
		float power = 1.0;
		if (out_of_order > 0.5) {
			power = fract(sin(mod(floor(t * 9.0), 4096.0) * 12.9898 + float(cabinet) * 7.31) * 43758.5453) > 0.95 ? 0.35 : 0.0;
		} else if (door >= 0 && sm_bit(dark_doors, door)) {
			// The pried door's lamp loom is torn: its glass goes dark.
			power = 0.0;
		}
		v_game = sm_game(cabinet, t);
		v_stops = sm_stops(cabinet, t);
		v_glass = vec4(sm_attract(cabinet, t) ? 1.0 : 0.0, sm_bit(tampered, cabinet) ? 1.0 : 0.0, power, fract(slot_seed * 0.0137 + float(cabinet) * 0.31));
	}
}

// A dim room with a bright horizon band: enough for chrome to read as chrome.
vec3 environment(vec3 direction) {
	float sky = smoothstep(-0.3, 0.7, direction.y);
	float band = exp(-pow((direction.y - 0.15) * 7.0, 2.0));
	return vec3(0.05, 0.05, 0.06) + vec3(0.32, 0.32, 0.36) * sky + vec3(0.9, 0.88, 0.85) * band;
}

void fragment() {
	vec3 reflected = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz);
	vec3 env = environment(reflected);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 emission = vec3(0.0);
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	if (v_surface == SURFACE_CHROME) {
		ALBEDO = COLOR.rgb * 0.8;
		METALLIC = 1.0;
		ROUGHNESS = 0.18;
		emission = env * COLOR.rgb * 0.35;
	} else if (v_surface == SURFACE_TOP_GLASS || v_surface == SURFACE_LOW_GLASS) {
		vec4 glass = texture(art, UV);
		if (glass.a < 0.5) {
			discard;
		}
		vec4 lamp = texture(lamp_mask, UV);
		int group = int(lamp.r * 255.0 / 16.0);
		float level = 1.0;
		if (group > 0) {
			int ordinal = int(lamp.g * 255.0 / 16.0);
			float lit = sm_glass_lamp(group, ordinal, v_glass.w, hallucination_time, v_game, v_stops, v_glass.x > 0.5, v_glass.y > 0.5);
			level = mix(1.0, lit, lamp.b);
		}
		ALBEDO = glass.rgb * 0.1;
		ROUGHNESS = 0.05;
		SPECULAR = 0.6;
		emission = glass.rgb * level * v_glass.z * 1.1 + env * (0.04 + 0.25 * fresnel);
	} else if (v_surface == SURFACE_DECAL) {
		vec3 decal = texture(art, UV).rgb;
		ALBEDO = decal;
		ROUGHNESS = 0.35;
		emission = env * decal * 0.06;
	} else if (v_surface == SURFACE_MATTE) {
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
	} else if (v_surface == SURFACE_TUBE) {
		ROUGHNESS = 0.25;
		emission = COLOR.rgb * 0.03;
	} else {
		// Black lacquer.
		ROUGHNESS = 0.22;
		SPECULAR = 0.55;
		emission = env * (0.025 + 0.12 * fresnel);
	}
	EMISSION = emission + vec3(0.3, 0.22, 0.1) * v_flash;
}
