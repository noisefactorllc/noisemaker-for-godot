#version 450
// filter/chrome program chBlurH — ported from glsl/chBlurH.glsl. No-layout effect: params and engine globals
// are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Chrome - horizontal Gaussian pass.
 *
 * Separable Gaussian blur of the source image. The blurred result
 * feeds chBlurV, and chMap reads its luminance as the height field driving
 * the self-distortion and oscillating tone curve.
 *
 * radius = mix(1.0, 16.0, smoothness/100): higher smoothness -> larger
 * blur radius -> coarser, larger chrome bands (Chrome's
 * "Smoothness" slider maps to feature scale).
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec2 dirPx = vec2(1.0, 0.0);
    float radius = mix(1.0, 16.0, smoothness / 100.0);
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
