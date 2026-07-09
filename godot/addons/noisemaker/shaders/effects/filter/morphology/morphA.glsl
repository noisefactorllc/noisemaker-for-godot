#version 450
// filter/morphology, program "morphA" — ported from wgsl/morphology's morphA.wgsl,
// cross-checked against glsl/morphA.glsl for the mix()-blend idiom (see below).
// Pass 1 of 2 (morphA -> morphB; see effects/filter/morphology.json). Square shape
// uses a horizontal-line structuring element (finished by morphB's vertical pass —
// min/max over a box is separable into two 1D passes); round shape computes the full
// disc structuring element here in one pass (min/max over a disc is NOT separable),
// so morphB is a passthrough copy for that shape. mode selects the op: dilate (0) =
// max, erode (1) = min.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define mode data[..]`, `#define radius data[..]`, `#define shape data[..]` as
// bare (float-valued) names. mode/shape are ints with `choices` in the JSON but
// arrive as raw floats here (Godot's synthesized layout has no integer path) — cast
// with int(...) at comparison sites (matches this port's established boolean/enum
// idiom, e.g. filter/grain's `int(pause) > 0`); the reference GLSL's
// `mix(hi, lo, float(mode))` blend already reads as a float both sides (mode/erode
// are exactly 0.0/1.0), so it needs no cast — kept verbatim.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texel = 1.0 / texSize;
	vec4 acc = texture(inputTex, uv);

	if (int(shape) == 1) {
		// Round: full disc structuring element, capped at radius 12 so the
		// worst case (625 taps) stays bounded regardless of the radius max.
		float r = min(radius, 12.0);
		float r2 = r * r;
		for (int y = -12; y <= 12; y++) {
			for (int x = -12; x <= 12; x++) {
				if (x == 0 && y == 0) { continue; }
				vec2 d = vec2(float(x), float(y));
				if (dot(d, d) > r2) { continue; }
				vec4 s = texture(inputTex, uv + d * texel);
				vec4 hi = max(acc, s);
				vec4 lo = min(acc, s);
				acc = mix(hi, lo, float(mode));
			}
		}
	} else {
		// Square: horizontal-line structuring element over |i| <= radius.
		float r = min(radius, 32.0);
		for (int i = 1; i <= 32; i++) {
			if (float(i) > r) { break; }
			vec2 o = vec2(float(i), 0.0) * texel;
			vec4 sL = texture(inputTex, uv - o);
			vec4 sR = texture(inputTex, uv + o);
			vec4 hi = max(acc, max(sL, sR));
			vec4 lo = min(acc, min(sL, sR));
			acc = mix(hi, lo, float(mode));
		}
	}

	frag = acc;
}
