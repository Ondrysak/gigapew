shader_type canvas_item;

// Full-screen UI overlay: scanlines, vignette, a slow bright sweep and
// optional glitch bands. Draws only darkening/tint; put it above 3D, below UI.

uniform float scanline_count = 320.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.12;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;
uniform float sweep_strength : hint_range(0.0, 1.0) = 0.05;
uniform float sweep_speed = 0.11;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.1, 0.85, 0.9, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float scan = scanline_strength * (0.5 + 0.5 * sin(UV.y * scanline_count * 6.2831853));
	float vignette = smoothstep(0.38, 0.95, distance(UV, vec2(0.5))) * vignette_strength;
	float sweep = smoothstep(0.018, 0.0, abs(UV.y - fract(TIME * sweep_speed))) * sweep_strength;
	float band_seed = hash(vec2(floor(UV.y * 36.0), floor(TIME * 20.0)));
	float band = step(1.0 - glitch * 0.3, band_seed) * glitch * 0.45;
	float light = sweep + band;
	float alpha = clamp(scan + vignette + light, 0.0, 1.0);
	COLOR = vec4(tint.rgb * (light / max(alpha, 0.001)), alpha);
}
