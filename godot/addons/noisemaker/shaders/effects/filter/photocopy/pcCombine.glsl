#version 450
// filter/photocopy, program "pcCombine" — ported verbatim from
// wgsl/pcCombine.wgsl. Pass 3 of 3: band = lum(src) - lum(blur) is the
// difference-of-Gaussians edge signal — positive on the light side of an
// edge, negative on the dark side. edgeInk keeps only the negative (dark)
// side, gained by `darkness`. A midtone-dropout term suppresses ink entirely
// in bright source regions so only edges over darker material show ink; a
// separate term adds solid ink in deep shadows regardless of edge content.
// Total ink is clamped to 1 and tonemapped as tonemap2(1-ink, inkColor,
// paperColor). DoG is isotropic (no directional light, no rotation, no
// fragment-coordinate-derived vectors) — no Y-compensation question here.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define darkness data[..]`, `#define inkColor data[..].xyz`, `#define
// paperColor data[..].xyz`. Inputs at set 0, binding 1.. in pass.inputs order
// (inputTex, blurTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec4 blur = texture(blurTex, uv);

	float lumSrc = lum(src.rgb);
	float lumBlur = lum(blur.rgb);
	float band = lumSrc - lumBlur;

	float gain = mix(2.0, 10.0, darkness / 100.0);
	float edgeInk = clamp(-band * gain, 0.0, 1.0);

	float ink = edgeInk * (1.0 - smoothstep(0.4, 0.75, lumSrc));
	ink = clamp(ink + (1.0 - smoothstep(0.06, 0.12, lumSrc)), 0.0, 1.0);

	vec3 outColor = tonemap2(1.0 - ink, inkColor, paperColor);
	frag = vec4(outColor, src.a);
}
