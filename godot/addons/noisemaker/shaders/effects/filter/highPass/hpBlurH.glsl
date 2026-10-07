#version 450
// filter/highPass program hpBlurH — ported from glsl/hpBlurH.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * High pass - horizontal Gaussian pass
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec2 dirPx = vec2(1.0, 0.0);
    float sigma = max(radius * 0.5, 0.001);
    float fTaps = min(radius, 32.0);
    // Beyond 32 taps we can't add more samples (bounded loop), so widen the
    // spacing between them to keep the kernel reaching the full radius.
    float stride = radius > 32.0 ? radius / 32.0 : 1.0;
    vec4 sum = texture(inputTex, uv);
    float wsum = 1.0;
    for (int i = 1; i <= 32; i++) {
        if (float(i) > fTaps) { break; }
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        vec2 o = dirPx * float(i) * stride / resolution;
        sum += (texture(inputTex, uv + o) + texture(inputTex, uv - o)) * w;
        wsum += 2.0 * w;
    }
    fragColor = sum / wsum;
}
