#version 450
// filter/emboss (program "emboss") — ported from wgsl/emboss.wgsl (extended with
// angle/height — sync reference 6d1acec4 + fcc54049; final post-a330fb83 state).
// 3x3 emboss convolution producing a raised relief appearance. angle/height
// rotate and scale the kernel's fixed 3x3 sampling geometry about its own
// built-in axis instead of replacing it outright: this kernel has no neutral
// (0.5) bias term (weights sum to 1, so flat regions pass through as the
// original color), so a literal Photoshop-style "0.5 + directional diff" formula
// can't reproduce this shader's pre-existing output. At angle=135, height=1 the
// rotation is identity and the scale is 1x, so every sample offset below equals
// the pre-existing hard-coded +/-texelSize grid exactly (byte-identical
// old-defaults output, for any amount) — reference angle 135 is the pre-existing
// kernel's own implicit direction, so theta=0 lands exactly there.
//
// Rotation handedness: uses (ct*basePx.x + st*basePx.y, -st*basePx.x +
// ct*basePx.y), the GLSL-textual form — NOT filter/pinch's raw
// (ct*x - st*y, st*x + ct*y) pattern, and NOT filter/spinBlur/pondRipples'
// now-established Godot convention derivation either (though it lands on the
// same formula). Per the WGSL source's own extensive doctrine comment: basePx
// is a FIXED, backend-agnostic kernel-shape CONSTANT (the same 9 numbers in
// both shader languages), added as a delta to the already-correct uv — it never
// touches the native per-pixel fragment coordinate, so there is nothing for a
// present-path/global Y-flip to cancel the way it does for an offset-from-center
// rotation (spinBlur/pondRipples); matching GLSL's formula textually is what
// keeps the sample offsets numerically identical. The reference empirically
// verified this on WebGPU vs WebGL2 (reverting to the raw/pinch form produced a
// horizontal-mirror mismatch at angle=45). This independently converges with
// this port's own spinBlur/pondRipples finding (PORTING-GUIDE) that Godot needs
// the GLSL-textual rotation form, not raw WGSL — so no separate verification
// question here, the WGSL source already ships the corrected formula.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define amount data[..]`, `#define angle data[..]`, `#define height data[..]`.
// Input at set 0, binding 1. renderScale is included in the offset scale
// (matches the GLSL golden; WGSL omits it — reference/07 hazard H1 — bare name,
// always 1.0 in this runtime today).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texelSize = 1.0 / texSize;

	vec4 origColor = texture(inputTex, uv);

	// Emboss kernel
	// -2 -1  0
	// -1  1  1
	//  0  1  2
	float kernel[9] = float[9](-2.0, -1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 2.0);

	// Base kernel tap positions, 1px units. angle/height rotate+scale this fixed
	// geometry about its own built-in axis (see header above).
	vec2 baseOffsetsPx[9] = vec2[9](
		vec2(-1.0, -1.0),
		vec2( 0.0, -1.0),
		vec2( 1.0, -1.0),
		vec2(-1.0,  0.0),
		vec2( 0.0,  0.0),
		vec2( 1.0,  0.0),
		vec2(-1.0,  1.0),
		vec2( 0.0,  1.0),
		vec2( 1.0,  1.0)
	);

	// Reference angle 135 is the pre-existing kernel's own implicit direction,
	// so theta=0 (identity rotation) lands exactly there.
	float theta = radians(angle - 135.0);
	float ct = cos(theta);
	float st = sin(theta);

	vec3 conv = vec3(0.0);

	for (int i = 0; i < 9; i++) {
		vec2 basePx = baseOffsetsPx[i];
		vec2 rotatedPx = vec2(ct * basePx.x + st * basePx.y, -st * basePx.x + ct * basePx.y) * height;
		vec2 offsetUV = rotatedPx * texelSize * amount * renderScale;
		vec3 sampleColor = texture(inputTex, uv + offsetUV).rgb;
		conv += sampleColor * kernel[i];
	}

	frag = vec4(clamp(conv, vec3(0.0), vec3(1.0)), origColor.a);
}
