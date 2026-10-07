#version 450
// filter/unsharpMask program usmCombine — ported from glsl/usmCombine.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Unsharp mask - combine pass: out = img + amount * (img - blur), threshold-gated
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec4 src = texture(inputTex, uv);
    vec4 blur = texture(blurTex, uv);
    vec3 diff = src.rgb - blur.rgb;
    // Soft threshold gate (PS levels 0-255 mapped to 0-100 param): fade in the
    // effect over a half-level band above the threshold to avoid banding.
    float t = threshold / 100.0;
    float mag = max(max(abs(diff.r), abs(diff.g)), abs(diff.b));
    float gate = smoothstep(t, t + 0.02, mag);
    vec3 outc = src.rgb + diff * (amount / 100.0) * gate;
    fragColor = vec4(clamp(outc, 0.0, 1.0), src.a);
}
