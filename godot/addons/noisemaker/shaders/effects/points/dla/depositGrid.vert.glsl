#version 450
layout(set = 0, binding = 1) uniform sampler2D xyzTex;
layout(set = 0, binding = 2) uniform sampler2D velTex;
layout(set = 0, binding = 3) uniform sampler2D rgbaTex;
layout(location = 0) out float v_weight;
layout(location = 1) out vec3 v_color;

void main() {
	ivec2 size = textureSize(xyzTex, 0);
	int count = size.x * size.y;
	if (gl_VertexIndex >= count) {
		gl_Position = vec4(-2.0, -2.0, 0.0, 1.0);
		gl_PointSize = 1.0;
		v_weight = 0.0;
		v_color = vec3(0.0);
		return;
	}

	ivec2 coord = ivec2(gl_VertexIndex % size.x, gl_VertexIndex / size.x);
	vec4 xyz = texelFetch(xyzTex, coord, 0);
	vec4 vel = texelFetch(velTex, coord, 0);
	vec4 rgba = texelFetch(rgbaTex, coord, 0);
	v_weight = vel.y;
	v_color = rgba.rgb;
	if (v_weight < 0.5) {
		gl_Position = vec4(-2.0, -2.0, 0.0, 1.0);
		gl_PointSize = 1.0;
		return;
	}

	gl_Position = vec4(xyz.xy * 2.0 - 1.0, 0.0, 1.0);
	gl_PointSize = 1.0;
}
