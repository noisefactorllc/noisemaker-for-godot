#version 450
// filter/flipMirror program flipMirror — ported from glsl/flipMirror.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Flip/Mirror effect
 * Apply horizontal/vertical flipping and various mirroring modes
 */
void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 globalUV = globalCoord / fullResolution;

    vec2 warpedUV = globalUV;

    if (int(flipMode) == 1) {
        // flip both
        warpedUV.x = 1.0 - warpedUV.x;
        warpedUV.y = 1.0 - warpedUV.y;
    } else if (int(flipMode) == 2) {
        // flip horizontal
        warpedUV.x = 1.0 - warpedUV.x;
    } else if (int(flipMode) == 3) {
        // flip vertical
        warpedUV.y = 1.0 - warpedUV.y;
    } else if (int(flipMode) == 11) {
        // mirror left to right
        if (warpedUV.x > 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
    } else if (int(flipMode) == 12) {
        // mirror right to left
        if (warpedUV.x < 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
    } else if (int(flipMode) == 13) {
        // mirror up to down
        if (warpedUV.y > 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    } else if (int(flipMode) == 14) {
        // mirror down to up
        if (warpedUV.y < 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    } else if (int(flipMode) == 15) {
        // mirror left to right, up to down
        if (warpedUV.x > 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
        if (warpedUV.y > 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    } else if (int(flipMode) == 16) {
        // mirror left to right, down to up
        if (warpedUV.x > 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
        if (warpedUV.y < 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    } else if (int(flipMode) == 17) {
        // mirror right to left, up to down
        if (warpedUV.x < 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
        if (warpedUV.y > 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    } else if (int(flipMode) == 18) {
        // mirror right to left, down to up
        if (warpedUV.x < 0.5) {
            warpedUV.x = 1.0 - warpedUV.x;
        }
        if (warpedUV.y < 0.5) {
            warpedUV.y = 1.0 - warpedUV.y;
        }
    }

    vec2 localUV = fract((warpedUV * fullResolution - tileOffset) / vec2(texSize));
    fragColor = texture(inputTex, localUV);
}