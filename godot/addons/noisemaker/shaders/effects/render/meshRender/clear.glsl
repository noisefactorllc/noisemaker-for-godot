#version 450
// Clear pass - fill with background color (premultiplied alpha)
layout(location = 0) out vec4 fragColor;
void main() {
    fragColor = vec4(bgColor * bgAlpha, bgAlpha);
}
