#version 450
// filter/unsharpMask, program "usmCombine" — ported verbatim from wgsl/usmCombine.wgsl.
// Combine pass (3 of 3: blurH -> blurV -> combine; see effects/filter/unsharpMask.json).
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define amount data[..]`, `#define threshold data[..]`, so we use the bare
// reference names. Inputs at set 0, binding 1.. in pass.inputs order (inputTex,
// blurTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec4 blur = texture(blurTex, uv);
	vec3 diff = src.rgb - blur.rgb;
	float t = threshold / 100.0;
	float mag = max(max(abs(diff.r), abs(diff.g)), abs(diff.b));
	float gate = smoothstep(t, t + 0.02, mag);
	vec3 outc = src.rgb + diff * (amount / 100.0) * gate;
	frag = vec4(clamp(outc, vec3(0.0), vec3(1.0)), src.a);
}
