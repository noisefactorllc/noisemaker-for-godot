#version 450
// filter/extrude (program "extrude") — ported from wgsl/extrude.wgsl (a documented
// 1:1 port of glsl/extrude.glsl; TOP_SIGN=1.0 is the SAME constant in both backends
// — this algorithm has no rotation matrix and is flip-symmetric, so PORTING-GUIDE's
// rotation-handedness exception (see filter/spinBlur/pondRipples) does not apply
// here). Photoshop Extrude: the image is broken into a grid of blocks or pyramids
// that project toward the viewer, taller/nearer where the source is brighter (or
// randomly, per depthSource) and displaced outward from the image center. Grid
// cells are center-anchored (not origin-anchored) so the same visual cell hashes
// identically regardless of image size.
//
// DSL param "type" is bound to the compile-time define "EXTRUDE_TYPE" in the
// reference (definition.js note: `type` collides with a WGSL reserved keyword and
// is overloaded elsewhere, so the shader-side identifier is renamed) — matches the
// reference's own compiled graph, which bakes `type` into `defines.EXTRUDE_TYPE`
// and `depthSource` into `defines.DEPTH_SOURCE`, never into `uniforms`. EXTRUDE_TYPE
// and DEPTH_SOURCE are compile-time defines injected by the runtime (definition.js
// globals.type.define / globals.depthSource.define), same mechanism as
// filter/oilPaint and filter/hatch. No-layout effect: the backend synthesizes the
// Params UBO and injects `#define size data[..]`, `#define depth data[..]`,
// `#define solidFront data[..]`. solidFront is a boolean, arrives as a raw float;
// cast int(...) at use sites (established idiom). Input at set 0, binding 1. Single
// texture, texSize-space throughout (no aspect correction — the grid operates
// directly in pixel space, matching both WGSL and GLSL).
#ifndef EXTRUDE_TYPE
#define EXTRUDE_TYPE 0
#endif
#ifndef DEPTH_SOURCE
#define DEPTH_SOURCE 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const float TOP_SIGN = 1.0;

const float SHADE_TOP = 0.8875;
const float SHADE_BOTTOM = 0.6625;
const float SHADE_LEFT = 0.969856;
const float SHADE_RIGHT = 0.580144;

const float EPS = 1e-4;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec2 toSampleUV(vec2 globalPixelPos, vec2 texSize) {
	return clamp(globalPixelPos / texSize, vec2(0.0), vec2(1.0));
}

// Small 3x3 average centered on a cell, spaced at size*0.25 so the full sample
// footprint (size*0.5 wide) stays inside the cell's own bounds.
vec4 cellAvgColor3x3(vec2 centerPx, vec2 texSize) {
	float sp = size * 0.25;
	vec4 sum = vec4(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 p = centerPx + vec2(float(i), float(j)) * sp;
			sum += textureLod(inputTex, toSampleUV(p, texSize), 0.0);
		}
	}
	return sum * (1.0 / 9.0);
}

float cellHeight(vec2 cellC, vec2 cellIdxF, vec2 texSize) {
	if (DEPTH_SOURCE == 1) {
		// Hash the cell index directly - both backends' fragment positions are
		// content-Y-up in this runtime, so the center-anchored cell indices are
		// already identical cross-backend for the same visual cell.
		return hash12(cellIdxF);
	}
	return lum(cellAvgColor3x3(cellC, texSize).rgb);
}

// Barycentric coords of p in triangle (a,b,c); w (.z) corresponds to c. Returns a
// component < -1.0 (impossible for a real barycentric coord) when the triangle is
// degenerate, so callers can treat it as a miss with the same ">= -EPS" containment
// test used for real triangles.
vec3 baryWeights(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 v0 = b - a;
	vec2 v1 = c - a;
	vec2 v2 = p - a;
	float d00 = dot(v0, v0);
	float d01 = dot(v0, v1);
	float d11 = dot(v1, v1);
	float d20 = dot(v2, v0);
	float d21 = dot(v2, v1);
	float denom = d00 * d11 - d01 * d01;
	if (abs(denom) < 1e-8) {
		return vec3(-2.0);
	}
	float v = (d11 * d20 - d01 * d21) / denom;
	float w = (d00 * d21 - d01 * d20) / denom;
	float u = 1.0 - v - w;
	return vec3(u, v, w);
}

// -1 if P misses all 4 faces; else 0=bottom,1=right,2=top,3=left (fixed
// per-triangle identity, independent of where apex actually projects to).
int pyramidTriHit(vec2 P, vec2 cellC, vec2 apex, vec2 halfCell) {
	vec2 topC = cellC + TOP_SIGN * vec2(0.0, halfCell.y);
	vec2 botC = cellC - TOP_SIGN * vec2(0.0, halfCell.y);
	float leftX = cellC.x - halfCell.x;
	float rightX = cellC.x + halfCell.x;
	vec2 Cbl = vec2(leftX, botC.y);
	vec2 Cbr = vec2(rightX, botC.y);
	vec2 Ctr = vec2(rightX, topC.y);
	vec2 Ctl = vec2(leftX, topC.y);

	vec3 bc = baryWeights(P, Cbl, Cbr, apex);
	if (bc.x >= -EPS && bc.y >= -EPS && bc.z >= -EPS) { return 0; }
	bc = baryWeights(P, Cbr, Ctr, apex);
	if (bc.x >= -EPS && bc.y >= -EPS && bc.z >= -EPS) { return 1; }
	bc = baryWeights(P, Ctr, Ctl, apex);
	if (bc.x >= -EPS && bc.y >= -EPS && bc.z >= -EPS) { return 2; }
	bc = baryWeights(P, Ctl, Cbl, apex);
	if (bc.x >= -EPS && bc.y >= -EPS && bc.z >= -EPS) { return 3; }
	return -1;
}

// Which side of the cell (relative to its center) a footprint pixel is nearest to
// - a simple X-pattern quadrant split.
float sideShade(vec2 P, vec2 cellC) {
	vec2 d = P - cellC;
	float dyUp = d.y * TOP_SIGN;
	if (abs(d.x) > abs(dyUp)) {
		return (d.x > 0.0) ? SHADE_RIGHT : SHADE_LEFT;
	}
	return (dyUp > 0.0) ? SHADE_TOP : SHADE_BOTTOM;
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 P = gl_FragCoord.xy + tileOffset;
	vec2 imgCenter = texSize * 0.5;
	vec2 halfCell = vec2(size * 0.5);

	vec2 toCenter = imgCenter - P;
	float distToCenter = length(toCenter);
	vec2 stepDir = vec2(0.0);
	if (distToCenter > 0.0) {
		stepDir = toCenter / distToCenter;
	}

	float bestPriority = -1.0e9;
	vec2 bestCenterPx = vec2(0.0);
	float bestS = 1.0;
	bool bestIsTop = false;
	int bestTri = -1;
	bool found = false;

	for (int i = 0; i < 6; i++) {
		float t = min(float(i) * size, distToCenter);
		vec2 samplePos = P + stepDir * t;
		// Center-anchored grid - see the file header for why (cross-backend
		// origin-anchoring mismatch).
		vec2 cellIdxF = floor((samplePos - imgCenter) / size);
		vec2 cellC = imgCenter + (cellIdxF + 0.5) * size;

		float h = cellHeight(cellC, cellIdxF, texSize);
		float s = 1.0 + h * (depth / 100.0) * 0.4;

		if (EXTRUDE_TYPE == 1) {
			// pyramids: priority is s alone (no flat-top tier).
			vec2 apex = imgCenter + (cellC - imgCenter) * s;
			int tri = pyramidTriHit(P, cellC, apex, halfCell);
			if (tri >= 0 && s > bestPriority) {
				bestPriority = s;
				bestCenterPx = cellC;
				bestS = s;
				bestTri = tri;
				found = true;
			}
		} else {
			// blocks: top face is the footprint scaled by s about the image
			// center; side band is the rest of the un-scaled footprint (only
			// ever true for i==0).
			vec2 faceCenter = imgCenter + (cellC - imgCenter) * s;
			vec2 faceHalf = halfCell * s;
			bool topHit = all(lessThanEqual(abs(P - faceCenter), faceHalf));
			bool sideHit = (!topHit) && all(lessThanEqual(abs(P - cellC), halfCell));
			if (topHit || sideHit) {
				float priority = s + (topHit ? 1000.0 : 0.0);
				if (priority > bestPriority) {
					bestPriority = priority;
					bestCenterPx = cellC;
					bestS = s;
					bestIsTop = topHit;
					found = true;
				}
			}
		}

		if (t >= distToCenter) { break; }
	}

	vec4 outColor;
	if (!found) {
		// Safety net: P's own cell should always produce a hit by construction;
		// this only guards float-precision edge cases exactly on a cell
		// boundary, so it never shows up as a visible crack.
		vec2 cellC = imgCenter + (floor((P - imgCenter) / size) + 0.5) * size;
		outColor = cellAvgColor3x3(cellC, texSize);
	} else if (EXTRUDE_TYPE == 1) {
		vec2 apex = imgCenter + (bestCenterPx - imgCenter) * bestS;
		vec2 topC = bestCenterPx + TOP_SIGN * vec2(0.0, halfCell.y);
		vec2 botC = bestCenterPx - TOP_SIGN * vec2(0.0, halfCell.y);
		float leftX = bestCenterPx.x - halfCell.x;
		float rightX = bestCenterPx.x + halfCell.x;
		vec2 Cbl = vec2(leftX, botC.y);
		vec2 Cbr = vec2(rightX, botC.y);
		vec2 Ctr = vec2(rightX, topC.y);
		vec2 Ctl = vec2(leftX, topC.y);

		vec2 Ci; vec2 Ci1; float shadeConst;
		if (bestTri == 0) { Ci = Cbl; Ci1 = Cbr; shadeConst = SHADE_BOTTOM; }
		else if (bestTri == 1) { Ci = Cbr; Ci1 = Ctr; shadeConst = SHADE_RIGHT; }
		else if (bestTri == 2) { Ci = Ctr; Ci1 = Ctl; shadeConst = SHADE_TOP; }
		else { Ci = Ctl; Ci1 = Cbl; shadeConst = SHADE_LEFT; }

		vec3 bc = baryWeights(P, Ci, Ci1, apex);
		float apexW = clamp(bc.z, 0.0, 1.0);

		vec4 baseColor;
		if (int(solidFront) != 0) {
			baseColor = cellAvgColor3x3(bestCenterPx, texSize);
		} else {
			vec2 localPos = bc.x * Ci + bc.y * Ci1 + bc.z * bestCenterPx;
			baseColor = textureLod(inputTex, toSampleUV(localPos, texSize), 0.0);
		}
		float shade = mix(1.0, shadeConst, apexW);
		outColor = vec4(baseColor.rgb * shade, baseColor.a);
	} else if (bestIsTop) {
		if (int(solidFront) != 0) {
			outColor = cellAvgColor3x3(bestCenterPx, texSize);
		} else {
			vec2 localPos = imgCenter + (P - imgCenter) / bestS;
			outColor = textureLod(inputTex, toSampleUV(localPos, texSize), 0.0);
		}
	} else {
		float shade = sideShade(P, bestCenterPx);
		vec4 meanColor = cellAvgColor3x3(bestCenterPx, texSize);
		outColor = vec4(meanColor.rgb * shade, meanColor.a);
	}

	frag = outColor;
}
