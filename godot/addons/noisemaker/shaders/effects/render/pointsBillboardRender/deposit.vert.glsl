#version 450
// render/pointsBillboardRender — program "deposit" VERTEX stage (scatter agents as
// billboard quads). Ported from glsl/deposit.vert. Drawn procedurally with N×6 vertices:
// gl_VertexIndex/6 selects the agent, gl_VertexIndex%6 the quad corner (two triangles).
// Each agent expands into a screen-facing quad of pointSize px (per-agent size + rotation
// variation), emitting a sprite UV for the fragment stage's SDF/sprite shapes.
//
// Reference 0ed489ec adds: a perspective VIEW_MODE 2 (shared camera model with
// renderLandscape3d/pointsRender at Z=80); an alpha-blend depth sort (BLEND_MODE 1 reads
// orderTex, produced by depthKeys+depthMerge, to redirect particleID to draw back-to-front);
// and aperture defocus blur, computed here as a per-agent blur radius from camera distance
// and consumed by the fragment stage against the spriteMean precompute. BLUR_LAYER splits
// each additive-mode deposit into two passes (broad/soft footprints vs the rest) so a focus
// transition never pops between them.
//
// viewMode/blendMode/blurLayer (reference 0ed489ec) are compile-time defines, not packed
// uniforms: the definition's `.flatMap()` clones this program per (viewMode, blendMode,
// blurLayer) combination, each carrying its own `defines: {VIEW_MODE, BLEND_MODE,
// BLUR_LAYER}` — the backend injects these unconditionally (nm_backend.gd's execute_pass()
// injects pass.defines regardless of layout-declared vs synthesized UBOs).
//
// Layout effect: vec4 data[6] (effects/render/pointsBillboardRender.json,
// uniformLayouts.deposit): resolution=data[0].xy, density=data[0].z, pointSize=data[0].w,
// sizeVariation=data[1].x, rotationVar=data[1].y, seed=data[1].z, rotateX=data[1].w,
// rotateY=data[2].x, rotateZ=data[2].y, viewScale=data[2].z, posX=data[2].w, posY=data[3].x,
// posZ=data[3].y, fieldOfView=data[3].z, sizeDistance=data[3].w, brightnessDistance=data[4].x,
// aperture=data[4].y, focalDistance=data[4].z, shapeMode=data[4].w, depositOpacity=data[5].x.
// Samplers: xyzTex=1, rgbaTex=2, orderTex=3.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[6]; };
#define resolution data[0].xy
#define density data[0].z
#define pointSize data[0].w
#define sizeVariation data[1].x
#define rotationVar data[1].y
#define seed data[1].z
#define rotateX data[1].w
#define rotateY data[2].x
#define rotateZ data[2].y
#define viewScale data[2].z
#define posX data[2].w
#define posY data[3].x
#define posZ data[3].y
#define fieldOfView data[3].z
#define sizeDistance data[3].w
#define brightnessDistance data[4].x
#define aperture data[4].y
#define focalDistance data[4].z
#define shapeMode int(data[4].w)
#define depositOpacity data[5].x

layout(set = 0, binding = 1) uniform sampler2D xyzTex;
layout(set = 0, binding = 2) uniform sampler2D rgbaTex;
layout(set = 0, binding = 3) uniform sampler2D orderTex;

layout(location = 0) out vec4 vColor;
layout(location = 1) out vec2 vSpriteUV;
layout(location = 2) out float vBlurRadius;

uint hash_uint(uint s) {
	uint state = s * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// Deterministic noise function for per-particle variation
float hash(float n) {
	return float(hash_uint(floatBitsToUint(n + seed))) / 4294967295.0;
}

void main() {
	vBlurRadius = 0.0;
#if BLUR_LAYER == 1
	if (aperture <= 0.0) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		vColor = vec4(0.0);
		vSpriteUV = vec2(0.0);
		return;
	}
#endif
	// Each quad uses 6 vertices (2 triangles)
	int particleID = gl_VertexIndex / 6;
	int vertexInQuad = gl_VertexIndex % 6;

	// Get state size from xyz texture dimensions
	ivec2 texSize = textureSize(xyzTex, 0);
	int stateSize = texSize.x;
	int totalAgents = stateSize * stateSize;

	// Cull particles beyond texture size
	if (particleID >= totalAgents) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		vColor = vec4(0.0);
		vSpriteUV = vec2(0.0);
		return;
	}

	if (BLEND_MODE == 1 && VIEW_MODE != 0) {
		particleID = int(texelFetch(orderTex, ivec2(particleID % stateSize, particleID / stateSize), 0).g);
	}

	// Density-based culling. PARITY (large-stateSize precision): the reference is
	// fract(particleID*GR); at ~1M agents the raw product exceeds float32 fractional precision
	// (step ~0.06 near 6.5e5) so fract() quantizes into ~16 buckets and Metal passes ~8x too
	// many agents vs the golden's ANGLE — over-depositing into an HDR over-bright trail that
	// drives navierStokes to a white-out. Hi/lo split keeps the products small so fract is exact.
	float cullThreshold = density / 100.0;
	float pidf = float(particleID);
	float pidHi = floor(pidf / 4096.0);
	float pidLo = pidf - pidHi * 4096.0;
	float particleRandom = fract(pidHi * fract(4096.0 * 0.618033988749895) + pidLo * 0.618033988749895);
	if (particleRandom > cullThreshold) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		vColor = vec4(0.0);
		vSpriteUV = vec2(0.0);
		return;
	}

	// Calculate UV for this particle
	int x = particleID % stateSize;
	int y = particleID / stateSize;

	// Read particle position and color
	vec4 pos = texelFetch(xyzTex, ivec2(x, y), 0);
	vec4 col = texelFetch(rgbaTex, ivec2(x, y), 0);

	// Check if particle is alive (pos.w >= 0.5 means alive)
	if (pos.w < 0.5) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		vColor = vec4(0.0);
		vSpriteUV = vec2(0.0);
		return;
	}

	// Calculate clip-space center position (same as pointsRender)
	vec2 clipPos;
	float cameraDepth = 80.0;
	float cameraDistance = 0.0;
	float projectedScale = 1.0;

	if (VIEW_MODE == 0) {
		// 2D mode: positions are normalized 0..1
		clipPos = pos.xy * 2.0 - 1.0;
	} else {
		// 3D mode: apply rotation and projection
		vec3 p = pos.xyz;

		// Detect if this is a 2D system (coords in 0-1) or 3D attractor (coords ±40)
		bool is2DSystem = VIEW_MODE == 1 && abs(p.z) < 1.0 && p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0;

		if (is2DSystem) {
			p.xy = p.xy - 0.5;
			p.z = 0.0;
		}

		// Apply rotation around X axis
		float cosX = cos(rotateX);
		float sinX = sin(rotateX);
		p = vec3(p.x, p.y * cosX - p.z * sinX, p.y * sinX + p.z * cosX);

		// Apply rotation around Y axis
		float cosY = cos(rotateY);
		float sinY = sin(rotateY);
		p = vec3(p.x * cosY + p.z * sinY, p.y, -p.x * sinY + p.z * cosY);

		// Apply rotation around Z axis
		float cosZ = cos(rotateZ);
		float sinZ = sin(rotateZ);
		p = vec3(p.x * cosZ - p.y * sinZ, p.x * sinZ + p.y * cosZ, p.z);

		// Apply X/Y offset after rotation
		p.x += posX;
		p.y += posY;
		p.z += posZ;
		cameraDepth = 80.0 - p.z;
		cameraDistance = length(vec3(p.xy, cameraDepth));

		// Orthographic projection with scale
		if (VIEW_MODE == 2) {
			// Camera looks down -Z from z=80. Reject the near plane before division.
			if (cameraDepth <= 0.1) {
				gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
				vColor = vec4(0.0);
				vSpriteUV = vec2(0.0);
				return;
			}
			float focalLength = 1.0 / tan(clamp(fieldOfView, 10.0, 150.0) * 0.00872664626);
			clipPos = p.xy * focalLength * viewScale / cameraDepth;
			clipPos.x *= resolution.y / resolution.x;
			projectedScale = 80.0 * focalLength * viewScale / (1.732050808 * cameraDepth);
		} else if (is2DSystem) {
			clipPos = p.xy * 3.5 * viewScale;
		} else {
			clipPos = p.xy / 40.0 * viewScale;
		}
	}

	// Per-particle size variation (seeded deterministic)
	float sizeNoise = hash(float(particleID));
	float sizeMultiplier = 1.0 - (sizeVariation / 100.0) * (sizeNoise - 0.5);
	float sizeFade = 1.0;
	float brightnessFade = 1.0;
	float blurPixels = 0.0;
	if (VIEW_MODE != 0) {
		if (sizeDistance > 0.0) sizeFade = 1.0 - smoothstep(0.0, sizeDistance, cameraDistance);
		if (brightnessDistance > 0.0) brightnessFade = 1.0 - smoothstep(0.0, brightnessDistance, cameraDistance);
		blurPixels = min(32.0, aperture * abs(cameraDepth - focalDistance) / max(abs(cameraDepth), 0.1));
	}
	float baseSize = pointSize * sizeMultiplier * projectedScale;
	// Textured blur integrates nodes across the whole source square. A
	// procedural footprint needs only its center's displacement as padding.
	float blurRadius = blurPixels / max(baseSize, 0.001);
	// Match the normalized fragment kernel's minimum support. Keep the
	// requested radius for interpolation and resolution-layer selection.
	float supportRadius = blurPixels > 0.0 ? max(blurRadius, 0.62582015) : 0.0;
	float supportPixels = blurPixels > 0.0 ? max(blurPixels, baseSize * 0.62582015) : 0.0;
	// Only broad, fully softened additive footprints can use the smaller
	// target. Complementary weights prevent a focus transition from popping.
	float lowWeight = BLEND_MODE == 0 ? smoothstep(4.0, 8.0, blurPixels * sizeFade) * smoothstep(0.5, 1.0, blurRadius) : 0.0;
	float layerWeight = BLUR_LAYER == 1 ? lowWeight : 1.0 - lowWeight;
	float blurPadding = blurPixels > 0.0 ? (shapeMode == 0 ? 0.5 : (shapeMode == 5 ? 0.04 : 0.0)) : 0.0;
	float finalSize = (baseSize * (1.0 + 2.0 * blurPadding) + 2.0 * supportPixels) * sizeFade;
	if (finalSize <= 0.0 || brightnessFade <= 0.0 || layerWeight <= 0.0) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		vColor = vec4(0.0);
		vSpriteUV = vec2(0.0);
		return;
	}
	vBlurRadius = blurRadius;

	// Per-particle rotation (seeded deterministic)
	float rotationNoise = hash(float(particleID) + 1234.5);
	float rotation = (rotationVar / 100.0) * rotationNoise * 6.283185; // 0 to 2π

	// Convert pixel size to clip-space units
	vec2 pixelToClip = 2.0 / resolution;
	float halfSize = finalSize * 0.5;
	vec2 sizeClip = halfSize * pixelToClip;

	// Quad vertex offsets (two triangles: 0-1-2, 2-1-3)
	// Winding order for proper face culling
	vec2 offsets[6];
	offsets[0] = vec2(-1.0, -1.0); // bottom-left
	offsets[1] = vec2( 1.0, -1.0); // bottom-right
	offsets[2] = vec2(-1.0,  1.0); // top-left
	offsets[3] = vec2(-1.0,  1.0); // top-left
	offsets[4] = vec2( 1.0, -1.0); // bottom-right
	offsets[5] = vec2( 1.0,  1.0); // top-right

	vec2 offset = offsets[vertexInQuad];

	// Apply rotation to offset
	float cosR = cos(rotation);
	float sinR = sin(rotation);
	vec2 rotatedOffset = vec2(
		offset.x * cosR - offset.y * sinR,
		offset.x * sinR + offset.y * cosR
	);

	// Scale offset and add to center position
	vec2 finalPos = clipPos + rotatedOffset * sizeClip;

	gl_Position = vec4(finalPos, 0.0, 1.0);
	vColor = col * brightnessFade * layerWeight;

	// Sprite UV coordinates (0-1 range)
	vSpriteUV = offset * (0.5 + blurPadding + supportRadius) + 0.5;
}
