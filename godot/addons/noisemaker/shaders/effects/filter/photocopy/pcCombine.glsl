#version 450
// filter/photocopy, program "pcCombine" — ported verbatim from
// wgsl/pcCombine.wgsl. Pass 3 of 3: two independent ink contributions,
// combined with max() so neither term has to carry the whole image alone.
//
// 1. Edge ink: band = lum(src) - lum(blur) is the difference-of-Gaussians
//    signal. abs(band) inks BOTH sides of an edge (a thin double-line
//    contour, the characteristic photocopier edge artifact), gained by
//    `darkness` via edgeGain = mix(4, 18, darkness/100).
// 2. Tonal ink: toneInk = 1 - smoothstep(toneLo, toneHi, lumSrc) fills the
//    source's own mid-dark regions with solid ink directly, independent of
//    edge content. toneHi = mix(0.35, 0.68, darkness/100) tracks `darkness`;
//    toneLo = toneHi - 0.26 is a fixed-width falling ramp below it.
//
// ink = clamp(max(edgeInk, toneInk), 0, 1), tonemapped as tonemap2(1-ink,
// inkColor, paperColor). DoG is isotropic (no directional light, no
// rotation, no fragment-coordinate-derived vectors) — no Y-compensation
// question here.
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

	float edgeGain = mix(4.0, 18.0, darkness / 100.0);
	float edgeInk = clamp(abs(band) * edgeGain, 0.0, 1.0);

	float toneHi = mix(0.35, 0.68, darkness / 100.0);
	float toneLo = toneHi - 0.26;
	float toneInk = 1.0 - smoothstep(toneLo, toneHi, lumSrc);

	float ink = clamp(max(edgeInk, toneInk), 0.0, 1.0);

	vec3 outColor = tonemap2(1.0 - ink, inkColor, paperColor);
	frag = vec4(outColor, src.a);
}
