#version 450
// filter/spinBlur (program "spinBlur") — ported from wgsl/spinBlur.wgsl (its RAW,
// uncompensated rotation expansion — see the extensive doctrine comment there and
// reference commit a330fb83, "Revert WGSL Y and handedness compensation to raw
// conventions"). Rotational blur (Photoshop Radial Blur, Spin mode): averages a
// fixed 32-tap comb, each tap resampling after rotating uv's offset-from-center by
// theta_i = (i/(N-1)-0.5)*radians(amount) + jitter around (centerX, centerY),
// aspect-corrected like filter/pinch's rotate2D. A per-pixel hash shifts the whole
// tap comb by up to half an angular step to hide banding.
//
// Y/handedness note: Godot/Vulkan RenderingDevice is top-left origin, matching
// WGSL exactly (PORTING-GUIDE golden rule 1) — a single global present-time flip
// reconciles to the webgl2/GLSL golden, structurally identical to how the WGSL
// comment describes WebGPU's own present-path flip. The reference's GLSL golden
// uses an aspect/rotation expansion (`mat2(co,-s,s,co)*p`) that is the
// theta-negated form of WGSL's raw expansion (`vec2(co*p.x-s*p.y, s*p.x+co*p.y)`)
// — algebraically, mat2(co,-s,s,co)*p == raw-expansion at angle -theta. Per the
// reverted-compensation doctrine, the WGSL raw form (used here, unflipped, matching
// this port's established no-per-effect-flip convention) is the screen-correct one
// once the single global flip is applied; centerX/centerY are also used raw
// (no 1-centerY flip), for the same reason.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define amount data[..]`, `#define centerX data[..]`, `#define centerY data[..]`.
// Input at set 0, binding 1. Single texture (inputTex), so — unlike
// filter/lighting/parallax's cross-texture heightMap case — no fullResolution
// remap is needed; sample directly by texSize-space UV (matches WGSL, which has
// no tiling concept at all).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const int N = 32;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Raw-convention expansion — do NOT hand-compensate for GLSL/WGSL's opposite raw
// fragment-coordinate handedness (see file header doctrine note).
vec2 rotateAround(vec2 uv, vec2 center, float angle, float ar) {
	vec2 p = uv;
	p.x *= ar;
	vec2 c = center;
	c.x *= ar;
	p -= c;
	float s = sin(angle);
	float co = cos(angle);
	p = vec2(co * p.x - s * p.y, s * p.x + co * p.y);
	p += c;
	p.x /= ar;
	return p;
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	float ar = texSize.x / texSize.y;
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 center = vec2(centerX, centerY);

	float arc = radians(amount);
	float angularStep = arc / float(N - 1);
	// Seed with globalCoord (tile-space + tileOffset), not gl_FragCoord.xy alone, so
	// the jitter field is continuous across CLI render tiles instead of restarting at
	// each tile's local origin (reference commit 82356652; tileOffset is always (0,0)
	// in this runtime today — see PORTING-GUIDE — so this is a no-op now, kept for
	// forward compatibility with tiled rendering).
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	float jitter = (hash12(globalCoord) - 0.5) * angularStep;

	vec4 sum = vec4(0.0);
	for (int i = 0; i < N; i++) {
		float theta = (float(i) / float(N - 1) - 0.5) * arc + jitter;
		vec2 distorted = clamp(rotateAround(uv, center, theta, ar), vec2(0.0), vec2(1.0));
		sum += texture(inputTex, distorted);
	}
	frag = sum / float(N);
}
