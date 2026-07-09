#version 450
// filter/watercolor, program "wcComposite" — ported verbatim from
// wgsl/wcComposite.wgsl. Pass 3 of 3: pigment pooling, paper granulation, warm
// paper tint, and a flat-wash lift, composited from the fully-simplified
// (wcSimplify) result and the original inputTex.
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define shadowIntensity data[..]`, `#define paperTexture data[..]`. Inputs
// at set 0, binding 1.. in pass.inputs order (inputTex, simplifiedTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D simplifiedTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// S6 gradient, applied to the SIMPLIFIED texture (pigment pooling edges).
vec2 lumGradientSimplified(vec2 uv) {
	vec2 texSize = vec2(textureSize(simplifiedTex, 0));
	vec2 px = 1.0 / texSize;
	float tl = lum(texture(simplifiedTex, uv + px * vec2(-1.0,  1.0)).rgb);
	float l  = lum(texture(simplifiedTex, uv + px * vec2(-1.0,  0.0)).rgb);
	float bl = lum(texture(simplifiedTex, uv + px * vec2(-1.0, -1.0)).rgb);
	float tr = lum(texture(simplifiedTex, uv + px * vec2( 1.0,  1.0)).rgb);
	float r  = lum(texture(simplifiedTex, uv + px * vec2( 1.0,  0.0)).rgb);
	float br = lum(texture(simplifiedTex, uv + px * vec2( 1.0, -1.0)).rgb);
	float t  = lum(texture(simplifiedTex, uv + px * vec2( 0.0,  1.0)).rgb);
	float b  = lum(texture(simplifiedTex, uv + px * vec2( 0.0, -1.0)).rgb);
	return vec2(tr + 2.0 * r + br - tl - 2.0 * l - bl,
	            tl + 2.0 * t + tr - bl - 2.0 * b - br);
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec3 simplified = texture(simplifiedTex, uv).rgb;

	float edge = length(lumGradientSimplified(uv));

	// Pigment pooling: darken along simplified-region boundaries, the way
	// watercolor pigment collects and dries darker at the edge of a wet wash.
	float pool = shadowIntensity / 100.0 * 0.7 * smoothstep(0.05, 0.4, edge);
	vec3 c = simplified * (1.0 - pool);

	// Paper granulation: hash/noise coordinate is the integer global pixel
	// index (grain lesson, commit ee181726). Both the grain strength and the
	// warm paper tint are gated by paperTexture, so paperTexture=0 yields a
	// smooth, untinted wash and paperTexture=100 is full grain plus full tint.
	vec2 gc = floor(gl_FragCoord.xy);
	c *= mix(1.0, 0.92 + 0.08 * vnoise(gc / 3.5), clamp(paperTexture, 0.0, 100.0) / 100.0);
	c = mix(c, c * vec3(1.02, 1.0, 0.95), paperTexture / 100.0);

	// Wash lift: on flat washes (edge near 0) lift the color very slightly
	// toward its own luminance (desaturate) and brighten a touch, as if the
	// pigment thinned out there and let the white paper glow through --
	// complement of the pooling darkening above, same `edge` field with an
	// inverted falloff.
	float flatness = 1.0 - smoothstep(0.0, 0.15, edge);
	c = mix(c, vec3(lum(c)), flatness * 0.12);
	c *= 1.0 + flatness * 0.05;

	frag = vec4(clamp(c, vec3(0.0), vec3(1.0)), src.a);
}
