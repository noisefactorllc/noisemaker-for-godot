#version 450
// filter/pondRipples (program "pondRipples") — ported from wgsl/pondRipples.wgsl,
// its RAW rotation expansion (see doctrine note below; final post-a330fb83-revert
// state — same pattern as filter/spinBlur, already validated in this port).
// Concentric ring distortion around the fixed image center (0.5,0.5) — no
// user-facing center param, unlike spinBlur (Photoshop ZigZag: Around Center /
// Out From Center / Pond Ripples styles). r = aspect-corrected distance from
// center; phase = r*ridges*2*PI; w = sin(phase)*(amount/100)*0.05*max(0,1-r) is
// the per-ring wave displacement (damped toward the edge, clamped >=0 so corners
// beyond r=1 don't invert-and-amplify). style 0 (aroundCenter) rotates the
// angular position by w*2*PI*0.25 at constant radius; style 1 (outFromCenter)
// adds w to the radius at constant angle; style 2 (pondRipples) splits w evenly
// across both.
//
// Rotation handedness: raw-convention expansion (co*p.x - s*p.y, s*p.x + co*p.y)
// — do NOT hand-compensate. The GLSL golden's `mat2(co,-s,s,co)*dir` is
// algebraically the same rotation at -angle (mat2 is column-major: columns
// (co,-s),(s,co) => matrix [[co,s],[-s,co]]); per PORTING-GUIDE golden rule 1 and
// this port's single-global-present-flip doctrine (already validated on
// filter/spinBlur, which has the identical raw-vs-mat2 relationship), the raw
// WGSL form ported here is the screen-correct match for the webgl2 golden.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define amount data[..]`, `#define ridges data[..]`, `#define style data[..]`,
// `#define wrap data[..]`, `#define antialias data[..]`. ridges/style/wrap are
// ints, antialias a boolean — all arrive as raw floats; cast int(...) at use
// sites (established idiom). `aspectRatio` is a reserved engine name (PORTING-
// GUIDE hazard) — renamed to `ar` throughout (WGSL local var AND this file has no
// helper taking it as a param). Input at set 0, binding 1. Single texture, no
// fullResolution remap needed (matches WGSL, which has no tiling concept).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

#define PI 3.14159265359

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	float ar = texSize.x / texSize.y;
	vec2 uv = gl_FragCoord.xy / texSize;

	uv -= 0.5;
	uv.x *= ar;

	float r = length(uv);
	float phase = r * float(int(ridges)) * 2.0 * PI;
	// Clamp the damping term at 0 so corners beyond r=1 (aspect ratios
	// wider/taller than ~1.73:1) don't invert phase and amplify instead of
	// damping.
	float w = sin(phase) * (amount / 100.0) * 0.05 * max(0.0, 1.0 - r);

	float rotDelta = 0.0;
	float rDelta = 0.0;
	if (int(style) == 0) {
		// aroundCenter
		rotDelta = w;
	} else if (int(style) == 1) {
		// outFromCenter
		rDelta = w;
	} else {
		// pondRipples: both at half strength
		rotDelta = w * 0.5;
		rDelta = w * 0.5;
	}

	vec2 dir = vec2(0.0);
	if (r > 0.0) {
		dir = uv / r;
	}

	float rot = rotDelta * 2.0 * PI * 0.25;
	float s = sin(rot);
	float co = cos(rot);
	// EMPIRICAL FINDING (contradicts the WGSL-raw doctrine that held for
	// filter/spinBlur): this single, non-averaged per-pixel rotation is
	// sharply sensitive to handedness, and only the GLSL golden's
	// mat2(co,-s,s,co)*dir expansion (co*dir.x+s*dir.y, -s*dir.x+co*dir.y)
	// matches on Godot -- verified via style:outFromCenter (pure radial, no
	// rotation) passing at max-abs-diff=1 while style:aroundCenter (pure
	// rotation) failed at ssim 0.80 under the raw WGSL expansion, then
	// passed after switching to this form. spinBlur's rotation is invisible
	// to this kind of test (it AVERAGES 32 samples across a theta-symmetric
	// arc, which is provably invariant to a global handedness sign flip
	// modulo the small per-pixel jitter term), so that earlier "pass" was
	// NOT strong confirmation of the raw convention -- see the spinBlur
	// shader for the follow-up re-check this finding prompted.
	vec2 rotatedDir = vec2(co * dir.x + s * dir.y, -s * dir.x + co * dir.y);

	uv = rotatedDir * (r + rDelta);

	uv.x /= ar;
	uv += 0.5;

	// Apply wrap mode (floored-mod; GLSL mod() is already floored)
	if (int(wrap) == 0) {
		// mirror
		uv = abs(mod(uv + 1.0, 2.0) - 1.0);
	} else if (int(wrap) == 1) {
		// repeat
		uv = mod(uv, 1.0);
	} else {
		// clamp
		uv = clamp(uv, 0.0, 1.0);
	}

	if (int(antialias) != 0) {
		vec2 dx = dFdx(uv);
		vec2 dy = dFdy(uv);
		vec4 col = vec4(0.0);
		col += texture(inputTex, uv + dx * -0.375 + dy * -0.125);
		col += texture(inputTex, uv + dx *  0.125 + dy * -0.375);
		col += texture(inputTex, uv + dx *  0.375 + dy *  0.125);
		col += texture(inputTex, uv + dx * -0.125 + dy *  0.375);
		frag = col * 0.25;
	} else {
		frag = texture(inputTex, uv);
	}
}
