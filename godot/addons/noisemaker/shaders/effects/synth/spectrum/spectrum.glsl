#version 450
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[36]; };
layout(location = 0) out vec4 fragColor;

#define resolution data[0].xy
#define tileOffset data[1].xy
#define fullResolution data[1].zw
#define lineColor data[2].xyz
#define lineThickness data[2].w
#define gain data[3].x

float spectrum_sample(int index) {
	return data[4 + index / 4][index % 4];
}

void main() {
	vec2 frame = fullResolution.x > 0.0 ? fullResolution : resolution;
	vec2 uv = (gl_FragCoord.xy + tileOffset) / frame;
	float sample_index = uv.x * 127.0;
	int i0 = int(floor(sample_index));
	int i1 = min(i0 + 1, 127);
	float magnitude = mix(spectrum_sample(i0), spectrum_sample(i1), fract(sample_index)) * gain;
	float distance_px = abs(uv.y - magnitude) * frame.y;
	float line = smoothstep(lineThickness + 1.0, lineThickness, distance_px);
	float fill = smoothstep(magnitude + 1.0 / frame.y, magnitude, uv.y) * 0.15;
	float alpha = max(line, fill);
	fragColor = vec4(lineColor * alpha, alpha);
}
