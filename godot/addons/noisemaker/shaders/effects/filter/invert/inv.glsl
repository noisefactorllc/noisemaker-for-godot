#version 450
// filter/invert (program "inv") — ported from wgsl/inv.wgsl (extended with mode —
// sync reference 70944878). mode 0 (full, default): simple RGB inversion,
// 1.0 - value. mode 1 (solarize): Photoshop Solarize parity, min(v, 1.0 - v) per
// channel (PS: output = v <= 128 ? v : 255 - v, equivalent to min(v, 1-v) in
// 0..1).
//
// No-layout effect now (the reference dropped invert's formerly-empty
// uniformLayout when it added the mode param — this file switches from the
// old declared-empty-UBO layout convention to the standard synthesized one,
// matching every other no-layout effect in this port): the backend synthesizes
// the Params UBO and injects `#define mode data[..]`. mode is an int with
// choices; arrives as a raw float, cast int(...) at the comparison site
// (established idiom). Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 color = texture(inputTex, uv);

	if (int(mode) == 1) {
		color = vec4(min(color.rgb, 1.0 - color.rgb), color.a);
	} else {
		color = vec4(1.0 - color.rgb, color.a);
	}

	frag = color;
}
