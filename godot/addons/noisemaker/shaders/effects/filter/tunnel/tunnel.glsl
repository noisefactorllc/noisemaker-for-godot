#version 450
// filter/tunnel program tunnel — ported from glsl/tunnel.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Perspective tunnel effect
 * Based on Inigo Quilez's tunnel shader
 * MIT License
 */
const float PI = 3.14159265359;
const float TAU = 6.28318530718;

float polygonShape(vec2 uv, int sides) {
    float a = atan(uv.x, uv.y) + PI;
    float r = TAU / float(sides);
    return cos(floor(0.5 + a / r) * r - a) * length(uv);
}

vec2 smod(vec2 v, float m) {
    return m * (0.75 - abs(fract(v) - 0.5) - 0.25);
}

void main() {
    ivec2 texSize = textureSize(inputTex, 0);
    vec2 tileDims = vec2(texSize);
    vec2 fullRes = fullResolution.x > 0.0 ? fullResolution : tileDims;
    vec2 uv = (gl_FragCoord.xy + tileOffset) / fullRes;

    // Center the coordinates
    vec2 centered = uv - 0.5;

    // Optional aspect ratio correction
    float ar = fullRes.x / fullRes.y;
    if (aspectLens != 0.0) { centered.x *= ar; }
    
    float a = atan(centered.y, centered.x);
    float r;
    
    if (int(shape) == 0) {
        // Circle
        r = length(centered);
    } else if (int(shape) == 1) {
        // Triangle
        r = polygonShape(centered * 2.0, 3);
    } else if (int(shape) == 2) {
        // Rounded square (superellipse)
        vec2 p = centered * centered * centered * centered * centered * centered * centered * centered;
        r = pow(p.x + p.y, 1.0 / 8.0);
    } else if (int(shape) == 3) {
        // Square
        r = polygonShape(centered * 2.0, 4);
    } else if (int(shape) == 4) {
        // Hexagon
        r = polygonShape(centered * 2.0, 6);
    } else {
        // Octagon
        r = polygonShape(centered * 2.0, 8);
    }
    
    // Apply scale
    r -= scale * 0.15;
    
    // Create tunnel coordinates
    vec2 tunnelCoords = smod(vec2(
        0.3 / r + time * speed,
        a / PI + time * rotation
    ), 1.0);
    
    // Sample with optional supersampling
    vec4 color;
    if (antialias != 0.0) {
        vec2 dx = dFdx(tunnelCoords);
        vec2 dy = dFdy(tunnelCoords);
        color = vec4(0.0);
        color += texture(inputTex, tunnelCoords + dx * -0.375 + dy * -0.125);
        color += texture(inputTex, tunnelCoords + dx *  0.125 + dy * -0.375);
        color += texture(inputTex, tunnelCoords + dx *  0.375 + dy *  0.125);
        color += texture(inputTex, tunnelCoords + dx * -0.125 + dy *  0.375);
        color *= 0.25;
    } else {
        color = texture(inputTex, tunnelCoords);
    }

    // Center vignette: smooth falloff to hide moiré at vanishing point
    if (center != 0.0) {
        float centerMask = smoothstep(0.0, 0.5, r);
        float amt = center / 100.0;
        if (amt < 0.0) {
            color.rgb *= mix(1.0, centerMask, -amt);
        } else {
            color.rgb = mix(color.rgb, vec3(1.0), (1.0 - centerMask) * amt);
        }
    }

    fragColor = color;
}
