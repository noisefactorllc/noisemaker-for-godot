#version 450
// filter/lowPoly — ported PIXEL-IDENTICALLY from wgsl/lowPoly.wgsl.
// Voronoi-based low-polygon art style: deterministic per-cell seed points, nearest
// Voronoi cell over a 3x3 neighborhood, filled with the input color sampled at the
// seed position. Modes: 0 flat, 1 edges (F2-F1 darkening), 2 distance2, 3 distance3.
// borderWidth (0=off) adds thick edgeColor "leading" along cell boundaries on top
// of whatever mode draws, reusing the edges mode's F2-F1 metric; lightIntensity
// (0=off) adds radial brightening from the image center. Both gate on `> 0.0` so
// they are exact byte-for-byte no-ops at their zero defaults — together with a
// dark edgeColor these give Photoshop Stained Glass parity.
// Final: rgb = mix(original.rgb, result, alpha); alpha passed through.
//
// No-layout effect (no reference uniformLayout): the backend injects the Params UBO
// + `#define scale …`/`seed`/`mode`/`edgeStrength`/`edgeColor`/`borderWidth`/
// `lightIntensity`/`alpha`/`speed` and engine globals (time, tileOffset,
// fullResolution), so bare names are used at the main() use sites. Input texture
// bound at set 0, binding 1 (pass.inputs order).
//
// pcg/hash2 are this effect's OWN PRNG — inlined VERBATIM under renamed symbols
// (lp_pcg/lp_hash2) rather than pulling include/nm_core.glsl. WGSL select(a,b,cond)
// == cond ? b : a (operands reversed); u32(...) is float->uint TRUNCATION toward
// zero -> uint(...); divisor is float(0xffffffffu) = 4294967295.0 (not 2^32).
// Backend sampler is NEAREST (coord-resampling); no per-effect Y-flip (gl_FragCoord
// is top-left in Godot/Vulkan, matching WGSL position.xy).
//
// LP_BORDER / LP_LIGHT are compile-time defines injected by the runtime
// (definition.js `define:` fields on borderWidth / lightIntensity, same
// mechanism as filter/oilPaint's mode) — NOT plain runtime uniforms; baking them
// preprocesses the border/light blocks out of the default variant entirely so a
// plain render is byte-identical to the mode result, matching the reference.
#ifndef LP_BORDER
#define LP_BORDER 0
#endif
#ifndef LP_LIGHT
#define LP_LIGHT 0
#endif

layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const float LP_TAU = 6.28318530718;

// PCG PRNG - MIT License (effect's own copy, inlined verbatim).
uvec3 lp_pcg(uvec3 seed_in) {
	uvec3 v = seed_in * 1664525u + 1013904223u;
	v.x = v.x + v.y * v.z;
	v.y = v.y + v.z * v.x;
	v.z = v.z + v.x * v.y;
	v = v ^ (v >> uvec3(16u));
	v.x = v.x + v.y * v.z;
	v.y = v.y + v.z * v.x;
	v.z = v.z + v.x * v.y;
	return v;
}

vec2 lp_hash2(vec2 p, float s) {
	uvec3 v = lp_pcg(uvec3(
		uint(p.x >= 0.0 ? p.x * 2.0 : -p.x * 2.0 + 1.0),
		uint(p.y >= 0.0 ? p.y * 2.0 : -p.y * 2.0 + 1.0),
		uint(s >= 0.0 ? s * 2.0 : -s * 2.0 + 1.0)
	));
	return vec2(v.xy) / float(0xffffffffu);
}

#if LP_BORDER > 0
// Border-only exact site position (reused by the wider 5x5 border search below;
// the primary nearest-site search above keeps its own inlined copy so its
// per-pixel FP result is untouched by adding this helper).
vec2 lp_lowPolySite(ivec2 siteCell, float n, float s, float spd) {
	vec2 siteCellF = vec2(siteCell);
	vec2 offset = lp_hash2(siteCellF, s);
	if (spd > 0.0) {
		vec2 animRand = lp_hash2(siteCellF, s + 100.0);
		float angle = time * LP_TAU + animRand.x * LP_TAU;
		float radius = animRand.y * spd;
		offset = clamp(offset + vec2(cos(angle), sin(angle)) * radius, vec2(0.0), vec2(1.0));
	}
	return (siteCellF + offset) / n;
}
#endif

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec2 globalUV = (gl_FragCoord.xy + tileOffset) / fullResolution;

	float n = max(102.0 - scale, 2.0);
	float s = seed;
	float spd = float(speed) * 0.3;

	// Aspect-corrected coordinates for square Voronoi cells
	float aspect = fullResolution.x / fullResolution.y;
	vec2 auv = vec2(globalUV.x * aspect, globalUV.y);

	// Scale to grid in corrected space
	vec2 scaled = auv * n;
	ivec2 cell = ivec2(floor(scaled));

	float minDist = 1e10;
	float secondDist = 1e10;
	float thirdDist = 1e10;
	vec2 nearestPoint = vec2(0.0);
#if LP_BORDER > 0
	ivec2 nearestCell = ivec2(0);
#endif

	// Search 3x3 neighborhood of cells
	for (int dy = -1; dy <= 1; dy = dy + 1) {
		for (int dx = -1; dx <= 1; dx = dx + 1) {
			ivec2 neighbor = cell + ivec2(dx, dy);
			vec2 neighborF = vec2(neighbor);

			// Generate seed point in this cell
			vec2 offset = lp_hash2(neighborF, s);

			// Animate: per-cell circular drift with unique phase/radius
			if (spd > 0.0) {
				vec2 animRand = lp_hash2(neighborF, s + 100.0);
				float angle = time * LP_TAU + animRand.x * LP_TAU;
				float radius = animRand.y * spd;
				offset = clamp(offset + vec2(cos(angle), sin(angle)) * radius, vec2(0.0), vec2(1.0));
			}

			vec2 point = (neighborF + offset) / n;
			float d = distance(auv, point);

			if (d < minDist) {
				thirdDist = secondDist;
				secondDist = minDist;
				minDist = d;
				nearestPoint = point;
#if LP_BORDER > 0
				nearestCell = neighbor;
#endif
			} else if (d < secondDist) {
				thirdDist = secondDist;
				secondDist = d;
			} else if (d < thirdDist) {
				thirdDist = d;
			}
		}
	}

	// Convert nearest point back to UV space for texture sampling
	vec4 cellColor = texture(inputTex, (vec2(nearestPoint.x / aspect, nearestPoint.y) * fullResolution - tileOffset) / texSize);

	vec3 result;
	int modeI = int(mode);
	if (modeI == 0) {
		// Flat: pure solid cell color
		result = cellColor.rgb;
	} else if (modeI == 1) {
		// Edges: solid cell color with F2-F1 edge darkening
		float edgeDist = clamp((secondDist - minDist) * n * 2.0, 0.0, 1.0);
		float edgeFactor = mix(edgeStrength, 0.0, edgeDist);
		result = mix(cellColor.rgb, edgeColor, edgeFactor);
	} else {
		// Distance: multiply distance field with cell color
		float selectedDist;
		if (modeI == 2) { selectedDist = secondDist; }
		else { selectedDist = thirdDist; }
		float raw = clamp(selectedDist * n, 0.0, 1.0);
		float distField = pow(raw, mix(0.5, 3.0, edgeStrength));
		result = cellColor.rgb * distField;
	}

	// Optional borders and lighting layer over the selected Low Poly mode. Both
	// controls are compile-time defines (LP_BORDER / LP_LIGHT): when zero these
	// blocks are preprocessed out entirely, so the established mode result
	// reaches the blend byte-identical to a plain render.
#if (LP_BORDER > 0) || (LP_LIGHT > 0)
	vec3 modeResult = result;
	float borderMask = 0.0;
#endif

#if LP_BORDER > 0
	// Draw a controllable band along cell boundaries. A bounded 5x5 site search
	// measures perpendicular distance to nearby Voronoi bisectors; width is a
	// percentage of the nominal cell radius.
	{
		// The established mode path above intentionally retains its original 3x3
		// search. Borders opt into a wider exact-nearest search because a fully
		// jittered site two cells away can own the current pixel.
		vec2 borderNearestPoint = nearestPoint;
		ivec2 borderNearestCell = nearestCell;
		float borderNearestDist = minDist;
		for (int dy = -2; dy <= 2; dy = dy + 1) {
			for (int dx = -2; dx <= 2; dx = dx + 1) {
				ivec2 candidateCell = cell + ivec2(dx, dy);
				vec2 candidatePoint = lp_lowPolySite(candidateCell, n, s, spd);
				float candidateDist = distance(auv, candidatePoint);
				if (candidateDist < borderNearestDist) {
					borderNearestDist = candidateDist;
					borderNearestPoint = candidatePoint;
					borderNearestCell = candidateCell;
				}
			}
		}
		float distToEdge = 1e10;
		for (int dy = -2; dy <= 2; dy = dy + 1) {
			for (int dx = -2; dx <= 2; dx = dx + 1) {
				ivec2 candidateCell = cell + ivec2(dx, dy);
				if (any(notEqual(candidateCell, borderNearestCell))) {
					vec2 candidatePoint = lp_lowPolySite(candidateCell, n, s, spd);
					vec2 siteVector = candidatePoint - borderNearestPoint;
					float siteDistance = max(length(siteVector), 1e-8);
					float bisectorDistance = dot(
						(borderNearestPoint + candidatePoint) * 0.5 - auv,
						siteVector / siteDistance
					);
					distToEdge = min(distToEdge, bisectorDistance);
				}
			}
		}
		float cellRadius = 0.5 / n;
		float borderHalfWidth = (float(LP_BORDER) / 100.0) * cellRadius;
		float borderFeather = max(fwidth(distToEdge), 1e-6);
		borderMask = 1.0 - smoothstep(
			borderHalfWidth - borderFeather,
			borderHalfWidth + borderFeather,
			distToEdge
		);
		result = mix(modeResult, edgeColor, borderMask);
	}
#endif

#if LP_LIGHT > 0
	// Raise the selected mode's value with a bounded exposure curve while scaling
	// RGB together. Composite the border afterward so it never brightens.
	{
		float intensity = clamp(float(LP_LIGHT) / 100.0, 0.0, 1.0);
		float paneValue = max(max(modeResult.r, modeResult.g), modeResult.b);
		float exposure = mix(1.0, 2.25, intensity);
		float litValue = 1.0 - pow(max(1.0 - paneValue, 0.0), exposure);
		vec3 litMode = paneValue > 1e-6 ? modeResult * (litValue / paneValue) : modeResult;
		result = mix(litMode, edgeColor, borderMask);
	}
#endif

	// Alpha blend with original
	vec4 original = texture(inputTex, uv);
	frag = vec4(mix(original.rgb, result, alpha), original.a);
}
