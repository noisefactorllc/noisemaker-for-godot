#version 450
// filter/craquelure (program "craquelure") — ported PIXEL-IDENTICALLY from
// wgsl/craquelure.wgsl (a 1:1 port; no rotation/handedness question anywhere in
// this effect — no angle param, no swirl. Every vector here is floor/fract-based
// Voronoi-cell math or a scalar broadcast, and reliefShade's light vector L is a
// plain function of the fixed 135-degree angle constant, not fragment-coordinate-
// derived at all, so it is textually identical between GLSL and WGSL — see
// filter/relief's rlShade.glsl precedent, whose reliefShade is reused verbatim
// below).
//
// Cracked-plaster groove network with carved relief over the image (Photoshop
// Filter Gallery > Texture > Craquelure): an S5-derived jittered-grid Voronoi
// field is extended to track F1 (nearest seed distance) AND F2 (second-nearest),
// whose difference (F2-F1) is a standard "distance to cell border" proxy used to
// carve a groove network (crackMask), then S8's relief shading (fixed 135-degree
// light) is beveled onto the groove walls from a true central-difference gradient
// of the crack mask. The height fed to reliefShade is -k (NOT +k): a crack is a
// carved groove (a dip), not a raised ridge. reliefShade's flat-gradient baseline
// is 0.6 (not 0.5) for any lightAngleDeg, so the bevel multiplier is centered
// there and gated by wallMask (built from the same central-diff gradient) so flat
// ground away from any crack reads EXACTLY shadeMul == 1.0. See
// effects/filter/craquelure.json / the reference definition.js for the full
// per-parameter description.
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// spacing data[..]`, `#define depth data[..]`, `#define brightness data[..]`,
// `#define seed data[..]`. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

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

// S4 - value noise (fBm not needed here).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// S5 extended - jittered-grid Voronoi F1/F2: returns x = nearest seed distance
// (F1), y = second-nearest seed distance (F2), in the same cell-space units as
// `p`. Squared distances compared internally; sqrt taken only for the two
// winners. Search radius is one ring of neighbor cells (exact for F1 at
// jitter<=1; F2 can rarely be under-counted near a cell's corner at jitter's
// maximum of 1.0 - a minor, infrequent error in the crack metric).
vec2 voronoiF1F2(vec2 p, float jitter, float seedVal) {
	vec2 g = floor(p);
	vec2 f = p - g;
	float best = 1e9;
	float second = 1e9;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 pt = cell + 0.5 + (hash22(g + cell + seedVal * 101.7) - 0.5) * jitter;
			float d = dot(pt - f, pt - f);
			if (d < best) {
				second = best;
				best = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(sqrt(best), sqrt(second));
}

// S8 - relief shade from height (verbatim; see filter/relief's rlShade.glsl).
float reliefShade(float hC, float hR, float hT, float strength, float lightAngleDeg) {
	vec2 grad = vec2(hR - hC, hT - hC) * strength;
	vec3 n = normalize(vec3(-grad, 1.0));
	float a = radians(lightAngleDeg);
	vec3 L = normalize(vec3(cos(a), sin(a), 0.75));
	return clamp(dot(n, L), 0.0, 1.0);
}

// Crack mask k at global pixel position gc: 1 on a cell border, falling to 0
// within `edge` px. Border wobble: two independent noise taps (one per axis) so
// the crack path weaves organically regardless of its local tangent angle.
float crackMask(vec2 gc, float spacingPx, float depthPct, float seedVal) {
	vec2 wob = vec2(vnoise(gc / 6.0), vnoise(gc / 6.0 + vec2(37.7, 91.3))) * 2.0;
	vec2 p = (gc + wob) / spacingPx;
	vec2 f1f2 = voronoiF1F2(p, 1.0, seedVal);
	float d = (f1f2.y - f1f2.x) * spacingPx;
	float edge = 1.5 + depthPct / 100.0 * 2.0;
	return 1.0 - smoothstep(0.0, edge, d);
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 src = texture(inputTex, uv);
	float seedF = float(seed);

	float kC = crackMask(globalCoord, spacing, depth, seedF);
	float kR = crackMask(globalCoord + vec2(1.0, 0.0), spacing, depth, seedF);
	float kL = crackMask(globalCoord - vec2(1.0, 0.0), spacing, depth, seedF);
	float kT = crackMask(globalCoord + vec2(0.0, 1.0), spacing, depth, seedF);
	float kB = crackMask(globalCoord - vec2(0.0, 1.0), spacing, depth, seedF);

	// Central-difference gradient of k; feeds both reliefShade's synthetic height
	// samples below and wallMask's locality gate.
	vec2 gradK = vec2((kR - kL) * 0.5, (kT - kB) * 0.5);

	// Height fed to reliefShade is -k: a crack is a carved groove (a dip), not a
	// raised ridge, so height must fall toward the crack center. Negating
	// hC/hR/hT flips the sign of the gradient/normal reliefShade sees, which
	// flips which groove wall catches the light.
	float hC = -kC;
	float hR = hC - gradK.x;
	float hT = hC - gradK.y;
	float shadeStrength = 6.0;
	float shade = reliefShade(hC, hR, hT, shadeStrength, 135.0);

	// reliefShade's flat-gradient baseline is 0.6, not 0.5 - recenter on it, and
	// gate by wallMask so flat ground away from any crack gets EXACTLY
	// shadeMul == 1.0 (gradK saturates to exactly 0 there by smoothstep's
	// clamped range).
	float gradMagK = length(gradK);
	float wallMask = smoothstep(0.0, 0.02, gradMagK);
	float shadeMul = 1.0 + (shade - 0.6) * 2.0 * (0.25 * depth / 100.0) * wallMask;

	vec3 darkened = src.rgb * mix(1.0, 0.35 + brightness / 100.0 * 0.5, kC);
	vec3 result = clamp(darkened * shadeMul, 0.0, 1.0);

	frag = vec4(result, src.a);
}
