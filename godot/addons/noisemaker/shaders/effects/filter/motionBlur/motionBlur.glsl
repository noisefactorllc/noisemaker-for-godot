#version 450
// filter/motionBlur program motionBlur — ported from glsl/motionBlur.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D selfTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Motion Blur - Simple frame blending shader.
 * Mixes current input with previous frame for a motion blur effect.
 * Amount 0-100 maps to mix factor (stronger at higher values).
 */
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    
    // If resetState is true, bypass feedback and return input directly
    if (resetState != 0.0) {
        fragColor = texture(inputTex, uv);
        return;
    }

    vec4 current = texture(inputTex, uv);
    vec4 previous = texture(selfTex, uv);
    
    // Map amount 0-100 to 0-0.8 (clamped)
    float mixFactor = clamp(amount * 0.008, 0.0, 0.98);
    
    fragColor = mix(current, previous, mixFactor);
}
