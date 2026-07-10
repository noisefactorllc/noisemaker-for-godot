#version 450
// filter/strokes (program "stkPost") — ported PIXEL-IDENTICALLY from
// wgsl/stkPost.glsl (a 1:1 port, no rotation/handedness question - the tent3x3
// kernel uses literal, backend-agnostic integer offsets, same category as
// filter/oilPaint's tent3x3 / filter/emboss's kernel). Unsharp-sharpens the
// smeared result from stkSmear by `sharpness`, using a 3x3 tent blur as the
// unsharp mask's low-pass reference. Alpha passes through from the original
// source (inputTex).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define sharpness data[..]`. Two inputs (pass.inputs order): inputTex at
// binding 1, smearTex (the _stkTmp internal texture) at binding 2.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D smearTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

// 3x3 tent blur of the smeared texture - same shape as filter/oilPaint's
// tent3x3 (daubs unsharp / knife soften).
vec3 tent3x3(vec2 uv) {
	vec2 px = 1.0 / resolution;
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			float w = (dx == 0 ? 2.0 : 1.0) * (dy == 0 ? 2.0 : 1.0);
			sum += texture(smearTex, uv + vec2(float(dx), float(dy)) * px).rgb * w;
			wsum += w;
		}
	}
	return sum / wsum;
}

void main() {
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 src = texture(inputTex, uv);
	vec3 c = texture(smearTex, uv).rgb;

	vec3 tent = tent3x3(uv);
	vec3 sharpened = c + (c - tent) * (sharpness / 33.0);

	frag = vec4(clamp(sharpened, 0.0, 1.0), src.a);
}
