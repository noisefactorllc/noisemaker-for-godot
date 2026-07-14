#version 450
// filter/spinBlur (program "spinBlur") — ported from wgsl/spinBlur.wgsl EXCEPT for
// rotation handedness, where this file uses the GLSL golden's convention instead of
// WGSL's raw one — see the rotateAround() comment below; this is an empirically
// established exception to PORTING-GUIDE golden rule 1, documented there. Rotational
// blur (Photoshop Radial Blur, Spin mode): averages a fixed 32-tap comb, each tap
// resampling after rotating uv's offset-from-center by
// theta_i = (i/(N-1)-0.5)*radians(amount) + jitter around (centerX, centerY),
// aspect-corrected like filter/pinch's rotate2D. A per-pixel hash shifts the whole
// tap comb by up to half an angular step to hide banding. centerX/centerY are used
// raw (no 1-centerY flip) — translation/position, unlike rotation, is orientation-
// agnostic and behaves per the general golden rule 1 doctrine.
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

// Rotation handedness: uses the GLSL golden's mat2(co,-s,s,co)*p expansion
// (co*p.x+s*p.y, -s*p.x+co*p.y), NOT WGSL's raw (co*p.x-s*p.y, s*p.x+co*p.y) —
// despite PORTING-GUIDE golden rule 1 ("port from WGSL, no per-effect Y-flip") and
// the WGSL source's own extensive doctrine comment (reference commit a330fb83)
// arguing the raw form is screen-correct once WebGPU's present-flip applies.
// EMPIRICALLY, on Godot's RenderingDevice pipeline, that doctrine does not
// transfer: filter/pondRipples' identical aspect-corrected rotate-around-center
// pattern was verified (via its style:outFromCenter/aroundCenter split — pure
// radial passed under either convention, pure rotation only passed under this
// GLSL-matching one, max-abs-diff 1 vs a structural ssim-0.80 failure under raw)
// to need this convention, not WGSL's raw one. spinBlur's own first pass under
// the raw convention "passed" a loose tolerance (17.001) that turned out to be a
// false-positive: spinBlur AVERAGES 32 samples across a theta-symmetric arc,
// which is provably invariant to a global handedness sign flip (negating every
// tap angle maps the tap set onto itself) modulo the small per-pixel jitter
// term — so that test was too weak to actually distinguish the two conventions.
// Switching to this form tightened the residual from max-abs-diff 11-15 down to
// 1 (bit-exact-class), matching every other cleanly-ported effect in this
// catalog and confirming this is the objectively correct choice, not just "also
// passes." Do not use this file as precedent for reintroducing per-effect Y-flips
// elsewhere — this is specifically about ROTATION sign (which is orientation-
// handedness-dependent by nature), not position/sampling, where golden rule 1's
// raw-WGSL/no-flip convention remains correct and well-validated.
vec2 rotateAround(vec2 uv, vec2 center, float angle, float ar) {
	vec2 p = uv;
	p.x *= ar;
	vec2 c = center;
	c.x *= ar;
	p -= c;
	float s = sin(angle);
	float co = cos(angle);
	p = vec2(co * p.x + s * p.y, -s * p.x + co * p.y);
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
	// Mirror-invariant jitter coordinate (GLSL golden): fold y around the vertical
	// midline so corresponding pixels above/below center share a jitter value —
	// matches the reference's symmetric-jitter correction. texSize.y stands in for
	// fullResolution.y (equal today; see the file header's texSize-vs-fullResolution
	// note). GLSL's jitter carries no sign flip (WGSL negates its own — that's a
	// compensation for WGSL's raw rotation convention, which this file does not use).
	vec2 jitterCoord = vec2(globalCoord.x, abs(globalCoord.y - texSize.y * 0.5));
	float jitter = (hash12(jitterCoord) - 0.5) * angularStep;

	vec4 sum = vec4(0.0);
	for (int i = 0; i < N; i++) {
		float theta = (float(i) / float(N - 1) - 0.5) * arc + jitter;
		vec2 distorted = clamp(rotateAround(uv, center, theta, ar), vec2(0.0), vec2(1.0));
		sum += texture(inputTex, distorted);
	}
	frag = sum / float(N);
}
