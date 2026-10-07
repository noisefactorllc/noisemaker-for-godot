#version 450
// filter/polar program polar — ported from glsl/polar.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Polar and vortex coordinate transforms
 */
const float TAU = 6.28318530718;

float smod(float v, float m) {
    return m * (0.75 - abs(fract(v) - 0.5) - 0.25);
}

vec2 smod2(vec2 v, float m) {
    return m * (0.75 - abs(fract(v) - 0.5) - 0.25);
}

vec2 polarCoords(vec2 uv, float aspect) {
    uv -= 0.5;
    if (aspectLens != 0.0) { uv.x *= aspect; }
    vec2 coord = vec2(atan(uv.y, uv.x) / TAU + 0.5, length(uv) - scale * 0.075);
    coord.x = smod(coord.x + time * -rotation, 1.0);
    coord.y = smod(coord.y + time * speed, 1.0);
    return coord;
}

vec2 vortexCoords(vec2 uv, float aspect) {
    uv -= 0.5;
    if (aspectLens != 0.0) { uv.x *= aspect; }
    float r2 = dot(uv, uv) - scale * 0.01;
    uv = uv / r2;
    uv.x = smod(uv.x + time * -rotation, 1.0);
    uv.y = smod(uv.y + time * speed, 1.0);
    return uv;
}

void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 tileDims = vec2(texSize);
    vec2 fullRes = fullResolution.x > 0.0 ? fullResolution : tileDims;
    vec2 uv = (gl_FragCoord.xy + tileOffset) / fullRes;
    float aspect = fullRes.x / fullRes.y;

    vec2 coord;
    if (int(polarMode) == 0) {
        coord = polarCoords(uv, aspect);
    } else {
        coord = vortexCoords(uv, aspect);
    }

    if (antialias != 0.0) {
        vec2 dx = dFdx(coord);
        vec2 dy = dFdy(coord);
        vec4 col = vec4(0.0);
        col += texture(inputTex, coord + dx * -0.375 + dy * -0.125);
        col += texture(inputTex, coord + dx *  0.125 + dy * -0.375);
        col += texture(inputTex, coord + dx *  0.375 + dy *  0.125);
        col += texture(inputTex, coord + dx * -0.125 + dy *  0.375);
        fragColor = col * 0.25;
    } else {
        fragColor = texture(inputTex, coord);
    }
}
