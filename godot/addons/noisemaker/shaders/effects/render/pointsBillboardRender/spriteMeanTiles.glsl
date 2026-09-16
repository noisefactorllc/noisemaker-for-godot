#version 450
// render/pointsBillboardRender — program "spriteMeanTiles" (32x32-texel reduction tiles
// over a 5x5 grid of overlapping bilinear-weighted nodes, feeding spriteMean). Ported from
// glsl/spriteMeanTiles.glsl. Only meaningful for shapeMode==0 (texture); skipped whenever
// aperture is 0 or viewMode is flat (no defocus blur possible in either case).
//
// Layout effect: vec4 data[1] (uniformLayouts.spriteMeanTiles): shapeMode=data[0].x,
// aperture=data[0].y, viewMode=data[0].z. Sampler: spriteTex=1.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[1]; };
#define shapeMode int(data[0].x)
#define aperture data[0].y
#define viewMode int(data[0].z)
layout(set = 0, binding = 1) uniform sampler2D spriteTex;

layout(location = 0) out vec4 fragColor;

// Each of 5x5 spatial nodes has 32x32 reduction tiles. Bilinear weights
// preserve source mass and first moments independently for all RGBA channels.
void main() {
	if (shapeMode != 0 || aperture <= 0.0 || viewMode == 0) {
		fragColor = vec4(0.0);
		return;
	}
	ivec2 dims = textureSize(spriteTex, 0);
	ivec2 coord = ivec2(gl_FragCoord.xy);
	ivec2 node = coord / 32;
	ivec2 tile = coord % 32;
	ivec2 start = max(tile * dims / 32, (node - 1) * dims / 4 - 1);
	ivec2 end = min((tile + 1) * dims / 32, (node + 1) * dims / 4 + 1);
	vec4 total = vec4(0.0);
	for (int y = start.y; y < end.y; y++) {
		for (int x = start.x; x < end.x; x++) {
			vec2 uv = (vec2(x, y) + 0.5) / vec2(dims);
			vec2 weight = max(vec2(0.0), 1.0 - abs(uv * 4.0 - vec2(node)));
			total += texelFetch(spriteTex, ivec2(x, y), 0) * (weight.x * weight.y);
		}
	}
	fragColor = total / float(dims.x * dims.y);
}
