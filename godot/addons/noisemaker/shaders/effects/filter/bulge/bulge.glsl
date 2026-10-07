#version 450
// filter/bulge — ported from glsl/bulge.glsl. No-layout effect: params and engine globals are
// injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Bulge distortion
 */
#define PI 3.14159265359

vec2 rotate2D(vec2 st, float rot, float ar) {
    st.x *= ar;
    float angle = rot * PI;
    st -= vec2(0.5 * ar, 0.5);
    st = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * st;
    st += vec2(0.5 * ar, 0.5);
    st.x /= ar;
    return st;
}

void main() {
    float ar = fullResolution.x / fullResolution.y;
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 uv = globalCoord / fullResolution;

    // Apply rotation before distortion
    uv = rotate2D(uv, rotation / 180.0, ar);

    float intensity = strength * -0.01;

    uv -= 0.5;

    if (aspectLens != 0.0) {
        uv.x *= ar;
    }

    float r = length(uv);
    float effect = pow(r, 1.0 - intensity);
    uv = normalize(uv) * effect;

    if (aspectLens != 0.0) {
        uv.x /= ar;
    }

    uv += 0.5;

    // Apply wrap mode
    if (int(wrap) == 0) {
        // mirror
        uv = abs(mod(uv + 1.0, 2.0) - 1.0);
    } else if (int(wrap) == 1) {
        // repeat
        uv = mod(uv, 1.0);
    } else {
        // clamp
        uv = clamp(uv, 0.0, 1.0);
    }

    // Reverse rotation after distortion
    uv = rotate2D(uv, -rotation / 180.0, ar);

    // Convert distorted global UV back to tile-local for texture sampling.
    // Use fract() to seamlessly wrap samples at tile boundaries.
    vec2 sampleUV = fract((uv * fullResolution - tileOffset) / resolution);

    if (antialias != 0.0) {
        // 4x supersample using distortion derivatives for adaptive spread
        vec2 dx = dFdx(sampleUV);
        vec2 dy = dFdy(sampleUV);
        vec4 col = vec4(0.0);
        col += texture(inputTex, sampleUV + dx * -0.375 + dy * -0.125);
        col += texture(inputTex, sampleUV + dx *  0.125 + dy * -0.375);
        col += texture(inputTex, sampleUV + dx *  0.375 + dy *  0.125);
        col += texture(inputTex, sampleUV + dx * -0.125 + dy *  0.375);
        fragColor = col * 0.25;
    } else {
        fragColor = texture(inputTex, sampleUV);
    }
}