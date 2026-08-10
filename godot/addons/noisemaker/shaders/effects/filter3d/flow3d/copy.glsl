#version 450
layout(set = 0, binding = 1) uniform sampler2D sourceTex;
// Copy Pass - Blit source to destination (for ping-pong correction after diffuse)
// This ensures the decayed trail is in the write buffer before deposit blends onto it

layout(location = 0) out vec4 fragColor;

void main() {
    // Use actual texture size, not canvas resolution
    ivec2 texSize = textureSize(sourceTex, 0);
    vec2 uv = gl_FragCoord.xy / vec2(texSize);
    fragColor = texture(sourceTex, uv);
}
