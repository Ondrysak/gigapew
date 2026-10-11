// Fruit-machine game shared by the slot cabinet shaders (reels, glass, lights).
// Everything is a pure function of the paused gameplay clock and per-deposit
// instance values: no script animates anything and pause freezes it all.
// The cycle maths is mirrored for review in scripts/lab/scenarios/mining_scenario.gd.

global uniform float hallucination_time;
// Integer-valued visual seed derived from the deposit seed (never an RNG draw).
instance uniform float slot_seed = 0.0;
// Bit c set once any door of cabinet c is pried: that cabinet's game halts.
instance uniform float tampered = 0.0;
// Bit d set once door d is pried: its glass lamps go dark.
instance uniform float dark_doors = 0.0;
// Set when the deposit is emptied: dead machine with the odd sputter.
instance uniform float out_of_order = 0.0;

// Symbols: 0 SEVEN, 1 BAR, 2 BELL, 3 MELON, 4 GRAPES, 5 PLUM, 6 ORANGE, 7 LEMON, 8 CHERRY.
// Strip cells top to bottom in reel_strip.png (tools/automat_art.py STRIP).
const int SM_STRIP[16] = {0, 8, 7, 5, 2, 6, 8, 4, 7, 1, 6, 3, 8, 5, 7, 4};
const float SM_PAY[9] = {750.0, 400.0, 300.0, 200.0, 100.0, 50.0, 50.0, 25.0, 25.0};
const float SM_WEIGHT[9] = {1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 9.0, 12.0, 14.0};
const float SM_WEIGHT_TOTAL = 59.0;
const float SM_SPEED = 24.0; // symbols per second at full reel speed
const float SM_JOLT = 0.13;
const float SM_ACCEL = 0.22;
const float SM_SESSION = 24.0; // games between hashed credit top-ups
const float SM_ATTRACT = 11.0;

// Glass lamp groups: red channel of glass_<theme>_mask.png (group * 16 + 8).
const int LAMP_LOGO = 1;
const int LAMP_STARS = 2;
const int LAMP_PAYROW = 3;
const int LAMP_WINLINE = 4;
const int LAMP_LADDER = 5;
const int LAMP_HOUSE = 6;
const int LAMP_RISK = 7;
const int LAMP_RISKBAR = 8;
const int LAMP_LOWLINE = 9;
const int LAMP_INFO = 10;
const int LAMP_INDICATOR = 11;
const int LAMP_LABEL = 12;
const int LAMP_RAYS = 13;

uint sm_hash(uint value) {
	uint x = value;
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

// Uniform 0..1 for (cabinet, cycle, salt); exact in float32 so the lab mirror agrees.
float sm_rand(int cabinet, float cycle, int salt) {
	uint h = sm_hash(uint(slot_seed) ^ (uint(cabinet) * 2654435769u));
	h = sm_hash(h ^ (uint(int(cycle) + 4096) * 2246822507u));
	h = sm_hash(h ^ (uint(salt) * 3266489909u));
	return float(h >> 8u) / 16777216.0;
}

bool sm_bit(float mask, int bit) {
	return ((int(mask + 0.5) >> bit) & 1) == 1;
}

bool sm_halted(int cabinet) {
	return out_of_order > 0.5 || sm_bit(tampered, cabinet);
}

float sm_time() {
	return hallucination_time;
}

// x: cycle index, y: seconds since that cycle's spin began. Cycles last 8-14 s.
vec2 sm_cycle(int cabinet, float t) {
	float len = 8.0 + 6.0 * sm_rand(cabinet, 0.0, 1);
	float x = t + sm_rand(cabinet, 0.0, 2) * len;
	float k = floor(x / len);
	return vec2(k, x - k * len);
}

// Reels stop left to right, 0.35-0.5 s apart.
float sm_stop_time(int cabinet, float k, int reel) {
	float t = 1.3 + 0.5 * sm_rand(cabinet, k, 10);
	for (int r = 1; r <= reel; r++) {
		t += 0.35 + 0.15 * sm_rand(cabinet, k, 10 + r);
	}
	return t;
}

// A 15-25 % win chance per cabinet.
bool sm_wins(int cabinet, float k) {
	return sm_rand(cabinet, k, 3) < 0.15 + 0.1 * sm_rand(cabinet, 0.0, 4);
}

int sm_win_symbol(int cabinet, float k) {
	float pick = sm_rand(cabinet, k, 5) * SM_WEIGHT_TOTAL;
	for (int s = 0; s < 8; s++) {
		pick -= SM_WEIGHT[s];
		if (pick < 0.0) {
			return s;
		}
	}
	return 8;
}

float sm_multiplier(int cabinet, float k) {
	float r = sm_rand(cabinet, k, 9);
	return r < 0.55 ? 1.0 : (r < 0.8 ? 2.0 : (r < 0.92 ? 3.0 : (r < 0.97 ? 5.0 : 10.0)));
}

float sm_payout(int cabinet, float k) {
	return sm_wins(cabinet, k) ? SM_PAY[sm_win_symbol(cabinet, k)] * sm_multiplier(cabinet, k) : 0.0;
}

// Strip cell on the payline of main reel `reel` once cycle k has stopped.
int sm_cell(int cabinet, float k, int reel) {
	if (sm_wins(cabinet, k)) {
		int symbol = sm_win_symbol(cabinet, k);
		int count = 0;
		for (int i = 0; i < 16; i++) {
			count += SM_STRIP[i] == symbol ? 1 : 0;
		}
		int pick = int(sm_rand(cabinet, k, 6 + reel) * float(count));
		for (int i = 0; i < 16; i++) {
			if (SM_STRIP[i] == symbol) {
				if (pick == 0) {
					return i;
				}
				pick--;
			}
		}
		return 0;
	}
	int c0 = int(sm_rand(cabinet, k, 6) * 16.0);
	int c1 = int(sm_rand(cabinet, k, 7) * 16.0);
	int c2 = int(sm_rand(cabinet, k, 8) * 16.0);
	// A losing spin never shows three of a kind.
	if (SM_STRIP[c0] == SM_STRIP[c1] && SM_STRIP[c1] == SM_STRIP[c2]) {
		c2 = (c2 + 1) % 16;
	}
	return reel == 0 ? c0 : (reel == 1 ? c1 : c2);
}

// Reel position in symbols (the payline shows strip cell posmod(-round(p), 16)) and
// speed: a jolt back, a hard spin-up, constant speed, then an exact stop on the
// target cell with a damped mechanical bounce.
vec2 sm_spin(float start_cell, float target_cell, float tau, float stop) {
	float start = -start_cell;
	float target = -target_cell;
	if (tau <= 0.0) {
		return vec2(start, 0.0);
	}
	if (tau >= stop) {
		float x = tau - stop;
		float bounce = x < 0.6 ? 0.2 * exp(-x * 12.0) * sin(x * 30.0) : 0.0;
		return vec2(target + bounce, 0.0);
	}
	if (tau < SM_JOLT) {
		return vec2(start - 0.22 * sin(3.14159265 * tau / SM_JOLT), 0.0);
	}
	float base = SM_SPEED * (stop - SM_JOLT - SM_ACCEL * 0.5);
	float rem = mod(target - start - base, 16.0);
	rem -= rem > 8.0 ? 16.0 : 0.0;
	float scale = (base + rem) / base;
	float v = tau - SM_JOLT;
	float d = v < SM_ACCEL ? SM_SPEED * v * v / (2.0 * SM_ACCEL) : SM_SPEED * (v - SM_ACCEL * 0.5);
	return vec2(start + scale * d, scale * SM_SPEED * min(v / SM_ACCEL, 1.0));
}

// Lower-game reels start spinning this long after the cycle's spin.
float sm_risk_start(int cabinet, float k) {
	return sm_stop_time(cabinet, k, 2) + 0.9;
}

// Position and speed of reel 0-2 (main game) or 3-5 (small risk game).
vec2 sm_reel(int cabinet, int reel, float t) {
	if (sm_halted(cabinet)) {
		// Halted by an open door: reels freeze between symbols where the brake caught them.
		return vec2(-floor(sm_rand(cabinet, 0.0, 30 + reel) * 16.0) + (sm_rand(cabinet, 0.0, 40 + reel) - 0.5) * 0.6, 0.0);
	}
	vec2 c = sm_cycle(cabinet, t);
	if (reel < 3) {
		return sm_spin(float(sm_cell(cabinet, c.x - 1.0, reel)), float(sm_cell(cabinet, c.x, reel)), c.y, sm_stop_time(cabinet, c.x, reel));
	}
	int r = reel - 3;
	float from = floor(sm_rand(cabinet, c.x - 1.0, 20 + r) * 16.0);
	float to = floor(sm_rand(cabinet, c.x, 20 + r) * 16.0);
	return sm_spin(from, to, c.y - sm_risk_start(cabinet, c.x), 0.9 + 0.3 * float(r));
}

// x: seconds since spin start, y: seconds since the last main reel stopped
// (negative while spinning), z: won symbol or -1, w: won multiplier.
vec4 sm_game(int cabinet, float t) {
	vec2 c = sm_cycle(cabinet, t);
	bool win = sm_wins(cabinet, c.x);
	return vec4(c.y, c.y - sm_stop_time(cabinet, c.x, 2), win ? float(sm_win_symbol(cabinet, c.x)) : -1.0, win ? sm_multiplier(cabinet, c.x) : 1.0);
}

// Seconds until each main reel stops (negative once stopped).
vec3 sm_stops(int cabinet, float t) {
	vec2 c = sm_cycle(cabinet, t);
	return vec3(sm_stop_time(cabinet, c.x, 0), sm_stop_time(cabinet, c.x, 1), sm_stop_time(cabinet, c.x, 2)) - c.y;
}

float sm_bet(int cabinet, float session) {
	float r = sm_rand(cabinet, session, 51);
	return r < 0.15 ? 1.0 : (r < 0.35 ? 2.0 : (r < 0.85 ? 5.0 : 10.0));
}

// Attract mode: every ~11 s the whole cabinet flashes for 1.3 s.
bool sm_attract(int cabinet, float t) {
	return fract((t + float(cabinet) * 3.7 + sm_rand(cabinet, 0.0, 60) * SM_ATTRACT) / SM_ATTRACT) < 0.12;
}

// LED display content. display: 0 credit (4 digits), 1 bet (3), 2 bonus (3).
// Returns x: value, y: mode (0 number, 1 dashes, 2 "door", 3 off), z: brightness.
vec3 sm_led(int cabinet, int display, float t) {
	if (out_of_order > 0.5) {
		float sputter = fract(sin(mod(floor(t * 7.0), 4096.0) * 12.9898 + float(cabinet * 3 + display) * 78.233) * 43758.5453);
		return vec3(8888.0, sputter > 0.97 ? 0.0 : 3.0, 0.35);
	}
	if (sm_bit(tampered, cabinet)) {
		return vec3(0.0, display == 0 ? 2.0 : 1.0, fract(t * 0.8) < 0.65 ? 1.0 : 0.25);
	}
	vec2 c = sm_cycle(cabinet, t);
	float session = floor(c.x / SM_SESSION);
	float bet = sm_bet(cabinet, session);
	float settled = c.y - sm_stop_time(cabinet, c.x, 2);
	if (display == 1) {
		// Bet, alternating with the machine's 95 % return figure while idle.
		bool rtp = settled > 1.5 && fract(t * 0.4) > 0.5;
		return vec3(rtp ? 95.0 : bet, 0.0, 1.0);
	}
	float credit = 200.0 + 5.0 * floor(sm_rand(cabinet, session, 50) * 600.0);
	float bonus = 0.0;
	int games = int(c.x - session * SM_SESSION);
	for (int i = 0; i < games; i++) {
		float earlier = sm_payout(cabinet, session * SM_SESSION + float(i));
		credit += earlier - bet;
		bonus += earlier > 0.0 ? 10.0 : 0.0;
	}
	credit -= bet;
	float pay = sm_payout(cabinet, c.x);
	if (pay > 0.0) {
		// The meter counts the win up after the reels settle.
		float counting = clamp((settled - 0.4) / clamp(pay / 250.0, 0.6, 2.5), 0.0, 1.0);
		credit += floor(pay * counting);
		bonus += settled > 0.4 ? 10.0 : 0.0;
	}
	if (display == 2) {
		return vec3(mod(bonus, 1000.0), 0.0, 1.0);
	}
	return vec3(clamp(credit, 0.0, 9999.0), 0.0, 1.0);
}

float sm_blink(float t, float hz) {
	return fract(t * hz) < 0.5 ? 1.0 : 0.0;
}

// Brightness of a glass lamp segment: 1 = plain backlight, ~0.3 unlit, ~2.2 lit.
// game/stops come from sm_game/sm_stops for this cabinet; halted and salt (0..1 per
// cabinet) are passed in so the fragment stage never reads instance uniforms.
float sm_glass_lamp(int group, int ordinal, float salt, float t, vec4 game, vec3 stops, bool attract, bool halted) {
	bool spinning = game.y < 0.0;
	bool won = game.z >= 0.0 && !spinning && !halted;
	float on = 2.2;
	float off = 0.3;
	if (group == LAMP_LOGO) {
		// Neon letters: steady, with a rare dropout per tube.
		float flick = fract(sin(mod(floor(t * 12.0), 4096.0) * 12.9898 + float(ordinal) * 4.1414 + salt * 91.7) * 43758.5453);
		float level = flick > 0.985 ? 0.6 : 1.9;
		return attract ? (float(ordinal) < fract(t * 0.75) * 14.0 ? 2.1 : 0.5) : level;
	}
	if (group == LAMP_LABEL) {
		return 1.6;
	}
	if (group == LAMP_RAYS) {
		if (attract) {
			return int(mod(floor(t * 6.0), 16.0)) == ordinal ? 2.4 : 0.9;
		}
		return won ? 1.0 + 0.5 * sm_blink(t, 1.2) : 1.0;
	}
	if (halted) {
		return group == LAMP_INDICATOR && ordinal == 0 ? on * sm_blink(t, 1.0) : off;
	}
	if (attract && group != LAMP_INFO && group != LAMP_INDICATOR) {
		return sm_blink(t, 2.5) > 0.5 ? on : off;
	}
	if (group == LAMP_STARS) {
		return won || int(mod(floor(t * 1.5), 4.0)) == ordinal ? on : 0.5;
	}
	if (group == LAMP_PAYROW) {
		if (won && ordinal == int(game.z + 0.5)) {
			return sm_blink(t, 1.6) > 0.5 ? 2.4 : 1.3;
		}
		return 0.9;
	}
	if (group == LAMP_WINLINE) {
		if (spinning && game.x > 0.0) {
			return 1.6;
		}
		if (won) {
			return ordinal == 2 ? (sm_blink(t, 2.0) > 0.5 ? on : off) : off;
		}
		return ordinal == 2 ? 1.2 : off;
	}
	if (group == LAMP_LADDER) {
		if (ordinal == 10) {
			return 1.8;
		}
		if (spinning && game.x > 0.0) {
			// Turbo ladder climbs x1 -> x10 while the reels run.
			return float(ordinal) <= floor(fract(game.x * 0.8) * 10.0) ? on : off;
		}
		float top = won ? game.w - 1.0 : 0.0;
		if (float(ordinal) < top) {
			return on;
		}
		return float(ordinal) == top ? (won ? (sm_blink(t, 1.5) > 0.5 ? on : 0.8) : on) : off;
	}
	if (group == LAMP_HOUSE) {
		if (spinning && game.x > 0.0) {
			return stops[ordinal] > 0.0 ? on : off;
		}
		return int(mod(floor(t * 1.2), 3.0)) == ordinal ? 1.8 : 0.45;
	}
	if (group == LAMP_RISK) {
		float risk = game.y - 0.9;
		if (risk > 0.0 && risk < 1.6) {
			return int(mod(floor(t * 2.5), 8.0)) == ordinal ? on : off;
		}
		if (won) {
			float level = min(7.0, floor(game.w));
			return float(ordinal) == level ? (sm_blink(t, 1.5) > 0.5 ? on : 0.8) : off;
		}
		return 0.45;
	}
	if (group == LAMP_RISKBAR) {
		return won ? (sm_blink(t, 1.5) > 0.5 ? on : 0.7) : 0.9;
	}
	if (group == LAMP_LOWLINE) {
		float risk = game.y - 0.9;
		if (risk > 0.0 && risk < 1.6) {
			return 1.6;
		}
		return ordinal == 1 ? 1.3 : off;
	}
	if (group == LAMP_INFO) {
		return int(mod(floor(t), 4.0)) == ordinal ? 1.9 : 0.5;
	}
	if (group == LAMP_INDICATOR) {
		return ordinal == 0 ? 1.8 : (won ? on * sm_blink(t, 1.0) : 0.35);
	}
	return 1.0;
}

// Button deck: 0 VÝPLATA, 1 SÁZKA, 2-4 DRŽ, 5 RISK, 6 START, 7 INFO.
float sm_button(int cabinet, int index, float t, vec4 game, vec3 stops, bool attract) {
	if (sm_bit(tampered, cabinet)) {
		return index == 7 ? 0.6 : 0.08;
	}
	if (attract) {
		return sm_blink(t, 2.5) > 0.5 ? 1.0 : 0.12;
	}
	bool spinning = game.y < 0.0 && game.x > 0.0;
	bool won = game.z >= 0.0 && game.y >= 0.0;
	if (index >= 2 && index <= 4) {
		return spinning && stops[index - 2] > 0.0 ? 1.0 : 0.15;
	}
	if (index == 6) {
		return spinning ? 1.0 : (sm_blink(t, 1.2) > 0.5 ? 1.0 : 0.15);
	}
	if (index == 0 || index == 5) {
		float phase = index == 0 ? 0.0 : 0.5;
		return won ? (fract(t + phase) < 0.5 ? 1.0 : 0.15) : 0.15;
	}
	return index == 1 ? 0.75 : 0.45;
}

// Lights mesh (SlotBankGeometry.Light): 0 candle tier (sub = tier), 1 button
// (sub = index), 3 coin window. Returns the level; `color` may turn service red.
float sm_light(int kind, int cabinet, int sub, float t, vec3 base, out vec3 color) {
	color = base;
	if (kind == 0) {
		if (out_of_order > 0.5) {
			float sputter = fract(sin(mod(floor(t * 8.0), 4096.0) * 12.9898 + float(cabinet * 2 + sub) * 5.3) * 43758.5453);
			return sub == 0 && sputter > 0.9 ? 0.6 : 0.03;
		}
		if (sm_bit(tampered, cabinet)) {
			// Door open: the service candle calls in red, tiers alternating at 2 Hz.
			color = vec3(1.0, 0.08, 0.05);
			return fract(t * 2.0 + float(sub) * 0.5) < 0.5 ? 1.0 : 0.1;
		}
		vec4 game = sm_game(cabinet, t);
		// A big multiplier win calls the attendant: the top tier pulses.
		if (sub == 1 && game.z >= 0.0 && game.y >= 0.0 && game.w >= 3.0) {
			return sm_blink(t, 1.0) > 0.5 ? 1.0 : 0.2;
		}
		return sub == 0 ? 0.9 : 0.75;
	}
	if (out_of_order > 0.5) {
		return 0.02;
	}
	if (kind == 1) {
		return sm_button(cabinet, sub, t, sm_game(cabinet, t), sm_stops(cabinet, t), sm_attract(cabinet, t));
	}
	return sm_bit(tampered, cabinet) ? 0.4 : 1.0;
}
