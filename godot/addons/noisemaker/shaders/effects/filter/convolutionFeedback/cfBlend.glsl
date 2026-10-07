#version 450
// filter/convolutionFeedback program cfBlend — ported from glsl/cfBlend.glsl. No-layout effect: params and engine globals
// are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D feedbackTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Convolution Feedback - Blend Pass
 * Blends processed feedback texture with input based on intensity
 */
void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    vec4 inputColor = texelFetch(inputTex, coord, 0);
    
    // If resetState is true, bypass feedback and return input directly
    if (resetState != 0.0) {
        fragColor = inputColor;
        return;
    }
    
    vec4 feedback = texelFetch(feedbackTex, coord, 0);
    
    // Blend input with processed feedback based on intensity
    vec3 result = mix(inputColor.rgb, feedback.rgb, intensity);
    
    fragColor = vec4(result, inputColor.a);
}
