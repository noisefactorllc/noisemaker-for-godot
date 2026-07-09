#version 450
// filter/stamp, program "stThreshold" — ported verbatim from
// wgsl/stThreshold.wgsl, a 1:1 port with NO manual Y compensation anywhere:
// the fbm/hash noise is isotropic per-pixel value noise with nothing
// fragment-coordinate-derived beyond the noise coordinate itself, so PORTING-
// GUIDE's rotation-handedness exception does not apply (matches
// filter/photocopy's DoG precedent).
//
// Blurred-luminance threshold into two flat ink/paper tones (Photoshop
// Stamp / Torn Edges): t = lum(blur) perturbed by tile-aware fbm noise
// scaled by `roughness` (0 = clean iso-line "Stamp", >0 = ragged "Torn
// Edges"); b = balance/100 is the threshold; aa is the smoothstep
// half-width (fwidth-based AA, widened by roughness so torn edges read
// slightly soft). m = smoothstep(b-aa, b+aa, t), tonemapped as tonemap2(m,
// inkColor, paperColor) (m=1 -> paper, m=0 -> ink).
//
// No-layout effect: the backend synthesizes the Params UBO and injects
// `#define balance data[..]`, `#define roughness data[..]`, `#define
// inkColor data[..].xyz`, `#define paperColor data[..].xyz`. Inputs at set 0,
// binding 1.. in pass.inputs order (inputTex, blurTex).
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(set = 0, binding = 2) uniform sampler2D blurTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p_in) {
	vec2 p = p_in;
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 tonemap2(float t, vec3 ink, vec3 paper) {
	return mix(ink, paper, clamp(t, 0.0, 1.0));
}

void main() {
	vec2 texSize = vec2(textureSize(inputTex, 0));
	vec2 uv = gl_FragCoord.xy / texSize;
	vec4 src = texture(inputTex, uv);
	vec4 blur = texture(blurTex, uv);

	vec2 globalCoord = floor(gl_FragCoord.xy);

	float lumBlur = lum(blur.rgb);
	float grain = (fbm(globalCoord / 3.0) - 0.5) * (roughness / 100.0) * 0.35;
	float t = lumBlur + grain;

	float b = balance / 100.0;
	float aa = max(fwidth(t), 0.01) + (roughness / 100.0) * 0.05;
	float m = smoothstep(b - aa, b + aa, t);

	vec3 outColor = tonemap2(m, inkColor, paperColor);
	frag = vec4(outColor, src.a);
}
