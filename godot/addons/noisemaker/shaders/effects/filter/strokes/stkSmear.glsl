#version 450
// filter/strokes (program "stkSmear") — ported from wgsl/stkSmear.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's mat2(co,-si,si,co)*v
// (expanded) form instead of WGSL's raw one — see PORTING-GUIDE.md's rotation-
// handedness note (filter/spinBlur, filter/pondRipples, filter/halftone,
// filter/stipple, filter/hatch): rotate2D here rotates a fragment-offset direction
// vector that is scaled and added to the sampling position in smear() —
// position-derived geometry, same category as those effects — and this port has
// empirically established that category needs the GLSL-textual form on Godot,
// contrary to the WGSL source's own doctrine comment (calibrated for WebGPU, which
// does not transfer to Godot's RenderingDevice pipeline).
//
// Bounded directional-smear stroke engine covering Photoshop's Angled Strokes,
// Sprayed Strokes, Dark Strokes, Sumi-e, and Smudge Stick (Brush Strokes / Artistic
// filters) via `mode`. Every mode samples up to MAX_TAPS taps on each side of uv
// along a direction dirUnit, with a per-pixel jittered run length
// L = mix(3, 50, strokeLength/100) * (0.5 + hash12(gc)) and exponential decay
// weights exp(-2i/L). MODE is a compile-time define injected by the runtime
// (definition.js globals.mode.define), same mechanism as filter/oilPaint and
// filter/hatch. See effects/filter/strokes.json / the reference definition.js for
// the full per-mode Photoshop-parity description.
//
// Early exit: L is per-pixel (jittered by hash12(gc)), so smear()'s data-dependent
// `if (fi > L) break;` makes every srcSample() call after the break non-uniform
// control flow. The WGSL port must route every fetch through textureSampleLevel to
// keep that legal there (WGSL/WebGPU validation requires uniform control flow for
// implicit-LOD textureSample) — see wgsl/stkSmear.wgsl's extensive comment. GLSL has
// no such uniform-control-flow requirement on texture(), and the reference's own
// GLSL twin never needed the workaround (plain texture() + a plain break), so this
// port matches the GLSL golden here too: srcSample/erode3x3 use plain texture().
// Numerically a no-op either way (confirmed by the WGSL header): taps past L are
// never sampled at all rather than being multiplicatively zeroed.
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// strokeLength data[..]`, `#define balance data[..]`, `#define intensity data[..]`
// (globals.length's uniform key is renamed "strokeLength" to avoid colliding with
// GLSL's builtin length()). Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const int MAX_TAPS = 24;

// S1 - hash / jitter.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// S2 - luminance.
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// S6 - gradient (Sobel on luminance); smudge (MODE 4) only. Backend-agnostic
// constant kernel offsets - textually identical in WGSL, no flip.
vec2 lumGradient(vec2 uv) {
	vec2 px = 1.0 / resolution;
	float tl = lum(texture(inputTex, uv + px * vec2(-1.0,  1.0)).rgb);
	float  l = lum(texture(inputTex, uv + px * vec2(-1.0,  0.0)).rgb);
	float bl = lum(texture(inputTex, uv + px * vec2(-1.0, -1.0)).rgb);
	float tr = lum(texture(inputTex, uv + px * vec2( 1.0,  1.0)).rgb);
	float  r = lum(texture(inputTex, uv + px * vec2( 1.0,  0.0)).rgb);
	float br = lum(texture(inputTex, uv + px * vec2( 1.0, -1.0)).rgb);
	float  t = lum(texture(inputTex, uv + px * vec2( 0.0,  1.0)).rgb);
	float  b = lum(texture(inputTex, uv + px * vec2( 0.0, -1.0)).rgb);
	return vec2(tr + 2.0 * r + br - tl - 2.0 * l - bl,
	            tl + 2.0 * t + tr - bl - 2.0 * b - br);
}

// Rotation handedness: GLSL golden's mat2(co,-si,si,co)*v form (expanded) - see
// file header.
vec2 rotate2D(vec2 v, float angleDeg) {
	float a = radians(angleDeg);
	float co = cos(a);
	float si = sin(a);
	return vec2(co * v.x + si * v.y, -si * v.x + co * v.y);
}

// MODE 3 (sumiE) only: 3x3 min filter (erode, morphology-style, inline). Declared
// unconditionally (harmless dead code in every other compiled variant).
vec4 erode3x3(vec2 sampleUV) {
	vec2 px = 1.0 / resolution;
	vec4 m = texture(inputTex, sampleUV);
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) { continue; }
			m = min(m, texture(inputTex, sampleUV + vec2(float(dx), float(dy)) * px));
		}
	}
	return m;
}

// Every smear fetch (center + taps) routes through here so sumiE's pre-erode
// applies uniformly across the whole smeared field. MODE is a compile-time const,
// so this is dead code in every other compiled variant (confirmed by construction,
// not just by luck).
vec4 srcSample(vec2 sampleUV) {
	if (MODE == 3) {
		return erode3x3(sampleUV);
	}
	return texture(inputTex, sampleUV);
}

// Bounded directional accumulation, up to MAX_TAPS taps on each side of uv along
// dirUnit, weights exp(-2i/L). jitterPx > 0 (sprayed, MODE 1 only) adds a symmetric
// per-tap 2D hash jitter to the sample position so dabs scatter off the stroke
// line; jitterPx == 0 keeps every other mode's tap path a clean, un-jittered comb.
vec4 smear(vec2 uv, vec2 gc, vec2 dirUnit, float L, float jitterPx) {
	vec2 px = 1.0 / resolution;
	vec4 sum = srcSample(uv);
	float wsum = 1.0;
	for (int i = 1; i <= MAX_TAPS; i++) {
		float fi = float(i);
		if (fi > L) { break; }
		float w = exp(-2.0 * fi / L);
		vec2 jp = vec2(0.0);
		vec2 jn = vec2(0.0);
		if (jitterPx > 0.0) {
			jp = (hash22(gc + vec2(fi * 3.71, 7.0)) - 0.5) * jitterPx;
			jn = (hash22(gc + vec2(7.0, fi * 3.71) + 91.7) - 0.5) * jitterPx;
		}
		vec2 sampP = uv + (dirUnit * fi) * px + jp * px;
		vec2 sampN = uv - (dirUnit * fi) * px + jn * px;
		sum += (srcSample(sampP) + srcSample(sampN)) * w;
		wsum += 2.0 * w;
	}
	return sum / wsum;
}

// Per-mode dispatch - mirrors filter/hatch's hatchColor / filter/oilPaint's
// modeColor structure (sequential if (MODE == N) { return ...; } checks, last mode
// as the unconditional fallback) rather than the reference GLSL's #if/#elif chain -
// this is a pure control-flow-shape choice (MODE is a compile-time const either
// way, so dead branches are eliminated identically) matching this port's own
// established convention and WGSL's own smearColor() function shape.
vec4 smearColor(vec2 uv, vec2 gc, vec4 src, float L) {
	if (MODE == 0) {
		// Angled Strokes: two diagonal fields, blended by tone side of `balance`.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		vec2 dir135 = rotate2D(vec2(1.0, 0.0), 135.0);
		vec4 field45 = smear(uv, gc, dir45, L, 0.0);
		vec4 field135 = smear(uv, gc, dir135, L, 0.0);
		float b = balance / 100.0;
		float side = smoothstep(b - 0.1, b + 0.1, lum(src.rgb));
		return mix(field135, field45, side);
	}
	if (MODE == 1) {
		// Sprayed Strokes: single 45deg field, per-tap jitter scaled by intensity.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		float jitterPx = intensity / 100.0 * 6.0;
		return smear(uv, gc, dir45, L, jitterPx);
	}
	if (MODE == 2) {
		// Dark Strokes: single 45deg field, then tone-dependent crush/lift.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		vec4 c = smear(uv, gc, dir45, L, 0.0);
		float t = lum(c.rgb);
		float bAmt = balance / 100.0;
		float exponent = (t < bAmt) ? (1.0 + intensity / 50.0) : (1.0 / (1.0 + intensity / 100.0));
		c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(exponent));
		return c;
	}
	if (MODE == 3) {
		// Sumi-e: srcSample() erodes every fetch this smear makes before it's
		// accumulated at 135deg through the same tap loop every mode uses (no
		// separate/additional blur pass); then a contrast-only pow curve darkens
		// the result.
		vec2 dir135 = rotate2D(vec2(1.0, 0.0), 135.0);
		vec4 c = smear(uv, gc, dir135, L, 0.0);
		c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(1.0 + intensity / 50.0));
		return c;
	}
	// Smudge Stick (4) - fallback arm (MODE always 0-4, injected by the runtime, so
	// the last value needs no explicit check). Direction follows local structure
	// instead of a fixed angle; only applied in shadows.
	vec2 grad = lumGradient(uv);
	float gradMag = length(grad);
	float edgeAngle = (gradMag > 1e-5) ? (degrees(atan(grad.y, grad.x)) + 90.0) : 45.0;
	vec2 dir = rotate2D(vec2(1.0, 0.0), edgeAngle);
	vec4 smeared = smear(uv, gc, dir, L, 0.0);
	float shadowMask = 1.0 - smoothstep(0.55, 0.65, lum(src.rgb));
	return mix(src, smeared, shadowMask);
}

void main() {
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 src = texture(inputTex, uv);
	vec2 gc = floor(gl_FragCoord.xy) + tileOffset;

	float runBase = mix(3.0, 50.0, strokeLength / 100.0);
	float L = runBase * (0.5 + hash12(gc));

	vec4 outc = smearColor(uv, gc, src, L);

	frag = vec4(clamp(outc.rgb, vec3(0.0), vec3(1.0)), src.a);
}
