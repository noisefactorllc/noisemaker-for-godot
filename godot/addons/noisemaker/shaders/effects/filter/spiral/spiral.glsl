#version 450
// filter/spiral — ported from glsl/spiral.glsl. No-layout effect: params and engine globals are
// injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Spiral distortion
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
    // Compute distortion in global UV space so the spiral center is
    // at the full image center, not each tile's center.
    float ar = fullResolution.x / fullResolution.y;
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 uv = globalCoord / fullResolution;

    // Apply rotation before distortion
    uv = rotate2D(uv, rotation / 180.0, ar);

    uv -= 0.5;

    if (aspectLens != 0.0) {
        uv.x *= ar;
    }

    // Convert to polar coordinates
    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Apply spiral distortion
    float spiralAmt = (strength * 0.05) * r;
    a += spiralAmt - (time * TAU * float(int(speed)) * sign(strength));

    // Convert back to cartesian coordinates
    uv = vec2(cos(a), sin(a)) * r;

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
    // When not tiling, tileOffset=0 and fullResolution=resolution, so this
    // is a no-op (identity transform). Clamp to tile bounds so that wrap
    // modes referencing other parts of the image don't sample past this
    // tile's coverage (producing edge-clamped stripes).
    vec2 sampleUV = clamp((uv * fullResolution - tileOffset) / resolution, 0.0, 1.0);

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
