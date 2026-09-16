#version 450
// render/pointsRender — program "deposit" VERTEX stage (scatter agents to the trail as
// point primitives). Ported from glsl/deposit.vert. Drawn procedurally: one vertex per
// agent, gl_VertexIndex (Vulkan's gl_VertexID) indexes the stateSize² agent grid; each
// vertex fetches its agent's position+color from the state textures and emits a 1px point
// at the agent's clip position. Dead/density-culled agents are pushed off-screen.
//
// Layout effect: vec4 data[3] (effects/render/pointsRender.json, uniformLayouts.deposit):
//   resolution=data[0].xy, density=data[0].z, rotateX=data[0].w, rotateY=data[1].x,
//   rotateZ=data[1].y, viewScale=data[1].z, posX=data[1].w, posY=data[2].x, posZ=data[2].y,
//   fieldOfView=data[2].z. Samplers: xyzTex=1, rgbaTex=2. Clip-space write is self-consistent
//   with the fullscreen passes' gl_FragCoord reads in Vulkan; the single global present-flip
//   reconciles to golden.
//
// viewMode (reference 0ed489ec) moved from a packed uniform to a compile-time define: the
// definition's `.flatMap()` clones this program per viewMode into deposit_0/1/2, each carrying
// its own `defines: {VIEW_MODE: n}` — the backend injects `#define VIEW_MODE <n>` regardless of
// this being a layout effect (nm_backend.gd's execute_pass() injects pass.defines unconditionally,
// only the synthesized-UBO step is layout-gated). Keep VIEW_MODE as a bare identifier.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[3]; };
#define resolution data[0].xy
#define density data[0].z
#define rotateX data[0].w
#define rotateY data[1].x
#define rotateZ data[1].y
#define viewScale data[1].z
#define posX data[1].w
#define posY data[2].x
#define posZ data[2].y
#define fieldOfView data[2].z

layout(set = 0, binding = 1) uniform sampler2D xyzTex;
layout(set = 0, binding = 2) uniform sampler2D rgbaTex;

layout(location = 0) out vec4 vColor;

void main() {
	// Get state size from xyz texture dimensions (inherited from pointsEmit)
	ivec2 texSize = textureSize(xyzTex, 0);
	int stateSize = texSize.x;
	int totalAgents = stateSize * stateSize;

	// Cull vertices beyond texture size
	if (gl_VertexIndex >= totalAgents) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		vColor = vec4(0.0);
		return;
	}

	// Density-based culling. PARITY (large-stateSize precision): fract(id*GR) loses float32
	// precision at ~1M agents (step ~0.06 near 6.5e5 → ~16 buckets → ~8x over-deposit on Metal
	// vs the golden's ANGLE). Hi/lo split keeps the products small so fract is exact.
	float cullThreshold = density / 100.0;
	float pidf = float(gl_VertexIndex);
	float pidHi = floor(pidf / 4096.0);
	float pidLo = pidf - pidHi * 4096.0;
	float particleRandom = fract(pidHi * fract(4096.0 * 0.618033988749895) + pidLo * 0.618033988749895);
	if (particleRandom > cullThreshold) {
		// Cull this particle by placing it off-screen
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		vColor = vec4(0.0);
		return;
	}

	// Calculate UV for this agent
	int x = gl_VertexIndex % stateSize;
	int y = gl_VertexIndex / stateSize;

	// Read agent position and color
	vec4 pos = texelFetch(xyzTex, ivec2(x, y), 0);
	vec4 col = texelFetch(rgbaTex, ivec2(x, y), 0);

	// Check if agent is alive (pos.w >= 0.5 means alive)
	if (pos.w < 0.5) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		vColor = vec4(0.0);
		return;
	}

	vec2 clipPos;

	if (VIEW_MODE == 0) {
		// 2D mode: positions are normalized 0..1
		clipPos = pos.xy * 2.0 - 1.0;
	} else {
		// 3D mode: rotate world coordinates before camera projection
		vec3 p = pos.xyz;

		// Detect if this is a 2D system (coords in 0-1) or 3D attractor (coords ±40)
		// 2D systems have Z near 0 and XY in 0-1 range
		bool is2DSystem = VIEW_MODE == 1 && abs(p.z) < 1.0 && p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0;

		if (is2DSystem) {
			// Center 2D coords around origin: 0-1 -> -0.5 to 0.5
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

		// Apply X/Y offset after rotation (pan in screen space)
		p.x += posX;
		p.y += posY;

		if (VIEW_MODE == 2) {
			// Match the billboard camera at Z=80, looking down negative Z.
			float cameraDepth = 80.0 - (p.z + posZ);
			if (cameraDepth <= 0.1) {
				gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
				gl_PointSize = 0.0;
				vColor = vec4(0.0);
				return;
			}
			float focalLength = 1.0 / tan(clamp(fieldOfView, 10.0, 150.0) * 0.00872664626);
			clipPos = p.xy * focalLength * viewScale / cameraDepth;
			clipPos.x = clipPos.x * resolution.y / resolution.x;
		} else if (is2DSystem) {
			// 2D systems: coords are now ±0.5, scale to fill viewport
			// Use 3.5x multiplier for close-up view that's nice to pan around
			clipPos = p.xy * 3.5 * viewScale;
		} else {
			// 3D attractors: coords range roughly ±40, normalize then scale
			clipPos = p.xy / 40.0 * viewScale;
		}
	}

	gl_Position = vec4(clipPos, 0.0, 1.0);
	gl_PointSize = 1.0;
	vColor = vec4(col.rgb, col.a);
}
