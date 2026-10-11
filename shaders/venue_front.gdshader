shader_type spatial;
render_mode diffuse_burley;

// Every part of a street's venue storefronts (boxes, bottles, awning stripes,
// sign boards) is one instance of a shared primitive mesh. Per instance custom
// data carries the linear paint colour in rgb and the glow strength in a, so a
// whole street of shopfronts costs three draw calls instead of one per colour.

varying vec4 paint;

void vertex() {
	paint = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = paint.rgb;
	ROUGHNESS = 0.8;
	EMISSION = paint.rgb * paint.a;
}
