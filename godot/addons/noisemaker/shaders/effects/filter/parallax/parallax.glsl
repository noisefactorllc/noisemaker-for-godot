#version 450
// filter/parallax (program "parallax") — ported from wgsl/parallax.wgsl, cross-checked
// against glsl/parallax.wgsl for the fullResolution/tileOffset remap (WGSL samples
// heightMap/inputTex directly by the same uv; the GLSL golden remaps each by its OWN
// textureSize, matching filter/lighting's heightMap convention — see that file).
// Ray-marched parallax occlusion mapping: march the view ray (direction.xy shifted by
// SHIFT_SCALE) against the heightMap's luminosity field to find where the ray height
// drops below the surface, then sample inputTex at that offset UV.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define direction data[..].xyz`, `#define pivot data[..].w` (bare reference names).
// Inputs bound at set 0, binding 1.. in pass.inputs order (inputTex, heightMap — see
// effects/filter/parallax.json). heightMap (surface, default "inputTex") resolves to
// the pass's own input when unwired (expander `pipeline`-kind fallback).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D heightMap;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const int MARCH_STEPS = 32;
const float SHIFT_SCALE = 0.15;

float getLuminosity(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

float getHeight(vec2 uv) {
	vec2 mapSize = vec2(textureSize(heightMap, 0));
	vec2 localUV = (uv * fullResolution - tileOffset) / mapSize;
	return getLuminosity(textureLod(heightMap, localUV, 0.0).rgb);
}

vec4 getInput(vec2 uv) {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 localUV = (uv * fullResolution - tileOffset) / texSize;
	return textureLod(inputTex, localUV, 0.0);
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = globalCoord / fullResolution;

	vec3 v = length(direction) > 0.0 ? normalize(direction) : vec3(0.0, 0.0, 1.0);
	vec2 shift = v.xy * SHIFT_SCALE;

	// View ray crosses this fragment's UV at height == pivot
	float t = 1.0;
	vec2 rayUV = uv + shift * (1.0 - pivot);
	float f = t - getHeight(rayUV);

	if (f > 0.0) {
		float stepSize = 1.0 / float(MARCH_STEPS);
		for (int i = 1; i <= MARCH_STEPS; i++) {
			float prevF = f;
			vec2 prevUV = rayUV;
			t = 1.0 - float(i) * stepSize;
			rayUV = uv + shift * (t - pivot);
			f = t - getHeight(rayUV);
			if (f <= 0.0) {
				// Refine: interpolate between the straddling samples
				float w = f / (f - prevF);
				rayUV = mix(rayUV, prevUV, vec2(w));
				break;
			}
		}
	}

	frag = getInput(rayUV);
}
