#version 450
// filter/sharpen program sharpen — ported from glsl/sharpen.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Sharpen convolution effect
 * Enhances image detail and edges
 */
void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 res = vec2(texSize);
    vec2 uv = globalCoord / fullResolution;
    vec2 texelSize = 1.0 / res;
    
    vec4 origColor = texture(inputTex, gl_FragCoord.xy / vec2(textureSize(inputTex, 0)));
    
    // Sharpen kernel
    // -1  0 -1
    //  0  5  0
    // -1  0 -1
    float kernel[9];
    kernel[0] = -1.0; kernel[1] = 0.0; kernel[2] = -1.0;
    kernel[3] = 0.0;  kernel[4] = 5.0; kernel[5] = 0.0;
    kernel[6] = -1.0; kernel[7] = 0.0; kernel[8] = -1.0;
    
    vec2 offsets[9];
    offsets[0] = vec2(-texelSize.x, -texelSize.y);
    offsets[1] = vec2(0.0, -texelSize.y);
    offsets[2] = vec2(texelSize.x, -texelSize.y);
    offsets[3] = vec2(-texelSize.x, 0.0);
    offsets[4] = vec2(0.0, 0.0);
    offsets[5] = vec2(texelSize.x, 0.0);
    offsets[6] = vec2(-texelSize.x, texelSize.y);
    offsets[7] = vec2(0.0, texelSize.y);
    offsets[8] = vec2(texelSize.x, texelSize.y);
    
    vec3 conv = vec3(0.0);
    
    for (int i = 0; i < 9; i++) {
        vec3 texSample = texture(inputTex, ((uv + offsets[i] * amount * renderScale) * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0))).rgb;
        conv += texSample * kernel[i];
    }
    
    fragColor = vec4(clamp(conv, 0.0, 1.0), origColor.a);
}
