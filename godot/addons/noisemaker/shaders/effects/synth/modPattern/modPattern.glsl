#version 450
// synth/modPattern program modPattern — ported from glsl/modPattern.glsl. Declared-layout effect: the shader names each layout slot with a #define;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[6]; };
#define resolution data[0].xy
#define time data[0].z
#define shape1 data[1].x
#define scale1 data[1].y
#define repeat1 data[1].z
#define shape2 data[1].w
#define scale2 data[2].x
#define repeat2 data[2].y
#define shape3 data[2].z
#define scale3 data[2].w
#define repeat3 data[3].x
#define blend data[3].y
#define speed data[3].z
#define smoothing data[3].w
#define animMode data[4].x
#define tileOffset data[5].xy
#define fullResolution data[5].zw
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

#define TAU 6.28318530718

// Generate a geometric shape from the given coordinates 
float shape(int shapeIndex, vec2 p) {
	float v;
	if (shapeIndex < 1) {
		// plus
		v = max(p.x, p.y);
	} else if (shapeIndex < 2) {
		// square
		v = min(p.x, p.y);
	} else {
		// diamond
		v = abs(p.x - p.y);
	}
	return v;
}

float smoothFract(float x) {
	float f = fract(x);
	float edgeWidth = smoothing * 0.01;
	if (f > 1.0 - edgeWidth) {
		return smoothstep(0.0, edgeWidth, 1.0 - f);
	}
	return f;
}

vec2 smoothFract(vec2 v) {
	return vec2(smoothFract(v.x), smoothFract(v.y));
}

vec3 smoothFract(vec3 v) {
	return vec3(smoothFract(v.x), smoothFract(v.y), smoothFract(v.z));
}

void main() {
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = (globalCoord - fullResolution * 0.5) / min(fullResolution.x, fullResolution.y);

	float spd = floor(speed);
	float anim = time * spd;

	// Create repeating cells with hard edges
	// mod(uv * scale, 2.0) creates repeating cells from 0 to 2
	// Subtracting 1.0 centers them from -1 to 1
	// abs() folds them, so you get a pattern that goes 0->1->0->1 with sharp peaks
	float s1 = 20.1 - scale1; // Map scale so larger number = lower frequency
	vec2 p = abs(mod(uv * s1, 2.0) - 1.0);

	// Pan mode: per-layer directional oscillation, scaled to layer frequency
	if (int(animMode) == 1) {
		float osc1 = sin(time * TAU * spd) * 0.03;
		p += vec2(osc1, 0.0);
	}

	// Generate a shape/pattern for the repeated coordinates
	float n1 = shape(int(shape1), p);

	// Phase mode: offset each layer independently
	float phase1 = (int(animMode) == 2) ? anim : 0.0;
	float phase2 = (int(animMode) == 2) ? anim : 0.0;
	float phase3 = (int(animMode) == 2) ? anim : 0.0;

	// Repeat the same fold operation but at a different frequency, and generate another shape
	float s2 = 10.1 - scale2; // Map scale so larger number = lower frequency
	p = abs(mod(p * s2, 2.0) - 1.0);

	// Pan mode: layer 2 pans up
	if (int(animMode) == 1) {
		float osc2 = sin(time * TAU * spd) * 0.07;
		p += vec2(0.0, osc2);
	}

	float n2 = shape(int(shape2), p);

	// Multiply each pattern by different amounts (like 3 and 5) and add them together.
	// The fract() wraps values back to 0-1, creating interference patterns
	float val = 0.0;
	if (int(blend) < 1) {
		val = fract(n1 * repeat1 + phase1 + n2 * repeat2 + phase2);
	} else {
		val = smoothFract(n1 * repeat1 + phase1 + n2 * repeat2 + phase2);
	}

	// Repeat again with scale3 frequency, modifying the coordinates and creating another
	// shape/pattern
	float s3 = 6.1 - scale3; // Map scale so larger number = lower frequency
	p = abs(mod(p * s3, 2.0) - 1.0);

	// Pan mode: layer 3 pans left
	if (int(animMode) == 1) {
		float osc3 = sin(time * TAU * spd) * 0.15;
		p += vec2(-osc3, 0.0);
	}

	float n3 = shape(int(shape3), p);

	// Shift mode: add time offset at the final blend stage
	float shift = (int(animMode) == 0) ? anim : 0.0;

	// Combine layers with selected blend mode
	vec3 color;
	if (int(blend) < 1) {
		// add
		color = smoothFract(vec3(fract(val + n3 * repeat3 + phase3 + shift)));
	} else if (int(blend) < 2) {
		// max
		color = vec3(max(val, smoothFract(n3 * repeat3 + phase3 + shift)));
	} else if (int(blend) < 3) {
		// mix
		color = vec3(mix(val, smoothFract(n3 * repeat3 + phase3 + shift), 0.5));
	} else {
		// rgb
		color = smoothFract(vec3(n1 * repeat1 + phase1, n2 * repeat2 + phase2, n3 * repeat3 + phase3 + shift));
	}

	fragColor = vec4(color, 1.0);
}
