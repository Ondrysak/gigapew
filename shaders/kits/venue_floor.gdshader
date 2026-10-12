shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/kits/kit_common.gdshaderinc"

// All finishes share one material. INSTANCE_CUSTOM.rg encode kind / 3 and
// variant / 2. Pattern dimensions are metres, independent of room transforms.

varying vec2 floor_metres;
varying flat vec2 floor_style;

void vertex() {
	floor_metres = VERTEX.xz * vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	floor_style = floor(INSTANCE_CUSTOM.rg * vec2(3.0, 2.0) + vec2(0.5));
}

// Filter narrow joints and motif outlines rather than letting them shimmer.
float floor_line(float distance_to_line, float half_width, float pixel_width) {
	float aa = max(pixel_width * 0.65, 0.0005);
	float coverage = min(1.0, half_width / aa);
	return (1.0 - smoothstep(max(half_width - aa, 0.0), half_width + aa, distance_to_line)) * coverage;
}

void fragment() {
	int venue_kind = int(floor_style.x);
	int variant = int(floor_style.y);
	vec2 p = floor_metres;
	vec2 pixel = max(fwidth(p), vec2(0.0001));
	float pixel_size = max(pixel.x, pixel.y);
	float fine_detail = 1.0 - smoothstep(0.015, 0.065, pixel_size);
	float age = kit_fbm(p * 0.42 + vec2(13.7, 4.2));
	float dirt = smoothstep(0.53, 0.76, kit_fbm(p * 0.8 + vec2(6.1, 21.4)));
	float speckle = (kit_noise(p * 24.0) - 0.5) * fine_detail;
	vec3 colour;
	float roughness;
	float specular = 0.32;

	if (venue_kind == 0) {
		// Narrow, staggered planks: old honey oak, dark walnut, grey-brown oak.
		float board_width = variant == 1 ? 0.17 : (variant == 2 ? 0.20 : 0.15);
		float board_length = variant == 1 ? 1.35 : (variant == 2 ? 1.60 : 1.15);
		float row = floor(p.y / board_width);
		float stagger = kit_hash(vec2(row, 18.4)) * board_length;
		vec2 board_p = vec2(p.x + stagger, p.y);
		vec2 cell_size = vec2(board_length, board_width);
		vec2 board_id = floor(board_p / cell_size);
		vec2 within = fract(board_p / cell_size) * cell_size;
		vec2 edge = min(within, cell_size - within);
		float joint = max(floor_line(edge.x, 0.0018, pixel.x), floor_line(edge.y, 0.0018, pixel.y));
		float board_tone = kit_hash(board_id + vec2(9.2, 3.6));
		vec3 wood = variant == 1 ? vec3(0.235, 0.145, 0.090) : (variant == 2 ? vec3(0.315, 0.275, 0.210) : vec3(0.395, 0.270, 0.155));
		colour = wood * mix(0.82, 1.15, board_tone);

		// Long, gently meandering grain; no submillimetre procedural fibres.
		float grain_phase = p.y * 125.0 + kit_noise(vec2(p.x * 0.75, row * 0.71)) * 5.0;
		float grain_filter = 1.0 - smoothstep(1.2, 3.2, fwidth(grain_phase));
		float grain = sin(grain_phase) * grain_filter;
		float ribbons = kit_noise(vec2(p.x * 0.55, p.y * 27.0));
		colour *= 0.93 + ribbons * 0.12 + grain * 0.025;

		// Sparse soft knots stay inside their own board, not across its seams.
		vec2 knot_centre = vec2(board_length * mix(0.25, 0.75, kit_hash(board_id + 11.3)), board_width * 0.5);
		vec2 knot_p = (within - knot_centre) / vec2(0.10, board_width * 0.15);
		float knot_distance = length(knot_p);
		float knot_present = step(0.76, kit_hash(board_id + 34.7));
		float knot = (1.0 - smoothstep(0.25, 1.6, knot_distance)) * knot_present;
		float knot_ring_phase = knot_distance * 13.0;
		float knot_ring_filter = 1.0 - smoothstep(1.2, 3.2, fwidth(knot_ring_phase));
		colour *= 1.0 - knot * (0.13 + sin(knot_ring_phase) * knot_ring_filter * 0.025);
		colour *= 0.93 + age * 0.12 - dirt * 0.07;
		colour = mix(colour, wood * 0.25, joint);
		roughness = clamp(0.48 + age * 0.23 + dirt * 0.10 + joint * 0.18, 0.0, 1.0);
	} else if (venue_kind == 1) {
		// Muted patterned gaming-room carpet: wine, forest green, tobacco brown.
		float repeat_size = variant == 1 ? 0.72 : (variant == 2 ? 0.82 : 0.66);
		vec2 motif = (fract(p / repeat_size) - 0.5) * repeat_size;
		float diamond_distance = abs(motif.x) + abs(motif.y);
		float motif_pixel = pixel.x + pixel.y;
		float outer = floor_line(abs(diamond_distance - repeat_size * 0.38), 0.009, motif_pixel);
		float inner = floor_line(abs(diamond_distance - repeat_size * 0.19), 0.006, motif_pixel);
		float centre = 1.0 - smoothstep(0.025, 0.043 + pixel_size, length(motif));
		// Small corner diamonds join into a quiet second lattice.
		float corner_distance = repeat_size - diamond_distance;
		float corners = floor_line(abs(corner_distance - repeat_size * 0.17), 0.006, motif_pixel);
		vec3 carpet = variant == 1 ? vec3(0.100, 0.155, 0.130) : (variant == 2 ? vec3(0.200, 0.155, 0.100) : vec3(0.205, 0.095, 0.105));
		vec3 thread = variant == 1 ? vec3(0.255, 0.275, 0.200) : (variant == 2 ? vec3(0.340, 0.285, 0.190) : vec3(0.330, 0.245, 0.170));
		float faded = 0.60 + age * 0.28;
		float pattern = max(max(outer * 0.68, inner * 0.42), max(centre * 0.55, corners * 0.38));
		colour = mix(carpet, thread, pattern * faded);
		colour *= 0.94 + age * 0.12 + speckle * 0.07;
		colour = mix(colour, carpet * 0.77, dirt * 0.24);
		roughness = 0.94 + speckle * 0.04;
		specular = 0.15;
	} else if (venue_kind == 2) {
		// Worn vinyl squares, with restrained cream/charcoal, tan/brown or grey/blue.
		float tile_size = variant == 1 ? 0.40 : (variant == 2 ? 0.45 : 0.30);
		vec2 tile_id = floor(p / tile_size);
		vec2 within = fract(p / tile_size) * tile_size;
		vec2 edge = min(within, vec2(tile_size) - within);
		float joint = max(floor_line(edge.x, 0.0012, pixel.x), floor_line(edge.y, 0.0012, pixel.y));
		float checker = mod(tile_id.x + tile_id.y, 2.0);
		vec3 light_tile = variant == 1 ? vec3(0.430, 0.365, 0.255) : (variant == 2 ? vec3(0.385, 0.400, 0.390) : vec3(0.485, 0.455, 0.365));
		vec3 dark_tile = variant == 1 ? vec3(0.195, 0.150, 0.110) : (variant == 2 ? vec3(0.145, 0.185, 0.205) : vec3(0.140, 0.145, 0.135));
		colour = mix(light_tile, dark_tile, checker);
		colour *= 0.95 + kit_hash(tile_id + 7.1) * 0.10 + speckle * 0.04;
		float scuff = smoothstep(0.54, 0.78, kit_noise(p * vec2(1.8, 16.0) + 12.3)) * fine_detail;
		colour = mix(colour, mix(light_tile, dark_tile, 0.55), scuff * 0.13);
		colour *= 0.91 + age * 0.14 - dirt * 0.08;
		colour = mix(colour, colour * 0.65, joint);
		roughness = clamp(0.54 + age * 0.24 + scuff * 0.12 + joint * 0.12, 0.0, 1.0);
	} else {
		// Practical shop ceramic: beige squares, staggered greige, cool grey squares.
		vec2 tile_size = variant == 1 ? vec2(0.40, 0.30) : (variant == 2 ? vec2(0.40) : vec2(0.30));
		vec2 tile_p = p;
		if (variant == 1) {
			tile_p.x += mod(floor(p.y / tile_size.y), 2.0) * tile_size.x * 0.5;
		}
		vec2 tile_id = floor(tile_p / tile_size);
		vec2 within = fract(tile_p / tile_size) * tile_size;
		vec2 edge = min(within, tile_size - within);
		float joint = max(floor_line(edge.x, 0.003, pixel.x), floor_line(edge.y, 0.003, pixel.y));
		float bevel = max(floor_line(edge.x, 0.006, pixel.x), floor_line(edge.y, 0.006, pixel.y));
		vec3 ceramic = variant == 1 ? vec3(0.350, 0.325, 0.285) : (variant == 2 ? vec3(0.365, 0.395, 0.395) : vec3(0.470, 0.430, 0.345));
		colour = ceramic * (0.94 + kit_hash(tile_id + 41.8) * 0.12);
		colour *= 0.96 + kit_noise(p * 5.0) * 0.08 + speckle * 0.025;
		colour *= 0.96 + age * 0.06 - dirt * 0.08;
		colour *= 1.0 - bevel * 0.06;
		vec3 grout = variant == 2 ? vec3(0.185, 0.200, 0.195) : vec3(0.215, 0.200, 0.170);
		colour = mix(colour, grout * (0.88 + age * 0.16), joint);
		roughness = clamp(0.50 + age * 0.20 + dirt * 0.08 + joint * 0.22, 0.0, 1.0);
	}

	ALBEDO = colour;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
}
