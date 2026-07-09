#version 450
// filter/median, program "medianPass" — ported verbatim from wgsl/medianPass.wgsl.
// Pass 2 of 3: 3x3 box median, executed `iterations` times per frame (pass repeat),
// ping-ponging the global_median_state surface (each iteration reads the previous
// iteration's result and writes the next one — see effects/filter/median.json and
// nm_backend.gd's _adopt_iteration_bindings). Standard 9-element min/max
// compare-exchange network (Devillard opt_med9) applied per RGB channel; element 4
// ends up holding the median. WGSL `ptr<function, vec3<f32>>` in/out params become
// GLSL `inout vec3`. Input at set 0, binding 1 (bound to global_median_state's read
// buffer by the pass.inputs mapping, not literally "inputTex" the surface — the
// sampler NAME is still inputTex per the WGSL/GLSL source).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void sort2(inout vec3 a, inout vec3 b) {
	vec3 lo = min(a, b);
	vec3 hi = max(a, b);
	a = lo;
	b = hi;
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 texel = 1.0 / texSize;
	vec2 uv = gl_FragCoord.xy / texSize;

	vec4 s0 = texture(inputTex, uv + vec2(-texel.x, -texel.y));
	vec4 s1 = texture(inputTex, uv + vec2(0.0, -texel.y));
	vec4 s2 = texture(inputTex, uv + vec2(texel.x, -texel.y));
	vec4 s3 = texture(inputTex, uv + vec2(-texel.x, 0.0));
	vec4 s4 = texture(inputTex, uv);
	vec4 s5 = texture(inputTex, uv + vec2(texel.x, 0.0));
	vec4 s6 = texture(inputTex, uv + vec2(-texel.x, texel.y));
	vec4 s7 = texture(inputTex, uv + vec2(0.0, texel.y));
	vec4 s8 = texture(inputTex, uv + vec2(texel.x, texel.y));

	vec3 p0 = s0.rgb; vec3 p1 = s1.rgb; vec3 p2 = s2.rgb;
	vec3 p3 = s3.rgb; vec3 p4 = s4.rgb; vec3 p5 = s5.rgb;
	vec3 p6 = s6.rgb; vec3 p7 = s7.rgb; vec3 p8 = s8.rgb;

	sort2(p1, p2); sort2(p4, p5); sort2(p7, p8);
	sort2(p0, p1); sort2(p3, p4); sort2(p6, p7);
	sort2(p1, p2); sort2(p4, p5); sort2(p7, p8);
	sort2(p0, p3); sort2(p5, p8); sort2(p4, p7);
	sort2(p3, p6); sort2(p1, p4); sort2(p2, p5);
	sort2(p4, p7); sort2(p4, p2); sort2(p6, p4);
	sort2(p4, p2);

	frag = vec4(p4, s4.a);
}
