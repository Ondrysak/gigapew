shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Independent of enemy anatomy: this pass only samples the rendered world,
// below the HUD layer, so menus, text and the crosshair never enter the loop.
global uniform float hallucination_intensity;
global uniform float hallucination_time;
global uniform float hallucination_escalation;
global uniform float hallucination_beat;
// Profile.HallucinationMode: feedback, vortex, liquid, crystal, heads, mix.
global uniform int hallucination_mode;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Recursion depth of the feedback loop; each level is one more echo.
const int LEVELS = 6;

vec3 world_sample(vec2 uv, vec2 edge) {
	return texture(screen_texture, clamp(uv, edge, vec2(1.0) - edge)).rgb;
}

// Mirrored repeat keeps every warped echo on real world pixels, never a seam.
vec2 mirror_wrap(vec2 uv) {
	return vec2(1.0) - abs(vec2(1.0) - mod(uv, 2.0));
}

vec3 hue_shift(vec3 color, float angle) {
	vec3 axis = vec3(0.57735);
	float c = cos(angle);
	return color * c + cross(axis, color) * sin(angle) + axis * dot(axis, color) * (1.0 - c);
}

vec2 vision_rotate(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Two slow quadrature fields, adapted from CrystalDive's gradient lensing.
// Analytic derivatives need no extra world/depth texture reads.
vec2 liquid_gradient(vec2 p, float t) {
	return vec2(
		cos(dot(p, vec2(6.1, 3.7)) + t * 0.43) * 0.7
			+ cos(dot(p, vec2(-3.9, 5.3)) - t * 0.31) * -0.45,
		cos(dot(p, vec2(6.1, 3.7)) + t * 0.43) * 0.42
			+ cos(dot(p, vec2(-3.9, 5.3)) - t * 0.31) * 0.61);
}

vec2 preset_warp(vec2 p, float t, float amount) {
	float r = length(p);
	if (hallucination_mode == 1) {
		float angle = sin(t * 0.37 - r * 5.0) * 0.34 * amount;
		return vision_rotate(p, angle) * (1.0 + sin(r * 7.0 - t * 0.29) * 0.05 * amount);
	}
	if (hallucination_mode == 2) {
		return p + liquid_gradient(p, t) * 0.045 * amount;
	}
	// CrystalDive's Bragg polar fold: reflect a sector, preserve its radius.
	float sector = TAU / 8.0;
	float angle = atan(p.y, p.x) + t * 0.055;
	float folded = abs(fract(angle / sector + 0.5) - 0.5) * sector;
	vec2 crystal = vision_rotate(vec2(cos(folded), sin(folded)) * r, -t * 0.055);
	crystal *= 1.0 + sin(r * 9.0 - t * 0.27) * 0.055;
	return mix(p, crystal, amount);
}

// Escalation changes sample coordinates only: no new reads, history or light
// flashes. The 100x rings breathe on the audible beat; higher ranks introduce
// nested angular harmonics, then a bounded second self-similar frequency.
vec2 escalation_warp(vec2 p, float t, float amount, float crystal, float maximum) {
	if (amount <= 0.0) {
		return p;
	}
	float r = length(p);
	float theta = atan(p.y, p.x);
	float breath = 0.65 + 0.70 * hallucination_beat;
	float rings = sin(r * (16.0 + maximum * 8.0) - t * 0.22);
	float twist = rings * 0.55 * breath;
	if (hallucination_mode == 2) {
		// Liquid remains a refractive field, never a rigid carousel.
		vec2 lens = liquid_gradient(p * (1.8 + maximum), t);
		return p + lens * amount * (0.035 * breath + 0.055 * crystal)
			+ p * rings * amount * 0.18 * breath;
	}
	if (hallucination_mode == 3) {
		// Sector harmonics deepen the selected crystal lens without switching
		// its mode; radial breathing stays continuous across sector boundaries.
		twist += sin(theta * 8.0 + t * 0.18) * (0.30 + 0.35 * crystal);
	} else {
		twist += sin(theta * 6.0 - r * 12.0 + t * 0.16) * 0.40 * crystal;
	}
	twist += sin(theta * 12.0 + r * 24.0 - t * 0.13) * 0.28 * maximum;
	return vision_rotate(p, twist * amount)
		* (1.0 + rings * amount * 0.18 * breath);
}

void fragment() {
	float strength = clamp(hallucination_intensity, 0.0, 1.0);
	vec2 uv = SCREEN_UV;
	vec2 edge = SCREEN_PIXEL_SIZE * 0.5;
	vec3 original = world_sample(uv, edge);
	// A circular clear aim region in screen pixels, not a stretched UV oval.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 centered = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	float radius = length(centered);
	float peripheral = smoothstep(0.11, 0.46, radius);
	float escalation = clamp(hallucination_escalation, 0.0, 1.0);
	// At high combos intensity has saturated at the saved ceiling. Dividing
	// recovers the rank, so a lower ceiling softens rather than hides tiers.
	float rank = clamp(escalation / max(strength, 0.0001), 0.0, 1.0);
	float crystal = smoothstep(0.35, 0.70, rank);
	float maximum = smoothstep(0.70, 1.0, rank);
	if (strength <= 0.0 || peripheral <= 0.0 || hallucination_mode == 4) {
		COLOR = vec4(original, 1.0);
	} else if (hallucination_mode >= 1 && hallucination_mode <= 3) {
		vec2 p = preset_warp(centered, hallucination_time, strength * peripheral);
		p = escalation_warp(p, hallucination_time, escalation * peripheral, crystal, maximum);
		vec2 q = mirror_wrap(p / vec2(aspect, 1.0) + vec2(0.5));
		vec2 split = SCREEN_PIXEL_SIZE * vec2(2.0, 0.75) * strength * peripheral;
		split += centered * escalation * peripheral * (0.025 + 0.025 * crystal + 0.016 * maximum)
			* (0.65 + 0.70 * hallucination_beat);
		vec3 warped = vec3(world_sample(q + split, edge).r,
			world_sample(q, edge).g, world_sample(q - split, edge).b);
		COLOR = vec4(mix(original, warped, peripheral), 1.0);
	} else {
		float t = hallucination_time;
		// Keep source edges crisp: the stronger effect comes from recursion,
		// folding and separated color copies, not an enlarged blur footprint.
		vec2 drift = vec2(sin(t * 0.21), sin(t * 0.17 + 1.8));
		vec2 ghost = (vec2(0.86, 0.32) + drift * vec2(0.12, 0.10))
			* SCREEN_PIXEL_SIZE * ((4.0 + 13.0 * strength) * strength * peripheral);
		vec2 blur = SCREEN_PIXEL_SIZE * (0.75 + 1.25 * strength) * peripheral;
		vec3 soft = original * 0.40;
		soft += world_sample(uv + vec2(blur.x, 0.0), edge) * 0.15;
		soft += world_sample(uv - vec2(blur.x, 0.0), edge) * 0.15;
		soft += world_sample(uv + vec2(0.0, blur.y), edge) * 0.15;
		soft += world_sample(uv - vec2(0.0, blur.y), edge) * 0.15;
		vec3 forward_ghost = world_sample(uv + ghost, edge);
		vec3 trailing_ghost = world_sample(uv - ghost * 0.78, edge);
		vec3 afterimage = mix(trailing_ghost, forward_ghost, 0.62);
		vec3 vision = mix(mix(original, soft, 0.24 * strength), afterimage, 0.34 * strength);

		// Fraksl-style video feedback, unrolled. A live loop
		//   next = frame + decay * hue(warp(previous))
		// settles to sum(decay^k * hue^k(frame(warp^k(uv)))); summing those
		// levels directly gives the same self-similar zoom tunnel without a
		// history buffer that would also capture the HUD. Each level samples
		// further out, so mirror-tiled copies of the world nest inside each
		// other; depth slides by one level per cycle, shrinking them endlessly
		// toward the aim point like a video tunnel.
		float feedback = strength * (1.45 - 0.45 * strength);
		float flow = fract(t * 0.07);
		float twist = (0.08 + 0.10 * sin(t * 0.05)) * (0.70 + 0.80 * strength)
			+ escalation * (0.15 * crystal + 0.12 * maximum);
		vec2 wander = vec2(sin(t * 0.13), cos(t * 0.11)) * 0.016 * feedback;
		float fold_angle = t * 0.04 + escalation * hallucination_beat * 0.12;
		float zoom = 1.30 + 0.35 * strength + escalation * (0.20 * crystal + 0.18 * maximum);
		float decay = 0.80 + 0.08 * strength;
		vec3 echoes = vec3(0.0);
		float total = 0.0;
		vec2 escalated_center = escalation_warp(centered, t, escalation * peripheral, crystal, maximum);
		for (int level = 0; level < LEVELS; level++) {
			float depth = float(level) + flow;
			vec2 p = escalated_center;
			if (hallucination_mode == 5) {
				// Slowly breathe between lensing and rotation, not abrupt mode rolls.
				float flow_mix = 0.5 + 0.5 * sin(t * 0.13);
				p = vision_rotate(p, sin(t * 0.23 - depth * 0.4) * 0.17 * feedback * flow_mix);
				p += liquid_gradient(p, t) * 0.035 * feedback * (1.0 - flow_mix);
			}
			// Deeper echoes fold into a six-way mirror, like crystaldive's polar folds.
			float fold = smoothstep(0.75, 2.75, depth) * feedback;
			if (fold > 0.0) {
				float sector = TAU / 6.0;
				float theta = atan(p.y, p.x) + fold_angle;
				float folded = abs(fract(theta / sector + 0.5) - 0.5) * sector;
				p = mix(p, vec2(cos(folded), sin(folded)) * length(p), fold);
			}
			float angle = twist * depth;
			p = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p
				* pow(zoom, depth) + wander * depth;
			vec2 q = mirror_wrap(p / vec2(aspect, 1.0) + vec2(0.5));
			// Separate crisp RGB copies instead of broadening the blur kernel.
			vec2 split = (q - vec2(0.5)) * depth
				* (0.026 * feedback + escalation * (0.028 + 0.018 * crystal + 0.014 * maximum)
					* (0.65 + 0.70 * hallucination_beat));
			vec3 echo = vec3(world_sample(q + split, edge).r, world_sample(q, edge).g, world_sample(q - split, edge).b);
			echo = hue_shift(echo, 0.24 * depth * feedback);
			float window = smoothstep(0.0, 1.0, depth)
				* (1.0 - smoothstep(float(LEVELS) - 1.6, float(LEVELS), depth));
			// Retain deeper copies, but normalize the sum rather than darken it.
			float weight = pow(decay, depth) * window;
			echoes += echo * weight;
			total += weight;
		}
		echoes /= max(total, 0.0001);
		float luma = dot(echoes, vec3(0.299, 0.587, 0.114));
		echoes = clamp(mix(vec3(luma), echoes, 1.0 + 0.28 * feedback), vec3(0.0), vec3(1.0));
		vision = mix(vision, echoes, 0.94 * feedback);
		COLOR = vec4(mix(original, vision, peripheral), 1.0);
	}
}
