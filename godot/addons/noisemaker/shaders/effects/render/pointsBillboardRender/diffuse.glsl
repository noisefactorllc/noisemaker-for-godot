#version 450
// render/pointsBillboardRender — program "diffuse" (decay the persistent billboard trail).
// Ported from glsl/diffuse.glsl. intensity=100 no decay, 0 instant fade.
// Reference 0ed489ec adds: in additive mode (blendMode==0) with a perspective/ortho view and
// nonzero aperture, the defocus accumulation target (built by the additive-mode deposit
// passes into "defocus", one quarter resolution) is bilinearly upsampled and added in on top
// of the decayed trail — alpha-blend mode never uses the defocus target (its deposit passes
// write straight to the trail with premultiplied alpha compositing instead).
//
// Layout effect: vec4 data[2] (uniformLayouts.diffuse): resolution=data[0].xy,
// intensity=data[0].z, aperture=data[0].w, viewMode=data[1].x, blendMode=data[1].y.
// Inputs: trailTex=1, defocusTex=2. gl_FragCoord top-left — NO Y-flip.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[2]; };
#define resolution data[0].xy
#define intensity data[0].z
#define aperture data[0].w
#define viewMode int(data[1].x)
#define blendMode int(data[1].y)
layout(set = 0, binding = 1) uniform sampler2D trailTex;
layout(set = 0, binding = 2) uniform sampler2D defocusTex;
layout(location = 0) out vec4 fragColor;
layout(location = 0) in vec2 v_uv;

vec4 sampleDefocus(vec2 uv) {
	// Internal targets use nearest sampling. Interpolate all four channels
	// explicitly so the lower-resolution footprint remains smooth.
	ivec2 dims = textureSize(defocusTex, 0);
	vec2 p = uv * vec2(dims) - 0.5;
	ivec2 lo = ivec2(floor(p));
	vec2 f = fract(p);
	ivec2 a = clamp(lo, ivec2(0), dims - 1);
	ivec2 b = clamp(lo + 1, ivec2(0), dims - 1);
	return mix(mix(texelFetch(defocusTex, a, 0), texelFetch(defocusTex, ivec2(b.x, a.y), 0), f.x),
		mix(texelFetch(defocusTex, ivec2(a.x, b.y), 0), texelFetch(defocusTex, b, 0), f.x), f.y);
}

void main() {
	vec2 uv = gl_FragCoord.xy / resolution;

	// Sample the trail texture directly (no blur)
	vec4 trailColor = texture(trailTex, uv);

	// Apply intensity decay (persistence)
	float decay = clamp(intensity / 100.0, 0.0, 1.0);
	fragColor = clamp(trailColor * decay, 0.0, 1.0);
	if (blendMode == 0 && aperture > 0.0 && viewMode != 0) fragColor += sampleDefocus(uv);
}
