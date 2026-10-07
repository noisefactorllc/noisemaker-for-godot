#version 450
// filter/normalize program apply — ported from glsl/apply.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D statsTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    ivec2 coord = ivec2(gl_FragCoord.xy);
    vec4 color = texelFetch(inputTex, coord, 0);
    
    // Read stats from the 1x1 texture
    vec4 stats = texelFetch(statsTex, ivec2(0, 0), 0);
    float minVal = stats.r;
    float maxVal = stats.g;
    
    // Avoid divide by zero
    if (maxVal - minVal < 0.00001) {
        fragColor = color;
        return;
    }
    
    vec3 normalized = (color.rgb - minVal) / (maxVal - minVal);
    fragColor = vec4(normalized, color.a);
}
