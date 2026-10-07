#version 450
// filter/celShading program celShadingBlend — ported from glsl/celShadingBlend.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D colorTex;
layout(set = 0, binding = 3) uniform sampler2D edgeTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Cel Shading - Blend Pass
 * Combines cel-shaded color with edge outlines
 */
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);

    vec4 origColor = texture(inputTex, uv);
    vec4 celColor = texture(colorTex, uv);
    float edgeStrength = texture(edgeTex, uv).r;

    // Apply edge color where edges are detected
    vec3 finalColor = mix(celColor.rgb, edgeColor, edgeStrength);

    // Mix with original based on mix amount
    finalColor = mix(origColor.rgb, finalColor, mixAmount);

    fragColor = vec4(finalColor, origColor.a);
}
