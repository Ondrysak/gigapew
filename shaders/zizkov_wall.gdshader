shader_type spatial;
render_mode diffuse_burley;

// Žižkov tenement facades for axis-aligned boxes drawn in world space: each
// stretch of wall is a different house in dirty ochre, grey or pastel plaster,
// flaking down to brick, with a rough-cast plinth, soot streaks and splash
// grime. `windows` adds a lit window grid for the distant skyline houses.

#include "res://shaders/zizkov_common.gdshaderinc"

uniform float house_width = 7.4;
// fbm threshold above which plaster has fallen off; lower shows more brick.
uniform float flaking = 0.63;
// 1 turns the wall into bare brick with plaster remnants.
uniform float brick_share = 0.0;
uniform bool windows = false;
uniform float storey_height = 3.1;
uniform float window_spacing = 2.4;
uniform float lit_share = 0.26;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.66, 0.3);
uniform vec3 tv_color : source_color = vec3(0.45, 0.6, 1.0);

const vec3 PLASTER[6] = {
	vec3(0.62, 0.47, 0.25),
	vec3(0.6, 0.55, 0.36),
	vec3(0.47, 0.46, 0.43),
	vec3(0.6, 0.45, 0.41),
	vec3(0.42, 0.49, 0.4),
	vec3(0.5, 0.38, 0.27)
};

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 box_center;
varying vec3 box_size;
varying vec3 box_local;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	box_center = MODEL_MATRIX[3].xyz;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	box_local = VERTEX;
}

void fragment() {
	vec3 n = normalize(world_normal);
	bool side = abs(n.x) > abs(n.z);
	float along = side ? world_position.z : world_position.x;
	// Block faces sit on the 2 m layout grid; this names the face's plane.
	float plane = floor((side ? world_position.x : world_position.z) * 0.5 + 0.25) + (side ? 0.5 : 0.0);
	float y = world_position.y;
	float base = box_center.y - box_size.y * 0.5;
	float top = box_center.y + box_size.y * 0.5;
	float height = y - base;

	float house_coord = along / house_width + zz_hash(vec2(plane, 3.0));
	float house = windows ? zz_hash(box_center.xz * 0.37) * 97.0 : floor(house_coord);
	float pick = zz_hash(vec2(house, plane));
	vec2 facade = vec2(along, y);
	vec3 plaster = PLASTER[int(pick * 5.999)] * (0.8 + 0.32 * zz_fbm(facade * 0.6 + pick * 53.0));

	vec2 brick_id;
	float mortar = zz_bond(facade, vec2(0.29, 0.085), 0.008, brick_id);
	vec3 brick = mix(vec3(0.38, 0.16, 0.1), vec3(0.55, 0.29, 0.18), zz_hash(brick_id + pick * 17.0));
	brick = mix(brick, vec3(0.4, 0.37, 0.33), mortar);

	float flake_field = zz_fbm(facade * 0.42 + vec2(pick * 91.0, plane * 7.0));
	float threshold = mix(flaking, 0.2, brick_share);
	float fw = fwidth(flake_field) + 0.008;
	float exposed = smoothstep(threshold, threshold + fw, flake_field);
	float rim = smoothstep(threshold - 0.04, threshold, flake_field) * (1.0 - exposed);
	vec3 color = mix(plaster * (1.0 + rim * 0.3), brick, exposed);

	// Rough-cast plinth, splash grime and soot streaks under the cornice.
	float plinth = 1.0 - smoothstep(0.84, 0.86, height);
	vec3 stone = vec3(0.24, 0.23, 0.22) * (0.75 + 0.4 * zz_noise(facade * 6.0));
	color = mix(color, stone, plinth);
	float splash = (1.0 - smoothstep(0.0, 2.4, height)) * (0.45 + 0.55 * zz_fbm(facade * vec2(1.5, 3.0)));
	float streak = smoothstep(0.55, 0.9, zz_noise(vec2(along * 2.2, y * 0.07 + pick * 13.0))) * (0.3 + 0.7 * smoothstep(top - 3.5, top, y));
	color *= 1.0 - 0.5 * splash - 0.35 * streak;

	float rough = 0.93;
	vec3 emission = vec3(0.0);
	if (windows) {
		float length_m = side ? box_size.z : box_size.x;
		float u = (side ? box_local.z : box_local.x) * length_m + length_m * 0.5;
		float columns = max(1.0, floor((length_m - 1.0) / window_spacing));
		float cu = u / (length_m / columns);
		float column = floor(cu);
		float fx = (fract(cu) - 0.5) * (length_m / columns);
		float storey = floor((height - 1.0) / storey_height);
		float fy = height - 1.0 - storey * storey_height;
		float valid = step(0.0, storey) * step(1.0 + storey * storey_height + 2.2, top - base - 0.8);
		float frame = valid * step(abs(fx), 0.62) * step(0.35, fy) * step(fy, 2.15);
		float glass = valid * step(abs(fx), 0.5) * step(0.47, fy) * step(fy, 2.03);
		float mullion = max(step(abs(fx), 0.035), step(abs(fy - 1.55), 0.035));
		glass *= 1.0 - mullion;
		float roll = zz_hash(vec2(column + house * 3.1, storey + plane));
		float lit = step(roll, lit_share);
		float tv = step(roll, lit_share * 0.22);
		vec3 light = mix(lamp_color, tv_color, tv) * (0.5 + 0.9 * zz_hash(vec2(roll * 41.0, column)));
		color = mix(color, vec3(0.42, 0.38, 0.32), frame);
		color = mix(color, mix(vec3(0.025, 0.03, 0.04), light * 0.3, lit), glass);
		emission = light * lit * glass * 0.9;
		rough = mix(rough, 0.25, glass);
	}
	if (abs(n.y) > 0.5) {
		color = vec3(0.07, 0.064, 0.06);
		emission = vec3(0.0);
	}
	ALBEDO = color;
	EMISSION = emission;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
