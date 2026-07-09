#version 450
// filter/morphology, program "morphB" — ported from wgsl/morphology's morphB.wgsl.
// Pass 2 of 2: square shape finishes the separable box structuring element with a
// vertical-line pass over morphA's horizontal result; round shape is a passthrough
// copy since morphA already computed the full disc structuring element. See
// morphA.glsl for the mode/shape int-cast and mix() notes.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 acc = texture(inputTex, uv);

	if (int(shape) == 0) {
		vec2 texel = 1.0 / texSize;
		float r = min(radius, 32.0);
		for (int i = 1; i <= 32; i++) {
			if (float(i) > r) { break; }
			vec2 o = vec2(0.0, float(i)) * texel;
			vec4 sD = texture(inputTex, uv - o);
			vec4 sU = texture(inputTex, uv + o);
			vec4 hi = max(acc, max(sD, sU));
			vec4 lo = min(acc, min(sD, sU));
			acc = mix(hi, lo, float(mode));
		}
	}
	// Round shape: acc is already morphA's disc-SE result; passthrough.

	frag = acc;
}
