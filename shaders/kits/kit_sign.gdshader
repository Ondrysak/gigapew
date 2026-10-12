shader_type spatial;
render_mode diffuse_burley;

// Printed signs of the Prague kits: one unit box per sign, the atlas cell is
// drawn on its +Z face, the edges and back are a dark painted board.
// INSTANCE_CUSTOM: r = column / grid.x, g = row / grid.y, b = glow 0..1,
// a = horizontal span in cells / grid.x (KitTarget.add_sign).

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 8.0);

varying vec4 cell;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	cell = INSTANCE_CUSTOM;
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 origin = floor(cell.rg * grid + 0.5);
	float span = max(1.0, floor(cell.a * grid.x + 0.5));
	vec3 albedo = vec3(0.09, 0.09, 0.1);
	float glow = 0.0;
	if (local_normal.z > 0.5) {
		vec2 uv = clamp(vec2(local_pos.x + 0.5, 0.5 - local_pos.y), vec2(0.004), vec2(0.996));
		vec2 at = (origin + vec2(uv.x * span, uv.y)) / grid;
		albedo = texture(atlas, at).rgb;
		glow = cell.b * 2.5;
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.55;
	EMISSION = albedo * glow;
}
