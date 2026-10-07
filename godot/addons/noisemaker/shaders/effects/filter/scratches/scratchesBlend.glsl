#version 450
// filter/scratches program scratchesBlend — ported from glsl/scratchesBlend.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D overlayTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main() {
    ivec2 coord = ivec2(gl_FragCoord.xy);
    vec4 base = texelFetch(inputTex, coord, 0);
    vec4 overlay = texelFetch(overlayTex, coord, 0);

    // Scratches use max-blend: bright white lines over image
    float scratchStrength = overlay.a * alpha;
    vec3 result = max(base.rgb, vec3(scratchStrength));
    fragColor = vec4(result, base.a);
}
