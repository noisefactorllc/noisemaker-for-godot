#version 450
// filter/median, program "medianSeed" — ported verbatim from wgsl/medianSeed.wgsl.
// Pass 1 of 3 (seed -> medianPass[repeat=iterations] -> final; see
// effects/filter/median.json). Copies inputTex into the global_median_state
// ping-pong surface before the iterated 3x3 median passes run. Input at set 0,
// binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	frag = texture(inputTex, uv);
}
