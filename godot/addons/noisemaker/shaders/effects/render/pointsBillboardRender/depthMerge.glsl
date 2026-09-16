#version 450
// render/pointsBillboardRender — program "depthMerge" (one stage of a 22-stage bottom-up
// merge sort over the depthKeys output, run for runLength = 1,2,4,...,4194304). Ported from
// glsl/depthMerge.glsl. Each output texel finds its rank via a Merge Path binary search
// across the two sorted runs it falls between, so the whole texture is merged in one pass
// per doubling of runLength. Only runs when blendMode==1 (alpha) and viewMode!=0.
//
// Layout effect: vec4 data[1] (uniformLayouts.depthMerge): runLength=data[0].x.
// Sampler: orderTex=1.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[1]; };
#define runLength int(data[0].x)
layout(set = 0, binding = 1) uniform sampler2D orderTex;

layout(location = 0) out vec4 fragColor;

vec2 keyAt(int index, int width) {
	return texelFetch(orderTex, ivec2(index % width, index / width), 0).rg;
}
bool before(vec2 a, vec2 b) {
	return a.x < b.x || (a.x == b.x && a.y <= b.y);
}

void main() {
	ivec2 dims = textureSize(orderTex, 0);
	ivec2 coord = ivec2(gl_FragCoord.xy);
	int index = coord.y * dims.x + coord.x;
	int count = dims.x * dims.y;
	if (runLength >= count) {
		fragColor = texelFetch(orderTex, coord, 0);
		return;
	}
	int start = (index / (2 * runLength)) * (2 * runLength);
	int lengthA = min(runLength, count - start);
	int lengthB = min(runLength, count - start - lengthA);
	int diagonal = index - start;
	int low = max(0, diagonal - lengthB);
	int high = min(diagonal, lengthA);
	// Find the partition for this output position in the two sorted runs.
	for (int step = 0; step < 22 && low < high; step++) {
		int mid = (low + high) / 2;
		int other = diagonal - mid;
		if (mid < lengthA && other > 0 && before(keyAt(start + mid, dims.x), keyAt(start + lengthA + other - 1, dims.x))) {
			low = mid + 1;
		} else {
			high = mid;
		}
	}
	int other = diagonal - low;
	vec2 a = low < lengthA ? keyAt(start + low, dims.x) : vec2(3.402823466e38);
	vec2 b = other < lengthB ? keyAt(start + lengthA + other, dims.x) : vec2(3.402823466e38);
	fragColor = vec4(before(a, b) ? a : b, 0.0, 1.0);
}
