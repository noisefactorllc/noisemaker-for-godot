#version 450
// filter/wind (program "wind") — ported verbatim from wgsl/wind.wgsl (its
// direct-uv/no-remap sampling; cross-checked against glsl/wind.glsl for the
// globalCoord = gl_FragCoord + tileOffset hash-seed convention). Directional
// streak filter (Photoshop Wind: Wind/Blast/Stagger). Each pixel marches upwind
// up to L=4+strength/100*60 samples looking for the brightest sample exceeding
// its own luminance by threshold/100, then paints a decayed (blast: no decay),
// per-scanline-segment-randomized echo of that sample back onto itself via
// max(src, streak).
//
// Y-convention note: horizontal-only march, no directional/rotational geometry
// crosses the Y axis, so a Y-origin mismatch cannot mirror the output geometry
// (see the WGSL/GLSL header comments) — the only Y-sensitivity is the hash seed
// (stagger band-parity, runScale), ported using gl_FragCoord.xy directly
// (top-left, matching WGSL's pos.xy) per this port's established no-per-effect-
// flip convention (PORTING-GUIDE golden rule 1).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define method data[..]`, `#define direction data[..]`, `#define strength
// data[..]`, `#define threshold data[..]`. method/direction are ints with
// choices; arrive as raw floats, cast int(...) at use sites (established idiom).
// Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

#define METHOD_BLAST 1
#define METHOD_STAGGER 2

const int MAX_STEPS = 64;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;

	vec4 src = texture(inputTex, uv);
	float lumBase = lum(src.rgb);

	float L = 4.0 + strength / 100.0 * 60.0;

	// fromLeft (0): wind blows left->right, streaks trail right, so the upwind
	// search direction (toward the bright source) is -x.
	float marchDir = (int(direction) == 0) ? -1.0 : 1.0;

	// Stagger: alternate 4px-tall row bands offset their march start by L/2 so
	// adjacent bands sample different parts of the upwind scanline.
	float staggerStart = 0.0;
	if (int(method) == METHOD_STAGGER) {
		float band = floor(globalCoord.y / 4.0);
		if (mod(band, 2.0) >= 1.0) {
			staggerStart = L * 0.5;
		}
	}

	vec3 bestColor = vec3(0.0);
	float bestLum = -1.0;
	float bestStep = 0.0;
	bool found = false;

	for (int i = 1; i <= MAX_STEPS; i++) {
		if (float(i) > L) { break; }
		float marchStep = staggerStart + float(i);
		vec2 sampleUV = clamp((gl_FragCoord.xy + vec2(marchDir * marchStep, 0.0)) / texSize, 0.0, 1.0);
		vec3 sampleColor = texture(inputTex, sampleUV).rgb;
		float sampleLum = lum(sampleColor);
		if (sampleLum > lumBase + threshold / 100.0 && sampleLum > bestLum) {
			bestLum = sampleLum;
			bestColor = sampleColor;
			bestStep = float(i);
			found = true;
		}
	}

	float decay = (int(method) == METHOD_BLAST) ? 1.0 : exp(-3.0 * bestStep / L);

	// Per-scanline-segment random run length: every pixel in the same
	// L-pixel-wide segment of a scanline shares one random scale factor, so
	// streaks break into randomized runs instead of a uniform wash. +17.0 is an
	// arbitrary decorrelation constant, not a uniform.
	float runScale = hash12(vec2(floor(globalCoord.y), floor(globalCoord.x / L)) + 17.0);

	float alpha = found ? decay * runScale : 0.0;
	vec3 streak = bestColor * alpha;

	frag = vec4(max(src.rgb, streak), src.a);
}
