#version 450
// filter/highPass program hpCombine — ported from glsl/hpCombine.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * High pass - combine pass: hp = src - blur + 0.5 gray, optional luminance-only
 */
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    vec4 src = texture(inputTex, uv);
    vec4 blur = texture(blurTex, uv);
    vec3 diff = src.rgb - blur.rgb;
    vec3 hp = (mono != 0.0) ? vec3(lum(diff) + 0.5) : (diff + 0.5);
    fragColor = vec4(clamp(hp, 0.0, 1.0), src.a);
}
