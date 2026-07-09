#version 450
// filter/oilPaint, program "oilPost" — ported verbatim from wgsl/oilPost.wgsl.
// Pass 2 of 2: reshapes the flattened (oilFlatten) result into one of six
// Photoshop-parity painterly looks selected by MODE, then applies a shared
// granulation pass to every mode. MODE 0 facet: pass through unchanged. MODE 1
// daubs: unsharp-mask the flattened result against its own tent blur, scaled by
// detail. MODE 2 dryBrush: posterize to 3-8 levels (by detail) with a capped
// gradient-based edge darken. MODE 3 fresco: gradient-scaled darken then an
// S-curve per channel. MODE 4 knife: blend toward a tent blur by detail
// (softening). MODE 5 sponge (default/fallback): fbm-banded brightness shift.
// Every mode then gets the same value-noise-based granulation, mixed in by
// textureAmount.
//
// globalCoord = floor(gl_FragCoord.xy) — floored to an INTEGER pixel coordinate
// (unlike filter/wind/scatter, which keep the raw +0.5-centered coordinate) to
// satisfy an integer-derived noise/hash input; this is an independent choice
// specific to oilPaint's kernels, not this port's general Y/tiling convention.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define size data[..]`, `#define detail data[..]`, `#define textureAmount
// data[..]`, `#define seed data[..]`. MODE is a compile-time #define (shared
// with oilFlatten, same globals.mode.define). seed is an int, cast int(...) at
// use sites. The DSL param "texture" maps to shader uniform "textureAmount"
// (reference definition.js: "texture" collides with GLSL's builtin texture()
// function) — carried through verbatim via the JSON's `uniform` field. Inputs
// at set 0, binding 1.. in pass.inputs order (inputTex, flatTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D flatTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p_in) {
	vec2 p = p_in;
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// S6 gradient, applied to the FLATTENED texture (fresco/dryBrush edges).
vec2 lumGradientFlat(vec2 uv) {
	vec2 texSize = vec2(textureSize(flatTex, 0));
	vec2 px = 1.0 / texSize;
	float tl = lum(texture(flatTex, uv + px * vec2(-1.0,  1.0)).rgb);
	float l  = lum(texture(flatTex, uv + px * vec2(-1.0,  0.0)).rgb);
	float bl = lum(texture(flatTex, uv + px * vec2(-1.0, -1.0)).rgb);
	float tr = lum(texture(flatTex, uv + px * vec2( 1.0,  1.0)).rgb);
	float r  = lum(texture(flatTex, uv + px * vec2( 1.0,  0.0)).rgb);
	float br = lum(texture(flatTex, uv + px * vec2( 1.0, -1.0)).rgb);
	float t  = lum(texture(flatTex, uv + px * vec2( 0.0,  1.0)).rgb);
	float b  = lum(texture(flatTex, uv + px * vec2( 0.0, -1.0)).rgb);
	return vec2(tr + 2.0 * r + br - tl - 2.0 * l - bl,
	            tl + 2.0 * t + tr - bl - 2.0 * b - br);
}

// 3x3 tent blur of the flattened texture. Shared verbatim by daubs' unsharp
// mask (MODE 1) and knife's softening blend (MODE 4) — same blur, ONE WAY
// ONLY; only the per-mode mix weight differs.
vec3 tent3x3(vec2 uv) {
	vec2 texSize = vec2(textureSize(flatTex, 0));
	vec2 px = 1.0 / texSize;
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			float w = (dx == 0 ? 2.0 : 1.0) * (dy == 0 ? 2.0 : 1.0);
			sum += texture(flatTex, uv + vec2(float(dx), float(dy)) * px).rgb * w;
			wsum += w;
		}
	}
	return sum / wsum;
}

float sCurve(float x) {
	float t = clamp(x, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Dispatch to the active mode's reshape — single variant selected at compile
// time by the MODE const.
vec3 modeColor(vec2 uv, vec3 c, vec2 globalCoord) {
	if (MODE == 0) {
		return c;
	}
	if (MODE == 1) {
		vec3 blurred = tent3x3(uv);
		return c + (c - blurred) * (detail / 25.0);
	}
	if (MODE == 2) {
		// GLSL round() ties are implementation-defined; floor(x + 0.5) is a
		// deterministic round-half-up that matches the reference bit-for-bit.
		float levels = floor(mix(8.0, 3.0, detail / 100.0) + 0.5);
		vec3 poster = floor(c * levels) / levels;
		float gradMag = length(lumGradientFlat(uv));
		// 1.5 (gradient-to-alpha gain) and 0.15 (max edge darken) are
		// implementer judgment calls, tuned by eye — reuses fresco's (MODE 3)
		// lumGradientFlat helper but applies it as a subtler, capped darken
		// rather than fresco's stronger detail-scaled darken.
		float edgeDarken = clamp(gradMag * 1.5, 0.0, 1.0) * 0.15;
		return poster * (1.0 - edgeDarken);
	}
	if (MODE == 3) {
		float gradMag = length(lumGradientFlat(uv));
		vec3 darkened = c * (1.0 - 0.6 * (detail / 100.0) * gradMag);
		return vec3(sCurve(darkened.x), sCurve(darkened.y), sCurve(darkened.z));
	}
	if (MODE == 4) {
		vec3 blurred = tent3x3(uv);
		return mix(c, blurred, detail / 100.0);
	}
	// sponge (5, default/fallback)
	float band = fbm((globalCoord + float(int(seed)) * 37.0) / (4.0 + size));
	float shift = (band * 2.0 - 1.0) * (detail / 100.0) * 0.25;
	return clamp(c + vec3(shift), vec3(0.0), vec3(1.0));
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec3 c = texture(flatTex, uv).rgb;

	vec2 globalCoord = floor(gl_FragCoord.xy);

	vec3 outc = modeColor(uv, c, globalCoord);

	vec3 grained = outc * (0.85 + 0.3 * vnoise(globalCoord / 2.0));
	outc = mix(outc, grained, (textureAmount / 100.0) * 0.5);

	frag = vec4(clamp(outc, vec3(0.0), vec3(1.0)), src.a);
}
