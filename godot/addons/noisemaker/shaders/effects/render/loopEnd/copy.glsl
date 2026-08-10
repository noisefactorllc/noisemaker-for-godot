#version 450
/*
 * Simple copy/blit shader - copies input to output unchanged.
 * Used for feedback texture updates.
 */
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) out vec4 fragColor;
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    fragColor = texture(inputTex, uv);
}
