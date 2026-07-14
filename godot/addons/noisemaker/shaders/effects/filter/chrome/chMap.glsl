#version 450
// filter/chrome, program "chMap" — ported verbatim from wgsl/chMap.wgsl, a
// 1:1 port with NO manual Y compensation anywhere: blurTex reads are
// orientation-transparent on both backends (same as filter/plasticWrap and
// filter/relief's blur-chain height fields), and the oscillating tone curve
// is a pure function of height only, nothing else fragment-coordinate-
// derived — PORTING-GUIDE's rotation-handedness exception does not apply.
//
// Liquid-metal chrome: reads the blurred image's luminance as a height
// field h via a true central difference (1px taps, NOT the forward-
// difference relief-shade form or the 3x3 Sobel form), self-distorts its
// own sample point by that gradient scaled by `distortion` (a cheap
// liquid-metal "refraction"; distortion=0 collapses uv2 to uv exactly),
// re-reads the height at the distorted point (h2), then runs h2 through an
// oscillating sine tone curve (band count driven by `detail`, plus a
// dephasing +h2*3.0 term so band spacing reads less mechanical) with a
// narrow rim-specular boost (pow(v,8)*0.5) and a cool/blue-gray tint.
// Grayscale only (no source color); alpha comes from inputTex's src.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define detail data[..]`, `#define distortion data[..]`. Inputs at set 0,
// binding 1.. in pass.inputs order (inputTex, blurTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texel = 1.0 / texSize;

	float hL = lum(texture(blurTex, uv - vec2(texel.x, 0.0)).rgb);
	float hR = lum(texture(blurTex, uv + vec2(texel.x, 0.0)).rgb);
	float hB = lum(texture(blurTex, uv - vec2(0.0, texel.y)).rgb);
	float hT = lum(texture(blurTex, uv + vec2(0.0, texel.y)).rgb);
	vec2 grad = vec2(hR - hL, hT - hB);

	vec2 uv2 = uv + grad * (distortion / 100.0) * 0.5;
	float h2 = lum(texture(blurTex, uv2).rgb);

	float cycles = mix(1.0, 7.0, detail / 100.0);
	float v = 0.5 + 0.5 * sin(h2 * cycles * 6.28318530718 + h2 * 3.0);
	v += pow(v, 8.0) * 0.5;
	v = clamp(v, 0.0, 1.0);

	vec3 outColor = clamp(vec3(v) * vec3(0.96, 0.98, 1.02), vec3(0.0), vec3(1.0));

	vec4 src = texture(inputTex, uv);
	frag = vec4(outColor, src.a);
}
