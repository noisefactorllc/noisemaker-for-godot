#version 450
// filter/pixels program pixels — ported from glsl/pixels.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Pixelation effect
 * Reduces image resolution for retro pixel art look
 */
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 tileDims = vec2(texSize);
    vec2 res = fullResolution.x > 0.0 ? fullResolution : tileDims;
    vec2 uv = gl_FragCoord.xy / tileDims;

    if (size < 1.0) {
        fragColor = texture(inputTex, uv);
        return;
    }

    float pixelSize = size;

    float dx = pixelSize / res.x;
    float dy = pixelSize / res.y;

    // Use global UV so pixel grid aligns across tiles
    vec2 globalUV = (gl_FragCoord.xy + tileOffset) / res;
    vec2 centered = globalUV - 0.5;
    vec2 globalCoord = vec2(dx * floor(centered.x / dx), dy * floor(centered.y / dy));
    globalCoord += 0.5;

    // Convert back to tile-local UV for sampling
    vec2 coord = (globalCoord * res - tileOffset) / tileDims;

    fragColor = texture(inputTex, coord);
}
