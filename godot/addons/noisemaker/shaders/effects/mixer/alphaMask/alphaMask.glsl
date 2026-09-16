#version 450
// mixer/alphaMask — ported from wgsl/alphaMask.wgsl. Alpha transparency blend of
// two surfaces. No-layout effect: backend injects Params UBO + `#define mixAmt …`/
// `maskMode …`. Three inputs (pass.inputs order): inputTex = base (binding 1),
// tex = layer (binding 2), baseTex = mask-mode background (binding 3, reference
// 0ed489ec). map_range is this effect's own per-effect copy.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D tex;
layout(set = 0, binding = 3) uniform sampler2D baseTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float map_range(float value, float inMin, float inMax, float outMin, float outMax) {
	return outMin + (outMax - outMin) * (value - inMin) / (inMax - inMin);
}

void main() {
	vec2 dims = vec2(textureSize(inputTex, 0));
	vec2 st = gl_FragCoord.xy / dims;

	vec4 color1 = texture(inputTex, st);
	vec4 color2 = texture(tex, st);

	// Inputs use premultiplied RGBA: masking must scale color and coverage (reference 0ed489ec).
	if (int(maskMode) != 0) {
		float maskVal = dot(color2.rgb, vec3(0.299, 0.587, 0.114));
		vec4 background = texture(baseTex, st);
		frag = mix(background, color1, maskVal);
		return;
	}

	// Premultiplied source-over. Slider direction selects which input is on top, so either slot
	// can serve as the alpha source — slide negative for A-on-top, positive for
	// B-on-top. each half reaches a full Porter-Duff source-over at the midpoint.
	vec4 color;
	if (mixAmt < 0.0) {
		vec4 AoverB = color2 * (1.0 - color1.a) + color1;
		color = mix(color1, AoverB, map_range(mixAmt, -100.0, 0.0, 0.0, 1.0));
	} else {
		vec4 BoverA = color1 * (1.0 - color2.a) + color2;
		color = mix(BoverA, color2, map_range(mixAmt, 0.0, 100.0, 0.0, 1.0));
	}

	frag = color;
}
