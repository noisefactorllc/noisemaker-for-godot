#version 450
// filter/highPass, program "hpBlurV" — ported from wgsl/hpBlurV.wgsl. See hpBlurH.glsl
// for the stride/radius notes. No-layout effect: the backend synthesizes the Params
// UBO and injects `#define radius data[..]`. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 dirPx = vec2(0.0, 1.0);
	float sigma = max(radius * 0.5, 0.001);
	float fTaps = min(radius, 32.0);
	float stride = radius > 32.0 ? radius / 32.0 : 1.0;
	vec4 sum = texture(inputTex, uv);
	float wsum = 1.0;
	for (int i = 1; i <= 32; i++) {
		if (float(i) > fTaps) { break; }
		float w = exp(-float(i * i) / (2.0 * sigma * sigma));
		vec2 o = dirPx * float(i) * stride / texSize;
		sum += (texture(inputTex, uv + o) + texture(inputTex, uv - o)) * w;
		wsum += 2.0 * w;
	}
	frag = sum / wsum;
}
