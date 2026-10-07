#version 450
// filter/step program step — ported from glsl/step.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Step threshold effect
 * Creates hard edge at threshold value
 */
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    vec4 color = texture(inputTex, uv);

    if (antialias != 0.0) {
        vec3 fw = fwidth(color.rgb);
        color.rgb = smoothstep(threshold - fw * 0.5, threshold + fw * 0.5, color.rgb);
    } else {
        color.rgb = step(threshold, color.rgb);
    }

    fragColor = color;
}
