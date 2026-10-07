#version 450
// filter/normalize program reduceMinmax — ported from glsl/reduceMinmax.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

// Reduce pass for intermediate min/max textures
// Input has min in .r, max in .g (from previous reduce pass)
// Samples 16x16 block and outputs new min/max
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 outCoord = ivec2(gl_FragCoord.xy);
    ivec2 inSize = textureSize(inputTex, 0);
    
    // Each output pixel covers a 16x16 area of input
    ivec2 baseCoord = outCoord * 16;
    
    float minVal = 100000.0;
    float maxVal = -100000.0;
    
    // Sample 16x16 block
    for (int dy = 0; dy < 16; dy++) {
        for (int dx = 0; dx < 16; dx++) {
            ivec2 sampleCoord = baseCoord + ivec2(dx, dy);
            
            // Clamp to texture bounds
            if (sampleCoord.x >= inSize.x || sampleCoord.y >= inSize.y) continue;
            
            vec4 color = texelFetch(inputTex, sampleCoord, 0);
            
            // Input has min in .r, max in .g
            minVal = min(minVal, color.r);
            maxVal = max(maxVal, color.g);
        }
    }
    
    fragColor = vec4(minVal, maxVal, 0.0, 1.0);
}
