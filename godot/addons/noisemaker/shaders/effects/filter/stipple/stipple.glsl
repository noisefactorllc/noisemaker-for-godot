#version 450
// filter/stipple (program "stipple") — ported from wgsl/stipple.wgsl EXCEPT for
// mezzoStrokes' rotation handedness, where this file uses the GLSL golden's
// mat2(co,-si,si,co)*v form instead of WGSL's raw one — see PORTING-GUIDE.md's
// rotation-handedness note (filter/spinBlur, filter/pondRipples, filter/halftone):
// rotate2D here rotates the fragment's own global coordinate (position-derived
// geometry), which this port has empirically established needs the GLSL-textual
// form on Godot, contrary to the WGSL source's own doctrine comment (calibrated
// for WebGPU, which does not transfer to Godot's RenderingDevice pipeline).
//
// Discrete random marks reproducing image tone (Photoshop Pointillize / Mezzotint
// / Reticulation via `mode`): 0 pointillize (colored dots on a paper background,
// one per jittered-grid Voronoi cell, sized by that cell's own darkness); 1/2/3
// mezzoDots/Lines/Strokes (each RGB channel hard-thresholded against shaped value
// noise scaled by grainSize, biased by density; strokes additionally rotates the
// sampling coordinate 45 degrees); 4 reticulation (two-tone ink/paper tonemap
// driven by luminance-modulated fBm clump noise).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define cellSize data[..]`, `#define grainSize data[..]`, `#define density
// data[..]`, `#define paperColor data[..].xyz`, `#define seed data[..]`. seed is
// an int, cast int(...) at use sites. MODE is a compile-time define injected by
// the runtime (definition.js globals.mode.define) — matches the reference's own
// compiled graph, which bakes `mode` into `defines.MODE`, never into `uniforms`.
// Input at set 0, binding 1. Single texture, texSize-space (no fullResolution
// remap — matches WGSL, no tiling concept). Every noise/hash helper is built from
// GLSL's floor/fract, which — like WGSL's — are floor-based (not truncated) for
// negative inputs, so the negative positions the rotation can produce need no
// separate floored-mod wrap.
#ifndef MODE
#define MODE 0
#endif

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

// S5 - jittered-grid Voronoi cell: returns xy = seed point in the same
// cell-space units as `p`, zw = integer cell id.
vec4 voronoiCell(vec2 p, float jitter, float seedVal) {
	vec2 g = floor(p);
	vec2 f = p - g;
	float best = 1e9;
	vec4 res = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 pt = cell + 0.5 + (hash22(g + cell + seedVal * 101.7) - 0.5) * jitter;
			float d = dot(pt - f, pt - f);
			if (d < best) {
				best = d;
				res = vec4(g + pt, g + cell);
			}
		}
	}
	return res;
}

// S9 - ink/paper tonemap.
vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

// Rotation handedness: GLSL golden's mat2(co,-si,si,co)*v form — see file header.
vec2 rotate2D(vec2 v, float angleDeg) {
	float a = radians(angleDeg);
	float co = cos(a);
	float si = sin(a);
	return vec2(co * v.x + si * v.y, -si * v.x + co * v.y);
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 globalCoord = gl_FragCoord.xy;
	vec2 uv = gl_FragCoord.xy / texSize;
	float alpha = texture(inputTex, uv).a;
	vec3 result;

	if (MODE == 0) {
		// Pointillize.
		vec2 p = globalCoord / cellSize;
		vec4 cell = voronoiCell(p, 0.9, float(int(seed)));
		vec2 seedGc = cell.xy * cellSize;
		vec2 seedUV = clamp(seedGc / texSize, vec2(0.0), vec2(1.0));
		vec3 seedColor = texture(inputTex, seedUV).rgb;
		float radius = 0.35 + 0.4 * (1.0 - lum(seedColor));
		float d = length(p - cell.xy);
		float aa = fwidth(d) * 1.5;
		float inside = smoothstep(radius + aa, radius - aa, d);
		result = mix(paperColor, seedColor, inside);
	} else if (MODE == 1 || MODE == 2 || MODE == 3) {
		// Mezzotint dots/lines/strokes.
		vec2 gc = globalCoord;
		if (MODE == 3) {
			gc = rotate2D(gc, 45.0);
		}
		vec2 noiseP;
		if (MODE == 1) {
			noiseP = gc / grainSize;
		} else {
			// Y keeps the coarse scale, X the fine scale, so streaks run
			// vertically.
			noiseP = gc * vec2(1.0 / grainSize, 1.0 / (grainSize * 8.0));
		}
		float n = vnoise(noiseP + float(int(seed)) * 101.7);
		n = n + (density - 50.0) / 100.0;
		vec3 src = texture(inputTex, uv).rgb;
		result = vec3(step(n, src.r), step(n, src.g), step(n, src.b));
	} else {
		// Reticulation.
		vec3 src = texture(inputTex, uv).rgb;
		float l = lum(src);
		float clumpNoise = fbm(globalCoord / (grainSize * 4.0) + float(int(seed)) * 101.7) * mix(1.2, 0.6, l);
		clumpNoise = clumpNoise + (density - 50.0) / 100.0;
		result = tonemap2(step(clumpNoise, l), vec3(0.05), vec3(0.97));
	}

	frag = vec4(result, alpha);
}
