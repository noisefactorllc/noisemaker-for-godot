#version 450
// filter/highPass, program "hpCombine" — ported from wgsl/hpCombine.wgsl.
// hp = src - blur + 0.5 gray, optional luminance-only (mono). No-layout effect: the
// backend synthesizes the Params UBO and injects `#define mono data[..]` — a boolean
// param arrives as a raw float in the packed buffer, tested as int(mono) > 0 (matches
// filter/grain's established idiom for boolean params in this port; equivalent to the
// reference's `mono` / `uniforms.mono != 0`). Inputs at set 0, binding 1.. in
// pass.inputs order (inputTex, blurTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec4 blur = texture(blurTex, uv);
	vec3 diff = src.rgb - blur.rgb;
	vec3 hp = (int(mono) > 0) ? vec3(lum(diff) + 0.5) : (diff + 0.5);
	frag = vec4(clamp(hp, 0.0, 1.0), src.a);
}
