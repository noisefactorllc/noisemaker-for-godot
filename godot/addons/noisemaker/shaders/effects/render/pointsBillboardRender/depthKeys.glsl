#version 450
// render/pointsBillboardRender — program "depthKeys" (emit one [depth, originalIndex] key
// per agent slot, back-to-front). Ported from glsl/depthKeys.glsl. Two pass clones select
// the world position differently: VIEW_MODE 1 (ortho) recenters a 2D system at the origin
// before rotating; VIEW_MODE 2 (perspective) rotates the raw position as-is. Feeds the
// depthMerge bitonic-style merge sort. Only runs when blendMode==1 (alpha) and viewMode!=0.
//
// Layout effect: vec4 data[1] (uniformLayouts.depthKeys): rotateX=data[0].x,
// rotateY=data[0].y, posZ=data[0].z. Sampler: xyzTex=1.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[1]; };
#define rotateX data[0].x
#define rotateY data[0].y
#define posZ data[0].z
layout(set = 0, binding = 1) uniform sampler2D xyzTex;

layout(location = 0) out vec4 fragColor;

void main() {
	ivec2 coord = ivec2(gl_FragCoord.xy);
	ivec2 dims = textureSize(xyzTex, 0);
	vec4 pos = texelFetch(xyzTex, coord, 0);
	vec3 p = pos.xyz;
	if (VIEW_MODE == 1 && abs(p.z) < 1.0 && p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0) {
		p.xy -= 0.5;
		p.z = 0.0;
	}
	p = vec3(p.x, p.y * cos(rotateX) - p.z * sin(rotateX), p.y * sin(rotateX) + p.z * cos(rotateX));
	p = vec3(p.x * cos(rotateY) + p.z * sin(rotateY), p.y, -p.x * sin(rotateY) + p.z * cos(rotateY));
	// Ascending negative camera depth gives back-to-front draw order.
	// Original slot breaks ties and retains per-particle identity.
	float depth = p.z + posZ - 80.0;
	// A non-finite key breaks the merge ordering and can duplicate valid IDs.
	float key = pos.w >= 0.5 && abs(depth) <= 3.402823466e38 ? depth : 3.402823466e38;
	fragColor = vec4(key, float(coord.y * dims.x + coord.x), 0.0, 1.0);
}
