#version 450
// filter/translate program translate — ported from glsl/translate.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
float nm_param_x() { return x; }
#undef x
float nm_param_y() { return y; }
#undef y
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Translate image X and Y
 */
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    
    // Apply translation
    uv.x = uv.x - nm_param_x();
    uv.y = uv.y - nm_param_y();
    
    // Apply wrap mode
    if (int(wrap) == 0) {
        // mirror
        uv = abs(mod(uv + 1.0, 2.0) - 1.0);
    } else if (int(wrap) == 1) {
        // repeat
        uv = fract(uv);
    } else {
        // clamp
        uv = clamp(uv, 0.0, 1.0);
    }

    fragColor = texture(inputTex, uv);
}
