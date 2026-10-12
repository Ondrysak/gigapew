shader_type spatial;
render_mode diffuse_burley;

// Prague metro vestibule wall cladding, one material per line (PragueKits):
//   mode 0  line A (Jiřího z Poděbrad): anodised aluminium "kalíšky" cup
//           pressings, golden field with a turquoise band;
//   mode 1  line B (Palmovka): white pearl glass panels over a marble dado;
//   mode 2  line C (Hlavní nádraží): small cream ceramic tiles.
// A slim stripe in the line colour runs at `stripe_y` on every mode.

#include "res://shaders/kits/kit_common.gdshaderinc"

uniform int mode = 0;
uniform vec4 line_color : source_color = vec4(0.0, 0.6, 0.3, 1.0);
uniform float base_y = 0.0;
uniform float stripe_y = 2.45;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = kit_wall_uv(world_pos, world_normal, base_y);
	vec3 albedo;
	float rough;
	float metal = 0.0;
	vec2 bump = vec2(0.0);
	if (mode == 0) {
		// Square pressings 0.32 m with a domed cup each; alternating rows dome in/out.
		vec2 cell = vec2(0.32);
		vec2 id = floor(uv / cell);
		vec2 f = fract(uv / cell) - 0.5;
		float r = length(f) / 0.42;
		float cup = mod(id.x + id.y, 2.0) < 1.0 ? 1.0 : -1.0;
		bump = r < 1.0 ? f * cup * 2.4 * (1.0 - r * r) : vec2(0.0);
		float seam = kit_grout(uv, cell, 0.012);
		vec3 gold = vec3(0.72, 0.55, 0.27);
		vec3 teal = vec3(0.12, 0.52, 0.55);
		bool band = uv.y > 1.6 && uv.y < 2.24;
		albedo = band ? teal : gold;
		albedo *= 0.85 + 0.15 * (1.0 - r);
		albedo = mix(albedo, vec3(0.08), seam * 0.8);
		rough = 0.32 + kit_noise(uv * 9.0) * 0.12;
		metal = 0.85;
	} else if (mode == 1) {
		if (uv.y < 1.0) {
			float vein = abs(sin((uv.x * 3.1 + uv.y * 1.7 + kit_fbm(uv * 3.0) * 3.5) * 2.0));
			albedo = mix(vec3(0.66, 0.63, 0.58), vec3(0.42, 0.4, 0.38), smoothstep(0.92, 1.0, vein));
			albedo = mix(albedo, vec3(0.1), kit_grout(uv, vec2(1.2, 1.0), 0.01));
			rough = 0.25;
		} else {
			float seam = kit_grout(uv - vec2(0.0, 1.0), vec2(1.2, 0.6), 0.02);
			float pearl = sin(uv.x * 2.3 + uv.y * 5.1 + kit_noise(uv * 2.0) * 3.0);
			albedo = vec3(0.86, 0.86, 0.84) + vec3(0.04, 0.0, 0.05) * pearl;
			albedo = mix(albedo, vec3(0.2), seam);
			rough = 0.1;
		}
	} else {
		vec2 cell = vec2(0.3, 0.15);
		vec2 id = floor(uv / cell);
		float shade = kit_hash(id) * 0.08;
		albedo = vec3(0.78, 0.72, 0.6) - shade;
		albedo = mix(albedo, vec3(0.35, 0.33, 0.3), kit_grout(uv, cell, 0.008));
		rough = 0.22 + shade;
	}
	float stripe = step(stripe_y, uv.y) * step(uv.y, stripe_y + 0.14);
	albedo = mix(albedo, line_color.rgb, stripe);
	metal *= 1.0 - stripe;
	// Dark skirting and foot-level grime.
	albedo = mix(albedo, vec3(0.06), step(uv.y, 0.12));
	albedo *= mix(0.7, 1.0, smoothstep(0.1, 0.9, uv.y + kit_fbm(uv * 4.0) * 0.4));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = normalize(vec3(bump * 0.5 + 0.5, 1.0));
}
