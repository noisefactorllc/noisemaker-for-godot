#version 450
layout(set = 0, binding = 2) uniform sampler2D meshPositions;
layout(set = 0, binding = 3) uniform sampler2D meshNormals;
layout(location = 0) out vec3 v_normal;

mat3 rotation_x(float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat3(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

mat3 rotation_y(float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat3(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

mat3 rotation_z(float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat3(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

void main() {
	ivec2 size = textureSize(meshPositions, 0);
	int x = gl_VertexIndex % size.x;
	int y = gl_VertexIndex / size.x;
	vec3 position = texelFetch(meshPositions, ivec2(x, y), 0).xyz;
	vec3 normal = texelFetch(meshNormals, ivec2(x, y), 0).xyz;
	position = position * meshScale + vec3(offsetX, offsetY, offsetZ);
	float deg_to_rad = 3.14159265 / 180.0;
	mat3 rotation = rotation_z(rotateZ * deg_to_rad)
		* rotation_y(rotateY * deg_to_rad)
		* rotation_x(rotateX * deg_to_rad);
	vec3 rotated_position = rotation * position;
	vec3 rotated_normal = rotation * normal;
	rotated_position.xy += vec2(posX, posY);
	vec2 clip = rotated_position.xy * viewScale;
	clip.x /= aspectRatio;
	float depth = (rotated_position.z + 10.0) / 20.0;
	gl_Position = vec4(clip, depth, 1.0);
	v_normal = rotated_normal;
}
