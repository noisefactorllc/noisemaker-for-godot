#version 450
// filter/bloom program composite — ported from glsl/composite.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D bloomTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Bloom composite pass
 * Adds tinted bloom to the original HDR scene
 * All operations in linear color space
 */
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 coord = ivec2(gl_FragCoord.xy);
    
    // Get original scene color (HDR)
    vec4 sceneColor = texelFetch(inputTex, coord, 0);
    
    // Get bloom color
    vec3 bloom = texelFetch(bloomTex, coord, 0).rgb;
    
    // Apply tint
    bloom *= tint;

    // Additive blend: finalHDR = sceneColor + intensity * bloom
    vec3 finalRgb = sceneColor.rgb + intensity * bloom;
    
    fragColor = vec4(finalRgb, sceneColor.a);
}
