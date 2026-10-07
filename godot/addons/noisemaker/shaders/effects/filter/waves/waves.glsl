#version 450
// filter/waves — ported from glsl/waves.glsl. No-layout effect: params and engine globals are
// injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Sine wave distortion
 */
#define PI 3.14159265359
#define TAU 6.28318530718

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

    // Sine wave distortion
    float displacement = sin(uv.x * scale * 10.0 + time * TAU * float(int(speed))) * (strength * 0.01);
    
    // Bound displacement to overlap in tile mode to prevent seams
    if (any(notEqual(tileOffset, vec2(0.0)))) {
        float maxDisplacementUV = 256.0 / fullResolution.y;
        displacement = clamp(displacement, -maxDisplacementUV, maxDisplacementUV);
    }
    
    uv.y += displacement;

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

    // Convert distorted global UV to tile-local UV.
    vec2 localCoord = (uv * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
    
    // In tile mode, wrap to enable seamless tiling. In normal mode, clamp to preserve original behavior.
    vec2 sampleUV = any(notEqual(tileOffset, vec2(0.0))) ? fract(localCoord) : clamp(localCoord, 0.0, 1.0);

    if (antialias != 0.0) {
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