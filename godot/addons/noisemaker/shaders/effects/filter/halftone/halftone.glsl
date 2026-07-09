#version 450
// filter/halftone (program "halftone") — ported from wgsl/halftone.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's mat2(co,-si,si,co)*v
// form instead of WGSL's raw one — see PORTING-GUIDE.md's rotation-handedness
// note (filter/spinBlur, filter/pondRipples): rotate2D here rotates the fragment's
// OWN global coordinate (position-derived geometry, the same category spinBlur/
// pondRipples fall in), which this port has empirically established needs the
// GLSL-textual form on Godot's RenderingDevice pipeline, contrary to the WGSL
// source's own doctrine comment (which argues raw is correct via WebGPU's
// present-flip — that argument does not transfer to Godot; see PORTING-GUIDE.md).
//
// Rotated-screen halftone reproduction, covering both Photoshop Color Halftone
// (mode 0: each RGB channel screened through its own rotated dot grid at angle +
// {108,162,90}, coverages multiplied for a CMY-style rosette) and Halftone
// Pattern (mode 1, mono: luminance screened through a user-selectable spot
// function — dot/line/circle — tonemapped between paperColor and inkColor).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define mode data[..]`, `#define pattern data[..]`, `#define frequency data[..]`,
// `#define angle data[..]`, `#define sharpness data[..]`,
// `#define inkColor data[..].xyz`, `#define paperColor data[..].xyz`. mode/pattern
// are ints with choices, cast int(...) at use sites. Input at set 0, binding 1.
// Single texture, texSize-space (no fullResolution remap — matches WGSL, no tiling
// concept).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

// Rotation handedness: GLSL golden's mat2(co,-si,si,co)*v form — see file header.
// Calling this with -angleDeg gives the exact inverse rotation, which
// cellSampleFromRuv relies on below.
vec2 rotate2D(vec2 v, float angleDeg) {
	float a = radians(angleDeg);
	float co = cos(a);
	float si = sin(a);
	return vec2(co * v.x + si * v.y, -si * v.x + co * v.y);
}

vec3 boxBlur3(vec2 uv, vec2 texel) {
	vec3 sum = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y)) * texel;
			sum += texture(inputTex, clamp(uv + o, vec2(0.0), vec2(1.0))).rgb;
		}
	}
	return sum / 9.0;
}

// Blurred RGB sampled at the center of the rotated screen cell whose
// already-rotated-and-scaled coordinate is `ruv` (= rotate2D(gc, angleDeg) /
// frequency).
vec3 cellSampleFromRuv(vec2 ruv, float angleDeg, vec2 texel) {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 cellId = floor(ruv) + 0.5;
	vec2 cellCenterGc = rotate2D(cellId * frequency, -angleDeg);
	vec2 cellUV = clamp(cellCenterGc / texSize, vec2(0.0), vec2(1.0));
	return boxBlur3(cellUV, texel);
}

float halftoneCoverage(float d, float value, float sharpnessPct) {
	float spot = sqrt(clamp(value, 0.0, 1.0)) * 0.7071;
	float softness = 1.0 - clamp(sharpnessPct / 100.0, 0.0, 1.0);
	float aa = mix(fwidth(d) * 1.5, 0.35, softness);
	return smoothstep(spot + aa, spot - aa, d);
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 globalCoord = gl_FragCoord.xy;
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texel = 1.0 / texSize;
	float alpha = texture(inputTex, uv).a;

	if (int(mode) == 0) {
		// Color Halftone.
		vec2 ruvR = rotate2D(globalCoord, angle + 108.0) / frequency;
		vec2 ruvG = rotate2D(globalCoord, angle + 162.0) / frequency;
		vec2 ruvB = rotate2D(globalCoord, angle + 90.0) / frequency;
		float valR = 1.0 - cellSampleFromRuv(ruvR, angle + 108.0, texel).r;
		float valG = 1.0 - cellSampleFromRuv(ruvG, angle + 162.0, texel).g;
		float valB = 1.0 - cellSampleFromRuv(ruvB, angle + 90.0, texel).b;
		float inkR = halftoneCoverage(length(fract(ruvR) - 0.5), valR, sharpness);
		float inkG = halftoneCoverage(length(fract(ruvG) - 0.5), valG, sharpness);
		float inkB = halftoneCoverage(length(fract(ruvB) - 0.5), valB, sharpness);
		frag = vec4(1.0 - inkR, 1.0 - inkG, 1.0 - inkB, alpha);
		return;
	}

	// Halftone Pattern (mono).
	float value = 0.0;
	float d = 0.0;
	if (int(pattern) == 2) {
		// circle: concentric rings from the fixed image center, unrotated.
		vec2 center = texSize * 0.5;
		value = 1.0 - lum(boxBlur3(uv, texel));
		float rd = length(globalCoord - center) / frequency;
		d = abs(fract(rd) - 0.5);
	} else {
		vec2 ruv = rotate2D(globalCoord, angle) / frequency;
		value = 1.0 - lum(cellSampleFromRuv(ruv, angle, texel));
		vec2 off = fract(ruv) - 0.5;
		d = (int(pattern) == 1) ? abs(off.y) : length(off); // 1 = line, else dot
	}
	float ink = halftoneCoverage(d, value, sharpness);
	frag = vec4(tonemap2(1.0 - ink, inkColor, paperColor), alpha);
}
