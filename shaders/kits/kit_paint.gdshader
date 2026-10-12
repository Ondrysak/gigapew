shader_type spatial;
render_mode diffuse_burley;

// Every palette primitive of the Prague kits (furniture, fixtures, goods) is an
// instance of one shared unit mesh. INSTANCE_CUSTOM carries the sRGB albedo in
// rgb and a finish code in a (KitTarget.add_paint):
//   a * 64 = finish * 8 + glow level, glow = level / 2 (emission multiplier).
// Finish: 0 matte, 1 satin plastic, 2 metal, 3 gloss ceramic, 4 mirror,
// 5 grime (matte with heavy stains). All finishes get light world-space wear.

varying vec4 paint;
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	paint = INSTANCE_CUSTOM;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float q = floor(paint.a * 64.0 + 0.5);
	float finish = floor(q / 8.0 + 0.01);
	float glow = (q - finish * 8.0) * 0.5;
	vec3 albedo = pow(clamp(paint.rgb, 0.0, 1.0), vec3(2.2));
	vec2 p = world_pos.xz * 1.7 + world_pos.y * vec2(0.9, -1.3);
	float wear = noise(p * 3.0) * 0.6 + noise(p * 11.0) * 0.4;
	float stain = smoothstep(0.55, 0.85, noise(p * 1.3 + 7.0));
	float rough = 0.9;
	float metal = 0.0;
	float dirt = 0.12;
	if (finish > 0.5 && finish < 1.5) {
		rough = 0.5;
	} else if (finish > 1.5 && finish < 2.5) {
		rough = 0.3 + wear * 0.2;
		metal = 0.85;
	} else if (finish > 2.5 && finish < 3.5) {
		rough = 0.12 + wear * 0.12;
		dirt = 0.18;
	} else if (finish > 3.5 && finish < 4.5) {
		rough = 0.04;
		metal = 1.0;
		dirt = 0.06;
	} else if (finish > 4.5) {
		dirt = 0.45;
		rough = 0.85;
	}
	vec3 grime = albedo * vec3(0.55, 0.5, 0.38);
	albedo = mix(albedo, grime, clamp(stain * dirt * 2.0 + (wear - 0.5) * dirt, 0.0, 1.0));
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	EMISSION = pow(clamp(paint.rgb, 0.0, 1.0), vec3(2.2)) * glow;
}
