#version 450
// filter/scatter, program "scatterSmooth" — ported verbatim from
// wgsl/scatterSmooth.wgsl. Pass 2 of 2: re-blends the jittered result from
// scatterJitter with a 3x3 tent blur, mixed in by smoothness/100 (Photoshop
// Spatter's Smoothness parameter). smoothness=0 leaves the pure per-pixel jitter
// untouched. No-layout effect: the backend synthesizes the Params UBO and injects
// `#define smoothness data[..]`. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texel = 1.0 / texSize;

	vec4 src = texture(inputTex, uv);

	// 3x3 tent kernel: weight (2 - |x|) * (2 - |y|) for x, y in {-1, 0, 1}, giving
	// weights 1/2/1 / 2/4/2 / 1/2/1 (sum 16).
	vec4 sum = vec4(0.0);
	float wsum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float w = (2.0 - abs(float(x))) * (2.0 - abs(float(y)));
			sum += texture(inputTex, uv + vec2(float(x), float(y)) * texel) * w;
			wsum += w;
		}
	}
	vec4 blurred = sum / wsum;

	frag = mix(src, blurred, clamp(smoothness / 100.0, 0.0, 1.0));
}
