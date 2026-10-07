#version 450
// filter/rotate program rot — ported from glsl/rot.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Rotate image 0..1 (0..360 degrees)
 */
const float TAU = 6.283185307179586;

mat2 rotate2D(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c);
}

void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    
    // Animate rotation: full continuous rotation
    float angle = rotation;
    if (int(speed) != 0) {
        angle += time * 360.0 * float(int(speed));
    }

    // Center, correct aspect, rotate, uncorrect, uncenter
    float aspect = float(texSize.x) / float(texSize.y);
    vec2 center = vec2(0.5);
    uv -= center;
    uv.x *= aspect;
    uv = rotate2D(-angle * TAU / 360.0) * uv;
    uv.x /= aspect;
    uv += center;
    
    // Apply wrap mode
    if (int(wrap) == 0) {
        // mirror
        uv = abs(mod(uv + 1.0, 2.0) - 1.0);
    } else if (int(wrap) == 1) {
        // repeat
        uv = fract(uv);
    } else {
        // clamp
        uv = clamp(uv, 0.0, 1.0);
    }

    fragColor = texture(inputTex, uv);
}
