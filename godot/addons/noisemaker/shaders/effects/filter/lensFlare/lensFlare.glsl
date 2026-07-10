#version 450
// filter/lensFlare (program "lensFlare") — ported PIXEL-IDENTICALLY from
// wgsl/lensFlare.wgsl (a 1:1 port; no rotation/handedness question anywhere in
// this effect — every shape primitive (core glow, streak, star, hex mask,
// circle/ring ghosts, halo band) is built from squared distances, cos(6*phi), or
// a 3-axis abs(dot(...)) max, all mirror-symmetric under a Y flip by
// construction. centerX/centerY are position-derived (flarePos) and used RAW,
// with no 1.0-centerY flip, per the general screen-truth doctrine — the only
// orientation-sensitive quantity in this whole effect).
//
// Photoshop-style additive lens flare (Filter > Render > Lens Flare). Every
// element sits along the flare axis A(t) = mix(flarePos, mirrorPos, t), where
// flarePos = (centerX, centerY) and mirrorPos = 1 - flarePos is flarePos
// reflected across the fixed image center. A fixed-size, fully-unrolled element
// table (core glow, anamorphic streak, 6-point star, rainbow halo, and a
// per-lensType ghost chain) is evaluated additively over the source image:
// out = clamp(src + flare, 0, 1), alpha copied from the source. All distances are
// measured in aspect-corrected UV space so circular/hexagonal elements stay
// round/regular regardless of image aspect ratio. See
// effects/filter/lensFlare.json / the reference definition.js for the full
// per-parameter and per-lensType description.
//
// lensType is a plain RUNTIME int uniform (choices, no compile-time `define`),
// so it arrives as a float component in the packed UBO — cast int(lensType) at
// comparison sites (established idiom, e.g. filter/hatch's direction).
//
// The reversed-edge smoothstep idiom in circleGhost/softCircleGhost/ringGhost/
// hexGhost (smoothstep(hi, lo, x) with hi > lo) is UNDEFINED per the GLSL/WGSL
// spec, which requires edge0 < edge1 — reference commit 92a73bf7 normalized this
// to `1.0 - smoothstep(lo, hi, x)` (ascending edges, then invert), which this
// port carries forward (not the pre-fix reversed-edge form).
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// brightness data[..]`, `centerX`, `centerY`, `lensType`, `tint`. Input at set 0,
// binding 1.
//
// Reserved-name collision: the reference's local `aspectRatio` (and its
// flareAxis helper's own `aspectRatio` parameter) collide with the
// engine-injected bare name `aspectRatio` (always available,
// PORTING-GUIDE.md's reserved-name list) - a same-named local/parameter
// macro-expands to `data[0].w` mid-declaration, which glslang rejects
// ("array size must be a positive integer"). Renamed to `ar` throughout
// (pure symbol rename, no behavior change, still computed explicitly as
// fullResolution.x/fullResolution.y to match the WGSL/GLSL source
// bit-for-bit rather than relying on the engine's own aspectRatio value) -
// established idiom, e.g. filter/hatch's direction/int-cast precedent and
// PORTING-GUIDE's own aspectRatio->ar example.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const float TAU = 6.28318530717958647692;

// Aspect-corrected point at parameter t along the flare axis.
vec2 flareAxis(vec2 flarePos, vec2 mirrorPos, float t, float ar) {
	vec2 a = mix(flarePos, mirrorPos, t);
	a.x *= ar;
	return a;
}

// Bright core: a tight Gaussian spike plus a wider soft glow skirt.
float coreGlow(float d) {
	return exp(-d * d * 900.0) * 1.2 + exp(-d * 8.0) * 0.4;
}

// Anamorphic streak: very tight vertically (dy weighted 4000x), long
// horizontally (dx weighted 18x).
float anamorphicStreak(vec2 delta) {
	return exp(-(delta.y * delta.y * 4000.0 + delta.x * delta.x * 18.0));
}

// 6-point star: cos(6*phi) spikes every 60 degrees around the flare.
float sixPointStar(vec2 delta, float d) {
	float phi = atan(delta.y, delta.x);
	return pow(max(0.0, cos(6.0 * phi)), 40.0) * exp(-d * 5.0) * 0.5;
}

// Simple 3-phase cosine palette for the halo's rainbow tint.
vec3 haloRainbow(float dc) {
	return 0.5 + 0.5 * cos(TAU * (dc * 10.0 + vec3(0.0, 0.3333333, 0.6666667)));
}

// Halo ring: a narrow band centered at radius 0.28 around the mirrored point
// (t=1.0).
float haloBand(float dc) {
	return exp(-abs(dc - 0.28) * 60.0) * 0.25;
}

// Filled-disc ghost with a soft edge (normalized ascending-edge smoothstep, then
// inverted - see file header).
float circleGhost(float dist, float size) {
	return (1.0 - smoothstep(size * 0.6, size, dist));
}

// Same idiom as circleGhost but with a wider falloff band, used for prime105's
// large "soft circle" ghosts.
float softCircleGhost(float dist, float size) {
	return (1.0 - smoothstep(size * 0.3, size, dist));
}

// Hollow ring ghost: an outer soft disc minus a smaller inner soft disc.
float ringGhost(float dist, float size) {
	float outer = (1.0 - smoothstep(size * 0.6, size, dist));
	float inner = (1.0 - smoothstep(size * 0.3, size * 0.6, dist));
	return outer - inner;
}

// Regular-hexagon "distance": max of abs(dot(p, axis)) over 3 axes 60 degrees
// apart.
float hexDist(vec2 p) {
	vec2 a0 = vec2(1.0, 0.0);
	vec2 a1 = vec2(0.5, 0.8660254038);
	vec2 a2 = vec2(-0.5, 0.8660254038);
	float d0 = abs(dot(p, a0));
	float d1 = abs(dot(p, a1));
	float d2 = abs(dot(p, a2));
	return max(d0, max(d1, d2));
}

float hexGhost(vec2 delta, float size) {
	return (1.0 - smoothstep(size * 0.6, size, hexDist(delta)));
}

void main() {
	float ar = fullResolution.x / fullResolution.y;
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = globalCoord / fullResolution;
	vec2 localUV = gl_FragCoord.xy / resolution;

	vec4 src = texture(inputTex, localUV);

	vec2 flarePos = vec2(centerX, centerY);
	vec2 mirrorPos = vec2(1.0) - flarePos;

	vec2 p = uv;
	p.x *= ar;

	vec2 aFlare = flareAxis(flarePos, mirrorPos, 0.0, ar);
	vec2 delta0 = p - aFlare;
	float d0 = length(delta0);

	vec3 flare = vec3(0.0);

	int lensTypeI = int(lensType);

	// Core glow (all lens types).
	flare += vec3(coreGlow(d0));

	// Anamorphic streak (all lens types; doubled for moviePrime).
	float streakVal = anamorphicStreak(delta0);
	if (lensTypeI == 3) {
		streakVal *= 2.0;
	}
	flare += vec3(streakVal);

	// 6-point star: zoom50_300 and moviePrime only.
	if (lensTypeI == 0 || lensTypeI == 3) {
		flare += vec3(sixPointStar(delta0, d0));
	}

	// Rainbow halo ring at t=1.0 (all lens types).
	vec2 aMirror = flareAxis(flarePos, mirrorPos, 1.0, ar);
	float dc = length(p - aMirror);
	flare += haloRainbow(dc) * haloBand(dc);

	// Ghost chain: table selected by lensType.
	vec2 g = vec2(0.0);
	if (lensTypeI == 0 || lensTypeI == 3) {
		// zoom50_300 (also the base table for moviePrime): 6 ghosts, the largest
		// (t=1.55) rendered hollow for classic-look variety.
		g = flareAxis(flarePos, mirrorPos, 0.25, ar);
		flare += vec3(1.00, 0.85, 0.60) * circleGhost(length(p - g), 0.06) * 0.35;

		g = flareAxis(flarePos, mirrorPos, 0.4, ar);
		flare += vec3(0.40, 0.90, 0.85) * circleGhost(length(p - g), 0.10) * 0.25;

		g = flareAxis(flarePos, mirrorPos, 0.6, ar);
		flare += vec3(0.65, 0.40, 0.95) * circleGhost(length(p - g), 0.045) * 0.45;

		g = flareAxis(flarePos, mirrorPos, 0.85, ar);
		flare += vec3(0.45, 0.90, 0.50) * circleGhost(length(p - g), 0.14) * 0.18;

		g = flareAxis(flarePos, mirrorPos, 1.2, ar);
		flare += vec3(1.00, 0.55, 0.20) * circleGhost(length(p - g), 0.08) * 0.30;

		g = flareAxis(flarePos, mirrorPos, 1.55, ar);
		flare += vec3(0.40, 0.55, 1.00) * ringGhost(length(p - g), 0.20) * 0.12;
	} else if (lensTypeI == 1) {
		// prime35: 4 tight hexagon ghosts.
		g = flareAxis(flarePos, mirrorPos, 0.3, ar);
		flare += vec3(1.00, 0.80, 0.55) * hexGhost(p - g, 0.04) * 0.35;

		g = flareAxis(flarePos, mirrorPos, 0.55, ar);
		flare += vec3(0.85, 0.85, 0.92) * hexGhost(p - g, 0.055) * 0.30;

		g = flareAxis(flarePos, mirrorPos, 0.8, ar);
		flare += vec3(0.95, 0.70, 0.50) * hexGhost(p - g, 0.065) * 0.25;

		g = flareAxis(flarePos, mirrorPos, 1.3, ar);
		flare += vec3(0.80, 0.85, 0.95) * hexGhost(p - g, 0.08) * 0.20;
	} else {
		// prime105: 3 large soft circles.
		g = flareAxis(flarePos, mirrorPos, 0.45, ar);
		flare += vec3(0.92, 0.85, 0.78) * softCircleGhost(length(p - g), 0.12) * 0.25;

		g = flareAxis(flarePos, mirrorPos, 0.9, ar);
		flare += vec3(0.85, 0.88, 0.95) * softCircleGhost(length(p - g), 0.16) * 0.20;

		g = flareAxis(flarePos, mirrorPos, 1.5, ar);
		flare += vec3(0.95, 0.88, 0.80) * softCircleGhost(length(p - g), 0.20) * 0.15;
	}

	vec3 outFlare = flare * tint * (brightness / 100.0);
	if (lensTypeI == 3) {
		// moviePrime: cooler overall tint multiplier on top of the user's tint.
		outFlare *= vec3(0.9, 0.95, 1.1);
	}

	frag = vec4(clamp(src.rgb + outFlare, 0.0, 1.0), src.a);
}
