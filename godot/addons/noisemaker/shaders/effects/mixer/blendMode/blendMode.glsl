#version 450
// mixer/blendMode — ported from wgsl/blendMode.wgsl. 16 blend modes + mix + Porter-Duff
// "over". No-layout effect: backend injects Params UBO + `#define mode …`/`mixAmt …`.
// Two inputs (pass.inputs order): inputTex = base (binding 1), tex = blend (binding 2).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D tex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float map_range(float value, float inMin, float inMax, float outMin, float outMax) {
	return outMin + (outMax - outMin) * (value - inMin) / (inMax - inMin);
}

float blendOverlay(float a, float b) {
	if (a < 0.5) {
		return 2.0 * a * b;
	} else {
		return 1.0 - 2.0 * (1.0 - a) * (1.0 - b);
	}
}

float blendSoftLight(float base, float blend) {
	if (blend < 0.5) {
		return 2.0 * base * blend + base * base * (1.0 - 2.0 * blend);
	} else {
		return sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend);
	}
}

vec4 applyBlendMode(vec4 color1, vec4 color2, int m) {
	if (m == 0) { return min(color1 + color2, vec4(1.0)); }
	if (m == 1) { return 1.0 - min((1.0 - color1) / max(color2, vec4(0.001)), vec4(1.0)); }
	if (m == 2) { return min(color1, color2); }
	if (m == 3) { return abs(color1 - color2); }
	if (m == 4) { return min(color1 / max(1.0 - color2, vec4(0.001)), vec4(1.0)); }
	if (m == 5) { return color1 + color2 - 2.0 * color1 * color2; }
	if (m == 6) {
		return vec4(blendOverlay(color2.r, color1.r), blendOverlay(color2.g, color1.g),
			blendOverlay(color2.b, color1.b), 1.0);
	}
	if (m == 7) { return max(color1, color2); }
	if (m == 8) { return (color1 + color2) * 0.5; }
	if (m == 9) { return color1 * color2; }
	if (m == 10) { return vec4(1.0) - abs(vec4(1.0) - color1 - color2); }
	if (m == 11) {
		return vec4(blendOverlay(color1.r, color2.r), blendOverlay(color1.g, color2.g),
			blendOverlay(color1.b, color2.b), 1.0);
	}
	if (m == 12) { return min(color1, color2) - max(color1, color2) + vec4(1.0); }
	if (m == 13) { return vec4(1.0) - (vec4(1.0) - color1) * (vec4(1.0) - color2); }
	if (m == 14) {
		return vec4(blendSoftLight(color1.r, color2.r), blendSoftLight(color1.g, color2.g),
			blendSoftLight(color1.b, color2.b), 1.0);
	}
	return max(color1 - color2, vec4(0.0));
}

void main() {
	vec2 dims = vec2(textureSize(inputTex, 0));
	vec2 st = gl_FragCoord.xy / dims;

	vec4 color1 = texture(inputTex, st);
	vec4 color2 = texture(tex, st);

	int m = int(mode);
	float amt = map_range(mixAmt, -100.0, 100.0, 0.0, 1.0);

	// The normal mixer axis ("mix", m==8) is source opacity. Other modes reach the full
	// blend at the midpoint, then transition to normal source-over at +100 (reference 0ed489ec).
	float opacity = (m == 8) ? amt : min(amt * 2.0, 1.0);
	float sourceAlpha = color2.a * opacity;
	vec3 source = color2.rgb * opacity;
	if (m != 8) {
		// Surfaces are premultiplied. Blend functions operate on straight RGB
		// only where both inputs cover the pixel; uncovered source stays intact.
		vec4 baseColor = vec4(0.0, 0.0, 0.0, 1.0);
		vec4 sourceColor = vec4(0.0, 0.0, 0.0, 1.0);
		if (color1.a > 0.0) { baseColor = vec4(color1.rgb / color1.a, 1.0); }
		if (color2.a > 0.0) { sourceColor = vec4(color2.rgb / color2.a, 1.0); }
		vec3 blended = applyBlendMode(baseColor, sourceColor, m).rgb;
		blended = mix(blended, sourceColor.rgb, max(amt * 2.0 - 1.0, 0.0));
		source = source * (1.0 - color1.a) + blended * sourceAlpha * color1.a;
	}

	frag = vec4(source + color1.rgb * (1.0 - sourceAlpha), sourceAlpha + color1.a * (1.0 - sourceAlpha));
}
