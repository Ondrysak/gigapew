// Value noise shared by the Žižkov (yard) floor and facade shaders.

float zz_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float zz_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(zz_hash(i), zz_hash(i + vec2(1.0, 0.0)), u.x), mix(zz_hash(i + vec2(0.0, 1.0)), zz_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float zz_fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += amplitude * zz_noise(p);
		p = p * 2.03 + vec2(17.1, 5.3);
		amplitude *= 0.5;
	}
	return value;
}

// Running-bond masonry: returns the joint coverage (1 on mortar) and writes
// the unit's id. `unit` is the brick/sett size in metres; joints fade to their
// average coverage once a unit shrinks to a few pixels.
float zz_bond(vec2 p, vec2 unit, float joint, out vec2 id) {
	vec2 q = p / unit;
	float row = floor(q.y);
	q.x += 0.5 * mod(row, 2.0) + (zz_hash(vec2(row, 11.0)) - 0.5) * 0.24;
	id = floor(q);
	vec2 f = fract(q);
	vec2 edge = min(f, 1.0 - f) * unit;
	float d = min(edge.x, edge.y);
	float fw = max(fwidth(d), 1e-5);
	float line = 1.0 - smoothstep(joint - fw * 0.5, joint + fw * 0.5, d);
	float average = clamp(2.0 * joint * (unit.x + unit.y) / (unit.x * unit.y), 0.0, 1.0);
	vec2 cells = fwidth(q);
	return mix(line, average, smoothstep(0.25, 0.6, max(cells.x, cells.y)));
}
