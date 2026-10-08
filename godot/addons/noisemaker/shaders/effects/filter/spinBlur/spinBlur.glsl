#version 450
// filter/spinBlur program spinBlur — ported from glsl/spinBlur.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Spin Blur - rotational blur around a center point (Radial
 * Blur, Spin mode). Averages a fixed N-tap comb; each tap resamples the
 * input after rotating the pixel's offset-from-center by
 * theta_i = (i/(N-1) - 0.5) * radians(amount) around (centerX, centerY),
 * aspect-corrected exactly the way filter/pinch's rotate2D corrects its
 * own distortion (multiply x by aspect before rotating, divide after).
 * A per-pixel hash shifts the whole tap comb by up to half an angular
 * step to hide banding from the fixed tap count.
 */
const int N = 32;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Rotate uv around center by angle, aspect-corrected exactly as
// filter/pinch's rotate2D corrects its own distortion.
vec2 rotateAround(vec2 uv, vec2 center, float angle, float aspectRatio_) {
    vec2 p = uv;
    p.x *= aspectRatio_;
    vec2 c = center;
    c.x *= aspectRatio_;
    p -= c;
    float s = sin(angle);
    float co = cos(angle);
    p = mat2(co, -s, s, co) * p;
    p += c;
    p.x /= aspectRatio_;
    return p;
}

void main() {
    float aspectRatio_ = fullResolution.x / fullResolution.y;
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 uv = globalCoord / fullResolution;
    vec2 center = vec2(centerX, centerY);

    float arc = radians(amount);
    float angularStep = arc / float(N - 1);
    // Mirror-invariant global coordinates, continuous across tiled renders.
    vec2 jitterCoord = vec2(globalCoord.x,
        abs(globalCoord.y - fullResolution.y * 0.5));
    float jitter = (hash12(jitterCoord) - 0.5) * angularStep;

    vec4 sum = vec4(0.0);
    for (int i = 0; i < N; i++) {
        float theta = (float(i) / float(N - 1) - 0.5) * arc + jitter;
        vec2 distorted = clamp(rotateAround(uv, center, theta, aspectRatio_), 0.0, 1.0);
        vec2 sampleUV = clamp((distorted * fullResolution - tileOffset) / resolution, 0.0, 1.0);
        sum += texture(inputTex, sampleUV);
    }
    fragColor = sum / float(N);
}
