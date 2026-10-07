#version 450
// filter/relief program rlBlurV — ported from glsl/rlBlurV.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Relief - vertical Gaussian pass.
 *
 * Second half of the separable blur (reads rlBlurH's output). See
 * rlBlurH.glsl for why this blurs rgb rather than luminance directly, and
 * for the smoothness->radius mapping.
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec2 dirPx = vec2(0.0, 1.0);
    float radius = mix(0.5, 15.0, smoothness / 100.0);
    float sigma = max(radius * 0.5, 0.001);
    float fTaps = min(radius, 32.0);
    vec4 sum = texture(inputTex, uv);
    float wsum = 1.0;
    for (int i = 1; i <= 32; i++) {
        if (float(i) > fTaps) { break; }
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        vec2 o = dirPx * float(i) / resolution;
        sum += (texture(inputTex, uv + o) + texture(inputTex, uv - o)) * w;
        wsum += 2.0 * w;
    }
    fragColor = sum / wsum;
}
