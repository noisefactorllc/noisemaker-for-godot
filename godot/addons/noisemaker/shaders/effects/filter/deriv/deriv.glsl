#version 450
// filter/deriv program deriv — ported from glsl/deriv.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Derivative-based edge detection
 * Computes image derivatives to highlight edges
 */
vec3 desaturate(vec3 color) {
    float avg = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
    return vec3(avg);
}

void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 texelSize = 1.0 / vec2(texSize);
    vec2 localUV = gl_FragCoord.xy * texelSize;
    
    float radiusPixels = amount * renderScale;
    radiusPixels = min(radiusPixels, 256.0);
    
    vec4 color = texture(inputTex, localUV);
    vec3 center = desaturate(color.rgb);
    vec3 right = desaturate(texture(inputTex, localUV + vec2(radiusPixels, 0.0) * texelSize).rgb);
    vec3 bottom = desaturate(texture(inputTex, localUV + vec2(0.0, radiusPixels) * texelSize).rgb);
    
    vec3 dx = center - right;
    vec3 dy = center - bottom;
    
    float dist = distance(dx, dy) * 2.5;
    
    fragColor = vec4(clamp(color.rgb * dist, 0.0, 1.0), color.a);
}