#version 450
// filter/median, program "medianFinal" — ported from wgsl/medianFinal.wgsl.
// Pass 3 of 3: threshold-gated mix between the original image and the fully-iterated
// median result. threshold == 0 always uses the plain median (classic Photoshop
// Median filter); threshold > 0 only replaces pixels whose original/median
// difference exceeds the threshold (Dust & Scratches behavior). No-layout effect:
// the backend synthesizes the Params UBO and injects `#define threshold data[..]`.
// Inputs at set 0, binding 1.. in pass.inputs order (inputTex, medTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D medTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 orig = texture(inputTex, uv);
	vec4 med = texture(medTex, uv);

	vec3 d = abs(orig.rgb - med.rgb);
	float maxDiff = max(max(d.r, d.g), d.b);
	float gate = (threshold <= 0.0) ? 1.0 : step(threshold / 100.0, maxDiff);

	frag = vec4(mix(orig.rgb, med.rgb, gate), orig.a);
}
