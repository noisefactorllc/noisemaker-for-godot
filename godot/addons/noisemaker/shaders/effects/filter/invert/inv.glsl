#version 450
// filter/invert program inv — ported from glsl/inv.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Invert brightness effect
 * mode 0 (full, default): simple RGB inversion, 1.0 - value
 * mode 1 (solarize): Solarize parity, min(v, 1.0 - v) per channel
 *   (PS: output = v <= 128 ? v : 255 - v, equivalent to min(v, 1-v) in 0..1)
 */
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    vec4 color = texture(inputTex, uv);

    // Invert the underlying color and retain premultiplied coverage.
    if (int(mode) == 1) {
        color.rgb = min(color.rgb, color.a - color.rgb);
    } else {
        color.rgb = color.a - color.rgb;
    }

    fragColor = color;
}
