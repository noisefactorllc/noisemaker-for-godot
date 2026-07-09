#version 450
// filter/oilPaint, program "oilFlatten" — ported verbatim from wgsl/oilFlatten.wgsl
// (the "f7ce21a4 Optimize oil paint flatten pass" stride-2 outer-ring
// optimization is already baked into this final source). Pass 1 of 2 (flatten
// -> post; see effects/filter/oilPaint.json). 8-sector Kuwahara filter: for
// each of 8 angular sectors around the pixel, accumulate mean/variance over a
// radius-fr disc, then output the sector with lowest variance (the
// "flattest"/most homogeneous patch), producing a painterly flattening core
// shared by every oilPaint mode. MODE 0 (facet) caps the flatten radius at 3px
// (a tighter facet-like flattening); all other modes use the full `size`.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define size data[..]`. MODE is a compile-time #define (globals.mode.define,
// same mechanism as synth/curl/filter/grain) — kept as a bare identifier.
// Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 px = 1.0 / texSize;

	float radius = size;
	if (MODE == 0) {
		radius = min(size, 3.0);
	}
	float fr = clamp(radius, 1.0, 12.0);
	float frSq = fr * fr;

	vec3 mean[8];
	vec3 sqr[8];
	float cnt[8];
	for (int k = 0; k < 8; k++) {
		mean[k] = vec3(0.0);
		sqr[k] = vec3(0.0);
		cnt[k] = 0.0;
	}

	for (int y = -12; y <= 12; y++) {
		for (int x = -12; x <= 12; x++) {
			vec2 d = vec2(float(x), float(y));
			if (abs(d.x) > fr || abs(d.y) > fr || dot(d, d) > frSq) { continue; }
			// Stride-2 outer ring: fr > 8.0 only when size > 8 (default size = 6
			// keeps fr <= 8 and this branch dead, so output is bit-identical to
			// the pre-optimization version at every size <= 8). Manhattan/
			// checkerboard parity (|x|+|y| even survives) keeps the thinned
			// ring isotropic rather than halving in just one axis.
			if (fr > 8.0 && dot(d, d) > 64.0 && (abs(x) + abs(y)) % 2 != 0) { continue; }

			// Octant classification without atan2: joint per-quadrant test
			// (verified against the atan2 formula for every integer offset in
			// [-12,12]x[-12,12]). (0,0) has no angle; pinned to sector 4,
			// matching the original atan2 guard's result.
			int k;
			if (x == 0 && y == 0) {
				k = 4;
			} else if (d.x > 0.0 && d.y >= 0.0) {
				k = (abs(d.x) <= abs(d.y)) ? 5 : 4;
			} else if (d.x <= 0.0 && d.y > 0.0) {
				k = (abs(d.x) < abs(d.y)) ? 6 : 7;
			} else if (d.x < 0.0 && d.y <= 0.0) {
				k = (abs(d.x) <= abs(d.y)) ? 1 : 0;
			} else {
				// remaining case: d.x >= 0.0 && d.y < 0.0
				k = (abs(d.x) < abs(d.y)) ? 2 : 3;
			}
			vec3 c = texture(inputTex, uv + d * px).rgb;
			mean[k] += c;
			sqr[k] += c * c;
			cnt[k] += 1.0;
		}
	}

	vec3 bestC = vec3(0.0);
	float bestV = 1e9;
	for (int k = 0; k < 8; k++) {
		if (cnt[k] < 1.0) { continue; }
		vec3 m = mean[k] / cnt[k];
		vec3 v = sqr[k] / cnt[k] - m * m;
		float tv = v.x + v.y + v.z;
		if (tv < bestV) {
			bestV = tv;
			bestC = m;
		}
	}

	frag = vec4(bestC, 1.0);
}
