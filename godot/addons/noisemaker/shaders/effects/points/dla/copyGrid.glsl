#version 450
// Copy Pass - Blit grid to write buffer for proper blending
layout(set = 0, binding = 1) uniform sampler2D gridTex;
layout(location = 0) out vec4 fragColor;
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    fragColor = texture(gridTex, uv);
}
