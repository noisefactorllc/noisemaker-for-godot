#version 450
// filter/pondRipples (program "pondRipples") — ported from wgsl/pondRipples.wgsl
// EXCEPT for rotation handedness, where this file uses the GLSL golden's
// convention instead (see doctrine note below).
// Concentric ring distortion around the fixed image center (0.5,0.5) — no
// user-facing center param, unlike spinBlur (Photoshop ZigZag: Around Center /
// Out From Center / Pond Ripples styles). r = aspect-corrected distance from
// center; phase = r*ridges*2*PI - time*2*PI*speed; w =
// sin(phase)*(amount/100)*0.05*max(0,1-r) is the per-ring wave displacement
// (damped toward the edge, clamped >=0 so corners beyond r=1 don't
// invert-and-amplify). style 0 (aroundCenter) rotates the angular position by
// w*2*PI*0.25 at constant radius; style 1 (outFromCenter) adds w to the radius
// at constant angle; style 2 (pondRipples) splits w evenly across both.
//
// speed is an INTEGER number of wave cycles per normalized time loop, so the
// animation is loop-seamless at any value (positive travels outward, negative
// inward). At speed=0 the phase term vanishes and the effect is static — which
// is why adding it leaves every existing default-param golden byte-identical.
//
// Rotation handedness: this file uses the GLSL golden's `mat2(co,-s,s,co)*dir`
// expansion (co*dir.x+s*dir.y, -s*dir.x+co*dir.y), NOT WGSL's raw form — see the
// EMPIRICAL FINDING comment at the rotation site below for the isolation test
// (style:outFromCenter vs style:aroundCenter) that established this.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define amount data[..]`, `#define ridges data[..]`, `#define speed data[..]`,
// `#define antialias data[..]` (real per-pass uniforms), plus the fixed engine
// header — `time` is one of those engine-provided globals (data[0].z), so it
// needs no JSON entry of its own. STYLE and WRAP are compile-time defines (globals.style/
// wrap.define in the JSON, matching the reference exactly) baked into the compiled
// program variant (see the graph pass's program name, e.g.
// "pondRipples__STYLE_0__WRAP_0") — bare uppercase identifiers, NOT uniform reads.
// This matters: a reference-produced graph never emits a runtime "style"/"wrap"
// uniform value at all (they're define-only upstream), so declaring them as
// `uniform:` here would silently fall back to this JSON's default (2/0) for every
// non-default style/wrap requested — exactly the bug this comment now documents
// against regressing. ridges is a real uniform int; antialias a real uniform bool —
// both arrive as raw floats, cast int(...) at use sites (established idiom).
// `aspectRatio` is a reserved engine name (PORTING-GUIDE hazard) — renamed to `ar`
// throughout (WGSL local var AND this file has no helper taking it as a param).
// Input at set 0, binding 1. Single texture, no fullResolution remap needed
// (matches WGSL, which has no tiling concept).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

#ifndef STYLE
#define STYLE 2
#endif
#ifndef WRAP
#define WRAP 0
#endif

#define PI 3.14159265359

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	float ar = texSize.x / texSize.y;
	vec2 uv = gl_FragCoord.xy / texSize;

	uv -= 0.5;
	uv.x *= ar;

	float r = length(uv);
	float phase = r * float(int(ridges)) * 2.0 * PI - time * 2.0 * PI * float(int(speed));
	// Clamp the damping term at 0 so corners beyond r=1 (aspect ratios
	// wider/taller than ~1.73:1) don't invert phase and amplify instead of
	// damping.
	float damping = max(0.0, 1.0 - r);
	float w;
	if (amount <= 30.0) {
		// Preserve the original 0..30 response, including the exact shipped
		// default expression at amount=30.
		w = sin(phase) * (amount / 100.0) * 0.05 * damping;
	} else {
		// Continue smoothly from the original default slope, then accelerate
		// toward a 2.0 gain at amount=100 (twice the previous maximum).
		float x = (amount - 30.0) / 70.0;
		float amountGain = 0.3 + 0.7 * x + x * x;
		w = sin(phase) * amountGain * 0.05 * damping;
	}

	float rotDelta = 0.0;
	float rDelta = 0.0;
#if STYLE == 0
	// aroundCenter
	rotDelta = w;
#elif STYLE == 1
	// outFromCenter
	rDelta = w;
#else
	// pondRipples: both at half strength
	rotDelta = w * 0.5;
	rDelta = w * 0.5;
#endif

	// r>0 guard avoids a 0/0 direction at the exact center pixel. With speed=0,
	// w is exactly 0 there anyway (sin(0)=0); with animation w can be nonzero at
	// r=0, and the zero dir pins the center pixel to sample the center, keeping
	// the reconstruction NaN-free and stable.
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
#if WRAP == 0
	// mirror
	uv = abs(mod(uv + 1.0, 2.0) - 1.0);
#elif WRAP == 1
	// repeat
	uv = mod(uv, 1.0);
#else
	// clamp
	uv = clamp(uv, 0.0, 1.0);
#endif

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
