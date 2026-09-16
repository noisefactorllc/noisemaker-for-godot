#version 450
// render/pointsBillboardRender — program "spriteMean" (reduce spriteMeanTiles' 160x160
// tiles into a 5x5 texel mean-sprite texture, or for a procedural shapeMode fill it with a
// fixed precomputed coverage constant). Ported from glsl/spriteMean.glsl. Skipped whenever
// aperture is 0 or viewMode is flat.
//
// Layout effect: vec4 data[1] (uniformLayouts.spriteMean): shapeMode=data[0].x,
// aperture=data[0].y, viewMode=data[0].z. Sampler: tilesTex=1.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[1]; };
#define shapeMode int(data[0].x)
#define aperture data[0].y
#define viewMode int(data[0].z)
layout(set = 0, binding = 1) uniform sampler2D tilesTex;

layout(location = 0) out vec4 fragColor;

float proceduralCoverage() {
	// Means of the same 5x5 centered SDF samples, evaluated in double
	// precision and rounded once to f32. Recompute if a shape changes.
	// Fixed values avoid driver-dependent coverage drift during defocus.
	if (shapeMode == 1) return 0.713220537;
	if (shapeMode == 2) return 0.310907274;
	if (shapeMode == 3) return 0.680000007;
	if (shapeMode == 4) return 0.519999981;
	if (shapeMode == 5) return 0.0951406509;
	if (shapeMode == 6) return 0.103062622;
	return 0.362012237; // Soft shape and the existing fallback.
}

void main() {
	if (aperture <= 0.0 || viewMode == 0) {
		fragColor = vec4(0.0);
		return;
	}
	if (shapeMode != 0) {
		fragColor = vec4(proceduralCoverage());
		return;
	}
	ivec2 origin = ivec2(gl_FragCoord.xy) * 32;
	vec4 total = vec4(0.0);
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 32; x++) {
			total += texelFetch(tilesTex, origin + ivec2(x, y), 0);
		}
	}
	fragColor = total;
}
