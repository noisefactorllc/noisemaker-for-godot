#version 450
// synth/bitwise program bitwise — ported from glsl/bitwise.glsl. Declared-layout effect: the shader names each layout slot with a #define;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[6]; };
#define resolution data[0].xy
#define time data[0].z
#define operation data[0].w
#define scale data[1].x
#define offsetX data[1].y
#define offsetY data[1].z
#define mask data[1].w
#define seed data[2].x
#define colorMode data[2].y
#define speed data[2].z
#define rotation data[2].w
#define colorOffset data[3].x
#define tileOffset data[4].xy
#define fullResolution data[4].zw
#define renderScale data[5].x
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

const float PI = 3.14159265358979;

// Branchless HSV to RGB conversion
vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// Perform the selected bitwise/arithmetic operation on two integers,
// mask the result, then normalize to 0..1
float bitOp(int a, int b, int op, int m) {
    int r = 0;
    if (op == 0)      r = a ^ b;           // xor
    else if (op == 1) r = a & b;           // and
    else if (op == 2) r = a | b;           // or
    else if (op == 3) r = ~(a & b);        // nand
    else if (op == 4) r = ~(a ^ b);        // xnor
    else if (op == 5) r = a * b;           // mul
    else if (op == 6) r = a + b;           // add
    else              r = a - b;           // sub
    r = r & m;
    return float(r) / float(m);
}

void main() {
    // Map scale so higher value = bigger cells (lower frequency).
    // Multiply by renderScale so pixel-sized cells scale with export resolution.
    float pixelScale = scale * 0.1 * renderScale;

    // Apply rotation around screen center
    float angle = rotation * PI / 180.0;
    float c = cos(angle);
    float s = sin(angle);
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 centered = globalCoord - fullResolution * 0.5;
    vec2 rotated = vec2(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
    vec2 coord = rotated + fullResolution * 0.5;

    // Time offset — uses 256 (pattern period) so it loops seamlessly at any speed
    int animOffset = int(floor(time * float(int(-speed)) * 256.0));

    // Compute integer coordinates
    int x = int(floor(coord.x / pixelScale)) + int(offsetX) + animOffset;
    int y = int(floor(coord.y / pixelScale)) + int(offsetY);

    // Seed XORs into coordinates (dramatic pattern shifts)
    x = x ^ int(seed);
    y = y ^ (int(seed) * 3);

    float v;
    if (int(colorMode) == 0) {
        // Mono: same operation across all channels
        v = bitOp(x, y, int(operation), int(mask));
        fragColor = vec4(v, v, v, 1.0);
    } else if (int(colorMode) == 1) {
        // RGB: channel-shifted patterns (chromatic aberration)
        float r = bitOp(x, y, int(operation), int(mask));
        float g = bitOp(x + int(colorOffset), y, int(operation), int(mask));
        float b = bitOp(x, y + int(colorOffset), int(operation), int(mask));
        fragColor = vec4(r, g, b, 1.0);
    } else {
        // HSV: bitwise value drives hue, full saturation and value
        // Scale hue to avoid wrapping both ends to red
        v = bitOp(x, y, int(operation), int(mask));
        float hueScale = float(int(mask)) / float(int(mask) + 1);
        fragColor = vec4(hsv2rgb(vec3(v * hueScale, 1.0, 1.0)), 1.0);
    }
}
