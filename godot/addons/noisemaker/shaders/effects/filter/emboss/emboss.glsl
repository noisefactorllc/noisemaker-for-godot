#version 450
// filter/emboss (program "emboss") — ported from wgsl/emboss.wgsl (extended with
// angle/height — sync reference 6d1acec4 + fcc54049; further extended with
// style/colorAmount for the opt-in gray relief style). Two explicit visual
// contracts selected by STYLE:
//   0 color - the shipped color convolution, preserved exactly (pinned default)
//   1 gray  - neutral-gray directional relief with edge-local chroma
//
// COLOR (STYLE==0): angle/height rotate and scale the kernel's fixed 3x3
// sampling geometry about its own built-in axis instead of replacing it
// outright: this kernel has no neutral (0.5) bias term (weights sum to 1, so
// flat regions pass through as the original color), so a literal
// Photoshop-style "0.5 + directional diff" formula can't reproduce this
// shader's pre-existing output. At angle=135, height=1 the general rotation is
// mathematically identity/1x, but the reference does NOT rely on trig folding
// to reach the pinned default bit-exactly — it keeps a SEPARATE, literal-offset
// exact path (colorDefaultEmboss) guarded by `angle==135.0 && height==1.0`, so
// this port mirrors that guard rather than trusting cos(radians(0))==1.0
// exactly. Do not simplify the two paths into one.
//
// Rotation handedness (colorGeneralEmboss only): uses (ct*basePx.x +
// st*basePx.y, -st*basePx.x + ct*basePx.y), the GLSL-textual form — NOT
// filter/pinch's raw (ct*x - st*y, st*x + ct*y) pattern, and NOT filter/
// spinBlur/pondRipples' now-established Godot convention derivation either
// (though it lands on the same formula). Per the WGSL source's own extensive
// doctrine comment: basePx is a FIXED, backend-agnostic kernel-shape CONSTANT
// (the same 9 numbers in both shader languages), added as a delta to the
// already-correct uv — it never touches the native per-pixel fragment
// coordinate, so there is nothing for a present-path/global Y-flip to cancel
// the way it does for an offset-from-center rotation (spinBlur/pondRipples);
// matching GLSL's formula textually is what keeps the sample offsets
// numerically identical. The reference empirically verified this on WebGPU vs
// WebGL2 (reverting to the raw/pinch form produced a horizontal-mirror
// mismatch at angle=45). This independently converges with this port's own
// spinBlur/pondRipples finding (PORTING-GUIDE) that Godot needs the
// GLSL-textual rotation form, not raw WGSL.
//
// GRAY (STYLE==1): samples luminance at +-direction*(height*renderScale) in
// GLOBAL (tile-aware) UV space via sampleGlobal(), forms a signed edge
// (positiveLuma - negativeLuma), maps it to a 0.5-centered relief, and tints
// edges with the source's own chroma scaled by edgeMagnitude*colorAmount.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define style data[..]` (STYLE compile-time define), `#define amount
// data[..]`, `#define angle data[..]`, `#define height data[..]`, `#define
// colorAmount data[..]`, plus engine globals `tileOffset`/`fullResolution`/
// `renderScale`. Input at set 0, binding 1. renderScale is included in the
// offset scale (matches the GLSL golden; WGSL omits it — reference/07 hazard
// H1 — bare name, always 1.0 in this runtime today).
#ifndef STYLE
#define STYLE 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const vec3 EMBOSS_LUMA = vec3(0.2126, 0.7152, 0.0722);

// Sample the input at a GLOBAL (tile-aware) UV, mapping back to the local
// texture's UV space. Matches the reference's sampleGlobal exactly.
vec3 sampleGlobal(vec2 globalUV) {
	vec2 localUV = (globalUV * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
	return texture(inputTex, localUV).rgb;
}

vec3 colorDefaultEmboss(vec2 uv, vec2 texelSize) {
	float kernel[9] = float[9](-2.0, -1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 2.0);

	// COLOR_DEFAULT_EXACT_BEGIN
	// Copied from the pre-angle/height shader: literal offsets and arithmetic
	// order intentionally stay intact so defaults never depend on trig folding.
	vec2 offsets[9] = vec2[9](
		vec2(-texelSize.x, -texelSize.y),
		vec2(0.0, -texelSize.y),
		vec2(texelSize.x, -texelSize.y),
		vec2(-texelSize.x, 0.0),
		vec2(0.0, 0.0),
		vec2(texelSize.x, 0.0),
		vec2(-texelSize.x, texelSize.y),
		vec2(0.0, texelSize.y),
		vec2(texelSize.x, texelSize.y)
	);

	vec3 conv = vec3(0.0);
	for (int i = 0; i < 9; i++) {
		vec3 texSample = texture(inputTex, ((uv + offsets[i] * amount * renderScale) * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0))).rgb;
		conv += texSample * kernel[i];
	}
	// COLOR_DEFAULT_EXACT_END
	return conv;
}

vec3 colorGeneralEmboss(vec2 uv, vec2 texelSize) {
	float kernel[9] = float[9](-2.0, -1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 2.0);

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
		vec3 texSample = texture(inputTex, ((uv + offsetUV) * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0))).rgb;
		conv += texSample * kernel[i];
	}
	return conv;
}

vec3 grayEmboss(vec2 uv, vec3 centerRGB) {
	float theta = radians(angle);
	// This direction is a backend-independent sample delta, so GLSL and WGSL
	// use the same constant-vector expansion.
	vec2 direction = vec2(cos(theta), sin(theta));
	vec2 offsetUV = direction * (height * renderScale) / fullResolution;
	float positiveLuma = dot(sampleGlobal(uv + offsetUV), EMBOSS_LUMA);
	float negativeLuma = dot(sampleGlobal(uv - offsetUV), EMBOSS_LUMA);
	float signedEdge = positiveLuma - negativeLuma;
	float edgeMagnitude = abs(signedEdge);
	float relief = 0.5 + 0.5 * signedEdge;

	float centerLuma = dot(centerRGB, EMBOSS_LUMA);
	vec3 sourceChroma = centerRGB - vec3(centerLuma);
	vec3 tracedColor = sourceChroma * edgeMagnitude * clamp(colorAmount / 100.0, 0.0, 1.0);
	return vec3(relief) + tracedColor;
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = globalCoord / fullResolution;
	vec2 texelSize = 1.0 / texSize;
	vec4 origColor = texture(inputTex, gl_FragCoord.xy / texSize);
	bool fullFrame = all(equal(tileOffset, vec2(0.0))) && all(equal(fullResolution, texSize));
	// Preserve the shipped full-frame sample delta exactly. A tiled input's
	// local texture is smaller than the print canvas, so only that path uses
	// the full-resolution pixel delta before mapping back to local UVs.
	vec2 colorTexelSize = fullFrame ? texelSize : 1.0 / fullResolution;

	vec3 result;
#if STYLE == 0
	if (angle == 135.0 && height == 1.0) {
		result = colorDefaultEmboss(uv, colorTexelSize);
	} else {
		result = colorGeneralEmboss(uv, colorTexelSize);
	}
#else
	result = grayEmboss(uv, origColor.rgb);
#endif

	frag = vec4(clamp(result, 0.0, 1.0), origColor.a);
}
