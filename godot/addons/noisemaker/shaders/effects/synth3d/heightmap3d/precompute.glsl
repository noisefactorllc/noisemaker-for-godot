#version 450
// synth3d/heightmap3d (program "precompute") — ported from wgsl/precompute.wgsl. Voxel
// heightfield: bakes separate height and diffuse-color 2D surfaces into the volume atlas.
// No-layout effect: backend injects Params UBO + `#define volumeSize …`/`heightScale …`/
// `baseHeight …`. Inputs (pass.inputs order): heightTex=1, tex=2.
layout(set = 0, binding = 1) uniform sampler2D heightTex;
layout(set = 0, binding = 2) uniform sampler2D tex;

// MRT outputs: volume cache and geometry buffer
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 geoOut;

// Native atlases and 2D surfaces use the same logical texel coordinates on both backends.
ivec2 imageTexel(ivec2 column, ivec2 size) {
    return clamp(((column * 2 + 1) * size) / (int(volumeSize) * 2), ivec2(0), size - 1);
}

float columnHeight(ivec2 column) {
    vec3 rgb = texelFetch(heightTex, imageTexel(column, textureSize(heightTex, 0)), 0).rgb;
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    return floor(clamp(luminance * heightScale + baseHeight, 0.0, 1.0) * float(volumeSize) + 0.5);
}

float density(ivec3 p) {
    if (any(lessThan(p, ivec3(0))) || any(greaterThanEqual(p, ivec3(int(volumeSize))))) { return 0.0; }
    return (float(p.y) < columnHeight(p.xz)) ? 1.0 : 0.0;
}

void main() {
    ivec2 atlas = ivec2(gl_FragCoord.xy);
    ivec3 p = ivec3(atlas.x, atlas.y % int(volumeSize), atlas.y / int(volumeSize));
    float occupied = density(p);
    fragColor = vec4(0.0);
    geoOut = vec4(0.5, 1.0, 0.5, 0.0);
    if (occupied == 0.0) { return; }

    vec3 color = texelFetch(tex, imageTexel(p.xz, textureSize(tex, 0)), 0).rgb;
    fragColor = vec4(color, occupied);
    vec3 normal = vec3(
        density(p - ivec3(1, 0, 0)) - density(p + ivec3(1, 0, 0)),
        density(p - ivec3(0, 1, 0)) - density(p + ivec3(0, 1, 0)),
        density(p - ivec3(0, 0, 1)) - density(p + ivec3(0, 0, 1))
    );
    if (dot(normal, normal) > 0.0) { normal = normalize(normal); }
    else { normal = vec3(0.0, 1.0, 0.0); }
    geoOut = vec4(normal * 0.5 + 0.5, occupied);
}
