#version 450
// filter/mosaicTiles (program "mosaicTiles") — ported PIXEL-IDENTICALLY from
// wgsl/mosaicTiles.wgsl (a 1:1 port; no rotation/handedness question anywhere in
// this effect — no angle param, no swirl. Every vector here is axis-aligned grid
// math (floor/fract/min/mix) or a scalar broadcast, and reliefShade's light
// vector is a plain function of the fixed 135-degree angle constant, matching
// filter/craquelure's precedent — reliefShade is reused verbatim below). `mode`
// is a plain RUNTIME branch (both branches always compile in), NOT a compile-time
// define, per the reference definition.js (globals.mode has no `define` key).
//
// Covers two Photoshop filters via `mode`:
//   mosaic (0)  - Filter Gallery > Texture > Mosaic Tiles: a square grid warped
//                 by value noise into wavy ceramic tiles. Each tile shows a
//                 mildly center-flattened sample of its own image region,
//                 separated by grout darkened and beveled with S8 relief shading.
//                 The height fed to reliefShade is -k (grout is a carved groove,
//                 not a raised ridge), mirroring filter/craquelure's polarity fix.
//   shifted (1) - Stylize > Tiles: a REGULAR (unwarped) square grid; each tile's
//                 content is grabbed from a randomly shifted source position (a
//                 per-cell hash offset, constant across the whole tile), leaving
//                 a small fixed gap filled per `gapFill`.
//
// groutWidth is a single shared uniform reused by BOTH modes (mosaic's grout
// half-width AND shifted's fixed inter-tile gap width); its UI control is gated
// to mosaic only at the definition-JSON layer, but the shader consumes whatever
// value the uniform holds in both branches. See effects/filter/mosaicTiles.json /
// the reference definition.js for the full per-parameter description.
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// mode data[..]`, `tileSize`, `groutWidth`, `relief`, `maxOffset`, `gapFill`,
// `backgroundColor`, `seed`. Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

// S1 - hash / jitter.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// S4 - value noise (fBm not needed here).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// S8 - relief shade from height (verbatim; see filter/relief's rlShade.glsl /
// filter/craquelure's precedent).
float reliefShade(float hC, float hR, float hT, float strength, float lightAngleDeg) {
	vec2 grad = vec2(hR - hC, hT - hC) * strength;
	vec3 n = normalize(vec3(-grad, 1.0));
	float a = radians(lightAngleDeg);
	vec3 L = normalize(vec3(cos(a), sin(a), 0.75));
	return clamp(dot(n, L), 0.0, 1.0);
}

// Mosaic mode's wavy-grid warp scalar (px) at global pixel position gc,
// broadcast equally to both axes when added to gc: a single continuous scalar
// field is enough to wave every cell border, because two neighboring pixels
// straddling a nominal border pick up slightly different offsets as the noise
// varies, bending the actual floor()-quantized cell boundary between them (same
// domain-warp-before-quantize mechanism as filter/craquelure's crack path).
float mosaicWarp(vec2 gc, float tileSizePx, float seedVal) {
	return vnoise(gc / tileSizePx + seedVal * 101.7) * 0.25 * tileSizePx;
}

// Mosaic mode's grout mask (1 = on grout, 0 = tile interior) at global pixel
// position gc: warps gc, finds the fractional position within its tileSizePx
// cell, and turns the distance to the nearest cell edge into an antialiased band
// of half-width `groutWidthPct% of tileSizePx/2`.
float mosaicGroutMask(vec2 gc, float tileSizePx, float groutWidthPct, float seedVal) {
	float warp = mosaicWarp(gc, tileSizePx, seedVal);
	vec2 cellFrac = fract((gc + vec2(warp)) / tileSizePx);
	float edgeDistPx = min(min(cellFrac.x, 1.0 - cellFrac.x), min(cellFrac.y, 1.0 - cellFrac.y)) * tileSizePx;
	float groutHalfWidthPx = groutWidthPct / 100.0 * (tileSizePx * 0.5);
	float groutAA = 1.25;
	return 1.0 - smoothstep(groutHalfWidthPx - groutAA, groutHalfWidthPx + groutAA, edgeDistPx);
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 srcHome = texture(inputTex, uv);
	float seedF = float(seed);

	vec3 result;

	if (int(mode) == 0) {
		// Mosaic: wavy tiles with beveled grout.
		float warp = mosaicWarp(globalCoord, tileSize, seedF);
		vec2 warpedCoord = globalCoord + vec2(warp);
		vec2 cellSpace = warpedCoord / tileSize;
		vec2 cellId = floor(cellSpace);
		vec2 cellFrac = fract(cellSpace);

		// Flattened sample position: bias this pixel's (warped) position toward
		// its cell's center by flattenAmount, entirely in cell-space, so it can
		// never cross into a neighboring cell. The warp is undone with the SAME
		// scalar computed at this pixel's own position (good approximation
		// across the small flatten displacement, no second noise lookup).
		float flattenAmount = 0.4;
		vec2 flattenedCellFrac = mix(cellFrac, vec2(0.5), flattenAmount);
		vec2 flattenedGc = (cellId + flattenedCellFrac) * tileSize - vec2(warp);
		vec2 sampleUV = clamp((flattenedGc - tileOffset) / resolution, 0.0, 1.0);
		vec3 tileColor = texture(inputTex, sampleUV).rgb;

		// True central-difference gradient of the grout mask (5 bounded
		// evaluations total), fed into S8's reliefShade exactly like
		// filter/craquelure's crack wall shading.
		float kC = mosaicGroutMask(globalCoord, tileSize, groutWidth, seedF);
		float kR = mosaicGroutMask(globalCoord + vec2(1.0, 0.0), tileSize, groutWidth, seedF);
		float kL = mosaicGroutMask(globalCoord - vec2(1.0, 0.0), tileSize, groutWidth, seedF);
		float kT = mosaicGroutMask(globalCoord + vec2(0.0, 1.0), tileSize, groutWidth, seedF);
		float kB = mosaicGroutMask(globalCoord - vec2(0.0, 1.0), tileSize, groutWidth, seedF);

		vec2 gradK = vec2((kR - kL) * 0.5, (kT - kB) * 0.5);

		// Height fed to reliefShade is -k, NOT +k: grout is a carved groove (a
		// dip), not a raised ridge - mirrors filter/craquelure's polarity fix.
		float hC = -kC;
		float hR = hC - gradK.x;
		float hT = hC - gradK.y;
		float shadeStrength = 6.0;
		float shade = reliefShade(hC, hR, hT, shadeStrength, 135.0);

		// reliefShade's flat-ground (zero-gradient) value is exactly 0.6 for ANY
		// lightAngleDeg, so centering the bevel multiplier there makes relief
		// contribute EXACTLY zero shading away from any grout. No additional
		// gradient gate is needed here (unlike craquelure's wallMask): the grout
		// mask k already saturates to an exact flat plateau (0) away from any
		// grout band by construction (mosaicGroutMask's smoothstep has a
		// clamped range), so gradK is already exactly zero there.
		float flatShade = 0.6;
		vec3 darkened = tileColor * mix(1.0, 0.35, kC);
		float shadeMul = 1.0 + (shade - flatShade) * 2.0 * (relief / 100.0);
		result = clamp(darkened * shadeMul, 0.0, 1.0);
	} else {
		// Shifted: regular grid, each tile's content grabbed from a randomly
		// shifted source position, small fixed gap between tiles filled per
		// gapFill.
		vec2 cellSpace = globalCoord / tileSize;
		vec2 cellId = floor(cellSpace);
		vec2 cellFrac = fract(cellSpace);
		float edgeDistPx = min(min(cellFrac.x, 1.0 - cellFrac.x), min(cellFrac.y, 1.0 - cellFrac.y)) * tileSize;

		float gapWidthPx = groutWidth / 100.0 * tileSize;
		float gapAA = 1.25;
		float gapMask = 1.0 - smoothstep(gapWidthPx * 0.5 - gapAA, gapWidthPx * 0.5 + gapAA, edgeDistPx);

		// x2.0: expands the hash's +/-0.5 span to +/-1.0 so offsetPx spans the
		// full +/-maxOffset% of tileSize.
		vec2 offsetPx = (hash22(cellId + seedF * 101.7) - 0.5) * 2.0 * (maxOffset / 100.0) * tileSize;
		vec2 shiftedGc = globalCoord + offsetPx;
		vec2 shiftedUV = clamp((shiftedGc - tileOffset) / resolution, 0.0, 1.0);
		vec3 tileColor = texture(inputTex, shiftedUV).rgb;

		vec3 gapColor;
		int gapFillI = int(gapFill);
		if (gapFillI == 0) {
			// background
			gapColor = backgroundColor;
		} else if (gapFillI == 1) {
			// inverse of the tile's own home pixel
			gapColor = 1.0 - srcHome.rgb;
		} else {
			// unaltered home pixel
			gapColor = srcHome.rgb;
		}

		result = mix(tileColor, gapColor, gapMask);
	}

	// Alpha always comes from the pixel's own unmodified home position.
	frag = vec4(result, srcHome.a);
}
