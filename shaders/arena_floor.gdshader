shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 width = max(fwidth(p), vec2(0.002));
	vec2 cell = mod(p + 1.0, 2.0);
	vec2 edge = min(cell, 2.0 - cell);
	float seam = 1.0 - smoothstep(0.025, 0.025 + max(width.x, width.y), min(edge.x, edge.y));
	float panel = mod(floor((p.x + 1.0) / 2.0) + floor((p.y + 1.0) / 2.0), 2.0);
	vec3 steel = mix(vec3(0.105, 0.145, 0.175), vec3(0.125, 0.17, 0.20), panel);
	steel = mix(steel, vec3(0.027, 0.047, 0.063), seam * 0.85);
	float aa = max(length(width), 0.003);
	float radius = length(p);
	float ring = 1.0 - smoothstep(0.035, 0.035 + aa, abs(radius - 3.6));
	float inner_ring = 1.0 - smoothstep(0.012, 0.012 + aa, abs(radius - 3.25));
	float broken_ring = ring * step(0.24, abs(sin(atan(p.y, p.x) * 4.0)));
	float lane = (1.0 - smoothstep(0.035, 0.035 + width.x, abs(abs(p.x) - 7.0))) * smoothstep(4.5, 5.0, abs(p.y));
	float perimeter = 1.0 - smoothstep(0.045, 0.045 + aa, abs(max(abs(p.x), abs(p.y)) - 10.8));
	float cyan = max(max(broken_ring, inner_ring * 0.38), lane * 0.7);
	float hatch_band = (1.0 - smoothstep(0.17, 0.17 + width.y, abs(abs(p.y) - 10.25))) * (1.0 - smoothstep(3.0, 3.05, abs(p.x)));
	float stripe_phase = mod(p.x + p.y, 0.85);
	float stripes = smoothstep(0.03, 0.03 + aa, stripe_phase) * (1.0 - smoothstep(0.42, 0.42 + aa, stripe_phase));
	float amber = max(perimeter * 0.65, hatch_band * stripes);
	ALBEDO = mix(mix(steel, vec3(0.10, 0.58, 0.63), cyan), vec3(0.78, 0.46, 0.12), amber);
	EMISSION = vec3(0.035, 0.33, 0.38) * cyan + vec3(0.22, 0.09, 0.015) * amber;
	ROUGHNESS = 0.78;
	METALLIC = 0.3;
}
