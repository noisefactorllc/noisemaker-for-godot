#version 450
// filter/sine program sine — ported from glsl/sine.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Sine wave distortion
 * RGB mode: apply sine to R, G, B independently
 * Non-RGB mode: convert to luminance, apply sine, output grayscale
 */
float normalized_sine(float value) {
    return (sin(value) + 1.0) * 0.5;
}

void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    vec4 color = texture(inputTex, uv);

    bool use_rgb = colorMode > 0.5;

    if (use_rgb) {
        color.r = normalized_sine(color.r * amount);
        color.g = normalized_sine(color.g * amount);
        color.b = normalized_sine(color.b * amount);
    } else {
        float lum = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
        float result = normalized_sine(lum * amount);
        color.rgb = vec3(result);
    }

    fragColor = color;
}
