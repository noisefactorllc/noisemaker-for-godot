#version 450
// filter/patchwork (program "patchwork") — ported PIXEL-IDENTICALLY from
// wgsl/patchwork.wgsl (a 1:1 port; no rotation/handedness question anywhere in
// this effect — cellIdxF/localPx/edgeNormal/imgCenter are all POSITION-DERIVED
// and ported with NO manual Y compensation, exactly like filter/extrude's
// center-anchored imgCenter; lightDir is a plain function of the lightAngle
// uniform, not fragment-coordinate-derived, so it is textually identical to the
// WGSL, matching filter/relief's rlShade / filter/craquelure's light-vector
// precedent).
//
// Needlepoint grid of solid-color squares raised by luminance with lit bevel
// edges (Photoshop Filter Gallery > Texture > Patchwork). Cells are squareSize-px
// squares in GLOBAL (tile-aware) pixel coordinates, anchored at the IMAGE CENTER
// (not the coordinate origin) — filter/extrude's proven fix for a cross-backend
// grid-boundary mismatch. Each cell is SOLID, sampled with a 3x3 mini-blur at the
// cell's own center (filter/extrude's cellAvgColor3x3 precedent); height
// h = lum(cellColor). Every pixel is shaded by its own cell's height alone
// (topFaceShade); the outer 15% rim of every cell is additionally beveled by an
// analytic per-side light term — NOT S8's gradient-based reliefShade, since the
// height field here is piecewise-constant between cells (a local finite-
// difference gradient can't see across a cell boundary). See
// effects/filter/patchwork.json / the reference definition.js for the full
// polarity derivation (raised cells — opposite of filter/craquelure's carved
// groove).
//
// cellAvgColor3x3 uses textureLod (explicit LOD 0), matching filter/extrude's own
// cellAvgColor3x3 precedent: it is called from inside main()'s `dMin < rimPx`
// branch, genuinely per-fragment data-dependent control flow. inputTex is a
// non-mipmapped render-target texture, so LOD 0 is numerically identical to
// texture()'s implicit LOD here either way.
//
// No-layout effect: the backend synthesizes the Params UBO and injects `#define
// squareSize data[..]`, `#define relief data[..]`, `#define lightAngle data[..]`.
// Input at set 0, binding 1.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// globalPixelPos is in GLOBAL pixel space; converts to a tile-local sample UV,
// clamped so the 3x3 mini-blur and neighbor-cell samples never read past this
// tile's own coverage.
vec2 toSampleUV(vec2 globalPixelPos) {
	return clamp((globalPixelPos - tileOffset) / resolution, 0.0, 1.0);
}

// 3x3 mini-blur centered on a cell (filter/extrude's cellAvgColor3x3 precedent):
// spaced at squareSize*0.25 so the full sample footprint (squareSize*0.5 wide)
// stays inside the cell's own bounds.
vec4 cellAvgColor3x3(vec2 centerPx) {
	float sp = squareSize * 0.25;
	vec4 sum = vec4(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 p = centerPx + vec2(float(i), float(j)) * sp;
			sum += textureLod(inputTex, toSampleUV(p), 0.0);
		}
	}
	return sum * (1.0 / 9.0);
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = gl_FragCoord.xy / resolution;
	vec4 srcOwn = texture(inputTex, uv);

	// Center-anchored grid - see file header for why.
	vec2 imgCenter = fullResolution * 0.5;
	vec2 relPx = globalCoord - imgCenter;
	vec2 cellIdxF = floor(relPx / squareSize);
	vec2 localPx = relPx - cellIdxF * squareSize;
	vec2 cellCenter = imgCenter + (cellIdxF + 0.5) * squareSize;

	vec3 cellColor = cellAvgColor3x3(cellCenter).rgb;
	float h = lum(cellColor);
	float topFaceShade = 0.9 + 0.2 * (h - 0.5);

	// Distance (px) from this rim pixel to each of the cell's 4 edges.
	float rimPx = 0.15 * squareSize;
	float dLeft = localPx.x;
	float dRight = squareSize - localPx.x;
	float dBottom = localPx.y;
	float dTop = squareSize - localPx.y;
	float dMin = min(min(dLeft, dRight), min(dBottom, dTop));

	float bevelMul = 1.0;
	if (dMin < rimPx) {
		vec2 neighborIdx = cellIdxF;
		vec2 edgeNormal;
		if (dMin == dLeft) {
			neighborIdx.x -= 1.0;
			edgeNormal = vec2(-1.0, 0.0);
		} else if (dMin == dRight) {
			neighborIdx.x += 1.0;
			edgeNormal = vec2(1.0, 0.0);
		} else if (dMin == dBottom) {
			neighborIdx.y -= 1.0;
			edgeNormal = vec2(0.0, -1.0);
		} else {
			neighborIdx.y += 1.0;
			edgeNormal = vec2(0.0, 1.0);
		}

		vec2 neighborCenter = imgCenter + (neighborIdx + 0.5) * squareSize;
		float hNeighbor = lum(cellAvgColor3x3(neighborCenter).rgb);
		float dh = h - hNeighbor;

		float a = radians(lightAngle);
		vec2 lightDir = vec2(cos(a), sin(a));
		float signTerm = dot(edgeNormal, lightDir);

		// Raised cells (opposite of filter/craquelure's carved groove) - see
		// the reference definition.js for the full polarity derivation.
		bevelMul = 1.0 + 0.35 * (relief / 100.0) * sign(dh) * signTerm;
	}

	vec3 result = clamp(cellColor * topFaceShade * bevelMul, 0.0, 1.0);
	frag = vec4(result, srcOwn.a);
}
