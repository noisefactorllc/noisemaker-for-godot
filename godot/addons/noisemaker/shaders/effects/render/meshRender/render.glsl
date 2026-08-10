#version 450
layout(location = 0) in vec3 v_normal;
layout(location = 0) out vec4 fragColor;

void main() {
	vec3 normal = normalize(v_normal);
	vec3 light_dir = normalize(lightDirection);
	vec3 view_dir = vec3(0.0, 0.0, 1.0);
	vec3 ambient = ambientColor * meshColor;
	float diffuse_factor = max(dot(normal, light_dir), 0.0);
	vec3 diffuse = diffuseColor * diffuse_factor * meshColor * diffuseIntensity;
	vec3 half_dir = normalize(light_dir + view_dir);
	float specular_factor = pow(max(dot(half_dir, normal), 0.0), shininess);
	vec3 specular = specularColor * specular_factor * specularIntensity;
	float rim = pow(1.0 - max(dot(normal, view_dir), 0.0), rimPower);
	vec3 color = ambient + diffuse + specular + vec3(rim * rimIntensity);
	if (int(wireframe) == 1) {
		vec3 normal_dx = dFdx(v_normal);
		vec3 normal_dy = dFdy(v_normal);
		if (length(normal_dx) + length(normal_dy) < 0.1) {
			discard;
		}
		color = meshColor;
	}
	fragColor = vec4(pow(max(color, vec3(0.0)), vec3(1.0 / 2.2)), 1.0);
}
