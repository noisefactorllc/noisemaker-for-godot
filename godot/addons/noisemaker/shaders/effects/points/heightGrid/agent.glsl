#version 450
// points/heightGrid program agent — ported from glsl/agent.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D xyzTex;
layout(set = 0, binding = 2) uniform sampler2D velTex;
layout(set = 0, binding = 3) uniform sampler2D heightTex;
layout(set = 0, binding = 4) uniform sampler2D diffuseTex;
layout(location = 0) in vec2 v_uv;

layout(location = 0) out vec4 outXYZ;
layout(location = 1) out vec4 outVel;
layout(location = 2) out vec4 outRGBA;

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    ivec2 stateSize = textureSize(xyzTex, 0);
    // pointsEmit allocates a square state texture: one grid vertex per slot.
    vec2 uv = (vec2(coord) + 0.5) / vec2(stateSize);
    vec3 heightColor = texture(heightTex, uv).rgb;
    float elevation = dot(heightColor, vec3(0.2126, 0.7152, 0.0722));
    // XZ ground plane, Y elevation. These are world coordinates, not UVs.
    outXYZ = vec4((uv.x - 0.5) * gridScale,
        elevation * heightScale + heightOffset,
        (uv.y - 0.5) * gridScale, 1.0);
    outVel = vec4(0.0, 0.0, 0.0, texelFetch(velTex, coord, 0).w);
    outRGBA = texture(diffuseTex, uv);
}
