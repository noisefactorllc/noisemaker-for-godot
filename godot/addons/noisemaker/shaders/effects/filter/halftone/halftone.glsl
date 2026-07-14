#version 450
// filter/halftone (program "halftone") — ported from wgsl/halftone.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's mat2(co,-si,si,co)*v
// form instead of WGSL's raw one — see PORTING-GUIDE.md's rotation-handedness
// note (filter/spinBlur, filter/pondRipples, filter/hatch): rotate2D here rotates
// the fragment's own global coordinate (position-derived geometry, the same
// category spinBlur/pondRipples/hatch fall in), which this port has empirically
// established needs the GLSL-textual form on Godot's RenderingDevice pipeline,
// contrary to the WGSL source's own doctrine comment (which argues raw is correct
// via WebGPU's present-flip — that argument does not transfer to Godot; see
// PORTING-GUIDE.md).
//
// Rotated-screen halftone reproduction, covering both Photoshop Color Halftone
// (mode 0: standard CMYK separation with full under-color removal, then four
// independent screens at cyanAngle/magentaAngle/yellowAngle/blackAngle, each
// screen's dot sampled at its OWN rotated-cell center so a cell's dot has one
// flat size, composited subtractively back to RGB) and Halftone Pattern (mode 1,
// mono: luminance screened through a user-selectable spot function — dot/line/
// circle — tonemapped between paperColor and inkColor). MODE and PATTERN are
// compile-time defines injected by the runtime (definition.js globals.mode.define
// / globals.pattern.define), baked so the compiler drops unselected mode/pattern
// arms instead of carrying a runtime int dispatch through every fragment.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define frequency data[..]`, `#define cyanAngle data[..]`, `#define
// magentaAngle data[..]`, `#define yellowAngle data[..]`, `#define blackAngle
// data[..]`, `#define monoAngle data[..]`, `#define sharpness data[..]`,
// `#define inkColor data[..].xyz`, `#define paperColor data[..].xyz`, plus engine
// globals `resolution`/`tileOffset`/`fullResolution`. Input at set 0, binding 1.
// No shared primitives used, so include/nm_core.glsl is omitted (its PI is lower
// precision than this effect's own full-precision HALFTONE_PI below — see
// PORTING-GUIDE.md rule 2).

#ifndef MODE
#define MODE 0
#endif

#ifndef PATTERN
#define PATTERN 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

// Standard CMYK separation with full under-color removal. The shared neutral
// component becomes K, leaving C/M/Y at zero for neutral RGB.
vec4 rgbToCmyk(vec3 rgb) {
	float k = 1.0 - max(max(rgb.r, rgb.g), rgb.b);
	float scale = max(1.0 - k, 0.00001);
	vec3 cmy = clamp((1.0 - rgb - vec3(k)) / scale, 0.0, 1.0);
	return vec4(cmy, k);
}

// Rotation handedness: GLSL golden's mat2(co,-si,si,co)*v form (expanded) — see
// file header. Because this matrix is orthonormal, calling it with -angleDeg
// gives the exact inverse rotation, which cellSampleFromRuv relies on below.
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
// frequency). Sampling the cell CENTER instead of the current fragment gives
// every dot in the cell one flat size.
vec3 cellSampleFromRuv(vec2 ruv, float angleDeg, vec2 texel) {
	vec2 cellId = floor(ruv) + 0.5;
	vec2 cellCenterGc = rotate2D(cellId * frequency, -angleDeg);
	vec2 cellUV = clamp((cellCenterGc - tileOffset) / resolution, vec2(0.0), vec2(1.0));
	return boxBlur3(cellUV, texel);
}

// Antialiased ink coverage (1 = full ink, 0 = bare paper) for a spot whose size
// is set by `value` (0..1, larger = more ink) at normalized distance `d` from
// the spot's feature. Used for line/circle patterns.
float halftoneCoverage(float d, float value, float sharpnessPct) {
	float spot = sqrt(clamp(value, 0.0, 1.0)) * 0.7071;
	float softness = 1.0 - clamp(sharpnessPct / 100.0, 0.0, 1.0);
	float aa = max(mix(fwidth(d) * 1.5, 0.35, softness), 0.00001);
	return 1.0 - smoothstep(spot - aa, spot + aa, d);
}

// Clustered dots remain center-origin circles over the full tone range. Up
// through 50% ink, the area-derived radius is unchanged. Darker tones continue
// growing that same circle toward a sub-cell cap, avoiding both hard grid seams
// and circles clipped into squares. Used for dot patterns (color CMYK screens
// and mono pattern 0).
const float DOT_AREA_CAP = 0.50;
const float HALFTONE_PI = 3.141592653589793;
const float MID_DOT_RADIUS = 0.39894228; // sqrt(0.5 / PI)
const float MAX_DOT_RADIUS = 0.48;

float roundDotCoverage(vec2 offset, float value, float sharpnessPct) {
	float inkAmount = clamp(value, 0.0, 1.0);
	float centerDistance = length(offset);
	float inkRadius = sqrt(min(inkAmount, DOT_AREA_CAP) / HALFTONE_PI);
	if (inkAmount > DOT_AREA_CAP) {
		inkRadius = mix(MID_DOT_RADIUS, MAX_DOT_RADIUS,
			(inkAmount - DOT_AREA_CAP) / (1.0 - DOT_AREA_CAP));
	}
	float softness = 1.0 - clamp(sharpnessPct / 100.0, 0.0, 1.0);
	float centerAA = max(mix(fwidth(centerDistance) * 1.5, 0.35, softness), 0.00001);
	float resolvedInk = smoothstep(0.0, 1.0 / 255.0, value);
	return (1.0 - smoothstep(-centerAA, centerAA,
		centerDistance - inkRadius)) * resolvedInk;
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = gl_FragCoord.xy / resolution;
	vec2 texel = 1.0 / resolution;
	float alpha = texture(inputTex, uv).a;

#if MODE == 0
	// Subtractive color halftone.
	vec2 ruvC = rotate2D(globalCoord, cyanAngle) / frequency;
	vec2 ruvM = rotate2D(globalCoord, magentaAngle) / frequency;
	vec2 ruvY = rotate2D(globalCoord, yellowAngle) / frequency;
	vec2 ruvK = rotate2D(globalCoord, blackAngle) / frequency;
	float valC = rgbToCmyk(cellSampleFromRuv(ruvC, cyanAngle, texel)).r;
	float valM = rgbToCmyk(cellSampleFromRuv(ruvM, magentaAngle, texel)).g;
	float valY = rgbToCmyk(cellSampleFromRuv(ruvY, yellowAngle, texel)).b;
	float valK = rgbToCmyk(cellSampleFromRuv(ruvK, blackAngle, texel)).a;
	float inkC = roundDotCoverage(fract(ruvC) - 0.5, valC, sharpness);
	float inkM = roundDotCoverage(fract(ruvM) - 0.5, valM, sharpness);
	float inkY = roundDotCoverage(fract(ruvY) - 0.5, valY, sharpness);
	float inkK = roundDotCoverage(fract(ruvK) - 0.5, valK, sharpness);
	vec3 screened = (vec3(1.0) - vec3(inkC, inkM, inkY)) * (1.0 - inkK);
	frag = vec4(screened, alpha);
#else
	// Monochrome screen pattern.
	float value;
	float d;
	vec2 dotOffset = vec2(0.0);
#if PATTERN == 2
	// circle: concentric rings from the fixed image center, unrotated.
	vec2 center = fullResolution * 0.5;
	value = 1.0 - lum(boxBlur3(uv, texel));
	float rd = length(globalCoord - center) / frequency;
	d = abs(fract(rd) - 0.5);
#else
	vec2 ruv = rotate2D(globalCoord, monoAngle) / frequency;
	value = 1.0 - lum(cellSampleFromRuv(ruv, monoAngle, texel));
	vec2 off = fract(ruv) - 0.5;
	dotOffset = off;
	// 1 = line, else dot
#if PATTERN == 1
	d = abs(off.y);
#else
	d = length(off);
#endif
#endif
#if PATTERN == 0
	float ink = roundDotCoverage(dotOffset, value, sharpness);
#else
	float ink = halftoneCoverage(d, value, sharpness);
#endif
	frag = vec4(tonemap2(1.0 - ink, inkColor, paperColor), alpha);
#endif
}
