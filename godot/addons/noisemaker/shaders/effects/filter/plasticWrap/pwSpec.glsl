#version 450
// filter/plasticWrap, program "pwSpec" — ported verbatim from wgsl/pwSpec.wgsl
// (which itself textually mirrors the GLSL golden, no manual Y compensation:
// the gradient taps and the key light vector are fixed, backend-agnostic
// constants, not derived from the fragment's own position relative to a
// center parameter, so PORTING-GUIDE's rotation-handedness exception does not
// apply here — same category as filter/emboss's fixed kernel taps, not
// filter/spinBlur/pondRipples/halftone/stipple's position-derived rotations).
// Pass 3 of 3: glossy specular plastic film hugging image contours. Derives a
// normal from the blurred luminance gradient, Blinn-Phong half-vector
// specular (with the flat-plane response subtracted out so unmodulated
// regions stay clean) against a user-configurable key light, boosted along
// ridges via an isotropic 5-point Laplacian, screened onto the source.
//
// The `lightDirection` control shares its convention with filter/lighting's
// user-facing heading; this height-field gradient uses the opposite XY
// direction, so its azimuth is rotated 180 degrees below (controlledLight)
// while Z stays toward the viewer — this keeps the established default
// Plastic Wrap pixels stable at the default lightDirection.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define highlight data[..]`, `#define smoothness data[..]`, `#define
// lightDirection data[..].xyz`. Inputs at set 0, binding 1.. in pass.inputs
// order (inputTex, blurTex).
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

	// Gradient-to-slope scale: 10.0 turns a full 0..1 luminance swing over a
	// ~2px span into a strongly tilted facet (grad ~0.5 * 10 = 5, well past the
	// point where the normal is mostly sideways) while leaving gentle/smoothed
	// contours near-flat.
	float strength = 10.0;
	vec3 n = normalize(vec3(-grad * strength, 1.0));
	float lightLengthSq = dot(lightDirection, lightDirection);
	vec3 operatorLight = lightLengthSq > 0.000001
		? lightDirection
		: vec3(-0.4, 0.6, 0.7);
	vec3 controlledLight = vec3(-operatorLight.xy, operatorLight.z);
	vec3 L = normalize(controlledLight);
	vec3 V = vec3(0.0, 0.0, 1.0);
	vec3 halfVector = L + V;
	float halfLengthSq = dot(halfVector, halfVector);
	vec3 defaultL = normalize(vec3(0.4, -0.6, 0.7));
	vec3 defaultHalf = normalize(defaultL + V);
	vec3 H = halfLengthSq > 0.000001
		? normalize(halfVector)
		: defaultHalf;

	float gloss = mix(24.0, 6.0, smoothness / 100.0);
	float flatSpec = pow(H.z, gloss);
	float rawSpec = pow(clamp(dot(n, H), 0.0, 1.0), gloss);
	// Remove the flat-plane response and normalize the remaining directional
	// highlight so unmodulated image regions do not receive a milky wash.
	float spec = clamp((rawSpec - flatSpec) / max(1.0 - flatSpec, 0.0001), 0.0, 1.0);

	// The negative five-point Laplacian is positive at a two-dimensional
	// height-field crest — responds equally to horizontal, vertical, and
	// curved contours (not just an x-only second derivative).
	float curv = 4.0 * hC - hL - hR - hB - hT;
	float ridge = clamp(curv * strength * 2.0, 0.0, 1.0);
	spec = clamp(spec * 1.35 + ridge * 0.75, 0.0, 1.0);

	vec3 specColor = clamp(vec3(spec) * (highlight / 100.0), vec3(0.0), vec3(1.0));
	// Screen blend: 1 - (1-a)(1-b). highlight=0 -> specColor=0 -> out=src exactly.
	vec3 outc = vec3(1.0) - (vec3(1.0) - src.rgb) * (vec3(1.0) - specColor);

	frag = vec4(outc, src.a);
}
