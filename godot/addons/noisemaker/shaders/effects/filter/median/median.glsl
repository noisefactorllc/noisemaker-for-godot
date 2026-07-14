#version 450
// filter/median, program "median" — ported from wgsl/median.wgsl (disambiguated against
// glsl/median.glsl; the two are algorithmically identical, no rotation/orientation
// concern since the sample window is a symmetric NxN neighborhood around gl_FragCoord).
//
// Exact dense whole-color Median / Dust & Scratches. RADIUS is a compile-time define
// (definition.js globals.radius, min 1 max 3): the 3x3/5x5/7x7 variants make exactly
// 9/25/49 clamped integer texture reads. A bounded in-place Hoare-partition selection
// finds the middle rank without fully sorting the neighborhood. threshold == 0 always
// replaces with the median (classic Photoshop Median); threshold > 0 only replaces
// pixels whose original/median difference exceeds the threshold (Dust & Scratches).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define threshold data[..]`. Single input at set 0, binding 1.
#ifndef RADIUS
#define RADIUS 3
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

#if RADIUS == 1
#define REAL_COUNT 9
#elif RADIUS == 2
#define REAL_COUNT 25
#else
#define REAL_COUNT 49
#endif

bool lessRecord(uvec2 a, uint blueA, uvec2 b, uint blueB) {
	if (a.x != b.x) return a.x < b.x;
	if (a.y != b.y) return a.y < b.y;
	return blueA < blueB;
}

uvec2 packRecordMajor(vec4 sampleColor) {
	float brightness = dot(sampleColor.rgb, vec3(0.2126, 0.7152, 0.0722));
	uint packedRg = packHalf2x16(sampleColor.rg);
	uint orderedRg = ((packedRg & 0xffffu) << 16) | (packedRg >> 16);
	return uvec2(floatBitsToUint(brightness), orderedRg);
}

uint packRecordBlue(vec4 sampleColor) {
	return packHalf2x16(vec2(sampleColor.b, 0.0)) & 0xffffu;
}

vec3 unpackRecordRgb(uvec2 major, uint blue) {
	uint packedRg = (major.y << 16) | (major.y >> 16);
	vec2 rg = unpackHalf2x16(packedRg);
	float b = unpackHalf2x16(blue).x;
	return vec3(rg, b);
}

vec4 readRecord(ivec2 center, ivec2 dimensions, int x, int y) {
	ivec2 coord = clamp(center + ivec2(x, y), ivec2(0), dimensions - ivec2(1));
	return texelFetch(inputTex, coord, 0);
}

void main() {
	uvec2 majorRecords[REAL_COUNT];
	uint blueRecords[REAL_COUNT];
	ivec2 dimensions = textureSize(inputTex, 0);
	ivec2 center = ivec2(gl_FragCoord.xy);
	vec3 originalRgb = vec3(0.0);
	float centerAlpha = 1.0;
	int index = 0;
	for (int y = -RADIUS; y <= RADIUS; y++) {
		for (int x = -RADIUS; x <= RADIUS; x++) {
			vec4 sampleColor = readRecord(center, dimensions, x, y);
			majorRecords[index] = packRecordMajor(sampleColor);
			blueRecords[index] = packRecordBlue(sampleColor);
			if (x == 0 && y == 0) {
				originalRgb = sampleColor.rgb;
				centerAlpha = sampleColor.a;
			}
			index++;
		}
	}

	int medianIndex = REAL_COUNT / 2;
	int left = 0;
	int right = REAL_COUNT - 1;
	while (left < right) {
		uvec2 pivotMajor = majorRecords[medianIndex];
		uint pivotBlue = blueRecords[medianIndex];
		int scanLeft = left;
		int scanRight = right;
		while (scanLeft <= scanRight) {
			while (lessRecord(majorRecords[scanLeft], blueRecords[scanLeft], pivotMajor, pivotBlue)) { scanLeft++; }
			while (lessRecord(pivotMajor, pivotBlue, majorRecords[scanRight], blueRecords[scanRight])) { scanRight--; }
			if (scanLeft <= scanRight) {
				uvec2 temporaryMajor = majorRecords[scanLeft];
				majorRecords[scanLeft] = majorRecords[scanRight];
				majorRecords[scanRight] = temporaryMajor;
				uint temporaryBlue = blueRecords[scanLeft];
				blueRecords[scanLeft] = blueRecords[scanRight];
				blueRecords[scanRight] = temporaryBlue;
				scanLeft++;
				scanRight--;
			}
		}
		if (scanRight < medianIndex) { left = scanLeft; }
		if (medianIndex < scanLeft) { right = scanRight; }
	}

	vec3 medianRgb = unpackRecordRgb(majorRecords[medianIndex], blueRecords[medianIndex]);
	vec3 difference = abs(originalRgb - medianRgb);
	float maxDifference = max(max(difference.r, difference.g), difference.b);
	bool replaceCenter = threshold <= 0.0 || maxDifference >= threshold / 100.0;
	frag = vec4(replaceCenter ? medianRgb : originalRgb, centerAlpha);
}
