#version 450
layout(location = 0) in float v_weight;
layout(location = 1) in vec3 v_color;
layout(location = 0) out vec4 fragColor;

void main() {
	if (v_weight < 0.5) {
		discard;
	}
	float energy = deposit * 0.1;
	fragColor = vec4(v_color * energy, energy);
}
