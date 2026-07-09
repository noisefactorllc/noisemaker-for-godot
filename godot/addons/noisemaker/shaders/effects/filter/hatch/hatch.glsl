#version 450
// filter/hatch (program "hatch") — ported from wgsl/hatch.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's
// mat2(co,-si,si,co)*v form instead of WGSL's raw one — see PORTING-GUIDE.md's
// rotation-handedness note (filter/spinBlur, filter/pondRipples,
// filter/halftone, filter/stipple): rotate2D here rotates the fragment's own
// global coordinate gc (position-derived geometry, the same category those
// effects fall in — confirmed by this file's own WGSL/GLSL source headers,
// which both explicitly categorize it that way), and this port has
// empirically established that category needs the GLSL-textual form on
// Godot, contrary to the WGSL source's own doctrine comment (calibrated for
// WebGPU, which does not transfer to Godot's RenderingDevice pipeline).
//
// Six-mode hand-drawn sketch engine covering Photoshop's Graphic Pen,
// Charcoal, Chalk & Charcoal, Conte Crayon, Crosshatch, and Colored Pencil
// filters via `mode`. Every mode reads the same elongated-value-noise stroke
// field (strokeField), sampled on the tile-aware global integer pixel
// coordinate. See effects/filter/hatch.json / the reference definition.js
// for the full per-mode Photoshop-parity description.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define strokeLength data[..]`, `#define direction data[..]`, `#define
// balance data[..]`, `#define pressure data[..]`, `#define inkColor
// data[..].xyz`, `#define paperColor data[..].xyz`. MODE is a compile-time
// #define (globals.mode.define, same mechanism as synth/curl/filter/grain/
// filter/oilPaint). direction is an int with choices, cast int(...) at use
// sites. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

// S1 - hash / jitter.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// S2 - luminance.
float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// S4 - value noise + fBm.
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

// S6 - gradient (Sobel on luminance), used by coloredPencil to bend strokes
// along image contours.
vec2 lumGradient(vec2 uv) {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 px = 1.0 / texSize;
	float tl = lum(texture(inputTex, uv + px * vec2(-1.0,  1.0)).rgb);
	float l  = lum(texture(inputTex, uv + px * vec2(-1.0,  0.0)).rgb);
	float bl = lum(texture(inputTex, uv + px * vec2(-1.0, -1.0)).rgb);
	float tr = lum(texture(inputTex, uv + px * vec2( 1.0,  1.0)).rgb);
	float r  = lum(texture(inputTex, uv + px * vec2( 1.0,  0.0)).rgb);
	float br = lum(texture(inputTex, uv + px * vec2( 1.0, -1.0)).rgb);
	float t  = lum(texture(inputTex, uv + px * vec2( 0.0,  1.0)).rgb);
	float b  = lum(texture(inputTex, uv + px * vec2( 0.0, -1.0)).rgb);
	return vec2(tr + 2.0 * r + br - tl - 2.0 * l - bl,
	            tl + 2.0 * t + tr - bl - 2.0 * b - br);
}

// S9 - ink/paper tonemap.
vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

// Rotation handedness: GLSL golden's mat2(co,-si,si,co)*v form — see file
// header.
vec2 rotate2D(vec2 v, float angleDeg) {
	float a = radians(angleDeg);
	float co = cos(a);
	float si = sin(a);
	return vec2(co * v.x + si * v.y, -si * v.x + co * v.y);
}

// direction (0..3) -> stroke angle in degrees: rightDiag/horizontal/
// leftDiag/vertical.
float dirAngle(int d) {
	if (d == 1) { return 0.0; }
	if (d == 2) { return 135.0; }
	if (d == 3) { return 90.0; }
	return 45.0; // rightDiag (0, default)
}

// Shared stroke field: elongated value noise along angleDeg.
float strokeField(vec2 gc, float angleDeg, float stretchAmt) {
	vec2 p = rotate2D(gc, angleDeg) * vec2(1.0 / stretchAmt, 0.9);
	return vnoise(p);
}

// Per-mode dispatch — MODE is a compile-time const, mirroring
// filter/oilPaint's oilPost.glsl modeColor structure: sequential
// `if (MODE == N) { return ...; }` checks with the last mode (coloredPencil,
// 5) as the unconditional fallback.
vec3 hatchColor(vec2 gc, vec2 uv, vec3 src, float theta, float stretchAmt, float t, float pb, float s) {
	if (MODE == 0) {
		// Graphic Pen.
		float inkMask = step(s, clamp(1.0 - t + pb * 0.3, 0.0, 1.0));
		return tonemap2(1.0 - inkMask, inkColor, paperColor);
	}
	if (MODE == 1) {
		// Charcoal.
		float s2 = strokeField(gc * 2.0 + 91.7, theta, stretchAmt * 0.5);
		float rough = s * 0.6 + s2 * 0.4;
		float shadow = 1.0 - smoothstep(0.15, 0.55, t);
		float coverage = clamp(shadow + pb * 0.5, 0.0, 1.0);
		float inkMask = step(1.0 - coverage, rough);
		float darkness = mix(0.55, 1.0, pressure / 100.0);
		vec3 inkC = mix(paperColor, inkColor, darkness);
		return mix(paperColor, inkC, inkMask);
	}
	if (MODE == 2) {
		// Chalk & Charcoal.
		vec3 midGray = mix(inkColor, paperColor, 0.5);
		float sBg = strokeField(gc, theta + 90.0, stretchAmt);
		float aa = mix(0.4, 0.04, pressure / 100.0);
		float fgGate = 1.0 - smoothstep(0.4 - aa, 0.4 + aa, t);
		float fgMask = step(1.0 - fgGate, s);
		float bgGate = smoothstep(0.6 - aa, 0.6 + aa, t);
		float bgMask = step(1.0 - bgGate, sBg);
		vec3 outc = midGray;
		outc = mix(outc, inkColor, fgMask);
		outc = mix(outc, paperColor, bgMask);
		return outc;
	}
	if (MODE == 3) {
		// Conte Crayon.
		float toneGate = smoothstep(0.3, 0.7, t);
		float texture2 = mix(s, fbm(gc / (stretchAmt * 0.6) + 41.0), 0.5);
		float level = mix(texture2, toneGate, abs(toneGate * 2.0 - 1.0));
		level = clamp(level + pb * 0.15, 0.0, 1.0);
		return tonemap2(1.0 - level, inkColor, paperColor);
	}
	if (MODE == 4) {
		// Crosshatch (color-preserving).
		float s45a = strokeField(gc, theta + 45.0, stretchAmt);
		float s45b = strokeField(gc, theta - 45.0, stretchAmt);
		float band1 = 1.0 - smoothstep(0.65, 0.85, t);
		float band2 = 1.0 - smoothstep(0.35, 0.55, t);
		float band3 = 1.0 - smoothstep(0.05, 0.25, t);
		float darkGain = mix(0.25, 1.0, pressure / 100.0);
		float f0 = 1.0 - band1 * darkGain * (1.0 - s);
		float f1 = 1.0 - band2 * darkGain * (1.0 - s45a);
		float f2 = 1.0 - band3 * darkGain * (1.0 - s45b);
		return clamp(src * f0 * f1 * f2, vec3(0.0), vec3(1.0));
	}
	// coloredPencil (5) - fallback arm (MODE is always 0-5, injected by the
	// runtime, so the last value needs no explicit check). Color-preserving.
	vec2 grad = lumGradient(uv);
	float gradMag = length(grad);
	float edgeAngle = degrees(atan(grad.y, grad.x)) + 90.0;
	float sEdge = strokeField(gc, edgeAngle, stretchAmt);
	float edgeBoost = clamp(gradMag * 3.0, 0.0, 1.0);
	float sCombined = mix(s, sEdge, edgeBoost);
	float coverage = clamp((1.0 - t) + pb * 0.4, 0.0, 1.0);
	float strokeMask = step(1.0 - coverage, sCombined);
	return mix(paperColor, src, strokeMask);
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec2 gc = floor(gl_FragCoord.xy);

	float theta = dirAngle(int(direction));
	float stretchAmt = mix(4.0, 40.0, strokeLength / 100.0);
	float t = lum(src.rgb) + (balance - 50.0) / 100.0;
	float pb = (pressure - 50.0) / 100.0;
	float s = strokeField(gc, theta, stretchAmt);

	vec3 outColor = hatchColor(gc, uv, src.rgb, theta, stretchAmt, t, pb, s);

	frag = vec4(clamp(outColor, vec3(0.0), vec3(1.0)), src.a);
}
