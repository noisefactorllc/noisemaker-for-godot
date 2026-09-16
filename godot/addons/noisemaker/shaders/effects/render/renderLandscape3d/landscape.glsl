#version 450
// render/renderLandscape3d (program "landscape") — ported from wgsl/landscape.wgsl.
// Isometric/perspective voxel raymarch with face lighting, consuming a synth3d generator's
// volume+geometry bundle (its own companion generator is synth3d/heightmap3d). No-layout
// effect: backend injects Params UBO for every param except `viewMode` (declared `define:
// "VIEW_MODE"` on the reference global, so it arrives as the bare compile-time identifier
// VIEW_MODE via the existing define-map promotion — no per-pass-defines fix needed here,
// unlike pointsRender/pointsBillboardRender). Inputs (pass.inputs order): volumeCache=1,
// analyticalGeo=2. Engine globals `resolution`/`tileOffset`/`fullResolution` are bare names.
layout(set = 0, binding = 1) uniform sampler2D volumeCache;
layout(set = 0, binding = 2) uniform sampler2D analyticalGeo;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 geoOut;

vec3 lighting(vec3 color, vec3 normal, vec3 viewDirection) {
    vec3 light = vec3(0.0, 1.0, 0.0);
    if (dot(lightDirection, lightDirection) > 0.000001) { light = normalize(lightDirection); }
    vec3 halfVector = light + viewDirection;
    float specular = 0.0;
    if (dot(halfVector, halfVector) > 0.000001) {
        specular = pow(max(dot(normal, normalize(halfVector)), 0.0), 32.0) * specularIntensity;
    }
    return color * (ambient + max(dot(normal, light), 0.0) * diffuseIntensity) + specular;
}

// Inverse of the billboard renderer's X -> Y -> Z rotation.
vec3 inverseRotation(vec3 inputVec) {
    vec3 c = cos(vec3(rotateX, rotateY, rotateZ));
    vec3 s = sin(vec3(rotateX, rotateY, rotateZ));
    vec3 p = vec3(inputVec.x * c.z + inputVec.y * s.z, -inputVec.x * s.z + inputVec.y * c.z, inputVec.z);
    p = vec3(p.x * c.y - p.z * s.y, p.y, p.x * s.y + p.z * c.y);
    return vec3(p.x, p.y * c.x + p.z * s.x, -p.y * s.x + p.z * c.x);
}

vec3 forwardRotation(vec3 inputVec) {
    vec3 c = cos(vec3(rotateX, rotateY, rotateZ));
    vec3 s = sin(vec3(rotateX, rotateY, rotateZ));
    vec3 p = vec3(inputVec.x, inputVec.y * c.x - inputVec.z * s.x, inputVec.y * s.x + inputVec.z * c.x);
    p = vec3(p.x * c.y + p.z * s.y, p.y, -p.x * s.y + p.z * c.y);
    return vec3(p.x * c.z - p.y * s.z, p.x * s.z + p.y * c.z, p.z);
}

struct LandscapeOutput {
    vec4 fragColor;
    vec4 geoOut;
};

LandscapeOutput renderPerspective(vec2 uv) {
    LandscapeOutput result;
    result.fragColor = vec4(bgColor * bgAlpha, bgAlpha);
    result.geoOut = vec4(0.5, 0.5, 1.0, 1.0);
    float size = float(volumeSize);
    float focalLength = 1.0 / tan(clamp(fieldOfView, 10.0, 150.0) * 0.00872664626);
    // The volume spans [-40,40]. Position follows rotation; camera Z is 80.
    vec3 origin = (inverseRotation(vec3(-posX, -posY, 80.0 - posZ)) / 80.0 + 0.5) * size;
    vec2 framedUv = (uv + vec2(panX, panY)) / max(zoom, 0.001);
    vec3 cameraRay = vec3(framedUv * 2.0 / (focalLength * max(viewScale, 0.001)), -1.0);
    vec3 direction = inverseRotation(cameraRay) * (size / 80.0);
    vec3 nearT = vec3(-1e30);
    vec3 farT = vec3(1e30);
    vec3 delta = vec3(1e30);
    ivec3 stepDir = ivec3(0);
    for (int axis = 0; axis < 3; axis++) {
        if (abs(direction[axis]) < 1e-8) {
            if (origin[axis] < 0.0 || origin[axis] >= size) { return result; }
        } else {
            float a = -origin[axis] / direction[axis];
            float b = (size - origin[axis]) / direction[axis];
            nearT[axis] = min(a, b);
            farT[axis] = max(a, b);
            delta[axis] = 1.0 / abs(direction[axis]);
            stepDir[axis] = (direction[axis] > 0.0) ? 1 : -1;
        }
    }
    float enter = max(max(nearT.x, nearT.y), nearT.z);
    float leave = min(min(farT.x, farT.y), farT.z);
    float distance = max(enter, 0.1);
    if (distance >= leave) { return result; }
    ivec3 cell = clamp(ivec3(floor(origin + direction * distance + vec3(stepDir) * 0.0001)), ivec3(0), ivec3(volumeSize - 1));
    vec3 nextT = vec3(1e30);
    for (int axis = 0; axis < 3; axis++) {
        if (stepDir[axis] != 0) {
            float boundary = float(cell[axis]) + ((stepDir[axis] > 0) ? 1.0 : 0.0);
            nextT[axis] = (boundary - origin[axis]) / direction[axis];
        }
    }
    vec3 viewDirection = normalize(-cameraRay);
    vec3 normal = normalize(-direction);
    if (enter >= 0.1) {
        normal = vec3(0.0);
        if (nearT.y >= nearT.x && nearT.y >= nearT.z) { normal.y = -float(stepDir.y); }
        else if (nearT.x >= nearT.z) { normal.x = -float(stepDir.x); }
        else { normal.z = -float(stepDir.z); }
    }
    for (int step = 0; step < volumeSize * 3; step++) {
        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(volumeSize))) || distance >= leave) { break; }
        ivec2 atlas = ivec2(cell.x, cell.y + cell.z * volumeSize);
        float density = texelFetch(analyticalGeo, atlas, 0).a;
        if (density > 0.0 && density >= threshold) {
            vec3 worldNormal = forwardRotation(normal);
            result.fragColor = vec4(lighting(texelFetch(volumeCache, atlas, 0).rgb, worldNormal, viewDirection), 1.0);
            result.geoOut = vec4(worldNormal * 0.5 + 0.5, clamp(distance / 320.0, 0.0, 1.0));
            return result;
        }
        distance = min(min(nextT.x, nextT.y), nextT.z);
        bvec3 crossed = lessThanEqual(nextT, vec3(distance));
        normal = vec3(0.0);
        if (crossed.y) { normal.y = -float(stepDir.y); }
        else if (crossed.x) { normal.x = -float(stepDir.x); }
        else { normal.z = -float(stepDir.z); }
        cell += ivec3(crossed) * stepDir;
        nextT += vec3(crossed) * delta;
    }
    return result;
}

void main() {
    fragColor = vec4(bgColor * bgAlpha, bgAlpha);
    geoOut = vec4(0.5, 0.5, 1.0, 1.0);
    vec2 fullRes = (fullResolution.x > 0.0) ? fullResolution : resolution;
    vec2 uv = (gl_FragCoord.xy + tileOffset - fullRes * 0.5) / fullRes.y;
    // VIEW_MODE is a compile-time #define (bare identifier); the inactive path never runs.
    if (VIEW_MODE == 2) {
        LandscapeOutput persp = renderPerspective(uv);
        fragColor = persp.fragColor;
        geoOut = persp.geoOut;
        return;
    }
    float size = float(volumeSize);
    float aspect = fullRes.x / fullRes.y;
    float span = max(1.6329931619, 1.4142135624 / aspect) * size * 1.08 / max(zoom, 0.001);
    vec3 right = vec3(0.7071067812, 0.0, -0.7071067812);
    vec3 up = vec3(-0.4082482905, 0.8164965809, -0.4082482905);
    vec3 origin = vec3(size * 2.5) + right * (uv.x + panX) * span + up * (uv.y + panY) * span;

    vec3 nearT = origin - size;
    float enter = max(max(nearT.x, nearT.y), nearT.z);
    float leave = min(min(origin.x, origin.y), origin.z);
    if (enter >= leave) { return; }
    float distance = max(enter, 0.0);
    ivec3 cell = clamp(ivec3(floor(origin - (distance + 0.0001))), ivec3(0), ivec3(volumeSize - 1));
    vec3 nextT = origin - vec3(cell);
    vec3 normal = vec3(0.0, 0.0, 1.0);
    if (nearT.y >= nearT.x && nearT.y >= nearT.z) { normal = vec3(0.0, 1.0, 0.0); }
    else if (nearT.x >= nearT.z) { normal = vec3(1.0, 0.0, 0.0); }

    for (int step = 0; step < volumeSize * 3; step++) {
        if (any(lessThan(cell, ivec3(0))) || distance >= leave) { break; }
        ivec2 atlas = ivec2(cell.x, cell.y + cell.z * volumeSize);
        float density = texelFetch(analyticalGeo, atlas, 0).a;
        if (density > 0.0 && density >= threshold) {
            vec3 color = texelFetch(volumeCache, atlas, 0).rgb;
            fragColor = vec4(lighting(color, normal, vec3(0.5773502692)), 1.0);
            geoOut = vec4(normal * 0.5 + 0.5, clamp(distance / (size * 4.0), 0.0, 1.0));
            return;
        }
        distance = min(min(nextT.x, nextT.y), nextT.z);
        bvec3 crossed = lessThanEqual(nextT, vec3(distance));
        if (crossed.y) { normal = vec3(0.0, 1.0, 0.0); }
        else if (crossed.x) { normal = vec3(1.0, 0.0, 0.0); }
        else { normal = vec3(0.0, 0.0, 1.0); }
        cell -= ivec3(crossed);
        nextT += vec3(crossed);
    }
}
