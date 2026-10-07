#version 450
// filter/watercolor program wcSeed — ported from glsl/wcSeed.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Watercolor - seed pass: copies the source image into the ping-pong state
 * texture before the iterated stride-median simplify passes run.
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    fragColor = texture(inputTex, uv);
}
