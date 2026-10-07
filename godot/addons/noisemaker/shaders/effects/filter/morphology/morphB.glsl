#version 450
// filter/morphology program morphB — ported from glsl/morphB.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Morphology - pass B: square shape finishes the separable box structuring
 * element with a vertical-line pass over morphA's horizontal result; round
 * shape is a passthrough copy since morphA already computed the full disc
 * structuring element (min/max over a disc is not separable).
 * mode selects the op: dilate (0) = max, erode (1) = min.
 */

// SHAPE is a compile-time definition (see definition.js `globals.shape.define`).
#ifndef SHAPE
#define SHAPE 0
#endif
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec4 acc = texture(inputTex, uv);

#if SHAPE==0
    vec2 texel = 1.0 / resolution;
    float r = min(radius, 32.0);
    for (int i = 1; i <= 32; i++) {
        if (float(i) > r) { break; }
        vec2 o = vec2(0.0, float(i)) * texel;
        vec4 sD = texture(inputTex, uv - o);
        vec4 sU = texture(inputTex, uv + o);
        vec4 hi = max(acc, max(sD, sU));
        vec4 lo = min(acc, min(sD, sU));
        acc = mix(hi, lo, float(int(mode)));
    }
#endif
    // Round shape: acc is already morphA's disc-SE result; passthrough.

    fragColor = acc;
}
