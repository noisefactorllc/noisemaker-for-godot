#version 450
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) out vec4 fragColor;
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    fragColor = texture(inputTex, uv);
}
