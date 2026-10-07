#version 450
// mixer/channelCombine program channelCombine — ported from glsl/channelCombine.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D rTex;
layout(set = 0, binding = 2) uniform sampler2D gTex;
layout(set = 0, binding = 3) uniform sampler2D bTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

float luminance(vec4 c) {
    return dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 st = globalCoord / fullResolution;

    float r = luminance(texture(rTex, gl_FragCoord.xy / vec2(textureSize(rTex, 0)))) * rLevel / 100.0;
    float g = luminance(texture(gTex, gl_FragCoord.xy / vec2(textureSize(gTex, 0)))) * gLevel / 100.0;
    float b = luminance(texture(bTex, gl_FragCoord.xy / vec2(textureSize(bTex, 0)))) * bLevel / 100.0;

    fragColor = vec4(r, g, b, 1.0);
}
