#version 450
// filter/directionalBlur (program "directionalBlur") — ported verbatim from
// wgsl/directionalBlur.wgsl. Linear motion blur (Photoshop Motion Blur): averages a
// fixed 32-tap comb stepped along dir=(cos(angle),sin(angle)), spanning blurDistance
// px total, with a per-pixel hash jitter (up to half a tap-step) to hide banding from
// the fixed tap count.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define angle data[..]`, `#define blurDistance data[..]`. The DSL-facing param
// name is "distance", but its shader uniform is "blurDistance" (reference definition
// note: GLSL/WGSL both have a builtin distance() function, so a uniform literally
// named "distance" risks a redefinition error) — this file only ever sees the
// already-renamed bare name. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const int N = 32;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 dir = vec2(cos(radians(angle)), sin(radians(angle)));

	float tapStep = blurDistance / float(N - 1);
	float jitter = (hash12(gl_FragCoord.xy) - 0.5) * tapStep;

	vec4 sum = vec4(0.0);
	for (int i = 0; i < N; i++) {
		float t = (float(i) / float(N - 1) - 0.5) * blurDistance + jitter;
		vec2 offset = dir * t;
		sum += texture(inputTex, (gl_FragCoord.xy + offset) / texSize);
	}
	frag = sum / float(N);
}
