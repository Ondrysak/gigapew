// Pattern-space hallucinations only: no vertex, collider or material changes.
// Include once per floor shader, never through the wall/kit common helpers.
global uniform float hallucination_intensity;
global uniform float hallucination_time;
global uniform float hallucination_escalation;
global uniform float hallucination_beat;
global uniform int hallucination_mode;

bool floor_hallucination_active() {
	return hallucination_intensity > 0.0
		&& (hallucination_mode == 1 || hallucination_mode == 2 || hallucination_mode == 5
			|| (hallucination_mode == 3 && hallucination_escalation > 0.0));
}

// World-anchored metres in, world-anchored metres out. Eight-metre swirl cells
// preserve radius, become identity with a flat derivative at their boundaries,
// and never rotate a whole arena about its origin. The two oblique travelling
// fields are a bounded analytical-gradient lens, inspired by CrystalDive's
// rotated bilayers; their slow relative phase slip makes interference drift.
vec2 floor_hallucinated_uv(vec2 metres) {
	if (!floor_hallucination_active()) {
		return metres;
	}
	float strength = clamp(hallucination_intensity, 0.0, 1.0);
	float t = hallucination_time;
	float escalation = clamp(hallucination_escalation, 0.0, 1.0);
	float rank = clamp(escalation / max(strength, 0.0001), 0.0, 1.0);
	float crystal = smoothstep(0.35, 0.70, rank);
	float maximum = smoothstep(0.70, 1.0, rank);
	float breath = 0.65 + 0.70 * hallucination_beat;
	float vortex = hallucination_mode == 1 ? 1.0 : 0.0;
	float liquid = hallucination_mode == 2 ? 1.0 : 0.0;
	if (hallucination_mode == 5) {
		vortex = 0.80 + 0.12 * sin(t * 0.09);
		liquid = 0.70 + 0.12 * sin(t * 0.07 + 1.4);
	}
	vec2 p = metres;
	if (vortex > 0.0 || escalation > 0.0) {
		vec2 cell = floor(metres / 8.0);
		vec2 local = metres - (cell + vec2(0.5)) * 8.0;
		float radius = length(local);
		float envelope = 1.0 - smoothstep(0.0, 4.0, radius);
		float angle = strength * vortex * envelope * (1.45 + 0.30 * sin(t * 0.23));
		if (escalation > 0.0) {
			float theta = atan(local.y, local.x);
			float rings = sin(radius * 4.5 - t * 0.18);
			// Stay within each local cell; no arena, warning stripe or wall
			// rotation. All floor callers apply this only to finish UVs.
			if (hallucination_mode != 2) {
				angle += escalation * envelope * (rings * 0.55 * breath
					+ sin(theta * 6.0 + radius * 2.0 - t * 0.14) * 0.90 * crystal
					+ sin(theta * 12.0 - radius * 5.0 + t * 0.11) * 0.65 * maximum);
			}
			// Smooth nested ring refraction, bounded and flat at cell edges.
			p += local * escalation * envelope * rings * (0.12 * breath + 0.08 * maximum);
		}
		float c = cos(angle);
		float s = sin(angle);
		vec2 rotated = vec2(c * local.x - s * local.y, s * local.x + c * local.y);
		p += rotated - local;
	}
	if (liquid > 0.0) {
		vec2 direction_a = vec2(0.96, 0.28);
		vec2 direction_b = vec2(0.80, 0.60);
		vec2 slip_direction = vec2(-0.31, 0.17);
		float slip = dot(metres, slip_direction) - t * 0.11;
		float phase_a = dot(metres, direction_a) * 1.15 - t * 0.24;
		float phase_b = dot(metres, direction_b) * 1.32 + t * 0.19 + 0.5 * sin(slip);
		vec2 gradient = direction_a * (1.15 * cos(phase_a))
			+ 0.8 * cos(phase_b) * (direction_b * 1.32 + slip_direction * (0.5 * cos(slip)));
		// At full strength this contribution remains below 0.71 metres.
		p += gradient * (0.30 * strength * liquid);
		if (escalation > 0.0) {
			float nested = dot(metres, vec2(-0.62, 0.78)) * (2.8 + maximum * 1.4) + t * 0.13;
			p += vec2(-0.62, 0.78) * cos(nested) * escalation
				* (0.16 * breath + 0.28 * crystal + 0.16 * maximum);
		}
	}
	return p;
}

// Only active warped kit floors use this derivative-filtered grout. Their
// inactive branch retains kit_grout verbatim, including its original coverage.
float floor_hallucinated_grout(vec2 p, vec2 cell, float grout) {
	vec2 within = fract(p / cell) * cell;
	vec2 distance_to_edge = min(within, cell - within);
	vec2 pixel = max(fwidth(p), vec2(0.00001));
	vec2 width = max(vec2(grout * 0.75), pixel * 0.5);
	vec2 coverage = (vec2(1.0) - smoothstep(width - pixel * 0.5, width + pixel * 0.5, distance_to_edge))
		* (vec2(grout * 0.75) / width);
	vec2 average = clamp(vec2(grout * 1.5) / cell, vec2(0.0), vec2(1.0));
	coverage = mix(coverage, average, smoothstep(vec2(0.2), vec2(0.5), pixel / cell));
	return 1.0 - (1.0 - coverage.x) * (1.0 - coverage.y);
}
