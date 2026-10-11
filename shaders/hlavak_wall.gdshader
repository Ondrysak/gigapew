shader_type spatial;
render_mode diffuse_burley;

// Hlavní nádraží, 1970s concourse: glazed cream-and-brown tile to head height,
// bare concrete above it, a nicotine ceiling stain, missing tiles and
// kiosk-grease grime. Axis-aligned boxes drawn in world space.

#include "res://shaders/zizkov_common.gdshaderinc"

uniform float tile_height = 2.9;
uniform vec2 tile_size = vec2(0.3, 0.15);
uniform vec3 tile_a : source_color = vec3(0.56, 0.48, 0.34);
uniform vec3 tile_b : source_color = vec3(0.4, 0.3, 0.19);
uniform vec3 frieze : source_color = vec3(0.22, 0.13, 0.08);
uniform vec3 grout : source_color = vec3(0.16, 0.14, 0.11);
uniform vec3 concrete : source_color = vec3(0.33, 0.31, 0.27);
uniform vec3 nicotine : source_color = vec3(0.3, 0.21, 0.08);

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 box_center;
varying vec3 box_size;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	box_center = MODEL_MATRIX[3].xyz;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	vec3 n = normalize(world_normal);
	bool side = abs(n.x) > abs(n.z);
	float along = side ? world_position.z : world_position.x;
	float plane = floor((side ? world_position.x : world_position.z) * 0.5 + 0.25) + (side ? 0.5 : 0.0);
	float y = world_position.y;
	float top = box_center.y + box_size.y * 0.5;
	vec2 facade = vec2(along, y);

	vec2 id;
	float seam = zz_bond(facade, tile_size, 0.007, id);
	float shade = zz_hash(id + plane);
	vec3 tile = mix(tile_a, tile_b, step(0.5, zz_hash(vec2(floor(y / 0.9), plane))) * 0.8 + shade * shade * 0.4);
	tile *= 0.86 + 0.28 * zz_hash(id + 5.0);
	// A brown frieze row at hip height.
	float band = smoothstep(1.0, 1.02, y) * (1.0 - smoothstep(1.3, 1.32, y));
	tile = mix(tile, frieze, band);
	tile = mix(tile, grout, seam);

	vec3 wall = concrete * (0.72 + 0.4 * zz_fbm(facade * 0.45 + plane * 3.0));
	float lost = smoothstep(0.7, 0.72, zz_fbm(facade * 0.8 + vec2(plane * 7.0, 2.0)));
	float is_tile = (1.0 - smoothstep(tile_height, tile_height + 0.05, y)) * (1.0 - lost);
	vec3 color = mix(wall, tile, is_tile);

	// Smokers' ceiling, streaks, and grease where hands lean.
	float ceiling = smoothstep(top - 3.2, top, y) * (0.45 + 0.55 * zz_fbm(facade * 0.7 + 9.0));
	color = mix(color, nicotine, ceiling * 0.7);
	float streak = smoothstep(0.55, 0.9, zz_noise(vec2(along * 2.4, y * 0.08 + plane * 5.0)));
	color *= 1.0 - 0.35 * streak;
	float grease = (1.0 - smoothstep(0.0, 1.6, y)) * (0.4 + 0.6 * zz_fbm(facade * vec2(1.3, 2.6)));
	color *= 1.0 - 0.4 * grease;

	if (abs(n.y) > 0.5) {
		color = vec3(0.07, 0.062, 0.052);
	}
	ALBEDO = color;
	ROUGHNESS = mix(0.9, 0.35, is_tile * (1.0 - seam));
	METALLIC = 0.0;
}
