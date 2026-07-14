#version 450
// filter/relief, program "rlShade" — ported verbatim from wgsl/rlShade.wgsl, a
// 1:1 port with NO manual Y compensation anywhere: the light vector
// L=normalize(cos(a),sin(a),0.75) is a plain function of the lightAngle
// uniform, not fragment-coordinate- or position-derived, so PORTING-GUIDE's
// rotation-handedness exception (spinBlur/pondRipples/halftone/stipple) does
// not apply — it is not even a rotation of an existing vector (no rotation
// matrix at all), just cos/sin building a direction, identical in both GLSL
// and WGSL already.
//
// Blurred-luminance relief shading, covering three Photoshop Sketch filters
// via `mode`: 0 basRelief (directional-light shade of the blurred height
// field, blended with the raw height, linear ink/paper tonemap); 1 plaster
// (height pushed through a hard smoothstep plateau and inverted, lit with a
// squared/glossier shade term); 2 notePaper (raw height hard-thresholded at
// `balance` into two flat sheets, with a directional bevel shade in a ~2px
// band around the threshold contour and per-pixel hash grain).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define detail data[..]`, `#define lightAngle data[..]`, `#define balance
// data[..]`, `#define graininess data[..]`, `#define inkColor data[..].xyz`,
// `#define paperColor data[..].xyz`. MODE is a compile-time define injected
// by the runtime (definition.js globals.mode.define) — matches the
// reference's own compiled graph, which bakes `mode` into `defines.MODE`,
// never into `uniforms` (confirmed via tools/export-graph.mjs output), same
// mechanism as filter/oilPaint and filter/hatch. Inputs at set 0, binding
// 1.. in pass.inputs order (inputTex, blurTex).
#ifndef MODE
#define MODE 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float reliefShade(float hC, float hR, float hT, float strength, float lightAngleDeg) {
	vec2 grad = vec2(hR - hC, hT - hC) * strength;
	vec3 n = normalize(vec3(-grad, 1.0));
	float a = radians(lightAngleDeg);
	vec3 L = normalize(vec3(cos(a), sin(a), 0.75));
	return clamp(dot(n, L), 0.0, 1.0);
}

vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 texel = 1.0 / texSize;
	vec4 src = texture(inputTex, uv);

	float hC = lum(texture(blurTex, uv).rgb);
	float hR = lum(texture(blurTex, uv + vec2(texel.x, 0.0)).rgb);
	float hT = lum(texture(blurTex, uv + vec2(0.0, texel.y)).rgb);

	float strength = detail * 0.2;
	vec3 outColor = vec3(0.0);

	if (MODE == 1) {
		// Plaster: hard blobby height plateau, inverted (dark source = raised),
		// glossy (squared) shade.
		float hhC = 1.0 - smoothstep(0.35, 0.65, hC);
		float hhR = 1.0 - smoothstep(0.35, 0.65, hR);
		float hhT = 1.0 - smoothstep(0.35, 0.65, hT);
		float shade = reliefShade(hhC, hhR, hhT, strength, lightAngle);
		float glossy = pow(shade, 2.0);
		outColor = tonemap2(mix(hhC, glossy, 0.75), inkColor, paperColor);
	} else if (MODE == 2) {
		// Note Paper: binary threshold cutout with a beveled contour band and
		// grain.
		float threshold = balance / 100.0;
		float m = step(threshold, hC);
		vec3 sheet = mix(inkColor * 0.9 + 0.1, paperColor, m);

		float shade = reliefShade(hC, hR, hT, strength, lightAngle);
		float gradMag = length(vec2(hR - hC, hT - hC));
		float bandHeight = max(gradMag * 2.0, 1e-5);
		float edge = 1.0 - smoothstep(0.0, bandHeight, abs(hC - threshold));
		vec3 beveled = clamp(sheet * mix(0.6, 1.4, shade), vec3(0.0), vec3(1.0));
		vec3 sheetOut = mix(sheet, beveled, edge);

		vec2 globalCoord = gl_FragCoord.xy + tileOffset;
		float grain = (hash12(floor(globalCoord)) - 0.5) * (graininess / 100.0) * 0.15;

		outColor = clamp(sheetOut + vec3(grain), vec3(0.0), vec3(1.0));
	} else {
		// Bas Relief (mode 0, default): shade blended with raw height, linear
		// tonemap.
		float shade = reliefShade(hC, hR, hT, strength, lightAngle);
		outColor = tonemap2(mix(hC, shade, 0.75), inkColor, paperColor);
	}

	frag = vec4(outColor, src.a);
}
