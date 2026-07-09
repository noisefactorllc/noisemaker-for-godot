#version 450
// filter/plasticWrap, program "pwSpec" — ported verbatim from wgsl/pwSpec.wgsl
// (which itself textually mirrors the GLSL golden, no manual Y compensation:
// the gradient taps and the key light vector L are fixed, backend-agnostic
// constants, not derived from the fragment's own position relative to a
// center parameter, so PORTING-GUIDE's rotation-handedness exception does not
// apply here — same category as filter/emboss's fixed kernel taps, not
// filter/spinBlur/pondRipples/halftone/stipple's position-derived rotations).
// Pass 3 of 3: glossy specular plastic film hugging image contours. Derives a
// normal from the blurred luminance gradient, Blinn-Phong-style specular
// against a fixed light direction L, boosted along ridges (local curvature),
// screened onto the source.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define highlight data[..]`, `#define smoothness data[..]`. Inputs at set
// 0, binding 1.. in pass.inputs order (inputTex, blurTex).
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
	vec4 src = texture(inputTex, uv);

	float hC = lum(texture(blurTex, uv).rgb);
	float hL = lum(texture(blurTex, uv - vec2(texel.x, 0.0)).rgb);
	float hR = lum(texture(blurTex, uv + vec2(texel.x, 0.0)).rgb);
	float hB = lum(texture(blurTex, uv - vec2(0.0, texel.y)).rgb);
	float hT = lum(texture(blurTex, uv + vec2(0.0, texel.y)).rgb);

	vec2 grad = vec2(hR - hL, hT - hB);

	float strength = 8.0;
	vec3 n = normalize(vec3(-grad * strength, 1.0));
	vec3 L = normalize(vec3(0.4, -0.6, 0.7));

	float gloss = mix(24.0, 6.0, smoothness / 100.0);
	float spec = pow(clamp(dot(n, L), 0.0, 1.0), gloss);

	float curv = hC * 2.0 - hL - hR;
	float ridge = clamp(curv * strength, 0.0, 1.0);
	spec = spec * (1.0 + ridge * 2.0);

	vec3 specColor = clamp(vec3(spec) * (highlight / 100.0), vec3(0.0), vec3(1.0));
	vec3 outc = vec3(1.0) - (vec3(1.0) - src.rgb) * (vec3(1.0) - specColor);

	frag = vec4(outc, src.a);
}
