#version 450
// filter/scatter, program "scatterJitter" — ported verbatim from
// wgsl/scatterJitter.wgsl. Pass 1 of 2 (scatterJitter -> scatterSmooth; see
// effects/filter/scatter.json). Random per-pixel scatter (Photoshop Diffuse, all
// four modes, and Spatter's core dissolve): samples the input at a random
// per-pixel offset within `radius` px. mode: 0 normal, 1 darkenOnly (min), 2
// lightenOnly (max), 3 anisotropic (offset projected along the local luminance
// edge direction), 4 clumped (hash coordinate quantized to 3px blocks so every
// pixel in a block shares the same random offset).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define radius data[..]`, `#define seed data[..]` as bare (float-valued)
// names — seed is an int with a range but arrives as a raw float here; cast
// with int(...) at comparison/arithmetic sites. MODE is a compile-time define
// injected by the runtime (definition.js globals.mode.define) — matches the
// reference's own compiled graph, which bakes `mode` into `defines.MODE`,
// never into `uniforms`. Input at set 0, binding 1.
#ifndef MODE
#define MODE 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Sobel gradient of luminance; used by anisotropic mode to find the local edge
// direction (perpendicular to the gradient = along the edge).
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

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;

	// Seed with the global (tile-aware) coordinate, not gl_FragCoord.xy alone,
	// so the scatter field is continuous across CLI render tiles instead of
	// restarting at each tile's local origin.
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;

	// Clumped mode: quantize the hash coordinate to 3px blocks BEFORE hashing so
	// every pixel in a block shares the same random offset.
	vec2 hashCoord = globalCoord;
	if (MODE == 4) {
		hashCoord = floor(globalCoord / 3.0) * 3.0;
	}

	vec2 rnd = hash22(hashCoord + float(int(seed)) * 101.7) - 0.5;
	vec2 offset = rnd * 2.0 * radius;

	if (MODE == 3) {
		// Anisotropic: project the offset onto the direction perpendicular to
		// the local luminance gradient (edge-following smear).
		vec2 grad = lumGradient(uv);
		float gradLen = length(grad);
		if (gradLen > 1e-5) {
			vec2 perp = vec2(-grad.y, grad.x) / gradLen;
			offset = dot(offset, perp) * perp;
		}
		// else: gradient ~zero (flat region) -- fall back to raw offset.
	}

	vec2 sampleUV = clamp((gl_FragCoord.xy + offset) / texSize, vec2(0.0), vec2(1.0));

	vec4 src = texture(inputTex, uv);
	vec4 samp = texture(inputTex, sampleUV);

	vec4 result = samp;
	if (MODE == 1) {
		result = min(src, samp);
	} else if (MODE == 2) {
		result = max(src, samp);
	}

	frag = result;
}
