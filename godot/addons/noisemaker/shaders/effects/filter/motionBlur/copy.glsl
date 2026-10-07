#version 450
// filter/motionBlur program copy — ported from glsl/copy.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Simple copy/blit shader - copies input to output unchanged.
 * Used for feedback texture updates.
 */
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    fragColor = texture(inputTex, uv);
}
