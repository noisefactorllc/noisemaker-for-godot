#version 450
// Clear the density texture to zero before deposit
layout(location = 0) out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
