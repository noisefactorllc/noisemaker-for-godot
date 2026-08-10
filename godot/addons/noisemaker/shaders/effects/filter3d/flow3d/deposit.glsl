#version 450
// Flow3D deposit fragment shader - outputs agent color at point position

layout(location = 0) in vec4 vColor;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = vColor;
}
