shader_type spatial;
render_mode cull_back;

// Curved reel drums of every fruit machine in a deposit (SlotBankGeometry._drum).
// Spin, blur, stops and bounce come from slot_machine.gdshaderinc.
#include "res://shaders/slot_machine.gdshaderinc"

// 16 stops, one 256x128 cell each, top to bottom (tools/automat_art.py).
uniform sampler2D strip : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// UV.x: across the strip; UV.y: symbols above the payline. UV2 = (reel 0-5, cabinet).
// COLOR.a = 0 marks the plastic reel rims.
varying flat vec2 v_reel;
// x: backlight, y: payline win flash.
varying flat vec2 v_light;

void vertex() {
	int reel = int(UV2.x + 0.5);
	int cabinet = int(UV2.y + 0.5);
	float t = sm_time();
	v_reel = sm_reel(cabinet, reel, t);
	float light = 1.0;
	float flash = 0.0;
	if (out_of_order > 0.5) {
		light = fract(sin(mod(floor(t * 9.0), 4096.0) * 12.9898 + float(cabinet * 6 + reel) * 3.17) * 43758.5453) > 0.96 ? 0.3 : 0.015;
	} else if (sm_bit(tampered, cabinet)) {
		light = 0.4;
	} else if (reel < 3) {
		vec4 game = sm_game(cabinet, t);
		flash = game.z >= 0.0 && game.y >= 0.0 ? sm_blink(t, 2.0) : 0.0;
	}
	v_light = vec2(light, flash);
}

vec3 strip_at(float u, float position) {
	return texture(strip, vec2(u, (0.5 - position) / 16.0)).rgb;
}

void fragment() {
	if (COLOR.a < 0.5) {
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.6;
	} else {
		float position = v_reel.x + UV.y;
		// Vertical smear over the distance travelled in ~1/30 s.
		float blur = min(abs(v_reel.y) / 30.0, 1.2);
		vec3 paper;
		if (blur < 0.02) {
			paper = strip_at(UV.x, position);
		} else {
			paper = vec3(0.0);
			for (int i = 0; i < 9; i++) {
				paper += strip_at(UV.x, position - (float(i) / 8.0 - 0.5) * blur);
			}
			paper /= 9.0;
		}
		// Lamps behind the strip light the payline row hardest.
		float row = exp(-UV.y * UV.y * 0.45);
		float win = v_light.y * (1.0 - smoothstep(0.42, 0.55, abs(UV.y)));
		ALBEDO = paper * 0.55;
		ROUGHNESS = 0.6;
		EMISSION = paper * (v_light.x * (0.35 + 0.6 * row) + win * 0.9);
	}
}
