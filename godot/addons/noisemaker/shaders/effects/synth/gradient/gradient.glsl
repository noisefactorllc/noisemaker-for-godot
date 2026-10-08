#version 450
// synth/gradient program gradient — ported from glsl/gradient.glsl. Declared-layout effect: the shader names each layout slot with a #define;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[8]; };
#define resolution data[0].xy
#define time data[0].z
#define speed data[0].w
#define rotation data[1].x
#define gradientType data[1].y
#define repeat data[1].z
#define colorCount data[1].w
#define seed data[2].x
#define color1 data[3].xyz
#define color2 data[4].xyz
#define color3 data[5].xyz
#define color4 data[6].xyz
#define tileOffset data[7].xy
#define fullResolution data[7].zw
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Gradient generator shader.
 * Renders linear, radial, conic, and four corners gradients with rotation and repeat.
 */
#define PI 3.14159265359
#define TAU 6.28318530718

vec2 rotate2D(vec2 st, float angle) {
    float aspectRatio_ = fullResolution.x / fullResolution.y;
    st.x *= aspectRatio_;
    st -= vec2(aspectRatio_ * 0.5, 0.5);
    float c = cos(angle);
    float s = sin(angle);
    st = mat2(c, -s, s, c) * st;
    st += vec2(aspectRatio_ * 0.5, 0.5);
    st.x /= aspectRatio_;
    return st;
}

vec3 getColor(int idx) {
    if (idx == 0) return color1;
    if (idx == 1) return color2;
    if (idx == 2) return color3;
    return color4;
}

// Blend colors based on a 0-1 parameter t, cycling through colorCount colors
vec3 blendColors(float t) {
    t = fract(t);
    float segment = t * float(int(colorCount));
    int idx = int(floor(segment));
    float localT = fract(segment);
    int next = idx + 1;
    if (next >= int(colorCount)) next = 0;
    return mix(getColor(idx), getColor(next), localT);
}

// PCG PRNG for noise gradient
uvec3 pcg(uvec3 v) {
    v = v * uint(1664525) + uint(1013904223);
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> uint(16);
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}

vec3 prng(vec3 p) {
    p.x = p.x >= 0.0 ? p.x * 2.0 : -p.x * 2.0 + 1.0;
    p.y = p.y >= 0.0 ? p.y * 2.0 : -p.y * 2.0 + 1.0;
    p.z = p.z >= 0.0 ? p.z * 2.0 : -p.z * 2.0 + 1.0;
    return vec3(pcg(uvec3(p))) / float(uint(0xffffffff));
}

// Value noise using PCG
float hash2D(vec2 p) {
    return prng(vec3(p, float(int(seed)))).x;
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash2D(i);
    float b = hash2D(i + vec2(1.0, 0.0));
    float c = hash2D(i + vec2(0.0, 1.0));
    float d = hash2D(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbmNoise(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    float maxVal = 0.0;
    for (int i = 0; i < 4; i++) {
        sum += valueNoise(p * freq) * amp;
        maxVal += amp;
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum / maxVal;
}

void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec2 st = globalCoord / fullResolution;
    float aspectRatio_ = fullResolution.x / fullResolution.y;
    
    // Convert rotation from degrees to radians
    float angle = -rotation * PI / 180.0;
    
    // Apply rotation for linear and conic gradients
    vec2 rotatedSt = rotate2D(st, angle);
    
    // Centered coordinates for radial and conic
    vec2 centered = st - 0.5;
    centered.x *= aspectRatio_;
    
    // Rotated centered for conic
    vec2 rotatedCentered = centered;
    float c = cos(angle);
    float s = sin(angle);
    rotatedCentered = mat2(c, -s, s, c) * centered;
    
    vec3 color;
    float t;
    float timeOffset = time * speed;

    if (int(gradientType) == 0) {
        // Conic/angular gradient
        float a = atan(rotatedCentered.y, rotatedCentered.x);
        t = (a + PI) / TAU;
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    } else if (int(gradientType) == 1) {
        // Diamond gradient - L1 distance with rotation
        t = abs(rotatedCentered.x) + abs(rotatedCentered.y);
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    } else if (int(gradientType) == 2) {
        // Four corners - bilinear interpolation
        // 4: TL=c1 TR=c2 BL=c3 BR=c4
        // 3: TL=c1 TR=c2 BL=c3 BR=c3
        // 2: TL=c1 TR=c1 BL=c2 BR=c2
        vec2 cornerSt = rotate2D(st, angle);
        vec3 cTL = color1;
        vec3 cTR = int(colorCount) >= 3 ? color2 : color1;
        vec3 cBL = int(colorCount) >= 3 ? color3 : color2;
        vec3 cBR = int(colorCount) >= 4 ? color4 : cBL;
        vec3 top = mix(cTL, cTR, cornerSt.x);
        vec3 bottom = mix(cBL, cBR, cornerSt.x);
        color = mix(bottom, top, cornerSt.y);
    } else if (int(gradientType) == 3) {
        // Linear gradient along rotated y-axis
        t = rotatedSt.y;
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    } else if (int(gradientType) == 4) {
        // Noise gradient with rotation
        vec2 noiseSt = rotatedCentered * 4.0;
        t = fbmNoise(noiseSt);
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    } else if (int(gradientType) == 5) {
        // Radial gradient from center
        vec2 rotatedPoint = mat2(c, -s, s, c) * centered;
        float dist = length(rotatedPoint) * 2.0;
        t = dist;
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    } else if (int(gradientType) == 6) {
        // Spiral gradient - angle + distance
        float a = atan(rotatedCentered.y, rotatedCentered.x);
        float dist = length(centered);
        t = fract(a / TAU + dist * 2.0);
        t = fract(t * float(int(repeat)) + timeOffset);
        color = blendColors(t);
    }

    fragColor = vec4(color, 1.0);
}
