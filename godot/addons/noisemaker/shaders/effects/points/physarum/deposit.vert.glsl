#version 450
layout(set = 0, binding = 1) uniform sampler2D xyzTex;
layout(set = 0, binding = 2) uniform sampler2D rgbaTex;
layout(location = 0) out vec4 v_color;

void main() {
	ivec2 size = textureSize(xyzTex, 0);
	int count = size.x * size.y;
	if (gl_VertexIndex >= count) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		v_color = vec4(0.0);
		return;
	}
	ivec2 coord = ivec2(gl_VertexIndex % size.x, gl_VertexIndex / size.x);
	vec4 pos = texelFetch(xyzTex, coord, 0);
	vec4 color = texelFetch(rgbaTex, coord, 0);
	if (pos.w < 0.5) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		v_color = vec4(0.0);
		return;
	}
	gl_Position = vec4(pos.xy * 2.0 - 1.0, 0.0, 1.0);
	gl_PointSize = 1.0;
	v_color = color * deposit;
}
