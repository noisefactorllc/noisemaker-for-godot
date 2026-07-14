#version 450
// filter/strokes (program "stkSmear") — ported from wgsl/stkSmear.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's mat2(co,-si,si,co)*v
// (expanded) form instead of WGSL's raw one — see PORTING-GUIDE.md's rotation-
// handedness note (filter/spinBlur, filter/pondRipples, filter/halftone,
// filter/stipple, filter/hatch): rotate2D here rotates a fragment-offset direction
// vector that is scaled and added to the sampling position in smear() and
// brushStrokeField() — position-derived geometry, same category as those effects —
// and this port has empirically established that category needs the GLSL-textual
// form on Godot, contrary to the WGSL source's own doctrine comment (calibrated for
// WebGPU, which does not transfer to Godot's RenderingDevice pipeline). The WGSL's
// own rotate2D is itself documented as "Numeric expansion of GLSL mat2(co,-si,si,co)
// * v", i.e. both backends agree on this form; only the comment framing differs.
//
// Bounded directional brush-mark engine covering Photoshop's Angled Strokes,
// Sprayed Strokes, Dark Strokes, Sumi-e, and Smudge Stick via `mode`. Every mode
// builds a fixed (or, for smudge, gradient-derived) direction, then blends two
// coherent-field layers along it:
//   - smear(): a bounded exponential-decay tap comb (up to MAX_TAPS taps each side
//     of uv along dirUnit, weights exp(-2i/L)), where L is a per-direction coherent
//     run length from strokeVariation() (a value-noise field in stroke-oriented
//     space), not a per-pixel hash.
//   - brushStrokeField(): a 3x3 neighboring-spawn-cell scan of softly antialiased,
//     slightly rotated bristled capsule marks (coherent length/width/center/phase
//     per cell), producing a center-sampled pigment and a coverage/field alpha.
// Each mode mixes smear()'s comb with brushStrokeField()'s capsule layer, then mixes
// that pigment over src by the capsule field alpha. MODE is a compile-time define
// injected by the runtime (definition.js globals.mode.define), same mechanism as
// filter/oilPaint and filter/hatch. See effects/filter/strokes.json / the reference
// definition.js for the full per-mode Photoshop-parity description:
//
//   angled (0)  - two smear fields (45deg, 135deg) blended by which side of
//                 `balance` the source luminance falls on.
//   sprayed (1) - single 45deg field; each tap gets an extra symmetric 2D jitter
//                 (smooth value noise via sprayJitter(), recentered around zero)
//                 scaled by `intensity`.
//   dark (2)    - single 45deg field, then a per-pixel tone crush/lift on the
//                 blended color: shadows darken via pow(c, 1+intensity/50),
//                 highlights lift via pow(c, 1/(1+intensity/100)).
//   sumiE (3)   - srcSample() returns a locally eroded source (4-neighbour cross
//                 min) for every fetch this mode's smear/brushStrokeField make, so
//                 the 135deg directional accumulation spreads expanded dark ink like
//                 wet ink; a contrast-only pow curve finishes it.
//   smudge (4)  - direction follows the local Sobel luminance gradient (falls back
//                 to 45deg where the gradient is ~0), applied only in shadows
//                 (soft gate over src lum 0.55-0.65) so highlights stay untouched.
//
// Early exit: L is a coherent per-direction field (not per-pixel-hashed), so
// smear()'s `if (fi > L) break;` makes every srcSample() call after the break
// non-uniform control flow across invocations — harmless in GLSL (no uniformity
// requirement on texture()), so the early exit stays a plain break here. The WGSL
// port routes every fetch through textureSampleLevel (explicit LOD, no uniformity
// requirement) instead, to keep the same break legal under WGSL/WebGPU's uniform-
// control-flow validation — see wgsl/stkSmear.wgsl's extensive comment. Both forms
// are the same algorithm; only the texture-sampling call WGSL needs differs.
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// strokeLength data[..]`, `#define balance data[..]`, `#define intensity data[..]`
// (globals.length's uniform key is renamed "strokeLength" to avoid colliding with
// GLSL's builtin length()). Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const int MAX_TAPS = 24;

// hash - hash / jitter.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float valueNoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0)), u.x), u.y);
}
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// luminance - luminance.
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Sobel gradient - gradient (Sobel on luminance); smudge (MODE 4) only. Backend-
// agnostic constant kernel offsets - textually identical in WGSL, no flip.
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

// Coherent per-direction run-length variation: a value-noise field evaluated in
// stroke-oriented space (along dirUnit / across it), not a per-pixel hash.
float strokeVariation(vec2 gc, vec2 dirUnit, float runBase) {
	vec2 across = vec2(-dirUnit.y, dirUnit.x);
	vec2 strokeSpace = vec2(
		dot(gc, dirUnit) / max(runBase, 3.0),
		dot(gc, across) / 3.5
	);
	return 0.72 + 0.56 * valueNoise2(strokeSpace * 0.65);
}

// Forward-declared: brushStrokeField() samples pigment through srcSample() (MODE==3
// erodes every fetch), defined below after brushStrokeField, matching the reference.
vec4 srcSample(vec2 sampleUV);

// 3x3 neighboring-spawn-cell scan of softly antialiased, slightly rotated bristled
// capsule marks. Each candidate cell has its own coherent center jitter, rotation,
// half-length, half-width, and bristle phase (all hashed from the cell index), so
// marks continue smoothly through lattice boundaries. Returns center-sampled
// pigment (weighted by mark coverage) and the max mark coverage as field alpha.
vec4 brushStrokeField(vec2 uv, vec2 gc, vec2 dirUnit, float runBase) {
	vec2 across = vec2(-dirUnit.y, dirUnit.x);
	vec2 oriented = vec2(dot(gc, dirUnit), dot(gc, across));
	vec2 spacing = vec2(max(runBase * 0.70, 4.0), 4.5);
	vec2 baseCell = floor(oriented / spacing);
	float field = 0.0;
	vec3 pigmentSum = vec3(0.0);
	float pigmentWeight = 0.0;

	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 cell = baseCell + vec2(float(cx), float(cy));
			vec2 jitter = hash22(cell + 17.3) - 0.5;
			vec2 center = (cell + 0.5 + jitter * vec2(0.56, 0.40)) * spacing;
			vec2 delta = oriented - center;
			float angle = (hash12(cell + 29.1) - 0.5) * 0.34;
			float co = cos(angle);
			float si = sin(angle);
			vec2 local = vec2(co * delta.x + si * delta.y,
			                  -si * delta.x + co * delta.y);
			float halfLength = runBase * (0.35 + 0.18 * hash12(cell + 43.7));
			float halfWidth = 1.4 + 1.2 * hash12(cell + 71.9);
			float capsule = length(vec2(max(abs(local.x) - halfLength, 0.0), local.y)) - halfWidth;
			// Capsule distance is measured in output pixels. A fixed pixel-space
			// transition avoids derivative spikes when the 3x3 candidate
			// neighborhood advances to the next spawn cell.
			float aa = 1.35;
			float body = 1.0 - smoothstep(-aa, aa, capsule);
			float bristle = 0.78 + 0.22 * (0.5 + 0.5 *
				sin(local.y * 5.2 + hash12(cell + 97.3) * 6.2831853));
			float mark = body * bristle;
			vec2 centerGlobal = dirUnit * center.x + across * center.y;
			vec2 centerUV = uv + (centerGlobal - gc) / resolution;
			pigmentSum += srcSample(centerUV).rgb * mark;
			pigmentWeight += mark;
			field = max(field, mark);
		}
	}
	vec3 pigment = pigmentWeight > 0.0001
		? pigmentSum / pigmentWeight
		: srcSample(uv).rgb;
	return vec4(pigment, clamp(field, 0.0, 1.0));
}

// Smooth (value-noise) symmetric 2D jitter for sprayed taps - recentered around
// zero so scatter is unbiased in every direction (an uncentered hash would bias
// every dab toward one quadrant).
vec2 sprayJitter(vec2 gc, float tap) {
	vec2 p = gc / 7.0;
	return vec2(
		valueNoise2(p + vec2(tap * 0.73, 7.0)),
		valueNoise2(p + vec2(11.0, tap * 0.79) + 37.1)
	) - 0.5;
}

// Every smear()/brushStrokeField() fetch routes through here so sumiE's pre-erode
// applies uniformly across the whole smeared field. MODE is a compile-time const,
// so this is dead code in every other compiled variant (confirmed by construction).
vec4 srcSample(vec2 sampleUV) {
	if (MODE == 3) {
		// Sumi-e reads a locally ERODED source, so the directional smear spreads
		// expanded dark ink exactly like the two-pass original (which smeared a
		// precomputed 3x3 min). A 4-neighbour cross min approximates that erosion
		// inline.
		vec2 px = 1.0 / resolution;
		vec4 s = texture(inputTex, sampleUV);
		vec3 e = s.rgb;
		e = min(e, texture(inputTex, sampleUV + vec2(px.x, 0.0)).rgb);
		e = min(e, texture(inputTex, sampleUV - vec2(px.x, 0.0)).rgb);
		e = min(e, texture(inputTex, sampleUV + vec2(0.0, px.y)).rgb);
		e = min(e, texture(inputTex, sampleUV - vec2(0.0, px.y)).rgb);
		return vec4(e, s.a);
	}
	return texture(inputTex, sampleUV);
}

// Bounded directional accumulation, up to MAX_TAPS taps on each side of uv along
// dirUnit, weights exp(-2i/L). jitterPx > 0 (sprayed, MODE 1 only) adds a symmetric,
// smoothly varying 2D jitter to the sample position so dabs scatter off the stroke
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
			jp = sprayJitter(gc, fi) * jitterPx;
			jn = sprayJitter(gc + 31.7, -fi) * jitterPx;
		}
		vec2 sampP = uv + (dirUnit * fi) * px + jp * px;
		vec2 sampN = uv - (dirUnit * fi) * px + jn * px;
		sum += (srcSample(sampP) + srcSample(sampN)) * w;
		wsum += 2.0 * w;
	}
	return sum / wsum;
}

// Per-mode dispatch - mirrors the reference WGSL's own smearColor() shape
// (sequential if (MODE == N) { return ...; } checks, last mode as the
// unconditional fallback) rather than the reference GLSL's #if/#elif chain in
// main() - a pure control-flow-shape choice (MODE is a compile-time const either
// way, so dead branches are eliminated identically).
vec4 smearColor(vec2 uv, vec2 gc, vec4 src, float runBase) {
	if (MODE == 0) {
		// Angled Strokes: two diagonal fields, blended by tone side of `balance`.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		vec2 dir135 = rotate2D(vec2(1.0, 0.0), 135.0);
		float l45 = runBase * strokeVariation(gc, dir45, runBase);
		float l135 = runBase * strokeVariation(gc, dir135, runBase);
		vec4 layer45 = brushStrokeField(uv, gc, dir45, runBase);
		vec4 layer135 = brushStrokeField(uv, gc, dir135, runBase);
		vec4 pigment45 = mix(smear(uv, gc, dir45, l45, 0.0), vec4(layer45.rgb, src.a), 0.72);
		vec4 pigment135 = mix(smear(uv, gc, dir135, l135, 0.0), vec4(layer135.rgb, src.a), 0.72);
		vec4 field45 = mix(src, pigment45, layer45.a);
		vec4 field135 = mix(src, pigment135, layer135.a);
		float b = balance / 100.0;
		float side = smoothstep(b - 0.1, b + 0.1, lum(src.rgb));
		return mix(field135, field45, side);
	}
	if (MODE == 1) {
		// Sprayed Strokes: single 45deg field, per-tap jitter scaled by intensity.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		float L = runBase * strokeVariation(gc, dir45, runBase);
		float jitterPx = intensity / 100.0 * 6.0;
		vec4 layer = brushStrokeField(uv, gc, dir45, runBase);
		vec4 pigment = mix(smear(uv, gc, dir45, L, jitterPx), vec4(layer.rgb, src.a), 0.68);
		return mix(src, pigment, layer.a);
	}
	if (MODE == 2) {
		// Dark Strokes: single 45deg field, then tone-dependent crush/lift.
		vec2 dir45 = rotate2D(vec2(1.0, 0.0), 45.0);
		float L = runBase * strokeVariation(gc, dir45, runBase);
		vec4 layer = brushStrokeField(uv, gc, dir45, runBase);
		vec4 pigment = mix(smear(uv, gc, dir45, L, 0.0), vec4(layer.rgb, src.a), 0.72);
		vec4 c = mix(src, pigment, layer.a);
		float t = lum(c.rgb);
		float bAmt = balance / 100.0;
		float exponent = (t < bAmt) ? (1.0 + intensity / 50.0) : (1.0 / (1.0 + intensity / 100.0));
		c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(exponent));
		return c;
	}
	if (MODE == 3) {
		// Sumi-e: srcSample() erodes every fetch this smear/brushStrokeField make
		// before it's accumulated at 135deg (no separate/additional blur pass);
		// then a contrast-only pow curve darkens the result.
		vec2 dir135 = rotate2D(vec2(1.0, 0.0), 135.0);
		float L = runBase * strokeVariation(gc, dir135, runBase);
		vec4 layer = brushStrokeField(uv, gc, dir135, runBase);
		vec4 pigment = mix(smear(uv, gc, dir135, L, 0.0), vec4(layer.rgb, src.a), 0.74);
		vec4 c = mix(src, pigment, layer.a);
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
	float L = runBase * strokeVariation(gc, dir, runBase);
	vec4 layer = brushStrokeField(uv, gc, dir, runBase);
	vec4 pigment = mix(smear(uv, gc, dir, L, 0.0), vec4(layer.rgb, src.a), 0.64);
	vec4 smeared = mix(src, pigment, layer.a);
	float shadowMask = 1.0 - smoothstep(0.55, 0.65, lum(src.rgb));
	return mix(src, smeared, shadowMask);
}

void main() {
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 src = texture(inputTex, uv);
	vec2 gc = gl_FragCoord.xy + tileOffset;

	float runBase = mix(3.0, 50.0, strokeLength / 100.0);
	vec4 outc = smearColor(uv, gc, src, runBase);

	frag = vec4(clamp(outc.rgb, vec3(0.0), vec3(1.0)), src.a);
}
