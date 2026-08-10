#version 450
/*
 * Chromatic aberration effect.
 */
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) out vec4 fragColor;
void main() {
    vec2 globalPixel = gl_FragCoord.xy + tileOffset;
    vec2 globalUV = globalPixel / fullResolution;

    float maxDisplacementUV = 256.0 / fullResolution.x;
    float boundedDisplacement = clamp(displacement, -maxDisplacementUV, maxDisplacementUV);

    vec2 redGlobalUV = globalUV + vec2(boundedDisplacement, 0.0);
    vec2 redLocalUV = (redGlobalUV * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
    vec4 red = texture(inputTex, redLocalUV);

    vec2 greenLocalUV = (globalUV * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
    vec4 green = texture(inputTex, greenLocalUV);

    vec2 blueGlobalUV = globalUV - vec2(boundedDisplacement, 0.0);
    vec2 blueLocalUV = (blueGlobalUV * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
    vec4 blue = texture(inputTex, blueLocalUV);

    fragColor = vec4(red.r, green.g, blue.b, green.a);
}
