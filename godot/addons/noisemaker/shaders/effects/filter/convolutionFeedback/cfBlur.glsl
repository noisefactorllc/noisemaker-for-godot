#version 450
// filter/convolutionFeedback program cfBlur — ported from glsl/cfBlur.glsl. No-layout effect: params and engine globals
// are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Convolution Feedback - Blur Pass
 * Applies Gaussian blur with configurable radius and amount
 */
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    ivec2 coord = ivec2(gl_FragCoord.xy);

    vec4 center = texelFetch(inputTex, coord, 0);

    int scaledRadius = int(float(int(blurRadius)) * renderScale);

    if (scaledRadius <= 0 || blurAmount <= 0.0) {
        fragColor = center;
        return;
    }

    // Compute sigma for Gaussian (radius ~= 2*sigma for good coverage)
    float sigma = float(scaledRadius) / 2.0;
    float sigma2 = sigma * sigma;
    
    vec3 sum = vec3(0.0);
    float weightSum = 0.0;
    
    for (int ky = -scaledRadius; ky <= scaledRadius; ky++) {
        for (int kx = -scaledRadius; kx <= scaledRadius; kx++) {
            ivec2 samplePos = coord + ivec2(kx, ky);
            samplePos = clamp(samplePos, ivec2(0), texSize - 1);
            
            float dist2 = float(kx * kx + ky * ky);
            float weight = exp(-dist2 / (2.0 * sigma2));
            
            vec4 texSample = texelFetch(inputTex, samplePos, 0);
            sum += texSample.rgb * weight;
            weightSum += weight;
        }
    }
    
    vec3 blurred = sum / weightSum;
    
    // Mix between original and blurred based on blurAmount
    vec3 result = mix(center.rgb, blurred, blurAmount);
    
    fragColor = vec4(result, center.a);
}
