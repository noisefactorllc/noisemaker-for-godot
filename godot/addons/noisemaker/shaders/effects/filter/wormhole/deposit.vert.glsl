#version 450
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) out vec4 v_color;

const float TAU = 6.28318530717959;

float oklab_l(vec3 rgb) {
	vec3 c = clamp(rgb, 0.0, 1.0);
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	float lc = pow(max(l, 0.0), 1.0 / 3.0);
	float mc = pow(max(m, 0.0), 1.0 / 3.0);
	float sc = pow(max(s, 0.0), 1.0 / 3.0);
	return 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc;
}

void main() {
	ivec2 size = textureSize(inputTex, 0);
	int count = size.x * size.y;
	if (gl_VertexIndex >= count) {
		gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
		gl_PointSize = 0.0;
		v_color = vec4(0.0);
		return;
	}

	int src_x = gl_VertexIndex % size.x;
	int src_y = gl_VertexIndex / size.x;
	vec4 src = texelFetch(inputTex, ivec2(src_x, src_y), 0);
	float lum = oklab_l(src.rgb);
	float angle = lum * TAU * kink + radians(rotation);
	float pixel_stride = 1024.0 * stride;
	int dest_x = int(floor(float(src_x) + (cos(angle) + 1.0) * pixel_stride));
	int dest_y = int(floor(float(src_y) + (sin(angle) + 1.0) * pixel_stride));
	int wrap_mode = int(wrap);
	if (wrap_mode == 0) {
		int mx = ((dest_x % (size.x * 2)) + size.x * 2) % (size.x * 2);
		int my = ((dest_y % (size.y * 2)) + size.y * 2) % (size.y * 2);
		dest_x = size.x - 1 - abs(mx - size.x + 1);
		dest_y = size.y - 1 - abs(my - size.y + 1);
	} else if (wrap_mode == 2) {
		dest_x = clamp(dest_x, 0, size.x - 1);
		dest_y = clamp(dest_y, 0, size.y - 1);
	} else {
		dest_x = ((dest_x % size.x) + size.x) % size.x;
		dest_y = ((dest_y % size.y) + size.y) % size.y;
	}

	vec2 clip = (vec2(dest_x, dest_y) + 0.5) / vec2(size) * 2.0 - 1.0;
	gl_Position = vec4(clip, 0.0, 1.0);
	gl_PointSize = 1.0;
	v_color = vec4(src.rgb * lum * lum, 0.0);
}
